package com.geqian.flyplayer.fly_player.mpv

import android.content.Context
import android.graphics.Bitmap

// lite flavor：不含 Paddle/FastDeploy。保留与 full 版完全一致的对外 API，但运行时
// 一律「不可用」(shouldAttempt() 永远 false)，使 DanmakuDynamicOcclusion 自动跳过
// AI 遮挡、功能优雅降级。不 import 任何 com.baidu.paddle.* —— lite 包不依赖
// fastdeploy.aar，从而省去 ~76MB 原生库 + 13MB 模型。
//
// 注意：DanmakuAiBackend / DanmakuNormalizedRect / DanmakuDynamicOcclusionConfig
// 定义在 main sourceSet 的 DanmakuDynamicOcclusion.kt，两个 flavor 都可见，
// 因此这里不重复定义（重复会冲突）。

data class DanmakuDetectionCandidate(
    val score: Float,
    val rect: DanmakuNormalizedRect,
)

data class DanmakuSegmentationOutput(
    val maskValues: FloatArray,
    val width: Int,
    val height: Int,
)

interface DanmakuSegmentationRuntime : AutoCloseable {
    val backend: DanmakuAiBackend
    val inputWidth: Int
    val inputHeight: Int
    val outputWidth: Int
    val outputHeight: Int

    fun run(bitmap: Bitmap): DanmakuSegmentationOutput
}

interface DanmakuDetectionRuntime : AutoCloseable {
    val backend: DanmakuAiBackend
    val inputWidth: Int
    val inputHeight: Int

    fun run(
        bitmap: Bitmap,
        scoreThreshold: Float,
    ): List<DanmakuDetectionCandidate>
}

class DanmakuSegmentationRuntimeFactory(
    @Suppress("UNUSED_PARAMETER") context: Context,
    @Suppress("UNUSED_PARAMETER") paddleModelAssetDir: String,
) {
    fun create(
        backend: DanmakuAiBackend,
        config: DanmakuDynamicOcclusionConfig,
    ): DanmakuSegmentationRuntime {
        error("Paddle segmentation is not available in the lite build")
    }

    // 永远不可用 → 调用方据此跳过 AI 遮挡，功能优雅降级。
    fun shouldAttempt(backend: DanmakuAiBackend): Boolean = false

    fun deviceSummary(): String = "lite-build-no-paddle"
}

class DanmakuDetectionRuntimeFactory(
    @Suppress("UNUSED_PARAMETER") context: Context,
    @Suppress("UNUSED_PARAMETER") paddleModelAssetDir: String,
) {
    fun create(backend: DanmakuAiBackend): DanmakuDetectionRuntime {
        error("Paddle detection is not available in the lite build")
    }

    fun shouldAttempt(backend: DanmakuAiBackend): Boolean = false

    fun deviceSummary(): String = "lite-build-no-paddle"
}
