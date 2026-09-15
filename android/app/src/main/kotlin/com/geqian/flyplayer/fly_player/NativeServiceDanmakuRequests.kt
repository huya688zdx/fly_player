package com.geqian.flyplayer.fly_player

/** Only public playback identity crosses the service request boundaries. */
internal data class NativeServiceDanmakuContext(
    val signedIn: Boolean,
    val accountIdentity: String,
    val statsScope: String,
    val playbackContextId: String,
    val seekEpoch: Long,
    val mediaArgs: Map<String, Any?>,
)

internal class NativeServiceDanmakuRequests {
    class Ticket internal constructor(val revision: Long, val context: NativeServiceDanmakuContext)

    private var revision = 0L

    fun begin(context: NativeServiceDanmakuContext) = Ticket(++revision, context)

    fun invalidate() { ++revision }

    fun accepts(ticket: Ticket, current: NativeServiceDanmakuContext, activityDestroying: Boolean): Boolean =
        !activityDestroying && current.signedIn && current.accountIdentity.isNotBlank() &&
            current.statsScope.isNotBlank() && current.playbackContextId.isNotBlank() &&
            !current.mediaArgs["itemGuid"]?.toString().isNullOrBlank() &&
            // 全集弹幕不绑定播放位置，快进仍可应用；媒体、账号和选源代数必须一致。
            ticket.revision == revision && ticket.context.copy(seekEpoch = current.seekEpoch) == current
}

internal data class NativeServiceDanmakuPayload(val path: String, val sourceKey: String) {
    fun matches(payload: Map<*, *>?): Boolean = payload?.get("sourceKey") == sourceKey

    companion object {
        fun fromReply(raw: Any?, allowOriginal: Boolean = false): NativeServiceDanmakuPayload? {
            val data = raw as? Map<*, *> ?: return null
            if (data["status"] != "ready") return null
            val path = (data["danmakuFile"] as? String)?.takeIf { it.isNotBlank() } ?: return null
            val key = (data["sourceKey"] as? String)?.takeIf {
                it.startsWith("nas:") || (allowOriginal && it.startsWith("dandan:"))
            } ?: return null
            return NativeServiceDanmakuPayload(path, key)
        }
    }
}
