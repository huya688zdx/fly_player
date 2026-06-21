package com.geqian.flyplayer.fly_player.mpv

import android.content.Context
import android.view.Surface
import `is`.xyz.mpv.MPVLib
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TrackSelectionControllerTest {
    /**
     * 复刻 error.log 3841-3848 的脏读现场：mpv 在轨道列表改写瞬间，`track-list/count`
     * 返回垃圾大值、匹配到的外挂字幕轨 `id` 读出越界垃圾值 3324941。修复后该垃圾 id
     * 必须被丢弃，绝不能被 setPropertyInt("sid", ...) 设进去（否则 mpv 报 -4，
     * 用户看到字幕切换失败 / 一直转圈）。
     */
    @Test
    fun applyPendingExternalSubtitleDropsBogusTrackIdInsteadOfSettingSid() {
        val path = "/data/code_cache/fly_player_sub_548d27ce.ass"
        val fake = FakeTrackListFacade(
            trackListCount = 64L, // 脏读：真实只有 3 轨，count 被读成垃圾大值
            tracks = mapOf(
                0 to mapOf("type" to "video"),
                1 to mapOf("type" to "audio"),
                2 to mapOf(
                    "type" to "sub",
                    "external-filename" to path,
                    "id" to "3324941", // 脏读：越界垃圾轨道号
                ),
            ),
        )
        val controller = TrackSelectionController(fake)

        controller.queueExternalSubtitle(path, initialized = true)
        controller.applyPendingExternalSubtitle()

        val bogusSidSet = fake.setIntCalls.any { it.first == "sid" && it.second == 3324941L }
        assertFalse("绝不能把脏读的垃圾轨道号设给 sid", bogusSidSet)
        // 回退到 purge+sub-add 重挂路径：应发出该外挂字幕的 sub-add 命令。
        val subAdded = fake.commands.any { it.firstOrNull() == "sub-add" && it.contains(path) }
        assertTrue("复用被丢弃后应回退到 sub-add 重挂外挂字幕", subAdded)
    }

    /** 合法的小轨道号仍应被正常复用（不要误杀正常路径）。 */
    @Test
    fun applyPendingExternalSubtitleReusesPlausibleTrackId() {
        val path = "/data/code_cache/fly_player_sub_plausible.ass"
        val fake = FakeTrackListFacade(
            trackListCount = 4L,
            tracks = mapOf(
                0 to mapOf("type" to "video"),
                1 to mapOf("type" to "audio"),
                2 to mapOf(
                    "type" to "sub",
                    "external-filename" to path,
                    "id" to "3",
                ),
            ),
        )
        val controller = TrackSelectionController(fake)

        controller.queueExternalSubtitle(path, initialized = true)
        val applied = controller.applyPendingExternalSubtitle()

        assertTrue("合法外挂字幕轨应被复用", applied)
        assertTrue(
            "复用应把 sid 设为该轨道号 3",
            fake.setIntCalls.any { it.first == "sid" && it.second == 3L },
        )
        assertFalse(
            "复用命中时不应再 sub-add",
            fake.commands.any { it.firstOrNull() == "sub-add" },
        )
    }

    private class FakeTrackListFacade(
        private val trackListCount: Long,
        private val tracks: Map<Int, Map<String, String>>,
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
