package com.geqian.flyplayer.fly_player

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class SeekThumbnailBifStoreTest {
    private fun bytes(): ByteArray = ByteBuffer.allocate(84).order(ByteOrder.LITTLE_ENDIAN).apply {
        put(byteArrayOf(0x89.toByte(), 0x42, 0x49, 0x46, 13, 10, 26, 10))
        putInt(12, 1); putInt(16, 1000); putInt(68, 80); putInt(72, -1); putInt(76, 84)
        position(80); put(byteArrayOf(1, 2, 3, 4))
    }.array()

    @Test fun localFileLoadsWithoutNetworkAndClearInvalidatesPendingResult() {
        val directory = Files.createTempDirectory("fly-bif-native-").toFile()
        try {
            val file = File(directory, "verified.bif").apply { writeBytes(bytes()) }
            val store = SeekThumbnailBifStore(directory)
            store.prepare("", emptyMap(), file)
            val deadline = System.nanoTime() + 2_000_000_000L
            while (store.frameFor(0) == null && System.nanoTime() < deadline) Thread.sleep(5)
            assertArrayEquals(byteArrayOf(1, 2, 3, 4), store.frameFor(0)?.bytes)
            store.prepare("", emptyMap())
            assertNull(store.frameFor(0))
            repeat(25) {
                store.prepare("", emptyMap(), file)
                store.prepare("", emptyMap())
            }
            Thread.sleep(50)
            assertNull(store.frameFor(0))
        } finally { directory.deleteRecursively() }
    }
}
