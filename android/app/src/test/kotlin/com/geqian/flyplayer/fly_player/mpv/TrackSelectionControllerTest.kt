package com.geqian.flyplayer.fly_player.mpv

import android.content.Context
import android.view.Surface
import `is`.xyz.mpv.MPVLib
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TrackSelectionControllerTest {
    /**
     * 复刻 error.log 7678-7689 的脏读现场：外挂字幕轨真实存在（第 3 条字幕），但
     * `track-list/count` 被读成垃圾大值、`track-list/$index/id` 读出越界垃圾 481040129029。
     * 修复后必须用「字幕序号」而非脏读的 id 复用该外挂轨——即 setPropertyInt("sid", 3)，
     * 而不是放弃复用去重复 sub-add（旧 bug 导致切换失败 / 一直转圈）。
     */
    @Test
    fun reuseFindsExternalSubtitleByOrdinalDespiteBogusId() {
        val path = "/data/code_cache/fly_player_sub_548d27ce.ass"
        val fake = FakeTrackListFacade(
            trackListCount = 64L, // 脏读：count 虚高
            tracks = mapOf(
                0 to mapOf("type" to "video"),
                1 to mapOf("type" to "audio"),
                2 to mapOf("type" to "sub", "id" to "1"), // 内嵌 PGS（第 1 条字幕）
                3 to mapOf("type" to "sub", "id" to "2"), // 内嵌 ass（第 2 条字幕）
                4 to mapOf(
                    "type" to "sub",
                    "external-filename" to path,
                    "id" to "481040129029", // 脏读：越界垃圾 id，必须被忽略
                ),
            ),
        )
        val controller = TrackSelectionController(fake)

        controller.queueExternalSubtitle(path, initialized = true)
        val applied = controller.applyPendingExternalSubtitle()

        assertTrue("应按字幕序号复用已加载的外挂字幕轨", applied)
        assertTrue(
            "外挂是第 3 条字幕 → sid 应设为 3（序号），而非脏读 id",
            fake.setIntCalls.any { it.first == "sid" && it.second == 3L },
        )
        assertFalse(
            "绝不能把脏读的垃圾 id 设给 sid",
            fake.setIntCalls.any { it.first == "sid" && it.second == 481040129029L },
        )
        assertFalse(
            "复用命中时不应再 sub-add（否则产生重复轨/振荡）",
            fake.commands.any { it.firstOrNull() == "sub-add" },
        )
    }

    /** 外挂字幕是唯一字幕轨时，序号为 1 → sid=1。 */
    @Test
    fun reuseSingleExternalSubtitleUsesOrdinalOne() {
        val path = "/data/code_cache/fly_player_sub_single.ass"
        val fake = FakeTrackListFacade(
            trackListCount = 3L,
            tracks = mapOf(
                0 to mapOf("type" to "video"),
                1 to mapOf("type" to "audio"),
                2 to mapOf("type" to "sub", "external-filename" to path, "id" to "999999999"),
            ),
        )
        val controller = TrackSelectionController(fake)

        controller.queueExternalSubtitle(path, initialized = true)
        val applied = controller.applyPendingExternalSubtitle()

        assertTrue(applied)
        assertEquals(
            listOf("sid" to 1L),
            fake.setIntCalls.filter { it.first == "sid" },
        )
        assertFalse(fake.commands.any { it.firstOrNull() == "sub-add" })
    }

    @Test
    fun reuseExistingExternalSubtitleIgnoresFalseSetterReturn() {
        val path = "/data/code_cache/fly_player_sub_false_return.ass"
        val fake = FakeTrackListFacade(
            trackListCount = 3L,
            tracks = mapOf(
                0 to mapOf("type" to "video"),
                1 to mapOf("type" to "audio"),
                2 to mapOf("type" to "sub", "external-filename" to path, "id" to "1"),
            ),
            falseSetIntProperties = setOf("sid"),
        )
        val controller = TrackSelectionController(fake)

        controller.queueExternalSubtitle(path, initialized = true)
        val applied = controller.applyPendingExternalSubtitle()

        assertTrue(applied)
        assertEquals(
            listOf("sid" to 1L),
            fake.setIntCalls.filter { it.first == "sid" },
        )
        assertFalse(
            "setPropertyInt 返回 false 不能触发重复 sub-add",
            fake.commands.any { it.firstOrNull() == "sub-add" },
        )
    }

    /** 外挂字幕尚未加载时，复用扫描应为空并回退到 sub-add 重挂。 */
    @Test
    fun fallsBackToSubAddWhenExternalNotLoaded() {
        val path = "/data/code_cache/fly_player_sub_missing.ass"
        val fake = FakeTrackListFacade(
            trackListCount = 3L,
            tracks = mapOf(
                0 to mapOf("type" to "video"),
                1 to mapOf("type" to "audio"),
                2 to mapOf("type" to "sub", "id" to "1"), // 仅有内嵌字幕，非目标外挂
            ),
        )
        val controller = TrackSelectionController(fake)

        controller.queueExternalSubtitle(path, initialized = true)
        val applied = controller.applyPendingExternalSubtitle()

        assertTrue(applied)
        assertTrue(
            "未命中复用应回退到 sub-add 重挂外挂字幕",
            fake.commands.any { it.firstOrNull() == "sub-add" && it.contains(path) },
        )
    }

    private class FakeTrackListFacade(
        private val trackListCount: Long,
        private val tracks: Map<Int, Map<String, String>>,
        private val falseSetIntProperties: Set<String> = emptySet(),
    ) : MpvFacade {
        val setIntCalls = mutableListOf<Pair<String, Long>>()
        val commands = mutableListOf<List<String>>()

        private val propRegex = Regex("""track-list/(\d+)/(.+)""")

        override fun getPropertyInt(property: String): Long {
            if (property == "track-list/count") return trackListCount
            val m = propRegex.find(property)
            if (m != null && m.groupValues[2] == "id") {
                val idx = m.groupValues[1].toInt()
                return tracks[idx]?.get("id")?.toLong()
                    ?: throw RuntimeException("property not found: $property")
            }
            return 0L
        }

        override fun getPropertyString(property: String): String? {
            val m = propRegex.find(property) ?: return null
            val idx = m.groupValues[1].toInt()
            return tracks[idx]?.get(m.groupValues[2])
        }

        override fun setPropertyInt(name: String, value: Long): Boolean {
            setIntCalls += name to value
            if (name in falseSetIntProperties) return false
            // 模拟 mpv 对不存在轨道号的拒绝（error -4）。
            if (name == "sid" && value > 256L) return false
            return true
        }

        override fun command(command: Array<String>): Int {
            commands += command.toList()
            return 0
        }

        override fun isAvailable(): Boolean = true

        override fun loadErrorMessage(): String? = null

        override fun isCreated(): Boolean = true

        override fun maybeCreate(context: Context): Boolean = true

        override fun maybeInit(): Boolean = true

        override fun shutdown() = Unit

        override fun addObserver(observer: MPVLib.EventObserver) = Unit

        override fun removeObserver(observer: MPVLib.EventObserver) = Unit

        override fun addLogObserver(observer: MPVLib.LogObserver) = Unit

        override fun removeLogObserver(observer: MPVLib.LogObserver) = Unit

        override fun attachSurface(surface: Surface) = Unit

        override fun detachSurface() = Unit

        override fun setOptionString(name: String, value: String): Boolean = true

        override fun setPropertyString(name: String, value: String): Boolean = true

        override fun setPropertyDouble(name: String, value: Double): Boolean = true

        override fun setPropertyBoolean(name: String, value: Boolean): Boolean = true

        override fun observeProperty(property: String, format: Int): Int = 0

        override fun getPropertyDouble(property: String): Double = 0.0

        override fun onStartFile(): Int = 0

        override fun onFileLoaded(): Int = 0

        override fun onEndFile(): Int = 0
    }
}
