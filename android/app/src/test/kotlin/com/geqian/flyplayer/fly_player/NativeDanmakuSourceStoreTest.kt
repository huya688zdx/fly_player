package com.geqian.flyplayer.fly_player

import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.lang.reflect.Proxy
import java.nio.file.Files
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class NativeDanmakuSourceStoreTest {
    // A real temporary file backs the Android preferences interface. Reopening a
    // store reads the persisted bytes, not the previous store's in-memory list.
    private fun preferences(file: File): SharedPreferences {
        fun read(): JSONObject = if (file.exists()) JSONObject(file.readText()) else JSONObject()
        return Proxy.newProxyInstance(SharedPreferences::class.java.classLoader, arrayOf(SharedPreferences::class.java)) { _, method, args ->
            when (method.name) {
                "getString" -> read().optString(args!![0] as String).ifEmpty { args[1] as String? }
                "edit" -> {
                    val changes = linkedMapOf<String, String>()
                    lateinit var editor: SharedPreferences.Editor
                    editor = Proxy.newProxyInstance(SharedPreferences.Editor::class.java.classLoader, arrayOf(SharedPreferences.Editor::class.java)) { _, edit, values ->
                        when (edit.name) {
                            "putString" -> { changes[values!![0] as String] = values[1] as String; editor }
                            "apply", "commit" -> { val json = read(); changes.forEach { (k, v) -> json.put(k, v) }; file.writeText(json.toString()); if (edit.name == "commit") true else null }
                            else -> error("Unexpected editor method ${edit.name}")
                        }
                    } as SharedPreferences.Editor
                    editor
                }
                else -> error("Unexpected preference method ${method.name}")
            }
        } as SharedPreferences
    }

    private fun store(file: File) = NativeDanmakuSourceStore(NativePlayerSettingsStore(preferences(file))) {
        if (it.optString("type") == "dandan") "dandan:${it.optLong("episodeId")}" else "local:${it.optString("uri")}"
    }
    private fun record(id: Int, media: String = "media-A") = JSONObject().apply {
        put("mediaKey", media); put("type", "dandan"); put("episodeId", id); put("label", "same label")
    }
    private fun identities(file: File): Set<String> {
        val raw = NativePlayerSettingsStore(preferences(file)).loadString(NativePlayerSettingsStore.KEY_DANMAKU_SOURCES)
        val arr = JSONArray(raw ?: "[]")
        return (0 until arr.length()).map { val o = arr.getJSONObject(it); "${o.getString("mediaKey")}:${o.getInt("episodeId")}" }.toSet()
    }
    private fun withFile(block: (File) -> Unit) {
        val directory = Files.createTempDirectory("a5_native_danmaku_").toFile()
        try { block(directory.resolve("preferences.json")) } finally { directory.deleteRecursively() }
    }

    @Test fun twoSuccessfulDeletesInEitherOrderDoNotResurrectAndPreserveNewSourceOnDisk() = withFile { file ->
        for (reverse in listOf(false, true)) {
            val store = store(file)
            (1..3).forEach { store.upsert(record(it)) }
            val deleteA = store.removalCompletion("media-A", "dandan:1")
            val deleteB = store.removalCompletion("media-A", "dandan:2")
            store.upsert(record(4))
            val completions = if (reverse) listOf(deleteB, deleteA) else listOf(deleteA, deleteB)
            completions.forEach { assertTrue(it(true)) }
            assertEquals(setOf("media-A:3", "media-A:4"), identities(file))
        }
    }

    @Test fun falseNullOrErrorCompletionDoesNotChangePersistentList() = withFile { file ->
        val store = store(file)
        store.upsert(record(1))
        for (result in listOf(false, null, "true")) {
            assertFalse(store.removalCompletion("media-A", "dandan:1")(result))
            assertEquals(setOf("media-A:1"), identities(file))
        }
    }

    @Test fun lateSuccessOnlyDeletesCapturedMediaAndStableSourceIdentity() = withFile { file ->
        val store = store(file)
        store.upsert(record(1))
        store.upsert(record(2))
        val late = store.removalCompletion("media-A", "dandan:1")
        store.upsert(record(1, "media-B"))
        assertTrue(late(true))
        assertEquals(setOf("media-A:2", "media-B:1"), identities(file))
        assertTrue(late(true)) // duplicate success is idempotent
        assertEquals(setOf("media-A:2", "media-B:1"), identities(file))
    }

    @Test fun localIdentityAndMalformedPersistenceDoNotDeleteUnrelatedState() = withFile { file ->
        val store = store(file)
        val first = record(1).put("type", "local").put("uri", "/tmp/first.xml")
        val second = record(2).put("type", "local").put("uri", "/tmp/second.xml")
        store.upsert(first)
        store.upsert(second)
        assertTrue(store.removalCompletion("media-A", "local:/tmp/first.xml")(true))
        assertEquals(setOf("media-A:2"), identities(file))
        val settings = NativePlayerSettingsStore(preferences(file))
        settings.saveString(NativePlayerSettingsStore.KEY_DANMAKU_SOURCES, "malformed JSON")
        assertFalse(store.removalCompletion("media-A", "local:/tmp/second.xml")(true))
        assertEquals("malformed JSON", settings.loadString(NativePlayerSettingsStore.KEY_DANMAKU_SOURCES))
    }

    @Test fun independentStoreInstancesSerializeConcurrentDeleteAndSave() = withFile { file ->
        val first = store(file)
        val second = store(file)
        (1..20).forEach { first.upsert(record(it)) }
        val callbacks = (1..20).map { first.removalCompletion("media-A", "dandan:$it") }
        val start = CountDownLatch(1)
        val pool = Executors.newFixedThreadPool(4)
        try {
            val futures = callbacks.map { callback -> pool.submit { start.await(); assertTrue(callback(true)) } } +
                (21..40).map { id -> pool.submit { start.await(); assertTrue(second.upsert(record(id))) } }
            start.countDown()
            futures.forEach { it.get(10, TimeUnit.SECONDS) }
        } finally { pool.shutdownNow() }
        assertEquals((21..40).map { "media-A:$it" }.toSet(), identities(file))
    }
}
