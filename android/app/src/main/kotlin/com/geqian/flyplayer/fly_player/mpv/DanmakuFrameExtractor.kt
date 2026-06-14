package com.geqian.flyplayer.fly_player.mpv

import android.graphics.Bitmap
import android.media.Image
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.SystemClock
import android.util.Log
import java.nio.ByteBuffer

/**
 * Plan B foundation: a standalone MediaCodec-based video frame extractor used to
 * decode frames AHEAD of playback so the occlusion mask can be precomputed and
 * applied PTS-synced (no live-capture latency).
 *
 * Decodes WITHOUT an output surface (raw YUV output buffers), pulls each frame via
 * [MediaCodec.getOutputImage] (YUV_420_888) and converts/downscales to an RGB
 * Bitmap at the segmenter's input size. Not thread-safe; use from a single worker
 * thread. Works on local file paths and http(s) URLs (NAS proxy) that are seekable.
 *
 * B1 scope: [extractFrameAt] seeks to the nearest prior sync sample and decodes
 * forward to the requested PTS. Sequential ahead-decode (avoiding re-seeks) is a
 * later optimization (B2/B5).
 */
class DanmakuFrameExtractor : AutoCloseable {
    private var extractor: MediaExtractor? = null
    private var codec: MediaCodec? = null
    private var videoTrack = -1
    private var sourceWidth = 0
    private var sourceHeight = 0
    private var lastDecodedUs = -1L

    val isOpen: Boolean
        get() = codec != null && extractor != null

    // Display aspect (w/h) of the decoded video, for mapping the full-frame mask to the
    // letterboxed video rect in the view. 0 if unknown/not open.
    val frameAspectRatio: Float
        get() = if (sourceWidth > 0 && sourceHeight > 0) sourceWidth.toFloat() / sourceHeight.toFloat() else 0f

    fun open(
        url: String,
        headers: Map<String, String>? = null,
    ): Boolean {
        close()
        return runCatching {
            val ex = MediaExtractor()
            if (headers.isNullOrEmpty()) {
                ex.setDataSource(url)
            } else {
                ex.setDataSource(url, headers)
            }
            var track = -1
            var format: MediaFormat? = null
            for (i in 0 until ex.trackCount) {
                val f = ex.getTrackFormat(i)
                val mime = f.getString(MediaFormat.KEY_MIME).orEmpty()
                if (mime.startsWith("video/")) {
                    track = i
                    format = f
                    break
                }
            }
            if (track < 0 || format == null) {
                ex.release()
                return@runCatching false
            }
            ex.selectTrack(track)
            sourceWidth = format.getInteger(MediaFormat.KEY_WIDTH)
            sourceHeight = format.getInteger(MediaFormat.KEY_HEIGHT)
            val mime = format.getString(MediaFormat.KEY_MIME)!!
            val dec = MediaCodec.createDecoderByType(mime)
            // null surface -> raw YUV output buffers (getOutputImage gives YUV_420_888).
            dec.configure(format, null, null, 0)
            dec.start()
            extractor = ex
            codec = dec
            videoTrack = track
            lastDecodedUs = -1L
            Log.i(TAG, "open ok ${sourceWidth}x$sourceHeight mime=$mime url=${url.take(80)}")
            true
        }.getOrElse { e ->
            Log.w(TAG, "open failed url=${url.take(80)}", e)
            close()
            false
        }
    }

    /**
     * Decode and return the first frame with PTS >= [targetUs], downscaled to
     * [outWidth]x[outHeight] RGB. Returns null on failure/EOS.
     */
    fun extractFrameAt(
        targetUs: Long,
        outWidth: Int,
        outHeight: Int,
    ): Bitmap? {
        val ex = extractor ?: return null
        val dec = codec ?: return null
        val startMs = SystemClock.elapsedRealtime()

        // Only re-seek when going backwards or jumping far; sequential forward decode
        // is cheap and avoids keyframe re-seek cost.
        if (lastDecodedUs < 0 || targetUs < lastDecodedUs || targetUs - lastDecodedUs > SEQUENTIAL_GAP_US) {
            ex.seekTo(targetUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            dec.flush()
        }

        val info = MediaCodec.BufferInfo()
        var inputDone = false
        var iterations = 0
        var forcedSeek = false
        while (iterations++ < MAX_ITERATIONS) {
            // Anti-spiral: if we've been grinding frames forward for too long (HW
            // decoder contention with mpv), abandon the sequential catch-up and jump
            // to the sync sample just before the target. Caps the worst case at one
            // keyframe→target decode instead of decoding every intermediate frame.
            if (!forcedSeek && SystemClock.elapsedRealtime() - startMs > FORCE_SEEK_BUDGET_MS) {
                forcedSeek = true
                ex.seekTo(targetUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
                dec.flush()
                inputDone = false
            }
            if (!inputDone) {
                val inIndex = dec.dequeueInputBuffer(DEQUEUE_TIMEOUT_US)
                if (inIndex >= 0) {
                    val inBuf = dec.getInputBuffer(inIndex)
                    val sampleSize = if (inBuf != null) ex.readSampleData(inBuf, 0) else -1
                    if (sampleSize < 0) {
                        dec.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                    } else {
                        dec.queueInputBuffer(inIndex, 0, sampleSize, ex.sampleTime, 0)
                        ex.advance()
                    }
                }
            }

            val outIndex = dec.dequeueOutputBuffer(info, DEQUEUE_TIMEOUT_US)
            if (outIndex >= 0) {
                val ptsUs = info.presentationTimeUs
                val isEos = (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                val reached = ptsUs >= targetUs - PTS_TOLERANCE_US
                if (reached && info.size > 0) {
                    val bitmap =
                        runCatching {
                            val image = dec.getOutputImage(outIndex)
                            if (image != null) {
                                yuvImageToBitmap(image, outWidth, outHeight)
                            } else {
                                null
                            }
                        }.getOrNull()
                    dec.releaseOutputBuffer(outIndex, false)
                    lastDecodedUs = ptsUs
                    if (bitmap != null) {
                        Log.d(
                            TAG,
                            "frame target=${targetUs / 1000}ms got=${ptsUs / 1000}ms " +
                                "in=${SystemClock.elapsedRealtime() - startMs}ms",
                        )
                        return bitmap
                    }
                } else {
                    dec.releaseOutputBuffer(outIndex, false)
                }
                if (isEos) {
                    return null
                }
            } else if (outIndex == MediaCodec.INFO_TRY_AGAIN_LATER && inputDone) {
                // draining with no more output
                return null
            }
        }
        Log.w(TAG, "extractFrameAt hit iteration cap target=${targetUs / 1000}ms")
        return null
    }

    private fun yuvImageToBitmap(
        image: Image,
        outWidth: Int,
        outHeight: Int,
    ): Bitmap {
        val w = sourceWidth.coerceAtLeast(1)
        val h = sourceHeight.coerceAtLeast(1)
        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]
        val yBuf: ByteBuffer = yPlane.buffer
        val uBuf: ByteBuffer = uPlane.buffer
        val vBuf: ByteBuffer = vPlane.buffer
        val yRow = yPlane.rowStride
        val yPix = yPlane.pixelStride
        val uRow = uPlane.rowStride
        val uPix = uPlane.pixelStride
        val vRow = vPlane.rowStride
        val vPix = vPlane.pixelStride

        val pixels = IntArray(outWidth * outHeight)
        var idx = 0
        for (oy in 0 until outHeight) {
            val sy = (oy * h / outHeight).coerceIn(0, h - 1)
            val uvY = sy / 2
            for (ox in 0 until outWidth) {
                val sx = (ox * w / outWidth).coerceIn(0, w - 1)
                val uvX = sx / 2
                val y = yBuf.get(sy * yRow + sx * yPix).toInt() and 0xFF
                val u = (uBuf.get(uvY * uRow + uvX * uPix).toInt() and 0xFF) - 128
                val v = (vBuf.get(uvY * vRow + uvX * vPix).toInt() and 0xFF) - 128
                // BT.601 YUV -> RGB
                val r = (y + ((91881 * v) shr 16)).coerceIn(0, 255)
                val g = (y - ((22554 * u + 46802 * v) shr 16)).coerceIn(0, 255)
                val b = (y + ((116130 * u) shr 16)).coerceIn(0, 255)
                pixels[idx++] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
            }
        }
        image.close()
        return Bitmap.createBitmap(pixels, outWidth, outHeight, Bitmap.Config.ARGB_8888)
    }

    override fun close() {
        runCatching { codec?.stop() }
        runCatching { codec?.release() }
        runCatching { extractor?.release() }
        codec = null
        extractor = null
        videoTrack = -1
        lastDecodedUs = -1L
    }

    private companion object {
        const val TAG = "FlyPlayerFrameExtract"
        const val DEQUEUE_TIMEOUT_US = 10_000L
        const val PTS_TOLERANCE_US = 20_000L // accept frames within 20ms of target
        const val SEQUENTIAL_GAP_US = 1_000_000L // re-seek if jumping >1s forward
        const val FORCE_SEEK_BUDGET_MS = 450L // grind budget before forcing a seek
        const val MAX_ITERATIONS = 600
    }
}
