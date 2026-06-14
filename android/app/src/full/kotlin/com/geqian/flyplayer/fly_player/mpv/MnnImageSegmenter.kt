package com.geqian.flyplayer.fly_player.mpv

import android.graphics.Bitmap

/**
 * Clean, self-contained MNN-backed foreground segmenter for danmaku occlusion.
 *
 * One instance wraps one model (anime: ISNet-anime; real: u2net_human_seg). The
 * model is fully convolutional, so [segment] can be called at different square
 * sizes — use a small size (e.g. 256) for coarse subject location and a larger
 * size (e.g. 512) for precise ROI masking.
 *
 * Preprocessing matches the PoC: resize-to-NxN, then (channel-wise) (x/255 - mean)/std,
 * laid out NCHW. Postprocessing min-max normalizes the raw output to [0,1].
 *
 * Not thread-safe across [segment] calls on different threads for the same
 * instance beyond what the native mutex guards; call from a single inference thread.
 */
internal class MnnImageSegmenter private constructor(
    private val handle: Long,
    private val mean: FloatArray,
    private val std: FloatArray,
) : AutoCloseable {

    // Serializes nativeRun vs nativeDestroy. Without this, destroying the runtime
    // (source switch / dispose) while an inference is mid-flight frees the native MNN
    // interpreter (and its mutex) under the running call → "pthread_mutex_lock on a
    // destroyed mutex" SIGABRT. close() now waits for an in-flight run; a run after
    // close returns null.
    private val nativeLock = Any()

    @Volatile
    private var closed = false

    data class Mask(
        val values: FloatArray, // length width*height, normalized [0,1]
        val width: Int,
        val height: Int,
    )

    /** Run segmentation at [size]x[size]. Returns null on inference failure. */
    fun segment(
        bitmap: Bitmap,
        size: Int,
    ): Mask? {
        require(size > 0) { "size must be positive" }
        // Preprocess (CPU) outside the lock; only the native call needs to be serialized
        // with close().
        val input = preprocess(bitmap, size)
        val raw =
            synchronized(nativeLock) {
                if (closed || handle == 0L) return null
                MnnSegNative.nativeRun(handle, input, size)
            } ?: return null
        // model output is input-sized (NxN); min-max normalize to [0,1]
        normalizeInPlace(raw)
        return Mask(values = raw, width = size, height = size)
    }

    private fun preprocess(
        bitmap: Bitmap,
        size: Int,
    ): FloatArray {
        // Hardware-scale to NxN, then ONE bulk getPixels() read. Per-pixel
        // bitmap.getPixel() in a 512x512 loop is ~262k JNI calls and takes
        // hundreds of ms — never do that.
        val scaled =
            if (bitmap.width == size && bitmap.height == size) {
                bitmap
            } else {
                Bitmap.createScaledBitmap(bitmap, size, size, true)
            }
        val pixels = IntArray(size * size)
        scaled.getPixels(pixels, 0, size, 0, 0, size, size)
        if (scaled !== bitmap && !scaled.isRecycled) {
            scaled.recycle()
        }

        val plane = size * size
        val out = FloatArray(3 * plane)
        val invR = 1f / std[0]
        val invG = 1f / std[1]
        val invB = 1f / std[2]
        for (i in 0 until plane) {
            val c = pixels[i]
            val r = ((c ushr 16) and 0xFF) / 255f
            val g = ((c ushr 8) and 0xFF) / 255f
            val b = (c and 0xFF) / 255f
            out[i] = (r - mean[0]) * invR // R plane
            out[plane + i] = (g - mean[1]) * invG // G plane
            out[2 * plane + i] = (b - mean[2]) * invB // B plane
        }
        return out
    }

    private fun normalizeInPlace(v: FloatArray) {
        var mi = Float.MAX_VALUE
        var ma = -Float.MAX_VALUE
        for (f in v) {
            if (f < mi) mi = f
            if (f > ma) ma = f
        }
        val range = ma - mi
        if (range <= 1e-6f) {
            return
        }
        val inv = 1f / range
        for (i in v.indices) {
            v[i] = (v[i] - mi) * inv
        }
    }

    override fun close() {
        synchronized(nativeLock) {
            if (closed) return
            closed = true
            if (handle != 0L) {
                MnnSegNative.nativeDestroy(handle)
            }
        }
    }

    companion object {
        // ISNet-anime: (x/255 - 0.5)/1.0
        private val ANIME_MEAN = floatArrayOf(0.5f, 0.5f, 0.5f)
        private val ANIME_STD = floatArrayOf(1f, 1f, 1f)

        // u2net_human_seg: ImageNet mean/std
        private val HUMAN_MEAN = floatArrayOf(0.485f, 0.456f, 0.406f)
        private val HUMAN_STD = floatArrayOf(0.229f, 0.224f, 0.225f)

        fun createAnime(
            modelPath: String,
            backend: Int = MnnSegNative.BACKEND_VULKAN,
            threads: Int = 4,
        ): MnnImageSegmenter? = create(modelPath, ANIME_MEAN, ANIME_STD, backend, threads)

        fun createHuman(
            modelPath: String,
            backend: Int = MnnSegNative.BACKEND_VULKAN,
            threads: Int = 4,
        ): MnnImageSegmenter? = create(modelPath, HUMAN_MEAN, HUMAN_STD, backend, threads)

        private fun create(
            modelPath: String,
            mean: FloatArray,
            std: FloatArray,
            backend: Int,
            threads: Int,
        ): MnnImageSegmenter? {
            if (!MnnSegNative.isAvailable) {
                return null
            }
            val handle = MnnSegNative.nativeCreate(modelPath, backend, threads)
            if (handle == 0L) {
                return null
            }
            return MnnImageSegmenter(handle, mean, std)
        }
    }
}
