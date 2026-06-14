package com.geqian.flyplayer.fly_player.mpv

import android.content.Context
import android.graphics.Bitmap
import android.os.Build
import android.util.Log
import java.io.File

// full flavor: danmaku dynamic occlusion backed by MNN (ISNet-anime). Paddle/
// FastDeploy has been removed — segmentation runs the MNN full-frame path and
// detection is no longer used. Keeps the exact public API of the lite stub so the
// flavor-agnostic orchestrator (src/main) compiles for both flavors.

private const val DANMAKU_MNN_SEG_ASSET_DIR = "models/mnn_seg"
// fp16 (not int8): GPU runs fp16 natively; int8 weight-quant is ~3x slower on GPU.
// Input size MUST match the size the .mnn was exported at. Runtime resizeTensor to a
// DIFFERENT size fails: the ONNX export bakes fixed Resize targets into the skip
// connections, so the encoder/skip shapes mismatch → MNN "Compute Shape Error for
// .../Concat" → every inference fails → masks永远为空 (seen on device with the old
// 384 model forced to 512). This model IS exported at 512 (E:\dm_seg_512\export_512.py,
// from skytnt/anime-seg isnetis.ckpt) — small/distant subjects that 384 missed
// (foreground ratio below the MIN gate) now segment reliably; weights identical so the
// file size is unchanged vs 384.
private const val DANMAKU_MNN_SEG_MODEL_FILE = "isnet-anime-512-fp16.mnn"
private const val DANMAKU_MNN_SEG_INPUT_SIZE = 512
private const val DANMAKU_MNN_CACHE_DIR_NAME = "danmaku_ai_mnn_models"
private const val TAG = "FlyPlayerDanmakuAI"

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

private class MnnSegmentationRuntime(
    private val segmenter: MnnImageSegmenter,
    private val size: Int,
) : DanmakuSegmentationRuntime {
    // Reuse the PADDLE wire value so the orchestrator keeps treating this as the
    // active AI backend without wider changes.
    override val backend: DanmakuAiBackend = DanmakuAiBackend.PADDLE
    override val inputWidth: Int = size
    override val inputHeight: Int = size
    override val outputWidth: Int = size
    override val outputHeight: Int = size

    override fun run(bitmap: Bitmap): DanmakuSegmentationOutput {
        val mask = segmenter.segment(bitmap, size) ?: error("MNN segmentation failed")
        return DanmakuSegmentationOutput(
            maskValues = mask.values,
            width = mask.width,
            height = mask.height,
        )
    }

    override fun close() {
        segmenter.close()
    }
}

class DanmakuSegmentationRuntimeFactory(
    private val context: Context,
    @Suppress("UNUSED_PARAMETER") paddleModelAssetDir: String,
) {
    fun create(
        backend: DanmakuAiBackend,
        config: DanmakuDynamicOcclusionConfig,
    ): DanmakuSegmentationRuntime {
        check(config.preferredBackendOrder.contains(DanmakuAiBackend.PADDLE)) {
            "AI backend must remain enabled"
        }
        return when (backend) {
            DanmakuAiBackend.PADDLE -> createMnnRuntime()
            DanmakuAiBackend.GPU,
            DanmakuAiBackend.CPU,
            -> error("backend ${backend.wireValue} is no longer supported")
            DanmakuAiBackend.DISABLED -> error("disabled backend cannot create runtime")
        }
    }

    fun shouldAttempt(backend: DanmakuAiBackend): Boolean {
        return when (backend) {
            DanmakuAiBackend.PADDLE ->
                MnnSegNative.isAvailable && assetDirectoryExists(DANMAKU_MNN_SEG_ASSET_DIR)
            DanmakuAiBackend.GPU,
            DanmakuAiBackend.CPU,
            DanmakuAiBackend.DISABLED,
            -> false
        }
    }

    fun deviceSummary(): String {
        val soc =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                Build.SOC_MANUFACTURER
            } else {
                Build.HARDWARE
            }
        return "mnn-cpu soc=$soc"
    }

    private fun createMnnRuntime(): DanmakuSegmentationRuntime {
        // MNN loads from a file path, so copy the bundled .mnn asset to cache once
        // (cache-aware: skip if already materialized).
        val destDir = File(File(context.cacheDir, DANMAKU_MNN_CACHE_DIR_NAME), "mnn_seg")
        val modelFile = File(destDir, DANMAKU_MNN_SEG_MODEL_FILE)
        // Evict superseded model copies (e.g. the old 384 one) — each is ~84MB of cache.
        destDir.listFiles()?.forEach { stale ->
            if (stale.isFile && stale.name != DANMAKU_MNN_SEG_MODEL_FILE) stale.delete()
        }
        if (!modelFile.isFile) {
            destDir.mkdirs()
            context.assets.open("$DANMAKU_MNN_SEG_ASSET_DIR/$DANMAKU_MNN_SEG_MODEL_FILE").use { input ->
                modelFile.outputStream().use { output -> input.copyTo(output) }
            }
        }
        // CPU backend. GPU was tried but: mpv itself already runs a Vulkan context
        // (libplacebo) on the Adreno GPU, and a second MNN Vulkan context alongside it
        // crashed. Thermal load from CPU inference is mitigated by the static-scene skip
        // instead. (To retry GPU, switch to BACKEND_VULKAN — the run/destroy race that
        // amplified the crash is now fixed, but the mpv-Vulkan coexistence risk remains.)
        val path = modelFile.absolutePath
        // 4 threads (was 2): 512 inference is ~1.8x the 384 compute, and the pipeline thread
        // is no longer pinned to the throttled background cpuset (see
        // DanmakuMaskPrecomputePipeline), so it can spread across the mid-core cluster and
        // halve per-inference latency → shorter CPU-contention windows + fresher masks.
        val segmenter =
            MnnImageSegmenter.createAnime(path, backend = MnnSegNative.BACKEND_CPU, threads = 4)
                ?.also { Log.i(TAG, "MNN seg backend=cpu") }
                ?: error("MNN segmenter init failed: $path")
        return MnnSegmentationRuntime(segmenter, DANMAKU_MNN_SEG_INPUT_SIZE)
    }

    private fun assetDirectoryExists(assetDir: String): Boolean {
        return runCatching {
            context.assets.list(assetDir)?.isNotEmpty() == true
        }.getOrDefault(false)
    }
}

// Detection (PicoDet) was only needed by the old Paddle ROI pipeline. The MNN
// full-frame path needs no detector, so this is a no-op kept only so the (now
// unused) detection code path in the orchestrator still compiles.
class DanmakuDetectionRuntimeFactory(
    @Suppress("UNUSED_PARAMETER") context: Context,
    @Suppress("UNUSED_PARAMETER") paddleModelAssetDir: String,
) {
    fun create(backend: DanmakuAiBackend): DanmakuDetectionRuntime {
        error("detection is not available (removed with Paddle)")
    }

    fun shouldAttempt(backend: DanmakuAiBackend): Boolean = false

    fun deviceSummary(): String = "detection-removed"
}
