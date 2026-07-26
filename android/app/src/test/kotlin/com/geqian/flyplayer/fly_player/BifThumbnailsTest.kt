package com.geqian.flyplayer.fly_player

import java.io.ByteArrayOutputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class BifThumbnailsTest {

    /** 造合法 BIF：64 字节头 + (N+1) 条索引 + JPEG 数据区（此处用任意字节代替）。 */
    private fun buildBif(
        frames: List<Pair<Long, ByteArray>>,
        multiplier: Long = 1000L,
        magic: ByteArray = byteArrayOf(0x89.toByte(), 0x42, 0x49, 0x46, 0x0D, 0x0A, 0x1A, 0x0A),
    ): ByteArray {
        val header = ByteArrayOutputStream()
        header.write(magic)
        header.writeUInt32(0L) // version
        header.writeUInt32(frames.size.toLong())
        header.writeUInt32(multiplier)
        repeat(44) { header.write(0) } // 保留区补到 64
        val indexSize = (frames.size + 1) * 8
        var offset = 64L + indexSize
        for ((timestamp, payload) in frames) {
            header.writeUInt32(timestamp)
            header.writeUInt32(offset)
            offset += payload.size
        }
        header.writeUInt32(0xFFFFFFFFL) // 终止哨兵
        header.writeUInt32(offset)
        for ((_, payload) in frames) header.write(payload)
        return header.toByteArray()
    }

    private fun ByteArrayOutputStream.writeUInt32(value: Long) {
        write((value and 0xFF).toInt())
        write(((value shr 8) and 0xFF).toInt())
        write(((value shr 16) and 0xFF).toInt())
        write(((value shr 24) and 0xFF).toInt())
    }

    @Test
    fun parsesFramesAndScalesTimestampsByMultiplier() {
        val bif = buildBif(
            frames = listOf(
                0L to byteArrayOf(1, 2, 3),
                10L to byteArrayOf(4, 5),
                20L to byteArrayOf(6),
            ),
            multiplier = 1000L,
        )

        val index = BifThumbnails.parse(bif)

        assertNotNull(index)
        assertEquals(3, index!!.frameCount)
        assertArrayEquals(longArrayOf(0L, 10_000L, 20_000L), index.timestampsMs)
        assertArrayEquals(byteArrayOf(1, 2, 3), index.frameBytes(0))
        assertArrayEquals(byteArrayOf(4, 5), index.frameBytes(1))
        assertArrayEquals(byteArrayOf(6), index.frameBytes(2))
    }

    @Test
    fun zeroMultiplierFallsBackToMilliseconds() {
        val bif = buildBif(
            frames = listOf(0L to byteArrayOf(1), 5000L to byteArrayOf(2)),
            multiplier = 0L,
        )

        val index = BifThumbnails.parse(bif)

        assertNotNull(index)
        assertArrayEquals(longArrayOf(0L, 5_000_000L), index!!.timestampsMs)
    }

    @Test
    fun frameIndexForPicksLastFrameAtOrBeforePosition() {
        val bif = buildBif(
            frames = listOf(
                0L to byteArrayOf(1),
                10L to byteArrayOf(2),
                20L to byteArrayOf(3),
            ),
        )
        val index = BifThumbnails.parse(bif)!!

        assertEquals(0, index.frameIndexFor(-50L)) // 目标在首帧前 → 首帧
        assertEquals(0, index.frameIndexFor(0L))
        assertEquals(0, index.frameIndexFor(9_999L))
        assertEquals(1, index.frameIndexFor(10_000L))
        assertEquals(1, index.frameIndexFor(19_999L))
        assertEquals(2, index.frameIndexFor(20_000L))
        assertEquals(2, index.frameIndexFor(999_999L)) // 目标在末帧后 → 末帧
    }

    @Test
    fun rejectsBadMagic() {
        val bif = buildBif(
            frames = listOf(0L to byteArrayOf(1)),
            magic = ByteArray(8) { 0x42 },
        )

        assertNull(BifThumbnails.parse(bif))
    }

    @Test
    fun rejectsZeroFrameCount() {
        assertNull(BifThumbnails.parse(buildBif(frames = emptyList())))
    }

    @Test
    fun rejectsTruncatedData() {
        val bif = buildBif(frames = listOf(0L to byteArrayOf(1, 2, 3), 10L to byteArrayOf(4)))

        // 掐掉尾部数据：末帧偏移越界，整文件判废。
        assertNull(BifThumbnails.parse(bif.copyOfRange(0, bif.size - 2)))
    }

    @Test
    fun rejectsNonMonotonicOffsets() {
        val bif = buildBif(frames = listOf(0L to byteArrayOf(1), 10L to byteArrayOf(2)))
        // 把第二帧偏移改到第一帧之前（64 + 8 + 4 = 第二条索引的 offset 字段）。
        bif[64 + 8 + 4] = 1

        assertNull(BifThumbnails.parse(bif))
    }

    @Test
    fun rejectsNonMonotonicTimestamps() {
        val bif = buildBif(frames = listOf(10L to byteArrayOf(1), 0L to byteArrayOf(2)))

        assertNull(BifThumbnails.parse(bif))
    }

    @Test
    fun rejectsTooShortInput() {
        assertNull(BifThumbnails.parse(ByteArray(16)))
    }
}
