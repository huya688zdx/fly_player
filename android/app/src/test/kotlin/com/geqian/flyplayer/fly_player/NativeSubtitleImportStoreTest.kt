package com.geqian.flyplayer.fly_player

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

class NativeSubtitleImportStoreTest {
    private fun entry(
        guid: String,
        mediaGuid: String = "media-1",
        itemGuid: String = "episode-1",
        fileName: String = "episode.srt",
        format: String = "srt",
        path: String = "/tmp/$fileName",
    ) = NativeSubtitleEntry(
        guid = guid,
        mediaGuid = mediaGuid,
        itemGuid = itemGuid,
        fileName = fileName,
        path = path,
        format = format,
        importedAtMs = 1L,
    )

    private fun stateOf(
        vararg entries: NativeSubtitleEntry,
        selectedItemGuid: String = "episode-1",
        selectedMediaGuid: String = "media-1",
        selected: String? = null,
    ): NativeSubtitleState {
        val scope = nativeSubtitleScopeKey(selectedItemGuid, selectedMediaGuid)
        return NativeSubtitleState(
            entries = entries.toList(),
            selectedByScope = if (selected == null || scope.isEmpty()) {
                emptyMap()
            } else {
                mapOf(scope to selected)
            },
        )
    }

    @Test
    fun legacyArrayMigratesToVersionedObject() {
        val legacy = """[{"guid":"local:sub:srt","mediaGuid":"media-1","itemGuid":"episode-1","fileName":"episode.srt","path":"/tmp/episode.srt","format":"srt","importedAtMs":1}]"""

        val state = decodeNativeSubtitleState(legacy)

        assertEquals("local:sub:srt", state.entries.single().guid)
        val encoded = JSONObject(encodeNativeSubtitleState(state))
        assertEquals(NATIVE_SUBTITLE_STATE_VERSION, encoded.getInt("version"))
        assertEquals(1, encoded.getJSONArray("entries").length())
        assertEquals(0, encoded.getJSONObject("selectedByScope").length())
    }

    @Test
    fun restoresSelectedSrtForSameItemAcrossMediaVariants() {
        val restored = restoreNativeSubtitleLoadArgs(
            loadArgs = mapOf(
                "itemGuid" to "episode-1",
                "mediaGuid" to "media-2",
                "subtitleTracks" to emptyList<Any>(),
            ),
            state = stateOf(
                entry(guid = "local:sub:srt"),
                selected = "local:sub:srt",
            ),
            fileExists = { true },
        )

        assertEquals("local:sub:srt", restored["subtitleTrackGuid"])
        assertEquals(true, restored["preferExternalSubtitle"])
        assertNull(restored["subtitleTrackIndex"])
        assertEquals(
            "/tmp/episode.srt",
            (restored["localSubtitleFiles"] as Map<*, *>)["local:sub:srt"],
        )
    }

    @Test
    fun restoresSupAndPgsAsBitmapLocalFiles() {
        val restored = restoreNativeSubtitleLoadArgs(
            loadArgs = mapOf(
                "itemGuid" to "episode-1",
                "mediaGuid" to "media-1",
            ),
            state = stateOf(
                entry(
                    guid = "local:sub:sup",
                    fileName = "episode.sup",
                    format = "sup",
                ),
                entry(
                    guid = "local:sub:pgs",
                    fileName = "episode.pgs",
                    format = "pgs",
                ),
                selected = "local:sub:sup",
            ),
            fileExists = { true },
        )

        @Suppress("UNCHECKED_CAST")
        val tracks = restored["subtitleTracks"] as List<Map<String, Any?>>
        assertEquals(listOf(1, 1), tracks.map { it["isBitmap"] })
        assertEquals(listOf(1, 1), tracks.map { it["isExternal"] })
        assertEquals(listOf(1, 1), tracks.map { it["extraFile"] })
        val files = restored["localSubtitleFiles"] as Map<*, *>
        assertEquals("/tmp/episode.sup", files["local:sub:sup"])
        assertEquals("/tmp/episode.pgs", files["local:sub:pgs"])
    }

    @Test
    fun doesNotLeakSubtitleIntoAnotherItem() {
        val restored = restoreNativeSubtitleLoadArgs(
            loadArgs = mapOf(
                "itemGuid" to "episode-2",
                "mediaGuid" to "media-2",
            ),
            state = stateOf(
                entry(guid = "local:sub:srt"),
                selected = "local:sub:srt",
            ),
            fileExists = { true },
        )

        assertEquals(emptyList<Any>(), restored["subtitleTracks"])
        assertNull(restored["subtitleTrackGuid"])
        assertEquals(emptyMap<String, String>(), restored["localSubtitleFiles"])
    }

    @Test
    fun stripsPreviousEpisodeManualSubtitleBeforeRestoringTargetItem() {
        val restored = restoreNativeSubtitleLoadArgs(
            loadArgs = mapOf(
                "itemGuid" to "episode-2",
                "mediaGuid" to "media-2",
                "subtitleTrackGuid" to "local:sub:episode-1",
                "preferExternalSubtitle" to true,
                "subtitleTracks" to listOf(
                    mapOf("guid" to "server:sub:episode-2", "title" to "内嵌字幕"),
                    mapOf("guid" to "local:sub:episode-1", "title" to "上一集字幕"),
                ),
                "localSubtitleFiles" to mapOf(
                    "server:sub:episode-2" to "/tmp/server.ass",
                    "local:sub:episode-1" to "/tmp/episode-1.srt",
                ),
            ),
            state = stateOf(
                entry(guid = "local:sub:episode-1"),
                selected = "local:sub:episode-1",
            ),
            fileExists = { true },
        )

        val tracks = restored["subtitleTracks"] as List<*>
        assertEquals(1, tracks.size)
        assertEquals(
            "server:sub:episode-2",
            (tracks.single() as Map<*, *>)["guid"],
        )
        assertEquals(
            mapOf("server:sub:episode-2" to "/tmp/server.ass"),
            restored["localSubtitleFiles"],
        )
        assertNull(restored["subtitleTrackGuid"])
        assertEquals(false, restored["preferExternalSubtitle"])
    }

    @Test
    fun restoresTargetEpisodeSelectionAfterStrippingPreviousManualSubtitle() {
        val previous = entry(
            guid = "local:sub:episode-1",
            itemGuid = "episode-1",
            fileName = "episode-1.srt",
            path = "/tmp/episode-1.srt",
        )
        val target = entry(
            guid = "local:sub:episode-2",
            mediaGuid = "media-2",
            itemGuid = "episode-2",
            fileName = "episode-2.sup",
            format = "sup",
            path = "/tmp/episode-2.sup",
        )
        val restored = restoreNativeSubtitleLoadArgs(
            loadArgs = mapOf(
                "itemGuid" to "episode-2",
                "mediaGuid" to "media-2",
                "subtitleTrackGuid" to previous.guid,
                "preferExternalSubtitle" to true,
                "subtitleTracks" to listOf(mapOf("guid" to previous.guid)),
                "localSubtitleFiles" to mapOf(previous.guid to previous.path),
            ),
            state = NativeSubtitleState(
                entries = listOf(previous, target),
                selectedByScope = mapOf("item:episode-2" to target.guid),
            ),
            fileExists = { true },
        )

        val tracks = restored["subtitleTracks"] as List<*>
        assertEquals(listOf(target.guid), tracks.map { (it as Map<*, *>)["guid"] })
        assertEquals(mapOf(target.guid to target.path), restored["localSubtitleFiles"])
        assertEquals(target.guid, restored["subtitleTrackGuid"])
        assertEquals(true, restored["preferExternalSubtitle"])
    }

    @Test
    fun removingSelectedSubtitleDropsEntryAndSelection() {
        val state = stateOf(
            entry(
                guid = "local:sub:sup",
                fileName = "episode.sup",
                format = "sup",
            ),
            selected = "local:sub:sup",
        )

        val result = removeNativeSubtitleFromState(state, "local:sub:sup")

        assertTrue(result.entries.isEmpty())
        assertTrue(result.selectedByScope.isEmpty())
    }

    @Test
    fun stateIsNotRemovedWhenFileDeletionFails() {
        val state = stateOf(
            entry(
                guid = "local:sub:pgs",
                fileName = "episode.pgs",
                format = "pgs",
            ),
            selected = "local:sub:pgs",
        )

        val result = deleteNativeSubtitle(
            state = state,
            guid = "local:sub:pgs",
            deleteFile = { false },
        )

        assertFalse(result.deleted)
        assertEquals("local:sub:pgs", result.state.entries.single().guid)
        assertEquals("local:sub:pgs", result.state.selectedByScope.values.single())
    }

    @Test
    fun deletesSrtSupAndPgsFilesWithMetadataAndSelections() {
        val directory = Files.createTempDirectory("native_manual_subtitle_delete").toFile()
        try {
            val entries = listOf("srt", "sup", "pgs").mapIndexed { index, format ->
                val file = directory.resolve("episode.$format").apply {
                    writeBytes(byteArrayOf(0x50, 0x47))
                }
                entry(
                    guid = "local:sub:$format",
                    mediaGuid = "media-$index",
                    itemGuid = "episode-$index",
                    fileName = file.name,
                    format = format,
                    path = file.absolutePath,
                )
            }
            var state = NativeSubtitleState(
                entries = entries,
                selectedByScope = entries.associate { item ->
                    nativeSubtitleScopeKey(item.itemGuid, item.mediaGuid) to item.guid
                },
            )

            for (item in entries) {
                val result = deleteNativeSubtitle(
                    state = state,
                    guid = item.guid,
                    deleteFile = { path ->
                        val file = java.io.File(path)
                        !file.exists() || file.delete()
                    },
                )
                assertTrue(result.deleted)
                assertFalse(java.io.File(item.path).exists())
                state = result.state
            }

            assertTrue(state.entries.isEmpty())
            assertTrue(state.selectedByScope.isEmpty())
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun supportedManualSubtitleFormatsIncludeTextAndPgsFiles() {
        assertTrue(nativeSubtitleImportFormatSupported("episode.srt"))
        assertTrue(nativeSubtitleImportFormatSupported("episode.ttml"))
        assertTrue(nativeSubtitleImportFormatSupported("episode.sup"))
        assertTrue(nativeSubtitleImportFormatSupported("episode.pgs"))
        assertFalse(nativeSubtitleImportFormatSupported("episode.xml"))
    }

    @Test
    fun localPgsUsesExternalFileWhileServerPgsStaysEmbedded() {
        assertTrue(
            nativeSubtitleUsesExternalFile(
                mapOf(
                    "guid" to "local:sub:pgs",
                    "format" to "pgs",
                    "isBitmap" to 1,
                ),
            ),
        )
        assertFalse(
            nativeSubtitleUsesExternalFile(
                mapOf(
                    "guid" to "server:pgs",
                    "format" to "pgs",
                    "isBitmap" to 1,
                    "isExternal" to 1,
                ),
            ),
        )
    }
}
