package com.geqian.flyplayer.fly_player.mpv

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodChannel

/**
 * 原生壳 → Flutter 的反向通道。
 *
 * 渐进原生化阶段 2：纯原生播放壳 `NativePlayerActivity` 是独立 task、没有自己的
 * FlutterEngine，凡是需要 NAS 解析的能力（选集、切画质、续播回写）都得回到 Flutter
 * 编排层完成。本桥借用「发起播放的 host」（详情页 `DetailActivity` 等，均继承
 * `FlutterHostActivity`，与原生壳同进程）已注册的 `fly_player/native_player`
 * MethodChannel，在主线程把请求 `invokeMethod` 回 Flutter，由详情页 State 注入的
 * 回调处理（解析新集 / 写回进度），结果再回到原生壳原地换源。
 *
 * 生命周期：host engine 在原生壳前台时理论上可能被系统回收 → [channel] 失效。此时
 * [dispatch] 走 [onError] 降级（原生壳弹提示而非崩溃）。详情页 host 通常由
 * ParallelWindowCoordinator 保活。[attach] 取最近一次发起的 host channel；host
 * 清理 channel 时 [detach]（仅当前持有者匹配才清，避免后注册的被错误清掉）。
 */
object NativePlayerReverseBridge {

    private const val TAG = "NativePlayerReverse"

    @Volatile
    private var channel: MethodChannel? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    fun attach(channel: MethodChannel) {
        this.channel = channel
    }

    fun detach(channel: MethodChannel) {
        if (this.channel === channel) {
            this.channel = null
        }
    }

    /**
     * 把一次反向请求投递回 Flutter。可在任意线程调用（内部切主线程）。
     *
     * @param onResult Flutter 处理成功的返回值（可空）。
     * @param onError  channel 不可用 / Flutter 端报错 / 未实现 时回调，供原生壳降级提示。
     */
    fun dispatch(
        method: String,
        args: Map<String, Any?>,
        onResult: (Any?) -> Unit = {},
        onError: (String?) -> Unit = {},
    ) {
        mainHandler.post {
            val target = channel
            if (target == null) {
                Log.w(TAG, "dispatch($method) dropped: no host channel attached")
                onError("no_host_channel")
                return@post
            }
            target.invokeMethod(
                method,
                args,
                object : MethodChannel.Result {
                    override fun success(result: Any?) = onResult(result)

                    override fun error(code: String, message: String?, details: Any?) {
                        Log.w(TAG, "dispatch($method) error: $code $message")
                        onError(code)
                    }

                    override fun notImplemented() {
                        Log.w(TAG, "dispatch($method) notImplemented on Flutter side")
                        onError("not_implemented")
                    }
                },
            )
        }
    }
}
