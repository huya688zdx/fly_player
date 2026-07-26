package com.geqian.flyplayer.fly_player.mpv

import android.graphics.Bitmap
import android.graphics.Color
import android.os.Handler
import android.os.HandlerThread
import android.os.Process
import android.os.SystemClock
import android.util.Log
import kotlin.math.abs

/**
 * Plan B v2 — producer pipeline (Phase A).
 *
 * Decodes video frames AHEAD of playback on its own background thread, runs the
 * segmentation runtime on a fixed STEP grid (~280ms of video time per mask), and
 * hands each finished mask to [onStep] tagged with the video PTS it belongs to.
 *
 * Why a separate pipeline (see docs/danmaku-occlusion-planb-v2-plan.md):
 *  - The old path (DanmakuDynamicOcclusion sampler) produced ONE mask per backoff
 *    interval (450–700ms) → PTS buffer too sparse → ±350ms alignment error, lag,
 *    residue. Moving inference off the realtime path AND raising mask density to
 *    one per ~280ms is what actually fixes latency/residue/tracking together.
 *  - Sequential decode (never re-seeking to chase a moving target) is far friendlier
 *    to the HW decoder than the old per-sample seek-one-frame-discard pattern.
 *
 * Threading: everything runs on a single background [HandlerThread]; [onStep] is
 * invoked on that thread — the caller is responsible for hopping to the main thread
 * before touching the overlay. Not reused across flavors that lack MNN: if the
 * runtime fails to create the pipeline simply never produces (clean no-op).
 *
 * Phase A scope: density + per-step velocity/sceneCut metadata + static reuse.
 * Empty steps (no subject / over-cap) are emitted as [MaskStep] with `mask == null`;
 * the renderer-side handling of them (clear-without-grace) lands in Phase B/C.
 */
class DanmakuMaskPrecomputePipeline(
    private val runtimeFactory: DanmakuSegmentationRuntimeFactory,
    private val configProvider: () -> DanmakuDynamicOcclusionConfig,
    private val positionMsProvider: () -> Long,
    private val playbackSpeedProvider: () -> Double,
    private val decodeSourceProvider: () -> DanmakuPlanBDecodeSource?,
    private val onStep: (MaskStep) -> Unit,
    private val onSourceFailure: (DanmakuPlanBDecodeSource, String) -> Unit,
) {
    /**
     * One produced mask on the video timeline. [mask] is a freshly-allocated ARGB
     * bitmap (alpha = mask coverage) owned by the consumer once handed over; `null`
     * means "this PTS has no occlusion" (no subject, or subject filled the frame).
     */
    class MaskStep(
        val ptsMs: Long,
        val mask: Bitmap?,
        val maskWidth: Int,
        val maskHeight: Int,
        val vxPerMs: Double,
        val vyPerMs: Double,
        val sceneCut: Boolean,
        val videoAspect: Double,
        val stepMs: Long,
        val inputWidth: Int,
        val reused: Boolean,
    )

    // NOT THREAD_PRIORITY_BACKGROUND: that bucket lands the thread (and the MNN worker
    // threads it spawns — child threads inherit the parent's cpuset at creation) in the
    // throttled "background" cpuset with a tiny CPU share. 384 inference was light enough
    // to fit; 512 isn't, so under the throttle a ~450ms inference spiralled to 6–13s on
    // device (buffer drains → back-to-back catch-up → throttle → worse). A foreground-cpuset
    // priority slightly below DEFAULT keeps inference fast while UI/render threads (DISPLAY
    // priority, more favorable) still preempt it, so it can't jank playback.
    private val thread =
        HandlerThread(
            "FlyPlayerMaskPipeline",
            Process.THREAD_PRIORITY_DEFAULT + Process.THREAD_PRIORITY_LESS_FAVORABLE,
        ).apply { start() }
    private val handler = Handler(thread.looper)

    @Volatile
    private var released = false

    // Producing = the tick loop is armed. Paused/idle does not produce but keeps the
    // decoder + runtime warm so resume is cheap.
    @Volatile
    private var producing = false

    // --- resources (created lazily on the pipeline thread) ---
    private var runtime: DanmakuSegmentationRuntime? = null
    private var extractor: DanmakuFrameExtractor? = null
    private var extractorSource: DanmakuPlanBDecodeSource? = null
    private var firstFrameStartedAtMs = 0L

    // --- production cursor (pipeline thread only) ---
    private var nextStepMs = -1L // next video PTS to produce; <0 = needs prime
    private var lastProducedPtsMs = -1L
    private var primePosMs = -1L
    private var stepMs = STEP_MS_DEFAULT
    private var stepBudgetEmaMs = STEP_BUDGET_SEED_MS

    // --- static reuse + motion (pipeline thread only) ---
    private var prevLumaGrid: IntArray? = null
    private var inferredLumaGrid: IntArray? = null
    private var consecutiveReuse = 0
    private var lastMaskValues: FloatArray? = null
    private var lastMaskWidth = 0
    private var lastMaskHeight = 0
    // E3: last real-inference foreground centroid (normalized, -1 = invalid) + its PTS and
    // ratio, for Δcentroid/Δt velocity.
    private var lastCentroidX = -1f
    private var lastCentroidY = -1f
    private var lastCentroidPtsMs = -1L
    private var lastForegroundRatio = 0f
    // Hysteresis: once a mask is active, hold it through small foreground-ratio dips/spikes
    // so a subject hovering near MIN/MAX doesn't flip the mask on/off frame-to-frame.
    private var maskActive = false
    // Anti-blip: consecutive null inferences inside a continuous shot (no scene cut).
    // A SINGLE out-of-gate result while the previous step had a subject is far more
    // likely model jitter than the subject actually leaving — device logs showed isolated
    // one-step empties in static shots, each punching a ~450ms hole in the renderer's
    // PTS buffer (mask off → danmaku flashes over the subject → on again). Carry the
    // previous mask through up to EMPTY_DEBOUNCE_STEPS such steps; sustained emptiness
    // or a scene cut clears immediately (no residue risk across cuts).
    private var emptyStreak = 0

    // Explicit Runnable types: tick and tickReschedule reference each other, so type
    // inference would otherwise recurse ("recursive problem").
    private val tick: Runnable =
        Runnable {
            if (released || !producing) return@Runnable
            runCatching { produceOnce() }
                .onFailure { Log.w(TAG, "produce step failed", it) }
            if (!released && producing) {
                handler.post(tickReschedule)
            }
        }

    // Indirection so a long idle (buffer full) reschedules with a delay without
    // re-entering produceOnce immediately.
    private val tickReschedule: Runnable =
        Runnable {
            if (released || !producing) return@Runnable
            val pos = positionMsProvider()
            val aheadMs = if (pos >= 0L && lastProducedPtsMs >= 0L) lastProducedPtsMs - pos else 0L
            val aheadCap = aheadMaxMs()
            if (aheadMs >= aheadCap) {
                handler.postDelayed(tick, IDLE_TICK_MS)
            } else {
                handler.post(tick)
            }
        }

    /** Start or resume producing. Safe to call repeatedly. */
    fun start() {
        if (released) return
        handler.post {
            if (released) return@post
            if (!producing) {
                producing = true
                // Force a fresh prime against the current position on (re)start.
                nextStepMs = -1L
            }
            handler.removeCallbacks(tick)
            handler.removeCallbacks(tickReschedule)
            handler.post(tick)
        }
    }

    /** Stop producing but keep the decoder + runtime warm. */
    fun pause() {
        if (released) return
        handler.post {
            producing = false
            handler.removeCallbacks(tick)
            handler.removeCallbacks(tickReschedule)
        }
    }

    /** Tear down everything and quit the thread. */
    fun release() {
        if (released) return
        released = true
        producing = false
        handler.removeCallbacksAndMessages(null)
        handler.post {
            runCatching { extractor?.close() }
            extractor = null
            runCatching { runtime?.close() }
            runtime = null
            lastMaskValues = null
            prevLumaGrid = null
            inferredLumaGrid = null
        }
        thread.quitSafely()
    }

    // --- pipeline thread ---

    private fun aheadMaxMs(): Long {
        val speed = playbackSpeedProvider().takeIf { it.isFinite() && it > 0.0 } ?: 1.0
        return (AHEAD_MAX_MS * speed).toLong().coerceIn(AHEAD_MAX_MS, AHEAD_MAX_HARD_CAP_MS)
    }

    private fun ensureRuntime(): DanmakuSegmentationRuntime? {
        runtime?.let { return it }
        val cfg = configProvider()
        if (!cfg.enabled) return null
        if (!runtimeFactory.shouldAttempt(DanmakuAiBackend.PADDLE)) return null
        val created =
            runCatching { runtimeFactory.create(DanmakuAiBackend.PADDLE, cfg) }
                .onFailure { Log.w(TAG, "seg runtime create failed", it) }
                .getOrNull()
        runtime = created
        return created
    }

    private fun ensureExtractor(): DanmakuFrameExtractor? {
        val source = decodeSourceProvider() ?: return null
        val existing = extractor
        if (existing != null && existing.isOpen && extractorSource == source) {
            return existing
        }
        existing?.close()
        val next = DanmakuFrameExtractor()
        val openStartedAtMs = SystemClock.elapsedRealtime()
        if (!next.open(source.url, source.headers)) {
            next.close()
            extractor = null
            extractorSource = null
            producing = false
            onSourceFailure(source, "open_failed")
            return null
        }
        extractor = next
        extractorSource = source
        firstFrameStartedAtMs = openStartedAtMs
        nextStepMs = -1L
        prevLumaGrid = null
        inferredLumaGrid = null
        lastMaskValues = null
        consecutiveReuse = 0
        return next
    }

    private fun produceOnce() {
        val pos = positionMsProvider()
        if (pos < 0L) {
            // Position unknown yet — back off briefly without producing.
            scheduleIdle()
            return
        }
        val runtime = ensureRuntime() ?: run { scheduleIdle(); return }
        val extractor = ensureExtractor() ?: run { scheduleIdle(); return }

        // Seek / first-prime detection: if our cursor is unset, fell behind playback,
        // or playback jumped backward, re-prime from just ahead of the current pos.
        val sceneCutFromSeek = maybeReprime(pos)

        // Pacing: stop producing once the buffer comfortably covers the lookahead.
        val aheadMs = if (lastProducedPtsMs >= 0L) lastProducedPtsMs - pos else Long.MIN_VALUE
        if (aheadMs >= aheadMaxMs()) {
            scheduleIdle()
            return
        }

        val targetMs = nextStepMs
        val startedAt = SystemClock.elapsedRealtime()
        val inW = runtime.inputWidth
        val inH = runtime.inputHeight
        val frame =
            runCatching { extractor.extractFrameAt(targetMs * 1000L, inW, inH) }
                .onFailure { Log.w(TAG, "decode failed target=${targetMs}ms", it) }
                .getOrNull()
        if (frame == null) {
            val failedSource = extractorSource
            if (firstFrameStartedAtMs > 0L && failedSource != null) {
                producing = false
                onSourceFailure(failedSource, "first_frame_failed")
                return
            }
            scheduleIdle()
            return
        }
        if (firstFrameStartedAtMs > 0L) {
            val firstFrameMs = SystemClock.elapsedRealtime() - firstFrameStartedAtMs
            val source = extractorSource
            if (source?.isNetworkProxy == true && firstFrameMs > NETWORK_FIRST_FRAME_TIMEOUT_MS) {
                frame.takeIf { !it.isRecycled }?.recycle()
                producing = false
                onSourceFailure(source, "first_frame_timeout_${firstFrameMs}ms")
                return
            }
            firstFrameStartedAtMs = 0L
        }

        val grid = sampleLumaGrid(frame)
        val sceneCut = sceneCutFromSeek || detectSceneCut(prevLumaGrid, grid)
        // E2: how much changed since the previous STEP frame → drives motion-adaptive step.
        val highMotion = !sceneCut && changedCellCount(prevLumaGrid, grid) >= MOTION_SHRINK_CELLS

        val reuse =
            !sceneCut &&
                lastMaskValues != null &&
                consecutiveReuse < STATIC_MAX_REUSE &&
                isStatic(inferredLumaGrid, grid)

        // E3: per-step velocity = Δ(foreground centroid)/Δt — tracks the masked SUBJECT
        // (works for both person motion and camera pan), not the camera's global luma shift.
        var vx = 0.0
        var vy = 0.0
        var carried = false
        val maskValues: FloatArray?
        val maskW: Int
        val maskH: Int
        if (reuse) {
            // Static → subject isn't moving → zero velocity; keep the last real centroid.
            maskValues = lastMaskValues
            maskW = lastMaskWidth
            maskH = lastMaskHeight
            consecutiveReuse += 1
        } else {
            val built =
                runCatching { buildMask(runtime.run(frame)) }
                    .onFailure { Log.w(TAG, "seg run failed", it) }
                    .getOrNull()
            if (built != null) {
                emptyStreak = 0
                val dt = targetMs - lastCentroidPtsMs
                val ratioJump =
                    if (lastForegroundRatio > 1e-3f) {
                        abs(built.ratio - lastForegroundRatio) / lastForegroundRatio
                    } else {
                        Float.MAX_VALUE
                    }
                if (lastCentroidX >= 0f && dt in 1L..1500L && !sceneCut && ratioJump <= CENTROID_RATIO_JUMP) {
                    vx = (built.centroidX - lastCentroidX).toDouble() / dt.toDouble()
                    vy = (built.centroidY - lastCentroidY).toDouble() / dt.toDouble()
                }
                lastCentroidX = built.centroidX
                lastCentroidY = built.centroidY
                lastCentroidPtsMs = targetMs
                lastForegroundRatio = built.ratio
                maskValues = built.values
                maskW = built.width
                maskH = built.height
                lastMaskValues = maskValues
                lastMaskWidth = maskW
                lastMaskHeight = maskH
                inferredLumaGrid = grid
                consecutiveReuse = 0
            } else if (!sceneCut && lastMaskValues != null && emptyStreak < EMPTY_DEBOUNCE_STEPS) {
                // Anti-blip carry-over: isolated null inside a continuous shot → keep the
                // previous mask this step. Deliberately does NOT touch inferredLumaGrid /
                // lastMaskValues: a static scene then keeps the mask alive via plain reuse
                // (correct for a model blip), while a真离场 scene keeps re-inferring (frames
                // change → no reuse) and clears once the streak exceeds the debounce.
                // Counts toward STATIC_MAX_REUSE so a spurious mask still re-validates.
                carried = true
                emptyStreak += 1
                maskValues = lastMaskValues
                maskW = lastMaskWidth
                maskH = lastMaskHeight
                consecutiveReuse += 1
            } else {
                // No subject (sustained / across a cut) → clear and invalidate tracking.
                emptyStreak = 0
                lastCentroidX = -1f
                lastCentroidPtsMs = -1L
                lastForegroundRatio = 0f
                maskValues = null
                maskW = 0
                maskH = 0
                lastMaskValues = null
                lastMaskWidth = 0
                lastMaskHeight = 0
                inferredLumaGrid = grid
                consecutiveReuse = 0
            }
        }
        maskActive = maskValues != null
        frame.takeIf { !it.isRecycled }?.recycle()

        prevLumaGrid = grid

        val maskBitmap =
            if (maskValues != null && maskW > 0 && maskH > 0) {
                buildMaskBitmap(maskW, maskH, maskValues)
            } else {
                null
            }

        val totalMs = SystemClock.elapsedRealtime() - startedAt
        if (!reuse) {
            // Track real inference cost (EMA) so the step never drops below what inference
            // can sustain.
            stepBudgetEmaMs = (stepBudgetEmaMs * 0.7) + (totalMs.toDouble() * 0.3)
        }
        // E2: shrink the step toward STEP_MS_MIN while the scene is moving (narrower bracket
        // "swept band" → tighter occlusion), relax to default when quiet; budget caps it.
        adaptStep(highMotion)

        lastProducedPtsMs = targetMs
        nextStepMs = targetMs + stepMs

        if (DEBUG_LOG) {
            Log.d(
                TAG,
                "planb2 pts=${targetMs}ms pos=${pos}ms ahead=${targetMs - pos}ms step=${stepMs}ms " +
                    "reuse=$reuse carry=$carried empty=${maskBitmap == null} sceneCut=$sceneCut " +
                    "vx=${"%.5f".format(vx)} vy=${"%.5f".format(vy)} ms=$totalMs",
            )
        }

        val step =
            MaskStep(
                ptsMs = targetMs,
                mask = maskBitmap,
                maskWidth = maskW,
                maskHeight = maskH,
                vxPerMs = vx,
                vyPerMs = vy,
                sceneCut = sceneCut,
                videoAspect = extractor.frameAspectRatio.toDouble(),
                stepMs = stepMs,
                inputWidth = inW,
                reused = reuse,
            )
        if (!released) {
            onStep(step)
        } else {
            maskBitmap?.takeIf { !it.isRecycled }?.recycle()
        }
    }

    private fun scheduleIdle() {
        if (released || !producing) return
        handler.removeCallbacks(tick)
        handler.removeCallbacks(tickReschedule)
        handler.postDelayed(tick, IDLE_TICK_MS)
    }

    // Returns true if this prime constitutes a discontinuity (seek) → the next mask
    // should be marked sceneCut so the renderer doesn't extrapolate across it.
    private fun maybeReprime(posMs: Long): Boolean {
        val needPrime =
            nextStepMs < 0L ||
                primePosMs < 0L ||
                posMs < primePosMs - SEEK_BACK_TOLERANCE_MS ||
                (lastProducedPtsMs in 0 until posMs) // playback overran the buffer
        if (!needPrime) return false
        nextStepMs = posMs + PRIME_AHEAD_MS
        lastProducedPtsMs = -1L
        primePosMs = posMs
        prevLumaGrid = null
        inferredLumaGrid = null
        lastMaskValues = null
        consecutiveReuse = 0
        maskActive = false
        emptyStreak = 0
        lastCentroidX = -1f
        lastCentroidPtsMs = -1L
        lastForegroundRatio = 0f
        return true
    }

    private fun adaptStep(highMotion: Boolean) {
        // Motion sets the target floor (140ms moving / 280ms quiet); budget raises it so a
        // step is never shorter than a real inference can sustain (budget has priority).
        val motionFloor = if (highMotion) STEP_MS_MIN else STEP_MS_DEFAULT
        val budgetMin = (stepBudgetEmaMs / STEP_SUSTAIN_RATIO).toLong()
        stepMs = maxOf(motionFloor, budgetMin).coerceIn(STEP_MS_MIN, STEP_MS_MAX)
    }

    // --- mask building (mirrors DanmakuDynamicOcclusion.buildFullFrameMaskResult) ---

    private class RawMask(
        val values: FloatArray,
        val width: Int,
        val height: Int,
        // E3: normalized [0,1] foreground centroid + ratio, for per-person velocity.
        val centroidX: Float,
        val centroidY: Float,
        val ratio: Float,
    )

    private fun buildMask(output: DanmakuSegmentationOutput): RawMask? {
        val w = output.width
        val h = output.height
        val values = output.maskValues
        if (w <= 0 || h <= 0 || values.size < w * h) return null
        // Count foreground AND accumulate its centroid in one pass.
        var foreground = 0
        var sumX = 0L
        var sumY = 0L
        var idx = 0
        for (y in 0 until h) {
            for (x in 0 until w) {
                if (values[idx] >= MASK_THRESHOLD) {
                    foreground += 1
                    sumX += x
                    sumY += y
                }
                idx += 1
            }
        }
        val ratio = foreground.toFloat() / (w * h).toFloat()
        // Hysteresis around MIN/MAX: when a mask is already active, require the ratio to fall
        // further (or rise higher) before turning it off — stops on/off flicker at the edges.
        val minGate = if (maskActive) MIN_FOREGROUND_RATIO - MIN_FOREGROUND_RATIO_HYST else MIN_FOREGROUND_RATIO
        val maxGate = if (maskActive) MAX_FOREGROUND_RATIO + MAX_FOREGROUND_RATIO_HYST else MAX_FOREGROUND_RATIO
        if (ratio < minGate) return null // scenery / no subject
        if (ratio > maxGate) return null // near-full-screen subject → leave danmaku readable
        val mask = FloatArray(w * h)
        val low = MASK_EDGE_LOW
        val span = (MASK_EDGE_HIGH - low).coerceAtLeast(1e-4f)
        for (i in 0 until w * h) {
            mask[i] = ((values[i] - low) / span).coerceIn(0f, 1f)
        }
        val cx = if (foreground > 0) sumX.toFloat() / foreground / w else 0.5f
        val cy = if (foreground > 0) sumY.toFloat() / foreground / h else 0.5f
        return RawMask(mask, w, h, cx, cy, ratio)
    }

    private fun buildMaskBitmap(width: Int, height: Int, values: FloatArray): Bitmap {
        val pixels = IntArray(width * height)
        for (i in pixels.indices) {
            val alpha = (values[i].coerceIn(0f, 1f) * 255f).toInt().coerceIn(0, 255)
            pixels[i] = Color.argb(alpha, 255, 255, 255)
        }
        return Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
    }

    // --- motion / static detection (mirrors DanmakuDynamicOcclusion helpers) ---

    private fun sampleLumaGrid(bitmap: Bitmap): IntArray {
        val w = MOTION_GRID_W
        val h = MOTION_GRID_H
        val scaled =
            if (bitmap.width == w && bitmap.height == h) bitmap else Bitmap.createScaledBitmap(bitmap, w, h, true)
        val pixels = IntArray(w * h)
        scaled.getPixels(pixels, 0, w, 0, 0, w, h)
        if (scaled !== bitmap && !scaled.isRecycled) scaled.recycle()
        val luma = IntArray(w * h)
        for (i in luma.indices) {
            val c = pixels[i]
            val r = (c ushr 16) and 0xFF
            val g = (c ushr 8) and 0xFF
            val b = c and 0xFF
            luma[i] = ((r * 77) + (g * 150) + (b * 29)) shr 8
        }
        return luma
    }

    // Number of grid cells whose luma changed appreciably vs the previous frame (-1 if no
    // comparable previous grid). Used by E2 motion detection.
    private fun changedCellCount(prev: IntArray?, curr: IntArray): Int {
        if (prev == null || prev.size != curr.size || prev.isEmpty()) return -1
        var changed = 0
        for (i in curr.indices) {
            if (abs(prev[i] - curr[i]) >= STATIC_CELL_DIFF) changed += 1
        }
        return changed
    }

    // Static when few cells changed appreciably — a max/count rule, NOT a frame-mean.
    // (The old mean-based rule froze masks on a small subject moving over a big static
    // background; that was the root cause of "small motion not tracked".)
    private fun isStatic(prev: IntArray?, curr: IntArray): Boolean {
        if (prev == null || prev.size != curr.size || prev.isEmpty()) return false
        var changed = 0
        for (i in curr.indices) {
            if (abs(prev[i] - curr[i]) >= STATIC_CELL_DIFF) {
                changed += 1
                if (changed > STATIC_CHANGED_CELLS) return false
            }
        }
        return true
    }

    private fun detectSceneCut(prev: IntArray?, curr: IntArray): Boolean {
        if (prev == null || prev.size != curr.size || prev.isEmpty()) return false
        var sum = 0L
        for (i in curr.indices) sum += abs(prev[i] - curr[i])
        val mean = sum.toFloat() / curr.size.toFloat()
        return mean >= SCENE_CUT_LUMA_DIFF
    }

    private companion object {
        const val TAG = "FlyPlayerMaskPipeline"
        const val DEBUG_LOG = true
        const val NETWORK_FIRST_FRAME_TIMEOUT_MS = 5_000L

        // Step grid (video ms per produced mask). Quiet scenes sit at DEFAULT; motion
        // shrinks toward MIN (E2); a real inference's cost (EMA / SUSTAIN) raises the floor
        // so the step is never shorter than inference can keep up with. Seed the budget at a
        // typical 512 CPU inference so the initial step isn't inflated.
        const val STEP_MS_MIN = 140L
        const val STEP_MS_DEFAULT = 280L
        // Generous cap: with 512 inference (~450ms on a mid-range tablet) a 480 cap pinned
        // the duty cycle near 100% — the MNN threads then fight mpv/UI for CPU and latency
        // spirals to seconds (seen on device). The budget rule needs room to back off;
        // sparse masks beat a starved buffer + janky playback.
        const val STEP_MS_MAX = 960L
        const val STEP_SUSTAIN_RATIO = 0.8 // step >= budgetEma / this
        const val STEP_BUDGET_SEED_MS = 280.0
        const val MOTION_SHRINK_CELLS = 64 // changed cells (of 48×27) vs prev step ⇒ "moving"
        const val CENTROID_RATIO_JUMP = 0.30f // foreground ratio jump > this ⇒ velocity 0 (E3 anti-jitter)
        // Anti-blip: carry the previous mask through this many isolated null inferences
        // (continuous shot only). 1 bridges the single-step blips seen on device; a real
        // subject exit clears at most one step (~300ms) later.
        const val EMPTY_DEBOUNCE_STEPS = 1

        // Lookahead window. Buffer ahead this far (scaled by playback speed), then idle.
        const val AHEAD_MAX_MS = 2500L
        const val AHEAD_MAX_HARD_CAP_MS = 6000L
        const val PRIME_AHEAD_MS = 300L
        const val IDLE_TICK_MS = 48L
        const val SEEK_BACK_TOLERANCE_MS = 250L

        // Mask thresholds (mirror DanmakuDynamicOcclusion constants).
        const val MASK_THRESHOLD = 0.5f
        const val MIN_FOREGROUND_RATIO = 0.012f
        // Raised from 0.55: medium/large close-ups now get masked (carved → subject shows
        // through = 穿透) instead of flipping the mask off near the old boundary (which
        // flickered). Only a near-full-screen subject (> MAX) is left unmasked so danmaku
        // isn't carved into nothing. Paired with hysteresis below to stop boundary chatter.
        const val MAX_FOREGROUND_RATIO = 0.80f
        const val MAX_FOREGROUND_RATIO_HYST = 0.06f // sticky band once masking is active
        const val MIN_FOREGROUND_RATIO_HYST = 0.006f
        // Full opacity at >= MASK_THRESHOLD (0.5): subject pixels become FULLY erased
        // (no semi-transparent ghost over low-confidence regions like light hair). A thin
        // [LOW,HIGH] band stays soft for an anti-aliased contour, not a blocky edge.
        const val MASK_EDGE_LOW = 0.40f
        const val MASK_EDGE_HIGH = 0.50f

        // Motion / static detection grid.
        const val MOTION_GRID_W = 48
        const val MOTION_GRID_H = 27
        const val STATIC_CELL_DIFF = 14 // per-cell luma delta (0-255) that counts as "changed"
        const val STATIC_CHANGED_CELLS = 8 // > this many changed cells → not static
        const val STATIC_MAX_REUSE = 24 // re-infer at least this often (~7s) to avoid frozen drift
        const val SCENE_CUT_LUMA_DIFF = 38f // mean per-cell luma delta → treat as a cut
    }
}
