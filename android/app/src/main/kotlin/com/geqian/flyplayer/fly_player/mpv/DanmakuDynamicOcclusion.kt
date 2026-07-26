package com.geqian.flyplayer.fly_player.mpv

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.Locale
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sqrt

private const val DANMAKU_AI_TAG = "FlyPlayerDanmakuAI"
private const val DANMAKU_AI_PADDLE_MODEL_ASSET_DIR = "models/pp_humansegv2_lite"
private const val DANMAKU_AI_PADDLE_DETECTION_MODEL_ASSET_DIR = "models/picodet_s_320_coco_lcnet"
private const val DANMAKU_AI_DEFAULT_SAMPLE_INTERVAL_MS = 800L
private const val DANMAKU_AI_MIN_SAMPLE_INTERVAL_MS = 500L
private const val DANMAKU_AI_MAX_SAMPLE_INTERVAL_MS = 1200L
private const val DANMAKU_AI_DEFAULT_INPUT_WIDTH = 256
private const val DANMAKU_AI_DEFAULT_INPUT_HEIGHT = 144
private const val DANMAKU_AI_DEFAULT_SAMPLE_AREA_RATIO = 1.0f
private const val DANMAKU_AI_MASK_THRESHOLD = 0.18f
private const val DANMAKU_AI_RECT_HELPER_THRESHOLD = 0.30f
private const val DANMAKU_AI_MASK_SOFT_EDGE_START = 0.08f
private const val DANMAKU_AI_MASK_SOLID_CORE_START = 0.44f
private const val DANMAKU_AI_OUTPUT_MASK_HARD_THRESHOLD = 0.56f
private const val DANMAKU_AI_OUTPUT_MASK_KEEP_THRESHOLD = 0.34f
private const val DANMAKU_AI_MULTI_SECONDARY_OUTPUT_MASK_HARD_THRESHOLD = 0.52f
private const val DANMAKU_AI_MULTI_SECONDARY_OUTPUT_MASK_KEEP_THRESHOLD = 0.30f
private const val DANMAKU_AI_OUTPUT_MASK_DILATION_RADIUS = 1
private const val DANMAKU_AI_RENDER_MASK_EXPAND_RADIUS = 1
private const val DANMAKU_AI_RENDER_MASK_MIN_VISIBLE_ALPHA = 0.12f
private const val DANMAKU_AI_RENDER_MASK_SUPPORT_THRESHOLD = 0.22f
private const val DANMAKU_AI_RENDER_MASK_ALPHA_GAMMA = 0.72f
private const val DANMAKU_AI_RENDER_MASK_CLOSING_RADIUS = 1
private const val DANMAKU_AI_RENDER_MASK_MAX_AREA_MULTIPLIER = 1.22f
private const val DANMAKU_AI_RENDER_MASK_MIN_COMPONENT_AREA_RATIO = 0.08f
private const val DANMAKU_AI_MIN_FOREGROUND_RATIO = 0.010f
private const val DANMAKU_AI_SUBJECT_MIN_FILL_RATIO = 0.18f
private const val DANMAKU_AI_SUBJECT_MIN_ASPECT_RATIO = 0.22f
private const val DANMAKU_AI_SUBJECT_MAX_SPARSE_AREA_RATIO = 0.55f
private const val DANMAKU_AI_SUBJECT_MAX_SPARSE_HEIGHT_RATIO = 0.72f
private const val DANMAKU_AI_SUBJECT_MAX_AREA_RATIO = 0.34f
private const val DANMAKU_AI_SUBJECT_MAX_WIDTH_RATIO = 0.78f
private const val DANMAKU_AI_SUBJECT_MAX_HEIGHT_RATIO = 0.82f
private const val DANMAKU_AI_MASK_SHAPE_MIN_CORE_FILL_RATIO = 0.24f
private const val DANMAKU_AI_MASK_SHAPE_MIN_ERODED_RATIO = 0.30f
private const val DANMAKU_AI_MASK_SHAPE_EROSION_RADIUS = 1
private const val DANMAKU_AI_MASK_SHAPE_MAX_THIN_TOWER_WIDTH_RATIO = 0.20f
private const val DANMAKU_AI_MASK_SHAPE_MIN_THIN_TOWER_HEIGHT_RATIO = 0.52f
private const val DANMAKU_AI_MASK_SHAPE_MIN_THIN_TOWER_ASPECT_RATIO = 2.35f
private const val DANMAKU_AI_MASK_SHAPE_MAX_THIN_TOWER_AREA_RATIO = 0.12f
private const val DANMAKU_AI_MASK_SHAPE_MAX_TAPERED_SIDE_RATIO = 0.42f
private const val DANMAKU_AI_MASK_SHAPE_MAX_OVERALL_AREA_RATIO = 0.36f
private const val DANMAKU_AI_MASK_SHAPE_MAX_BOUNDING_WIDTH_RATIO = 0.80f
private const val DANMAKU_AI_MASK_SHAPE_MAX_BOUNDING_HEIGHT_RATIO = 0.84f
private const val DANMAKU_AI_MASK_SHAPE_MAX_HOLE_AREA_RATIO = 0.10f
private const val DANMAKU_AI_MASK_SHAPE_MAX_HOLE_COUNT = 2
private const val DANMAKU_AI_AMBIGUOUS_COMPONENT_MIN_PIXELS = 96
private const val DANMAKU_AI_AMBIGUOUS_SECOND_COMPONENT_RATIO = 0.60f
private const val DANMAKU_AI_AMBIGUOUS_MULTI_COMPONENT_COUNT = 4
private const val DANMAKU_AI_AMBIGUOUS_LARGEST_FOREGROUND_SHARE = 0.52f
private const val DANMAKU_AI_MAX_EMPTY_FRAMES = 4
private const val DANMAKU_AI_EMPTY_RESULT_GRACE_MS = 180L
private const val DANMAKU_AI_OVER_BUDGET_LIMIT = 3
private const val DANMAKU_AI_MASK_SMOOTHING_ALPHA = 0.72f
private const val DANMAKU_AI_RECT_SMOOTHING_ALPHA = 0.38f
private const val DANMAKU_AI_TEMPORAL_SMOOTHING_MIN_IOU = 0.28f
private const val DANMAKU_AI_SCENE_CUT_SAMPLE_WIDTH = 32
private const val DANMAKU_AI_SCENE_CUT_SAMPLE_HEIGHT = 18
private const val DANMAKU_AI_SCENE_CUT_AVERAGE_DELTA_THRESHOLD = 22.0
private const val DANMAKU_AI_SCENE_CUT_CHANGED_PIXEL_DELTA = 32
private const val DANMAKU_AI_SCENE_CUT_CHANGED_RATIO_THRESHOLD = 0.32
private const val DANMAKU_AI_SCENE_CUT_BURST_INTERVAL_MS = 180L
private const val DANMAKU_AI_SCENE_CUT_BURST_SAMPLE_COUNT = 3
private const val DANMAKU_AI_SCENE_CUT_STABLE_MASK_FRAMES = 2
private const val DANMAKU_AI_MOTION_BURST_INTERVAL_MS = 220L
private const val DANMAKU_AI_MOTION_BURST_SAMPLE_COUNT = 3
private const val DANMAKU_AI_MOTION_BURST_MAX_DEGRADATION_STAGE = 1
private const val DANMAKU_AI_MOTION_BURST_LATENCY_MULTIPLIER = 2.4
private const val DANMAKU_AI_MOTION_BURST_HEADROOM_MS = 60L
private const val DANMAKU_AI_MOTION_SAMPLE_WIDTH = 64
private const val DANMAKU_AI_MOTION_SAMPLE_HEIGHT = 36
private const val DANMAKU_AI_MOTION_ROI_EXPAND_HORIZONTAL_RATIO = 0.45f
private const val DANMAKU_AI_MOTION_ROI_EXPAND_VERTICAL_RATIO = 0.40f
private const val DANMAKU_AI_MOTION_FALLBACK_CENTER_WIDTH_RATIO = 0.34f
private const val DANMAKU_AI_MOTION_FALLBACK_CENTER_HEIGHT_RATIO = 0.34f
private const val DANMAKU_AI_MOTION_MIN_RECT_AREA = 0.018f
private const val DANMAKU_AI_MOTION_SEARCH_RADIUS_PX = 8
private const val DANMAKU_AI_MOTION_MAX_TRANSLATION_RATIO = 0.30f
private const val DANMAKU_AI_MOTION_MAX_AVERAGE_DELTA = 24.0
private const val DANMAKU_AI_MOTION_MIN_OVERLAP_SAMPLES = 48
private const val DANMAKU_AI_MOTION_MAX_FAILURES = 3
private const val DANMAKU_AI_MOTION_GATE_MIN_IOU = 0.32f
private const val DANMAKU_AI_MOTION_GATE_MAX_DX_NORMALIZED = 0.14f
private const val DANMAKU_AI_MOTION_GATE_MAX_DY_NORMALIZED = 0.12f
private const val DANMAKU_AI_MOTION_GATE_MIN_AREA_RATIO = 0.72f
private const val DANMAKU_AI_MOTION_GATE_MAX_AREA_RATIO = 1.30f
private const val DANMAKU_AI_MOTION_GATE_MAX_AVERAGE_DELTA = 21.5
private const val DANMAKU_AI_MOTION_MAX_CONSECUTIVE_COMPENSATED_FRAMES = 6
private const val DANMAKU_AI_MOTION_MISS_TEMPORAL_FALLBACK_MIN_IOU = 0.34f
private const val DANMAKU_AI_MOTION_PREDICTION_MAX_GAP_MS = 2200L
private const val DANMAKU_AI_MOTION_PREDICTION_DAMPING = 0.82f
private const val DANMAKU_AI_MOTION_PREDICTION_MAX_DX_NORMALIZED = 0.18f
private const val DANMAKU_AI_MOTION_PREDICTION_MAX_DY_NORMALIZED = 0.16f
private const val DANMAKU_AI_MOTION_PREDICTION_MIN_SCALE = 0.88f
private const val DANMAKU_AI_MOTION_PREDICTION_MAX_SCALE = 1.16f
private const val DANMAKU_AI_TRACKED_ROI_MIN_AREA_RATIO = 0.65f
private const val DANMAKU_AI_TRACKED_ROI_MAX_AREA_RATIO = 1.45f
private const val DANMAKU_AI_CACHE_DIR_NAME = "danmaku_ai_cache"
private const val DANMAKU_AI_CACHE_VERSION = 5
private const val DANMAKU_AI_CACHE_STATE_FILE_NAME = "state.json"
private const val DANMAKU_AI_CACHE_FRAME_FILE_NAME = "frame.webp"
private const val DANMAKU_AI_CACHE_MASK_FILE_NAME = "mask.webp"
private const val DANMAKU_AI_CACHE_FRAME_WRITE_INTERVAL_MS = 4000L
private const val DANMAKU_AI_CACHE_WARM_START_DELAY_MS = 2500L
private const val DANMAKU_AI_PLAYBACK_WARM_START_DELAY_MS = 1800L
private const val DANMAKU_AI_HIGH_REFRESH_SAMPLE_INTERVAL_72HZ_MS = 420L
private const val DANMAKU_AI_HIGH_REFRESH_SAMPLE_INTERVAL_90HZ_MS = 440L
private const val DANMAKU_AI_HIGH_REFRESH_SAMPLE_INTERVAL_120HZ_MS = 460L
private const val DANMAKU_AI_CAPTURE_SLOW_LOG_THRESHOLD_MS = 24L
private const val DANMAKU_AI_INFERENCE_SLOW_LOG_THRESHOLD_MS = 90L
private const val DANMAKU_AI_TOTAL_SLOW_LOG_THRESHOLD_MS = 120L
private const val DANMAKU_AI_SAMPLE_INTERVAL_BACKOFF_HEADROOM_MS = 120L
// 1.3 (was 6.0): with the fast MNN path we want the sample interval to track
// (latency + headroom), not 6x latency. 6x pinned the interval to MAX and added
// ~1s of staleness lag. Sustainable rate = process time + small headroom.
private const val DANMAKU_AI_SAMPLE_INTERVAL_LATENCY_MULTIPLIER = 1.3
private const val DANMAKU_AI_UNAVAILABLE_REASON_CAPTURE_UNSUPPORTED = "capture_unsupported"
private const val DANMAKU_AI_UNAVAILABLE_REASON_CAPTURE_BUDGET_UNSUPPORTED = "capture_budget_unsupported"
private const val DANMAKU_AI_DETECTION_SCORE_THRESHOLD = 0.30f
private const val DANMAKU_AI_MULTI_DETECTION_SCORE_THRESHOLD = 0.22f
private const val DANMAKU_AI_DETECTION_MIN_AREA_RATIO = 0.012f
private const val DANMAKU_AI_DETECTION_EXPAND_HORIZONTAL_RATIO = 0.10f
private const val DANMAKU_AI_DETECTION_EXPAND_VERTICAL_RATIO = 0.08f
private const val DANMAKU_AI_TRACKED_ROI_EXPAND_HORIZONTAL_RATIO = 0.04f
private const val DANMAKU_AI_TRACKED_ROI_EXPAND_VERTICAL_RATIO = 0.06f
private const val DANMAKU_AI_COARSE_DETECTION_AREA_RATIO = 0.72f
private const val DANMAKU_AI_COARSE_DETECTION_WIDTH_RATIO = 0.84f
private const val DANMAKU_AI_COARSE_DETECTION_HEIGHT_RATIO = 0.84f
private const val DANMAKU_AI_COARSE_DETECTION_EDGE_THRESHOLD = 0.03f
private const val DANMAKU_AI_DETECTION_STABILIZE_MAX_CENTER_DISTANCE = 0.28f
private const val DANMAKU_AI_DETECTION_STABILIZE_BLEND_ALPHA = 0.26f
private const val DANMAKU_AI_DETECTION_STABILIZE_MAX_GROWTH = 1.32f
private const val DANMAKU_AI_TRACKING_RECT_STABILIZE_BLEND_ALPHA = 0.22f
private const val DANMAKU_AI_TRACKING_RECT_MAX_GROWTH = 1.18f
private const val DANMAKU_AI_TRACKING_RECT_MAX_CENTER_DISTANCE = 0.32f
private const val DANMAKU_AI_SEGMENTATION_TARGET_ASPECT_RATIO = 16f / 9f
private const val DANMAKU_AI_TRACKING_MIN_IOU = 0.18f
private const val DANMAKU_AI_LARGE_MOTION_CANCEL_MAX_DX_NORMALIZED = 0.10f
private const val DANMAKU_AI_LARGE_MOTION_CANCEL_MAX_DY_NORMALIZED = 0.09f
private const val DANMAKU_AI_LARGE_MOTION_CANCEL_SCALE_DELTA = 0.10f
private const val DANMAKU_AI_LARGE_MOTION_CANCEL_MIN_AREA_RATIO = 0.58f
private const val DANMAKU_AI_LARGE_MOTION_CANCEL_MAX_AREA_RATIO = 1.72f
private const val DANMAKU_AI_LARGE_MOTION_CANCEL_MIN_IOU = 0.10f
private const val DANMAKU_AI_LARGE_MOTION_CANCEL_CENTER_DISTANCE = 0.16f
private const val DANMAKU_AI_LARGE_MOTION_CANCEL_DETECTION_AREA_RATIO = 0.80f
private const val DANMAKU_AI_LARGE_MOTION_CANCEL_DETECTION_WIDTH_RATIO = 0.88f
private const val DANMAKU_AI_LARGE_MOTION_CANCEL_DETECTION_HEIGHT_RATIO = 0.90f
private const val DANMAKU_AI_TARGET_CENTER_X = 0.5f
private const val DANMAKU_AI_TARGET_CENTER_Y = 0.42f
private const val DANMAKU_AI_DETECTION_WEIGHT_AREA = 0.35f
private const val DANMAKU_AI_DETECTION_WEIGHT_DISTANCE = 0.22f
private const val DANMAKU_AI_DETECTION_WEIGHT_SCORE = 0.65f
private const val DANMAKU_AI_REFINE_MIN_WIDTH = 256
private const val DANMAKU_AI_REFINE_MAX_WIDTH = 320
private const val DANMAKU_AI_REFINE_MIN_FOREGROUND_RATIO = 0.010f
private const val DANMAKU_AI_REFINE_MIN_BOX_COVERAGE = 0.10f
private const val DANMAKU_AI_REFINE_MIN_BOX_IOU = 0.08f
private const val DANMAKU_AI_MULTI_SECONDARY_REFINE_MIN_FOREGROUND_RATIO = 0.007f
private const val DANMAKU_AI_MULTI_SECONDARY_REFINE_MIN_BOX_COVERAGE = 0.06f
private const val DANMAKU_AI_MULTI_SECONDARY_REFINE_MIN_BOX_IOU = 0.04f
private const val DANMAKU_AI_CAPTURE_WIDTH = 320
private const val DANMAKU_AI_CAPTURE_HEIGHT = 320
// Phase 2: run the MNN segmenter (ISNet-anime) on the FULL captured frame and emit
// its foreground directly — no PicoDet detection, no ROI cropping, no small-multi,
// no PaddleSeg-tuned shape rejection. The model itself handles multi-person and
// scenery rejection. This is what makes anime masking work (PicoDet can't see anime).
private const val DANMAKU_AI_MNN_FULL_FRAME = true
private const val DANMAKU_AI_MNN_MASK_THRESHOLD = 0.5f
private const val DANMAKU_AI_MNN_MIN_FOREGROUND_RATIO = 0.012f
// Only a near-full-screen subject (> this) is left unmasked. Raised from 0.55 so
// medium/large close-ups still get masked (subject shows through = 穿透) instead of
// flickering the mask off near the old boundary. (Pipeline path mirrors this + hysteresis.)
private const val DANMAKU_AI_MNN_MAX_FOREGROUND_RATIO = 0.80f
// Alpha-steepening knee for the subject mask. Probabilities >= HIGH become fully
// opaque (interior fully erases danmaku — no faint imprint); [LOW,HIGH] is a thin
// soft edge so the contour stays precise (no dilation/blockiness); < LOW is dropped.
private const val DANMAKU_AI_MNN_MASK_EDGE_LOW = 0.40f
// Full opacity at >= MASK_THRESHOLD (0.5) so subject pixels fully erase danmaku (no
// semi-transparent ghost over low-confidence regions); [LOW,HIGH] stays a thin AA edge.
private const val DANMAKU_AI_MNN_MASK_EDGE_HIGH = 0.50f
// Static-scene skip thresholds. Mean per-cell luma diff (0-255) below this vs the last
// inferred frame ⇒ treat as static and reuse the last mask. Forced re-infer cadence
// bounds how long a (slowly drifting) scene can keep skipping.
private const val DANMAKU_AI_STATIC_SKIP_LUMA_DIFF = 3.2f
private const val DANMAKU_AI_STATIC_SKIP_MAX_CONSECUTIVE = 8
// Plan B: local files are served by the DanmakuMaskPrecomputePipeline (decode-ahead,
// PTS-synced). Network sources fall back to the live-capture path. This flag gates
// planBActive(), which routes local sources to the pipeline.
private const val DANMAKU_AI_PLAN_B = true
// Global frame-motion estimation (for between-sample mask extrapolation).
private const val DANMAKU_AI_MOTION_VEL_GRID_W = 48
private const val DANMAKU_AI_MOTION_VEL_GRID_H = 27
private const val DANMAKU_AI_MOTION_VEL_SEARCH = 6
private const val DANMAKU_AI_BASE_INPUT_WIDTH_60HZ = 288
private const val DANMAKU_AI_BASE_INPUT_WIDTH_90HZ = 256
private const val DANMAKU_AI_BASE_INPUT_WIDTH_120HZ = 224
private const val DANMAKU_AI_BASE_INPUT_WIDTH_60HZ_QUALITY = 320
private const val DANMAKU_AI_BASE_INPUT_WIDTH_90HZ_QUALITY = 288
private const val DANMAKU_AI_BASE_INPUT_WIDTH_120HZ_QUALITY = 256
private const val DANMAKU_AI_DEGRADED_INPUT_WIDTH = 160
private const val DANMAKU_AI_REDUCED_INPUT_WIDTH = 192
private const val DANMAKU_AI_HIGH_QUALITY_INPUT_WIDTH_THRESHOLD = 288
private const val DANMAKU_AI_MASK_SCALE_APPLY_THRESHOLD = 0.02f
private const val DANMAKU_AI_SCALE_RESCUE_EXPAND_RATIO = 0.12f
private const val DANMAKU_AI_SCALE_RESCUE_MIN_DELTA = 0.06f
private const val DANMAKU_AI_SCALE_RESCUE_LATENCY_HEADROOM_RATIO = 0.72
private const val DANMAKU_AI_DEGRADATION_INTERVAL_BACKOFF_MS = 180L
private const val DANMAKU_AI_DEGRADATION_RECOVERY_SAMPLES = 3
private const val DANMAKU_AI_DEGRADATION_RECOVERY_LATENCY_RATIO = 0.48
private const val DANMAKU_AI_TRACKED_DETECTION_REFRESH_INTERVAL_90HZ_MS = 1400L
private const val DANMAKU_AI_TRACKED_DETECTION_REFRESH_INTERVAL_120HZ_MS = 1700L
private const val DANMAKU_AI_TRACKED_DETECTION_REFRESH_INTERVAL_DEGRADED_MS = 2200L
private const val DANMAKU_AI_TRACKED_DETECTION_REFRESH_INTERVAL_STABLE_90HZ_MS = 1900L
private const val DANMAKU_AI_TRACKED_DETECTION_REFRESH_INTERVAL_STABLE_120HZ_MS = 2200L
private const val DANMAKU_AI_TRACKED_DETECTION_REFRESH_INTERVAL_WEAK_MS = 1200L
private const val DANMAKU_AI_TRACKED_DETECTION_MAX_CONSECUTIVE_SAMPLES = 1
private const val DANMAKU_AI_TRACKED_DETECTION_MAX_CONSECUTIVE_SAMPLES_DEGRADED = 2
private const val DANMAKU_AI_TRACKED_DETECTION_MAX_CONSECUTIVE_SAMPLES_STABLE = 3
private const val DANMAKU_AI_TRACKED_DETECTION_MAX_CONSECUTIVE_SAMPLES_WEAK = 1
private const val DANMAKU_AI_TRACKER_REUSE_MIN_CONFIDENCE = 0.72f
private const val DANMAKU_AI_TRACKER_REUSE_MAX_CENTER_DELTA = 0.18f
private const val DANMAKU_AI_TRACKER_REUSE_MAX_AREA_RATIO = 1.42f
private const val DANMAKU_AI_TRACKER_REUSE_MIN_AREA_RATIO = 0.70f
private const val DANMAKU_AI_TRACKER_WARMUP_STREAK = 2
private const val DANMAKU_AI_TRACKER_WEAK_STREAK = 2
private const val DANMAKU_AI_TRACKER_RECOVER_STREAK = 2
private const val DANMAKU_AI_TRACKER_LOST_STREAK = 2
private const val DANMAKU_AI_TRACKER_STABLE_MIN_CONFIDENCE = 0.79f
private const val DANMAKU_AI_TRACKER_WEAK_CONFIDENCE = 0.74f
private const val DANMAKU_AI_TRACKER_GEOMETRY_WEAK_PENALTY = 0.26f
private const val DANMAKU_AI_TRACKER_GEOMETRY_LOST_PENALTY = 0.44f
private const val DANMAKU_AI_TRACKER_DETECTION_MISMATCH_IOU = 0.22f
private const val DANMAKU_AI_TRACKER_DETECTION_MISMATCH_CENTER_DISTANCE = 0.18f
private const val DANMAKU_AI_PRIMARY_TARGET_CONTINUITY_MIN_IOU = 0.28f
private const val DANMAKU_AI_PRIMARY_TARGET_CONTINUITY_MAX_CENTER_DISTANCE = 0.16f
private const val DANMAKU_AI_PRIMARY_TARGET_CONTINUITY_MIN_SIZE_RATIO = 0.62f
private const val DANMAKU_AI_PRIMARY_TARGET_CONTINUITY_MAX_SIZE_RATIO = 1.62f
private const val DANMAKU_AI_PRIMARY_TARGET_SWITCH_CONFIRM_SAMPLES = 2
private const val DANMAKU_AI_PRIMARY_TARGET_SWITCH_COOLDOWN_SAMPLES = 2
private const val DANMAKU_AI_PRIMARY_TARGET_SWITCH_SCORE_MARGIN = 0.18f
private const val DANMAKU_AI_MASK_ADJUST_MIN_RECT_AREA = 0.020f
private const val DANMAKU_AI_MASK_ADJUST_EDGE_SAMPLE_STEP = 3
private const val DANMAKU_AI_MASK_ADJUST_EDGE_WEIGHT_THRESHOLD = 18f
private const val DANMAKU_AI_MASK_ADJUST_MAX_DX_RATIO = 0.08f
private const val DANMAKU_AI_MASK_ADJUST_MAX_DY_RATIO = 0.10f
private const val DANMAKU_AI_MASK_ADJUST_MAX_SCALE_DELTA = 0.08f
private const val DANMAKU_AI_MASK_ADJUST_MIN_EDGE_WEIGHT = 420f
private const val DANMAKU_AI_SMALL_MULTI_MODE_LATENCY_HEADROOM_RATIO = 0.60
private const val DANMAKU_AI_SMALL_MULTI_MODE_LATENCY_HOLD_RATIO = 0.76
private const val DANMAKU_AI_SMALL_MULTI_MAX_PEOPLE = 2
private const val DANMAKU_AI_SMALL_MULTI_MIN_SCORE = 0.28f
private const val DANMAKU_AI_SMALL_MULTI_MIN_AREA_RATIO = 0.006f
private const val DANMAKU_AI_SMALL_MULTI_MAX_AREA_RATIO = 0.14f
private const val DANMAKU_AI_SMALL_MULTI_MAX_WIDTH_RATIO = 0.55f
private const val DANMAKU_AI_SMALL_MULTI_MAX_HEIGHT_RATIO = 0.55f
private const val DANMAKU_AI_SMALL_MULTI_MAX_IOU = 0.20f
private const val DANMAKU_AI_SMALL_MULTI_SINGLE_MASK_MAX_AREA_RATIO = 0.18f
private const val DANMAKU_AI_SMALL_MULTI_UNION_MAX_AREA_RATIO = 0.45f
private const val DANMAKU_AI_SMALL_MULTI_BASE_SHORT_SIDE_DP = 411f
private const val DANMAKU_AI_SMALL_MULTI_MIN_DIMENSION_SCALE = 0.92f
private const val DANMAKU_AI_SMALL_MULTI_MAX_DIMENSION_SCALE = 1.14f
private const val DANMAKU_AI_SMALL_MULTI_MIN_AREA_SCALE = 0.85f
private const val DANMAKU_AI_SMALL_MULTI_MAX_AREA_SCALE = 1.30f
private const val DANMAKU_AI_SMALL_MULTI_STICKY_SAMPLES = 2
private const val DANMAKU_AI_SMALL_MULTI_INPUT_WIDTH_REDUCTION = 32
private const val DANMAKU_AI_SMALL_MULTI_RELAXED_MAX_AREA_MULTIPLIER = 1.24f
private const val DANMAKU_AI_SMALL_MULTI_RELAXED_MAX_WIDTH_MULTIPLIER = 1.10f
private const val DANMAKU_AI_SMALL_MULTI_RELAXED_MAX_HEIGHT_MULTIPLIER = 1.10f
private const val DANMAKU_AI_SMALL_MULTI_WEAK_MIN_SCORE = 0.20f
private const val DANMAKU_AI_SMALL_MULTI_WEAK_MAX_AREA_MULTIPLIER = 1.34f
private const val DANMAKU_AI_SMALL_MULTI_WEAK_MAX_WIDTH_MULTIPLIER = 1.18f
private const val DANMAKU_AI_SMALL_MULTI_WEAK_MAX_HEIGHT_MULTIPLIER = 1.18f
private const val DANMAKU_AI_SMALL_MULTI_SECONDARY_MASK_MAX_AREA_MULTIPLIER = 1.08f
private const val DANMAKU_AI_SMALL_MULTI_TRACK_MAX_COUNT = 2
private const val DANMAKU_AI_SMALL_MULTI_TRACK_MAX_MISS_SAMPLES = 2
private const val DANMAKU_AI_SMALL_MULTI_TRACK_MAX_MISS_SAMPLES_WEAK = 3
private const val DANMAKU_AI_SMALL_MULTI_TRACK_MIN_HIT_SAMPLES = 2
private const val DANMAKU_AI_SMALL_MULTI_TRACK_ASSOCIATION_MIN_IOU = 0.02f
private const val DANMAKU_AI_SMALL_MULTI_TRACK_ASSOCIATION_MAX_CENTER_DISTANCE = 0.24f
private const val DANMAKU_AI_SMALL_MULTI_TRACK_ASSOCIATION_MIN_AREA_RATIO = 0.45f
private const val DANMAKU_AI_SMALL_MULTI_TRACK_ASSOCIATION_MAX_AREA_RATIO = 2.20f
private const val DANMAKU_AI_SMALL_MULTI_COARSE_ONLY_CLEAR_SAMPLES = 3
private const val DANMAKU_AI_SMALL_MULTI_COARSE_SPLIT_MIN_REMAINDER_WIDTH = 0.08f
private const val DANMAKU_AI_SMALL_MULTI_COARSE_SPLIT_MIN_REMAINDER_HEIGHT = 0.12f
private const val DANMAKU_AI_SMALL_MULTI_COARSE_SPLIT_MIN_REMAINDER_AREA = 0.008f

enum class DanmakuAiBackend(val wireValue: String) {
    PADDLE("paddle"),
    GPU("gpu"),
    CPU("cpu"),
    DISABLED("disabled"),
    ;

    companion object {
        fun fromValue(raw: String?): DanmakuAiBackend? {
            val normalized = raw?.trim()?.lowercase().orEmpty()
            return entries.firstOrNull { it.wireValue == normalized }
        }
    }
}

data class DanmakuNormalizedRect(
    val x: Float,
    val y: Float,
    val width: Float,
    val height: Float,
) {
    val left: Float
        get() = x

    val top: Float
        get() = y

    val right: Float
        get() = (x + width).coerceIn(0f, 1f)

    val bottom: Float
        get() = (y + height).coerceIn(0f, 1f)

    val centerX: Float
        get() = (x + (width / 2f)).coerceIn(0f, 1f)

    val centerY: Float
        get() = (y + (height / 2f)).coerceIn(0f, 1f)

    fun area(): Float = width.coerceAtLeast(0f) * height.coerceAtLeast(0f)

    fun iou(other: DanmakuNormalizedRect): Float {
        val intersectLeft = maxOf(left, other.left)
        val intersectTop = maxOf(top, other.top)
        val intersectRight = minOf(right, other.right)
        val intersectBottom = minOf(bottom, other.bottom)
        val intersectWidth = (intersectRight - intersectLeft).coerceAtLeast(0f)
        val intersectHeight = (intersectBottom - intersectTop).coerceAtLeast(0f)
        val intersection = intersectWidth * intersectHeight
        if (intersection <= 0f) {
            return 0f
        }
        val union = area() + other.area() - intersection
        return if (union <= 0f) 0f else (intersection / union).coerceIn(0f, 1f)
    }

    fun expanded(horizontalRatio: Float, verticalRatio: Float): DanmakuNormalizedRect {
        val expandX = width * horizontalRatio
        val expandY = height * verticalRatio
        val left = (x - (expandX / 2f)).coerceIn(0f, 1f)
        val top = (y - (expandY / 2f)).coerceIn(0f, 1f)
        val right = (x + width + (expandX / 2f)).coerceIn(0f, 1f)
        val bottom = (y + height + (expandY / 2f)).coerceIn(0f, 1f)
        return DanmakuNormalizedRect(
            x = left,
            y = top,
            width = (right - left).coerceAtLeast(0f),
            height = (bottom - top).coerceAtLeast(0f),
        )
    }

    fun lerp(target: DanmakuNormalizedRect, alpha: Float): DanmakuNormalizedRect {
        val clampedAlpha = alpha.coerceIn(0f, 1f)

        fun mix(start: Float, end: Float): Float = start + ((end - start) * clampedAlpha)

        return DanmakuNormalizedRect(
            x = mix(x, target.x).coerceIn(0f, 1f),
            y = mix(y, target.y).coerceIn(0f, 1f),
            width = mix(width, target.width).coerceIn(0f, 1f),
            height = mix(height, target.height).coerceIn(0f, 1f),
        )
    }

    fun toMap(): Map<String, Double> {
        return mapOf(
            "x" to x.toDouble(),
            "y" to y.toDouble(),
            "width" to width.toDouble(),
            "height" to height.toDouble(),
        )
    }
}

data class DanmakuDynamicOcclusionState(
    val enabled: Boolean,
    val available: Boolean,
    val backend: String,
    val occlusionMode: String = DanmakuOcclusionMode.DISABLED.wireValue,
    val updatedAtMs: Long,
    val maskPath: String?,
    val maskSignature: String?,
    val maskWidth: Int,
    val maskHeight: Int,
    val framePath: String?,
    val cacheHit: Boolean,
    val captureAreaRatio: Float,
    val normalizedRect: DanmakuNormalizedRect?,
    val unavailableReason: String?,
    val captureBackend: String,
    val degradationLevel: String,
    val effectiveSampleIntervalMs: Long,
    val effectiveInputWidth: Int,
    // Estimated global frame motion (normalized units per ms) for between-sample
    // mask extrapolation in the renderer. 0 = no motion.
    val maskVelocityX: Double = 0.0,
    val maskVelocityY: Double = 0.0,
    // Plan B: video PTS (ms) this mask was computed for; overlay PTS-syncs to it. 0 = none.
    val maskPtsMs: Long = 0L,
    // Plan B v2: this mask starts a new scene (cut detected). The renderer won't
    // extrapolate it (or across it). false = continuous with the previous mask.
    val maskSceneCut: Boolean = false,
    // Plan B: video display aspect (w/h) of the raw decoded frame the mask came from.
    // The overlay maps the mask to the letterboxed video rect inside the view (the raw
    // frame has no black bars; the displayed video does). 0 = none (live-capture path
    // masks the rendered surface, which already includes bars → full-view mapping).
    val videoAspect: Double = 0.0,
) {
    fun toMap(): Map<String, Any?> {
        return mapOf(
            "enabled" to enabled,
            "available" to available,
            "backend" to backend,
            "occlusionMode" to occlusionMode,
            "updatedAtMs" to updatedAtMs,
            "maskPath" to maskPath,
            "maskSignature" to maskSignature,
            "maskWidth" to maskWidth,
            "maskHeight" to maskHeight,
            "framePath" to framePath,
            "cacheHit" to cacheHit,
            "captureAreaRatio" to captureAreaRatio.toDouble(),
            "normalizedRect" to normalizedRect?.toMap(),
            "unavailableReason" to unavailableReason,
            "captureBackend" to captureBackend,
            "degradationLevel" to degradationLevel,
            "effectiveSampleIntervalMs" to effectiveSampleIntervalMs,
            "effectiveInputWidth" to effectiveInputWidth,
            "maskVelocityX" to maskVelocityX,
            "maskVelocityY" to maskVelocityY,
            "maskPtsMs" to maskPtsMs,
            "maskSceneCut" to maskSceneCut,
            "videoAspect" to videoAspect,
        )
    }

    companion object {
        fun disabled(): DanmakuDynamicOcclusionState {
            return DanmakuDynamicOcclusionState(
                enabled = false,
                available = false,
                backend = DanmakuAiBackend.DISABLED.wireValue,
                occlusionMode = DanmakuOcclusionMode.DISABLED.wireValue,
                updatedAtMs = 0L,
                maskPath = null,
                maskSignature = null,
                maskWidth = 0,
                maskHeight = 0,
                framePath = null,
                cacheHit = false,
                captureAreaRatio = 1.0f,
                normalizedRect = null,
                unavailableReason = null,
                captureBackend = "none",
                degradationLevel = DanmakuOcclusionDegradationLevel.NONE.wireValue,
                effectiveSampleIntervalMs = DANMAKU_AI_DEFAULT_SAMPLE_INTERVAL_MS,
                effectiveInputWidth = DANMAKU_AI_DEFAULT_INPUT_WIDTH,
            )
        }
    }
}

enum class DanmakuOcclusionMode(val wireValue: String) {
    DISABLED("disabled"),
    BBOX("bbox"),
    MASK("mask"),
    ;
}

private enum class DanmakuOcclusionDegradationLevel(val wireValue: String) {
    NONE("none"),
    INTERVAL("interval"),
    REDUCED_INPUT("reduced_input"),
    DISABLED("disabled"),
}

private enum class TrackerLifecycleState(val wireValue: String) {
    WARMUP("warmup"),
    STABLE("stable"),
    WEAK("weak"),
    LOST("lost"),
}

data class DanmakuDynamicOcclusionConfig(
    val enabled: Boolean,
    val sampleIntervalMs: Long,
    val renderTargetFrameRateHz: Int,
    val preferredBackendOrder: List<DanmakuAiBackend>,
    val inputWidth: Int,
    val inputHeight: Int,
    val displayAreaRatio: Float,
    val sampleAreaRatio: Float,
    val motionTrackingEnabled: Boolean,
    val networkPrecomputeEnabled: Boolean,
) {
    companion object {
        val defaults =
            DanmakuDynamicOcclusionConfig(
                enabled = false,
                sampleIntervalMs = DANMAKU_AI_DEFAULT_SAMPLE_INTERVAL_MS,
                renderTargetFrameRateHz = 60,
                preferredBackendOrder =
                    listOf(
                        DanmakuAiBackend.PADDLE,
                    ),
                inputWidth = DANMAKU_AI_DEFAULT_INPUT_WIDTH,
                inputHeight = DANMAKU_AI_DEFAULT_INPUT_HEIGHT,
                displayAreaRatio = 1.0f,
                sampleAreaRatio = DANMAKU_AI_DEFAULT_SAMPLE_AREA_RATIO,
                motionTrackingEnabled = true,
                networkPrecomputeEnabled = true,
            )

        fun fromMap(raw: Map<String, Any?>): DanmakuDynamicOcclusionConfig {
            val preferredBackendOrder =
                (raw["preferredBackendOrder"] as? List<*>)
                    ?.mapNotNull { DanmakuAiBackend.fromValue(it?.toString()) }
                    ?.filter { it == DanmakuAiBackend.PADDLE }
                    ?.distinct()
                    ?.takeIf { it.isNotEmpty() }
                    ?: defaults.preferredBackendOrder
            return DanmakuDynamicOcclusionConfig(
                enabled = raw["enabled"] == true,
                sampleIntervalMs =
                    (raw["sampleIntervalMs"]?.toLongValue() ?: defaults.sampleIntervalMs)
                        .coerceIn(
                            DANMAKU_AI_MIN_SAMPLE_INTERVAL_MS,
                            DANMAKU_AI_MAX_SAMPLE_INTERVAL_MS,
                        ),
                renderTargetFrameRateHz =
                    (raw["renderTargetFrameRateHz"]?.toIntValue()
                        ?: defaults.renderTargetFrameRateHz)
                        .coerceIn(24, 120),
                preferredBackendOrder = preferredBackendOrder,
                inputWidth =
                    (raw["inputWidth"]?.toIntValue() ?: defaults.inputWidth).coerceIn(64, 512),
                inputHeight =
                    (raw["inputHeight"]?.toIntValue() ?: defaults.inputHeight).coerceIn(64, 512),
                displayAreaRatio =
                    ((raw["displayAreaRatio"]?.toDoubleValue()?.toFloat())
                        ?: defaults.displayAreaRatio)
                        .coerceIn(0.1f, 1.0f),
                sampleAreaRatio =
                    ((raw["sampleAreaRatio"]?.toDoubleValue()?.toFloat())
                        ?: defaults.sampleAreaRatio)
                        .coerceIn(0.1f, 1.0f),
                motionTrackingEnabled =
                    raw["motionTrackingEnabled"] as? Boolean ?: defaults.motionTrackingEnabled,
                networkPrecomputeEnabled =
                    raw["networkPrecomputeEnabled"] as? Boolean ?: defaults.networkPrecomputeEnabled,
            )
        }
    }
}

private data class DanmakuPrimaryDetection(
    val rect: DanmakuNormalizedRect,
    val score: Float,
)

private data class DanmakuSmallMultiTrack(
    val trackId: Int,
    val rect: DanmakuNormalizedRect,
    val score: Float,
    val age: Int,
    val missCount: Int,
    val hitCount: Int,
    val lastMatchedSampleId: Long,
    val lastMaskAreaRatio: Float,
)

private data class DanmakuSmallMultiTrackTarget(
    val trackId: Int,
    val rect: DanmakuNormalizedRect,
    val score: Float,
    val missCount: Int,
    val hitCount: Int,
    val source: String,
    val association: String,
)

private data class DanmakuSmallMultiMatchedCandidate(
    val candidate: DanmakuPrimaryDetection,
    val candidateIndex: Int,
    val association: String,
)

private data class DanmakuSmallMultiSelection(
    val targets: List<DanmakuSmallMultiTrackTarget>,
    val candidateCount: Int,
    val thresholdScale: Float,
    val viewportShortSideDp: Float,
    val dropReason: String? = null,
    val trackState: List<DanmakuSmallMultiTrack> = emptyList(),
    val trackCount: Int = 0,
    val trackHits: String? = null,
    val trackMisses: String? = null,
    val trackSource: String? = null,
    val association: String? = null,
    val coarseOnlySamples: Int = 0,
)

private data class DanmakuSmallMultiThresholds(
    val thresholdScale: Float,
    val viewportShortSideDp: Float,
    val maxAreaRatio: Float,
    val maxWidthRatio: Float,
    val maxHeightRatio: Float,
    val singleMaskMaxAreaRatio: Float,
    val unionMaxAreaRatio: Float,
)

private data class DanmakuSegmentationRoi(
    val bitmap: Bitmap,
    val rect: DanmakuNormalizedRect,
    val contentRect: DanmakuNormalizedRect,
    val mode: String,
    val inputWidth: Int,
    val inputHeight: Int,
)

private enum class DanmakuSegmentationRoiMode(val wireValue: String) {
    TRACKED("tracked"),
    DETECT("detect"),
}

private data class DanmakuSegmentationAttempt(
    val extraction: DanmakuMaskExtraction?,
    val latencyMs: Long,
    val roiRect: DanmakuNormalizedRect,
    val roiMode: DanmakuSegmentationRoiMode,
    val inputWidth: Int,
    val inputHeight: Int,
    val rejectReason: String?,
    val scaleRescueApplied: Boolean,
)

private data class DanmakuSegmentationPassResult(
    val extraction: DanmakuMaskExtraction?,
    val rejectReason: String?,
    val roiRect: DanmakuNormalizedRect,
    val inputWidth: Int,
    val inputHeight: Int,
    val latencyMs: Long,
)

private data class DanmakuMaskPlane(
    val values: FloatArray,
    val width: Int,
    val height: Int,
)

private data class DanmakuMaskResult(
    val maskValues: FloatArray,
    val maskWidth: Int,
    val maskHeight: Int,
    val normalizedRect: DanmakuNormalizedRect?,
    val occlusionMode: DanmakuOcclusionMode = DanmakuOcclusionMode.MASK,
)

private data class DanmakuSmallMultiMaskCandidate(
    val trackId: Int,
    val rect: DanmakuNormalizedRect,
    val attempt: DanmakuSegmentationAttempt,
    val maskResult: DanmakuMaskResult,
    val priorityScore: Float,
    val areaRatio: Float,
)

private data class DanmakuSmallMultiSegmentationResult(
    val maskResult: DanmakuMaskResult?,
    val latencyMs: Long,
    val keptCount: Int,
    val unionAreaRatio: Float,
    val dropReason: String?,
    val roiRect: DanmakuNormalizedRect?,
    val inputWidth: Int,
    val inputHeight: Int,
    val maskAreaByTrackId: Map<Int, Float> = emptyMap(),
)

private data class DanmakuFrameContinuity(
    val sceneCut: Boolean,
    val signature: IntArray,
)

private data class DanmakuMotionRoi(
    val left: Int,
    val top: Int,
    val right: Int,
    val bottom: Int,
) {
    val width: Int
        get() = (right - left + 1).coerceAtLeast(0)

    val height: Int
        get() = (bottom - top + 1).coerceAtLeast(0)

    val area: Int
        get() = width * height
}

private data class DanmakuMotionReferenceFrame(
    val lumaSamples: IntArray,
    val sampleWidth: Int,
    val sampleHeight: Int,
    val normalizedRect: DanmakuNormalizedRect,
    val timestampMs: Long,
)

private data class DanmakuMotionCompensation(
    val dxSamplePx: Int,
    val dySamplePx: Int,
    val dxMaskPx: Int,
    val dyMaskPx: Int,
    val dxNormalized: Float,
    val dyNormalized: Float,
    val scale: Float,
    val score: Double,
)

private data class DanmakuPredictedTransform(
    val dxNormalized: Float,
    val dyNormalized: Float,
    val dxSamplePx: Int,
    val dySamplePx: Int,
    val scale: Float,
    val predictedAreaRatio: Float,
)

private data class DanmakuTrackedRectCandidate(
    val rect: DanmakuNormalizedRect,
    val source: String,
    val predictedScale: Float,
    val predictedAreaRatio: Float,
    val confidence: Float? = null,
)

private data class PrimaryTargetMemory(
    val rect: DanmakuNormalizedRect,
    val score: Float,
    val ageSamples: Int,
    val cooldownSamples: Int,
)

private data class PrimaryTargetSelection(
    val detection: DanmakuPrimaryDetection?,
    val stable: Boolean,
    val switched: Boolean,
    val switchReason: String?,
    val continuityScore: Float,
)

private data class MaskGeometryStats(
    val boundingRect: DanmakuNormalizedRect,
    val centroidX: Float,
    val centroidY: Float,
)

private data class MaskReuseAdjustment(
    val dxPx: Int,
    val dyPx: Int,
    val scale: Float,
    val source: String,
) {
    fun deltaSummary(): String = "dx=$dxPx,dy=$dyPx,scale=${"%.3f".format(Locale.US, scale)}"
}

private data class InferenceOutcome(
    val maskResult: DanmakuMaskResult?,
    val motionLumaSamples: IntArray,
    val motionSampleWidth: Int,
    val motionSampleHeight: Int,
    val motionCompensation: DanmakuMotionCompensation?,
    val motionCompensationAttempted: Boolean,
    val detectLatencyMs: Long,
    val refineLatencyMs: Long,
    val occlusionMode: DanmakuOcclusionMode,
    val detectionPerformed: Boolean,
    val trackedRectReused: Boolean,
    val primaryRect: DanmakuNormalizedRect?,
    val segmentationRoiMode: String?,
    val segmentationRoiRect: DanmakuNormalizedRect?,
    val segmentationInputWidth: Int,
    val segmentationInputHeight: Int,
    val predictedScale: Float,
    val predictedAreaRatio: Float,
    val trackedRectSource: String?,
    val maskScaleApplied: Boolean,
    val maskScaleValue: Float,
    val scaleRescueApplied: Boolean,
    val trackingStateEligible: Boolean = true,
    val multiSmallMode: Boolean = false,
    val multiCandidateCount: Int = 0,
    val multiKeptCount: Int = 0,
    val multiUnionAreaRatio: Float = 0f,
    val multiViewportScale: Float = 1f,
    val multiDropReason: String? = null,
    val multiTrackCount: Int = 0,
    val multiTrackHits: String? = null,
    val multiTrackMisses: String? = null,
    val multiTrackSource: String? = null,
    val multiAssociation: String? = null,
    val nextSmallMultiTracks: List<DanmakuSmallMultiTrack>? = null,
    val nextSmallMultiCoarseOnlySamples: Int? = null,
    val suppressMaskGrace: Boolean = false,
    val suppressionReason: String? = null,
    val trackerUsed: Boolean = false,
    val trackerSuccessful: Boolean = false,
    val trackerSource: String? = null,
    val trackerMaskReused: Boolean = false,
    val trackerConfidence: Float? = null,
    val trackerLatencyMs: Long = 0L,
    val trackerFallbackReason: String? = null,
    val trackerState: String? = null,
    val trackerStateReason: String? = null,
    val primaryTargetStable: Boolean = false,
    val primaryTargetSwitched: Boolean = false,
    val primaryTargetSwitchReason: String? = null,
    val detectionSkippedByStableTracker: Boolean = false,
    val segmentationSkippedByStableTracker: Boolean = false,
    val maskAdjustmentUsed: Boolean = false,
    val maskAdjustmentSource: String? = null,
    val maskAdjustmentDelta: String? = null,
)

private data class DanmakuMaskExtraction(
    val maskResult: DanmakuMaskResult,
    val appliedMotionCompensation: DanmakuMotionCompensation?,
    val maskScaleApplied: Boolean,
    val maskScaleValue: Float,
)

private data class DanmakuMaskExtractionResult(
    val extraction: DanmakuMaskExtraction?,
    val rejectReason: String?,
)

private data class RoiMaskValidationMetrics(
    val coverage: Float,
    val iou: Float,
    val foregroundRatio: Float,
)

private data class DanmakuPrimaryComponent(
    val rect: DanmakuNormalizedRect,
    val pixelCount: Int,
    val fillRatio: Float,
)

private data class DanmakuPrimaryMaskComponent(
    val maskValues: FloatArray,
    val component: DanmakuPrimaryComponent,
)

private data class DanmakuForegroundComplexity(
    val significantComponentCount: Int,
    val largestPixelCount: Int,
    val secondLargestPixelCount: Int,
    val totalForegroundPixels: Int,
)

private data class MaskHoleStats(
    val holeCount: Int,
    val largestHolePixels: Int,
    val totalHolePixels: Int,
)

private data class DanmakuOcclusionCacheEntry(
    val backend: String,
    val updatedAtMs: Long,
    val maskPath: String,
    val maskSignature: String?,
    val maskWidth: Int,
    val maskHeight: Int,
    val framePath: String?,
    val normalizedRect: DanmakuNormalizedRect?,
)

private class DanmakuOcclusionCacheStore(
    private val context: Context,
) {
    fun load(source: MpvSource): DanmakuOcclusionCacheEntry? {
        val directory = entryDirectory(source)
        val stateFile = File(directory, DANMAKU_AI_CACHE_STATE_FILE_NAME)
        if (!stateFile.isFile) {
            return null
        }
        return runCatching {
            val json = JSONObject(stateFile.readText())
            if (json.optInt("cacheVersion", 0) != DANMAKU_AI_CACHE_VERSION) {
                return null
            }
            val maskFile = File(directory, DANMAKU_AI_CACHE_MASK_FILE_NAME)
            if (!maskFile.isFile || maskFile.length() <= 0L) {
                return null
            }
            val frameFile = File(directory, DANMAKU_AI_CACHE_FRAME_FILE_NAME)
            val rect =
                if (json.has("x") && json.has("y") && json.has("width") && json.has("height")) {
                    DanmakuNormalizedRect(
                        x = json.optDouble("x", 0.0).toFloat(),
                        y = json.optDouble("y", 0.0).toFloat(),
                        width = json.optDouble("width", 0.0).toFloat(),
                        height = json.optDouble("height", 0.0).toFloat(),
                    )
                } else {
                    null
                }
            DanmakuOcclusionCacheEntry(
                backend = json.optString("backend", DanmakuAiBackend.PADDLE.wireValue),
                updatedAtMs = json.optLong("updatedAtMs", 0L),
                maskPath = maskFile.absolutePath,
                maskSignature = json.optString("maskSignature").takeIf { it.isNotBlank() },
                maskWidth = json.optInt("maskWidth", 0),
                maskHeight = json.optInt("maskHeight", 0),
                framePath = frameFile.takeIf { it.isFile && it.length() > 0L }?.absolutePath,
                normalizedRect = rect,
            )
        }.getOrNull()
    }

    fun save(
        source: MpvSource,
        backend: String,
        updatedAtMs: Long,
        maskSignature: String?,
        normalizedRect: DanmakuNormalizedRect?,
        frameBitmap: Bitmap?,
        maskWidth: Int,
        maskHeight: Int,
        maskValues: FloatArray,
    ): DanmakuOcclusionCacheEntry? {
        val directory = entryDirectory(source)
        if (!directory.exists() && !directory.mkdirs()) {
            return null
        }
        return runCatching {
            val frameFile = File(directory, DANMAKU_AI_CACHE_FRAME_FILE_NAME)
            if (frameBitmap != null) {
                frameFile.outputStream().use { output ->
                    frameBitmap.compress(Bitmap.CompressFormat.WEBP_LOSSY, 82, output)
                }
            }

            val maskFile = File(directory, DANMAKU_AI_CACHE_MASK_FILE_NAME)
            createMaskBitmap(maskWidth, maskHeight, maskValues).use { maskBitmap ->
                maskFile.outputStream().use { output ->
                    maskBitmap.compress(Bitmap.CompressFormat.WEBP_LOSSLESS, 100, output)
                }
            }

            val stateFile = File(directory, DANMAKU_AI_CACHE_STATE_FILE_NAME)
            val json =
                JSONObject()
                    .put("cacheVersion", DANMAKU_AI_CACHE_VERSION)
                    .put("backend", backend)
                    .put("updatedAtMs", updatedAtMs)
                    .put("maskSignature", maskSignature)
                    .put("maskWidth", maskWidth)
                    .put("maskHeight", maskHeight)
            if (normalizedRect != null) {
                json
                    .put("x", normalizedRect.x.toDouble())
                    .put("y", normalizedRect.y.toDouble())
                    .put("width", normalizedRect.width.toDouble())
                    .put("height", normalizedRect.height.toDouble())
            }
            stateFile.writeText(json.toString())

            DanmakuOcclusionCacheEntry(
                backend = backend,
                updatedAtMs = updatedAtMs,
                maskPath = maskFile.absolutePath,
                maskSignature = maskSignature,
                maskWidth = maskWidth,
                maskHeight = maskHeight,
                framePath = frameFile.takeIf { it.isFile && it.length() > 0L }?.absolutePath,
                normalizedRect = normalizedRect,
            )
        }.getOrNull()
    }

    private fun entryDirectory(source: MpvSource): File {
        return File(File(context.cacheDir, DANMAKU_AI_CACHE_DIR_NAME), cacheKey(source))
    }

    private fun cacheKey(source: MpvSource): String {
        val stableIdentity =
            listOf(
                source.itemGuid.trim(),
                source.mediaGuid.trim(),
                source.videoGuid.trim(),
                source.url.trim(),
                source.title.trim(),
            ).joinToString("|")
        val digest = MessageDigest.getInstance("SHA-256").digest(stableIdentity.toByteArray())
        return digest.joinToString("") { byte -> "%02x".format(Locale.US, byte) }
    }

    private fun createMaskBitmap(
        width: Int,
        height: Int,
        maskValues: FloatArray,
    ): Bitmap {
        val pixels = IntArray(width * height)
        for (index in pixels.indices) {
            val alpha = (maskValues[index].coerceIn(0f, 1f) * 255f).toInt().coerceIn(0, 255)
            pixels[index] = Color.argb(alpha, 255, 255, 255)
        }
        return Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
    }
}

private inline fun <T : Bitmap?, R> T.use(block: (T) -> R): R {
    return try {
        block(this)
    } finally {
        this?.recycle()
    }
}

class DanmakuDynamicOcclusionController(
    private val context: Context,
    private val videoOutputTarget: VideoOutputTarget,
    private val stateListener: (DanmakuDynamicOcclusionState, Bitmap?) -> Unit,
    // Plan B: current playback position in ms (mpv time-pos). -1 = unknown. Used to
    // decode frames ahead of playback via DanmakuFrameExtractor instead of capturing
    // the rendered surface. Default no-op keeps the Flutter PlatformView path working.
    private val positionProviderMs: () -> Long = { -1L },
    // Plan B v2: current playback speed (1.0 = normal). Scales the producer pipeline's
    // lookahead window so masks stay ahead of playback at faster speeds.
    private val playbackSpeedProvider: () -> Double = { 1.0 },
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val inferenceThread = HandlerThread("FlyPlayerDanmakuOcclusion").apply { start() }
    private val inferenceHandler = Handler(inferenceThread.looper)
    private val cacheStore = DanmakuOcclusionCacheStore(context)
    private val runtimeFactory =
        DanmakuSegmentationRuntimeFactory(
            context = context,
            paddleModelAssetDir = DANMAKU_AI_PADDLE_MODEL_ASSET_DIR,
        )
    private val detectionRuntimeFactory =
        DanmakuDetectionRuntimeFactory(
            context = context,
            paddleModelAssetDir = DANMAKU_AI_PADDLE_MODEL_ASSET_DIR,
        )
    @Volatile
    private var disposed = false

    @Volatile
    private var config = DanmakuDynamicOcclusionConfig.defaults

    @Volatile
    private var paused = true

    @Volatile
    private var externallyPaused = false

    @Volatile
    private var hasDanmakuOnScreen = true

    @Volatile
    private var sourceLoaded = false

    @Volatile
    private var surfaceReady = false

    @Volatile
    private var videoOutputReady = false

    @Volatile
    private var processing = false

    @Volatile
    private var capturePending = false

    @Volatile
    private var captureInFlight = false

    @Volatile
    private var samplingScheduled = false

    @Volatile
    private var warmStartDelayUntilUptimeMs = 0L

    private var latestState = DanmakuDynamicOcclusionState.disabled()
    private var latestRect: DanmakuNormalizedRect? = null
    private var latestTrackingRect: DanmakuNormalizedRect? = null
    private var latestMaskValues: FloatArray? = null
    private var latestMaskWidth = 0
    private var latestMaskHeight = 0
    private var latestMaskPath: String? = null
    private var latestMaskSignature: String? = null
    private var latestFramePath: String? = null
    private var latestMaskTimestampMs = 0L
    private var latestMaskAppliedAtUptimeMs = 0L
    private var latestRuntimeMaskBitmap: Bitmap? = null
    private var currentSource: MpvSource? = null
    private var failedPlanBSourceUrl: String? = null
    private var consecutiveEmptyFrames = 0
    private var activeBackendIndex = 0
    private var activeRuntime: DanmakuSegmentationRuntime? = null
    private var activeDetectionRuntime: DanmakuDetectionRuntime? = null
    private var personTrackerRuntime: PersonTrackerRuntime? = null
    private var averageLatencyMs = 0.0
    private var overBudgetCount = 0
    private var activeCaptureRequestId: Long? = null
    private var lastCaptureBackend = "none"
    private var degradationStage = 0
    private var stableRecoverySamples = 0
    private val runtimeLock = Any()
    private var previousFrameLumaSignature: IntArray? = null
    private var lastFrameCacheWriteAtMs = 0L
    private var sampleSequence = 0L
    private var cacheRestoreEligible = true
    private var latestRectTrackingEligible = false
    private var latestMotionReferenceFrame: DanmakuMotionReferenceFrame? = null
    private var previousMotionReferenceFrame: DanmakuMotionReferenceFrame? = null
    private var lastMotionCompensation: DanmakuMotionCompensation? = null
    private var consecutiveMotionCompensationFailures = 0
    private var consecutiveCompensatedFrames = 0
    private var nextEligibleSampleUptimeMs = 0L
    private var lastSuccessfulDetectionUptimeMs = 0L
    private var consecutiveTrackedReuseSamples = 0
    private var smallMultiStickySamplesRemaining = 0
    private var smallMultiTracks = emptyList<DanmakuSmallMultiTrack>()
    private var smallMultiNextTrackId = 1
    private var smallMultiCoarseOnlySamples = 0
    private var pendingMaskGraceBackend: DanmakuAiBackend? = null
    private var pendingMaskGraceClearAtUptimeMs = 0L
    private var lastTrackerReuseFallbackReason: String? = null
    private var trackerLifecycleState = TrackerLifecycleState.LOST
    private var trackerLifecycleReason = "uninitialized"
    private var trackerSuccessStreak = 0
    private var trackerFailureStreak = 0
    private var trackerWeakStreak = 0
    private var trackerStableSinceUptimeMs = 0L
    private var lastTrackerConfidence = 0f
    private var lastTrackerGeometryPenalty = 1f
    private var primaryTargetMemory: PrimaryTargetMemory? = null
    private var primaryTargetCandidateRect: DanmakuNormalizedRect? = null
    private var primaryTargetCandidateWins = 0
    private var primaryTargetSwitchCooldownSamples = 0
    private var lastAcceptedTargetSource = "none"

    private val maskGraceExpireRunnable =
        Runnable {
            val backend = pendingMaskGraceBackend ?: return@Runnable
            pendingMaskGraceBackend = null
            pendingMaskGraceClearAtUptimeMs = 0L
            if (disposed) {
                return@Runnable
            }
            if (consecutiveEmptyFrames >= DANMAKU_AI_MAX_EMPTY_FRAMES) {
                clearRuntimeMaskState()
            }
            emitUnavailableState(backend = backend, keepEnabled = true)
        }

    @Volatile
    private var sceneCutRecoveryActive = false

    @Volatile
    private var sceneCutBurstSamplesRemaining = 0

    @Volatile
    private var stableMaskFramesSinceSceneCut = 0

    @Volatile
    private var motionBurstSamplesRemaining = 0

    @Volatile
    private var motionBurstReason: String? = null

    @Volatile
    private var pendingMotionBurstReason: String? = null

    private val sampleRunnable =
        Runnable {
            samplingScheduled = false
            if (disposed || !shouldSample()) {
                return@Runnable
            }
            if (processing || captureInFlight) {
                capturePending = true
                return@Runnable
            }
            captureFrameAndInfer()
        }

    fun updateConfig(raw: Map<String, Any?>) {
        if (disposed) return
        val next = DanmakuDynamicOcclusionConfig.fromMap(raw)
        val backendOrderChanged = next.preferredBackendOrder != config.preferredBackendOrder
        val inputSizeChanged =
            next.inputWidth != config.inputWidth || next.inputHeight != config.inputHeight
        val networkPrecomputeChanged = next.networkPrecomputeEnabled != config.networkPrecomputeEnabled
        config = next
        if (networkPrecomputeChanged) {
            failedPlanBSourceUrl = null
            releasePrecomputePipeline()
        }
        if (!next.enabled) {
            stopSampling(clearPending = true)
            releasePrecomputePipeline()
            releaseRuntime()
            clearRuntimeMaskState()
            emitState(DanmakuDynamicOcclusionState.disabled())
            return
        }
        val captureUnavailableReason = captureUnavailableReason()
        if (captureUnavailableReason != null && !planBActive()) {
            stopSampling(clearPending = true)
            releaseRuntime()
            clearRuntimeMaskState()
            emitUnavailableState(
                backend = currentBackendOrFallback(),
                keepEnabled = true,
                backendWireValue = videoOutputTarget.backend.wireValue,
                unavailableReason = captureUnavailableReason,
            )
            return
        }
        if (backendOrderChanged || inputSizeChanged) {
            activeBackendIndex = 0
            averageLatencyMs = 0.0
            overBudgetCount = 0
            degradationStage = 0
            stableRecoverySamples = 0
            releaseRuntime()
        }
        evaluateSamplingState(resetStaleMask = false)
    }

    fun updatePlaybackState(
        paused: Boolean,
        sourceLoaded: Boolean,
        surfaceReady: Boolean,
        videoOutputReady: Boolean,
    ) {
        if (disposed) return
        val wasSamplingEligible = shouldSample()
        this.paused = paused
        this.sourceLoaded = sourceLoaded
        this.surfaceReady = surfaceReady
        this.videoOutputReady = videoOutputReady
        val samplingJustBecameEligible = !wasSamplingEligible && shouldSample()
        if (samplingJustBecameEligible) {
            armWarmStartDelay(DANMAKU_AI_PLAYBACK_WARM_START_DELAY_MS)
        }
        evaluateSamplingState(resetStaleMask = !sourceLoaded || !surfaceReady)
    }

    fun setExternallyPaused(value: Boolean) {
        if (disposed || externallyPaused == value) return
        val wasSamplingEligible = shouldSample()
        externallyPaused = value
        val samplingJustBecameEligible = !wasSamplingEligible && shouldSample()
        if (samplingJustBecameEligible) {
            armWarmStartDelay(DANMAKU_AI_PLAYBACK_WARM_START_DELAY_MS)
        }
        evaluateSamplingState(resetStaleMask = false)
    }

    fun setHasDanmakuOnScreen(value: Boolean) {
        if (disposed || hasDanmakuOnScreen == value) return
        val wasSamplingEligible = shouldSample()
        hasDanmakuOnScreen = value
        val samplingJustBecameEligible = !wasSamplingEligible && shouldSample()
        if (samplingJustBecameEligible) {
            armWarmStartDelay(DANMAKU_AI_PLAYBACK_WARM_START_DELAY_MS)
        }
        evaluateSamplingState(resetStaleMask = false)
    }

    fun onSourceChanged(source: MpvSource) {
        if (disposed) return
        currentSource = source
        failedPlanBSourceUrl = null
        releasePrecomputePipeline()
        cacheRestoreEligible = true
        clearRuntimeMaskState()
        capturePending = false
        captureInFlight = false
        activeBackendIndex = 0
        averageLatencyMs = 0.0
        overBudgetCount = 0
        degradationStage = 0
        stableRecoverySamples = 0
        warmStartDelayUntilUptimeMs = 0L
        lastFrameCacheWriteAtMs = 0L
        nextEligibleSampleUptimeMs = 0L
        lastSuccessfulDetectionUptimeMs = 0L
        consecutiveTrackedReuseSamples = 0
        resetTrackerLifecycle(reason = "source_changed")
        resetPrimaryTargetMemory()
        restoreCachedState()
        if (latestMaskPath == null) {
            emitUnavailableState(backend = currentBackendOrFallback(), keepEnabled = config.enabled)
        }
    }

    fun currentStateMap(): Map<String, Any?> = latestState.toMap()

    fun dispose() {
        if (disposed) return
        disposed = true
        stopSampling(clearPending = true)
        releasePrecomputePipeline()
        mainHandler.removeCallbacksAndMessages(null)
        inferenceHandler.removeCallbacksAndMessages(null)
        replaceRuntimeMaskBitmap(null)
        releaseRuntime()
        inferenceThread.quitSafely()
    }

    private fun clearRuntimeMaskState() {
        cancelPendingMaskGrace()
        latestRect = null
        latestTrackingRect = null
        latestRectTrackingEligible = false
        latestMaskValues = null
        latestMaskWidth = 0
        latestMaskHeight = 0
        latestMaskPath = null
        latestMaskSignature = null
        latestFramePath = null
        latestMaskTimestampMs = 0L
        latestMaskAppliedAtUptimeMs = 0L
        replaceRuntimeMaskBitmap(null)
        consecutiveEmptyFrames = 0
        // Force a fresh segmentation on the next sample (don't reuse a stale baseline).
        lastInferredLumaGrid = null
        consecutiveStaticSkips = 0
        previousFrameLumaSignature = null
        sceneCutRecoveryActive = false
        sceneCutBurstSamplesRemaining = 0
        stableMaskFramesSinceSceneCut = 0
        clearMotionBurst()
        latestMotionReferenceFrame = null
        previousMotionReferenceFrame = null
        lastMotionCompensation = null
        consecutiveMotionCompensationFailures = 0
        consecutiveCompensatedFrames = 0
        stableRecoverySamples = 0
        lastSuccessfulDetectionUptimeMs = 0L
        consecutiveTrackedReuseSamples = 0
        smallMultiStickySamplesRemaining = 0
        lastTrackerReuseFallbackReason = null
        resetTrackerLifecycle(reason = "clear_state")
        resetPrimaryTargetMemory()
        clearSmallMultiTracks()
    }

    private fun clearSmallMultiTracks() {
        smallMultiTracks = emptyList()
        smallMultiNextTrackId = 1
        smallMultiCoarseOnlySamples = 0
    }

    private fun resetTrackerLifecycle(reason: String = "reset") {
        trackerLifecycleState = TrackerLifecycleState.LOST
        trackerLifecycleReason = reason
        trackerSuccessStreak = 0
        trackerFailureStreak = 0
        trackerWeakStreak = 0
        trackerStableSinceUptimeMs = 0L
        lastTrackerConfidence = 0f
        lastTrackerGeometryPenalty = 1f
    }

    private fun resetPrimaryTargetMemory() {
        primaryTargetMemory = null
        primaryTargetCandidateRect = null
        primaryTargetCandidateWins = 0
        primaryTargetSwitchCooldownSamples = 0
        lastAcceptedTargetSource = "none"
    }

    private fun clearMotionBurst() {
        motionBurstSamplesRemaining = 0
        motionBurstReason = null
        pendingMotionBurstReason = null
    }

    private fun consumeMotionBurstSample() {
        if (motionBurstSamplesRemaining <= 0) {
            return
        }
        motionBurstSamplesRemaining -= 1
        if (motionBurstSamplesRemaining <= 0) {
            Log.d(
                DANMAKU_AI_TAG,
                "motion_burst end reason=${motionBurstReason ?: "complete"}",
            )
            motionBurstReason = null
        }
    }

    private fun markMotionBurstRequested(reason: String?) {
        val sanitizedReason = reason?.takeIf { it.isNotBlank() } ?: return
        pendingMotionBurstReason = sanitizedReason
    }

    private fun clearPendingMotionBurstRequest() {
        pendingMotionBurstReason = null
    }

    private fun consumePendingMotionBurstRequest(): String? {
        val reason = pendingMotionBurstReason
        pendingMotionBurstReason = null
        return reason
    }

    private fun shouldAllowMotionBurst(): Boolean {
        return !sceneCutRecoveryActive &&
            config.renderTargetFrameRateHz >= 90 &&
            degradationStage <= DANMAKU_AI_MOTION_BURST_MAX_DEGRADATION_STAGE
    }

    private fun currentMotionBurstIntervalMs(): Long {
        val floorInterval =
            max(
                DANMAKU_AI_MOTION_BURST_INTERVAL_MS,
                recommendedSamplingFloorMs() / 3L,
            )
        if (averageLatencyMs <= 0.0) {
            return floorInterval
        }
        val latencyBound =
            max(
                floorInterval,
                max(
                    averageLatencyMs.roundToInt().toLong() + DANMAKU_AI_MOTION_BURST_HEADROOM_MS,
                    (averageLatencyMs * DANMAKU_AI_MOTION_BURST_LATENCY_MULTIPLIER)
                        .roundToInt()
                        .toLong(),
                ),
            )
        return latencyBound.coerceIn(
            DANMAKU_AI_MOTION_BURST_INTERVAL_MS,
            preferredSampleIntervalMs(),
        )
    }

    private fun requestMotionBurst(reason: String) {
        if (!shouldAllowMotionBurst()) {
            return
        }
        val intervalMs = currentMotionBurstIntervalMs()
        val previousRemaining = motionBurstSamplesRemaining
        val nextRemaining = max(motionBurstSamplesRemaining, DANMAKU_AI_MOTION_BURST_SAMPLE_COUNT)
        val nextEligibleAt = SystemClock.uptimeMillis() + intervalMs
        val reasonChanged = motionBurstReason != reason
        motionBurstSamplesRemaining = nextRemaining
        motionBurstReason = reason
        nextEligibleSampleUptimeMs =
            if (nextEligibleSampleUptimeMs > 0L) {
                minOf(nextEligibleSampleUptimeMs, nextEligibleAt)
            } else {
                nextEligibleAt
            }
        if (reasonChanged || previousRemaining <= 0) {
            Log.d(
                DANMAKU_AI_TAG,
                "motion_burst start reason=$reason remaining=$nextRemaining intervalMs=$intervalMs trackerState=${trackerLifecycleState.wireValue}",
            )
        }
    }

    private fun cancelPendingMaskGrace() {
        pendingMaskGraceBackend = null
        pendingMaskGraceClearAtUptimeMs = 0L
        mainHandler.removeCallbacks(maskGraceExpireRunnable)
    }

    private fun evaluateSamplingState(resetStaleMask: Boolean) {
        if (!config.enabled) {
            return
        }
        if (!sourceLoaded || !surfaceReady || !videoOutputReady) {
            stopSampling(clearPending = true)
            stopPrecomputePipeline()
            if (resetStaleMask) {
                clearRuntimeMaskState()
            }
            emitUnavailableState(backend = currentBackendOrFallback(), keepEnabled = true)
            return
        }
        if (paused) {
            stopSampling(clearPending = false)
            stopPrecomputePipeline()
            emitLatestMaskStateIfAvailable()
            return
        }
        if (externallyPaused || !hasDanmakuOnScreen) {
            stopSampling(clearPending = false)
            stopPrecomputePipeline()
            emitLatestMaskStateIfAvailable()
            return
        }
        if (planBActive()) {
            stopSampling(clearPending = true)
            ensurePrecomputePipeline().start()
            return
        }
        val captureUnavailableReason = captureUnavailableReason()
        if (captureUnavailableReason != null) {
            stopSampling(clearPending = true)
            stopPrecomputePipeline()
            if (resetStaleMask) {
                clearRuntimeMaskState()
            }
            emitUnavailableState(
                backend = currentBackendOrFallback(),
                keepEnabled = true,
                backendWireValue = videoOutputTarget.backend.wireValue,
                unavailableReason = captureUnavailableReason,
            )
            return
        }
        stopPrecomputePipeline()
        val delayMs = (warmStartDelayUntilUptimeMs - SystemClock.uptimeMillis()).coerceAtLeast(0L)
        if (delayMs > 0L) {
            scheduleNextSample(delayMs = delayMs)
            return
        }
        maybeWarmupRuntime()
        if (samplingScheduled || processing || captureInFlight) {
            capturePending = true
            return
        }
        scheduleImmediateSample()
    }

    private fun armWarmStartDelay(delayMs: Long) {
        if (delayMs <= 0L) {
            return
        }
        val targetUptimeMs = SystemClock.uptimeMillis() + delayMs
        if (targetUptimeMs > warmStartDelayUntilUptimeMs) {
            warmStartDelayUntilUptimeMs = targetUptimeMs
        }
    }

    private fun captureUnavailableReason(): String? {
        if (videoOutputTarget.supportsAsyncBitmapCapture) {
            return null
        }
        if (videoOutputTarget.supportsBitmapCapture) {
            return if (config.renderTargetFrameRateHz > 60) {
                DANMAKU_AI_UNAVAILABLE_REASON_CAPTURE_BUDGET_UNSUPPORTED
            } else {
                null
            }
        }
        return DANMAKU_AI_UNAVAILABLE_REASON_CAPTURE_UNSUPPORTED
    }

    private fun maybeWarmupRuntime() {
        inferenceHandler.post {
            if (disposed || !config.enabled) {
                return@post
            }
            // Full-frame seg path (always on) needs no detector — just warm the seg
            // runtime. (Local sources warm their own decoder inside the pipeline.)
            ensureRuntime()
        }
    }

    private fun finishSamplingCycle() {
        if (disposed || !shouldSample()) {
            return
        }
        if (capturePending) {
            capturePending = false
            scheduleImmediateSample()
            return
        }
        scheduleNextSample()
    }

    private fun shouldSample(): Boolean {
        return config.enabled &&
            sourceLoaded &&
            surfaceReady &&
            videoOutputReady &&
            !paused &&
            !externallyPaused &&
            hasDanmakuOnScreen
    }

    private fun allowMaskRefinement(): Boolean {
        if (degradationStage < 3) {
            return true
        }
        return sampleSequence % DANMAKU_AI_DEGRADATION_RECOVERY_SAMPLES.toLong() == 0L
    }

    private fun currentDegradationLevel(): DanmakuOcclusionDegradationLevel {
        return when (degradationStage) {
            1 -> DanmakuOcclusionDegradationLevel.INTERVAL
            2 -> DanmakuOcclusionDegradationLevel.REDUCED_INPUT
            3 -> DanmakuOcclusionDegradationLevel.DISABLED
            else -> DanmakuOcclusionDegradationLevel.NONE
        }
    }

    private fun preferredInputWidthForFrameRate(): Int {
        val userPreferredWidth =
            config.inputWidth.coerceIn(
                DANMAKU_AI_DEGRADED_INPUT_WIDTH,
                DANMAKU_AI_REFINE_MAX_WIDTH,
            )
        val prefersHighQuality = userPreferredWidth >= DANMAKU_AI_HIGH_QUALITY_INPUT_WIDTH_THRESHOLD
        return when {
            config.renderTargetFrameRateHz >= 110 && prefersHighQuality ->
                DANMAKU_AI_BASE_INPUT_WIDTH_120HZ_QUALITY
            config.renderTargetFrameRateHz >= 110 ->
                DANMAKU_AI_BASE_INPUT_WIDTH_120HZ
            config.renderTargetFrameRateHz >= 90 && prefersHighQuality ->
                DANMAKU_AI_BASE_INPUT_WIDTH_90HZ_QUALITY
            config.renderTargetFrameRateHz >= 90 ->
                DANMAKU_AI_BASE_INPUT_WIDTH_90HZ
            prefersHighQuality ->
                DANMAKU_AI_BASE_INPUT_WIDTH_60HZ_QUALITY
            else ->
                DANMAKU_AI_BASE_INPUT_WIDTH_60HZ
        }
    }

    private fun effectiveInputWidth(): Int {
        val userPreferredWidth =
            config.inputWidth.coerceIn(
                DANMAKU_AI_DEGRADED_INPUT_WIDTH,
                DANMAKU_AI_REFINE_MAX_WIDTH,
            )
        val baselineWidth =
            minOf(
                userPreferredWidth,
                preferredInputWidthForFrameRate(),
            )
        return when {
            degradationStage >= 2 -> minOf(baselineWidth, DANMAKU_AI_REDUCED_INPUT_WIDTH)
            else -> baselineWidth
        }.coerceIn(DANMAKU_AI_DEGRADED_INPUT_WIDTH, DANMAKU_AI_REFINE_MAX_WIDTH)
    }

    private fun preferredSampleIntervalMs(): Long {
        var interval =
            max(
                config.sampleIntervalMs.coerceIn(
                    DANMAKU_AI_MIN_SAMPLE_INTERVAL_MS,
                    DANMAKU_AI_MAX_SAMPLE_INTERVAL_MS,
                ),
                recommendedSamplingFloorMs(),
            )
        if (degradationStage >= 1) {
            interval += DANMAKU_AI_DEGRADATION_INTERVAL_BACKOFF_MS
        }
        if (degradationStage >= 2) {
            interval += DANMAKU_AI_DEGRADATION_INTERVAL_BACKOFF_MS
        }
        if (degradationStage >= 3) {
            interval += DANMAKU_AI_DEGRADATION_INTERVAL_BACKOFF_MS
        }
        return interval.coerceIn(
            DANMAKU_AI_MIN_SAMPLE_INTERVAL_MS,
            DANMAKU_AI_MAX_SAMPLE_INTERVAL_MS,
        )
    }

    private fun trackedDetectionRefreshIntervalMs(): Long {
        return when {
            trackerLifecycleState == TrackerLifecycleState.WEAK ->
                DANMAKU_AI_TRACKED_DETECTION_REFRESH_INTERVAL_WEAK_MS
            trackerLifecycleState == TrackerLifecycleState.STABLE &&
                config.renderTargetFrameRateHz >= 110 &&
                degradationStage <= 0 ->
                DANMAKU_AI_TRACKED_DETECTION_REFRESH_INTERVAL_STABLE_120HZ_MS
            trackerLifecycleState == TrackerLifecycleState.STABLE &&
                config.renderTargetFrameRateHz >= 90 &&
                degradationStage <= 0 ->
                DANMAKU_AI_TRACKED_DETECTION_REFRESH_INTERVAL_STABLE_90HZ_MS
            config.renderTargetFrameRateHz >= 110 && degradationStage >= 2 ->
                DANMAKU_AI_TRACKED_DETECTION_REFRESH_INTERVAL_DEGRADED_MS
            config.renderTargetFrameRateHz >= 110 ->
                DANMAKU_AI_TRACKED_DETECTION_REFRESH_INTERVAL_120HZ_MS
            config.renderTargetFrameRateHz >= 90 && degradationStage >= 2 ->
                DANMAKU_AI_TRACKED_DETECTION_REFRESH_INTERVAL_DEGRADED_MS
            config.renderTargetFrameRateHz >= 90 ->
                DANMAKU_AI_TRACKED_DETECTION_REFRESH_INTERVAL_90HZ_MS
            else -> 0L
        }
    }

    private fun trackedDetectionMaxConsecutiveSamples(): Int {
        return when {
            config.renderTargetFrameRateHz < 90 -> 0
            trackerLifecycleState == TrackerLifecycleState.STABLE && degradationStage <= 0 ->
                DANMAKU_AI_TRACKED_DETECTION_MAX_CONSECUTIVE_SAMPLES_STABLE
            trackerLifecycleState == TrackerLifecycleState.WEAK ->
                DANMAKU_AI_TRACKED_DETECTION_MAX_CONSECUTIVE_SAMPLES_WEAK
            degradationStage >= 2 -> DANMAKU_AI_TRACKED_DETECTION_MAX_CONSECUTIVE_SAMPLES_DEGRADED
            else -> DANMAKU_AI_TRACKED_DETECTION_MAX_CONSECUTIVE_SAMPLES
        }
    }

    private fun resolveTrackedRectCandidate(
        trackerCandidate: DanmakuTrackedRectCandidate?,
        motionCompensation: DanmakuMotionCompensation?,
    ): DanmakuTrackedRectCandidate? {
        trackerCandidate?.let { candidate ->
            if (candidate.rect.area() >= DANMAKU_AI_DETECTION_MIN_AREA_RATIO) {
                return candidate
            }
        }
        val predictedTransform =
            predictTrackedTransform(
                sampleWidth = DANMAKU_AI_MOTION_SAMPLE_WIDTH,
                sampleHeight = DANMAKU_AI_MOTION_SAMPLE_HEIGHT,
            )
        val predictedRect = buildPredictedTrackedRect(predictedTransform)
        val compensatedRect = buildCompensatedPreviousRect(motionCompensation)
        val candidateRect =
            when {
                predictedRect != null && compensatedRect != null ->
                    blendTrackedRectCandidate(predictedRect, compensatedRect)
                compensatedRect != null ->
                    compensatedRect
                predictedRect != null ->
                    predictedRect
                else ->
                    trackingRectOrDisplayRect()
            } ?: return null
        if (candidateRect.area() < DANMAKU_AI_DETECTION_MIN_AREA_RATIO) {
            return null
        }
        val previousArea = trackingRectOrDisplayRect()?.area()?.takeIf { it > 0f }
        val predictedAreaRatio =
            predictedTransform?.predictedAreaRatio
                ?: previousArea?.let { (candidateRect.area() / it).coerceAtLeast(0f) }
                ?: 1f
        return DanmakuTrackedRectCandidate(
            rect = candidateRect,
            source =
                when {
                    predictedRect != null && compensatedRect != null -> "predicted+motion"
                    compensatedRect != null -> "motion"
                    predictedRect != null -> "predicted"
                    else -> "latest"
                },
            predictedScale = predictedTransform?.scale ?: 1f,
            predictedAreaRatio = predictedAreaRatio,
        )
    }

    private fun shouldAttemptTrackedRoi(
        frameContinuity: DanmakuFrameContinuity,
        trackedCandidate: DanmakuTrackedRectCandidate?,
    ): Boolean {
        if (frameContinuity.sceneCut || sceneCutRecoveryActive) {
            return false
        }
        if (trackerLifecycleState == TrackerLifecycleState.LOST) {
            return false
        }
        val trackedRect = trackedCandidate?.rect
        if (trackedRect == null || consecutiveEmptyFrames > 1) {
            return false
        }
        val previousArea = trackingRectOrDisplayRect()?.area()
        if (previousArea != null && previousArea > 0f) {
            val candidateAreaRatio = trackedRect.area() / previousArea
            if (
                candidateAreaRatio < DANMAKU_AI_TRACKED_ROI_MIN_AREA_RATIO ||
                    candidateAreaRatio > DANMAKU_AI_TRACKED_ROI_MAX_AREA_RATIO
            ) {
                return false
            }
        }
        val refreshIntervalMs = trackedDetectionRefreshIntervalMs()
        if (refreshIntervalMs <= 0L || lastSuccessfulDetectionUptimeMs <= 0L) {
            return false
        }
        if (consecutiveTrackedReuseSamples >= trackedDetectionMaxConsecutiveSamples()) {
            return false
        }
        return SystemClock.uptimeMillis() - lastSuccessfulDetectionUptimeMs < refreshIntervalMs
    }

    private fun centerDistanceBetweenRects(
        first: DanmakuNormalizedRect,
        second: DanmakuNormalizedRect,
    ): Float {
        return sqrt(
            ((first.centerX - second.centerX).pow(2)) +
                ((first.centerY - second.centerY).pow(2)),
        )
    }

    private fun shouldCancelMaskForLargeMotion(
        trackedCandidate: DanmakuTrackedRectCandidate?,
        motionCompensation: DanmakuMotionCompensation?,
        detectionRect: DanmakuNormalizedRect? = null,
        relaxDetectionPositionJump: Boolean = false,
    ): String? {
        val previousRect = trackingRectOrDisplayRect() ?: return null
        val previousArea = previousRect.area().takeIf { it > 0f } ?: return null
        motionCompensation?.let { compensation ->
            if (
                abs(compensation.dxNormalized) >= DANMAKU_AI_LARGE_MOTION_CANCEL_MAX_DX_NORMALIZED ||
                    abs(compensation.dyNormalized) >= DANMAKU_AI_LARGE_MOTION_CANCEL_MAX_DY_NORMALIZED
            ) {
                return "motion_translation"
            }
            if (abs(compensation.scale - 1f) >= DANMAKU_AI_LARGE_MOTION_CANCEL_SCALE_DELTA) {
                return "motion_scale"
            }
        }
        trackedCandidate?.let { candidate ->
            val trackedAreaRatio = (candidate.rect.area() / previousArea).coerceAtLeast(0f)
            if (
                trackedAreaRatio < DANMAKU_AI_LARGE_MOTION_CANCEL_MIN_AREA_RATIO ||
                    trackedAreaRatio > DANMAKU_AI_LARGE_MOTION_CANCEL_MAX_AREA_RATIO
            ) {
                return "tracked_area_jump"
            }
            val trackedIou = candidate.rect.iou(previousRect)
            val trackedCenterDistance = centerDistanceBetweenRects(candidate.rect, previousRect)
            if (
                trackedIou < DANMAKU_AI_LARGE_MOTION_CANCEL_MIN_IOU &&
                    trackedCenterDistance >= DANMAKU_AI_LARGE_MOTION_CANCEL_CENTER_DISTANCE
            ) {
                return "tracked_position_jump"
            }
        }
        detectionRect?.let { rect ->
            val detectionAreaRatio = (rect.area() / previousArea).coerceAtLeast(0f)
            if (
                detectionAreaRatio < DANMAKU_AI_LARGE_MOTION_CANCEL_MIN_AREA_RATIO ||
                    detectionAreaRatio > DANMAKU_AI_LARGE_MOTION_CANCEL_MAX_AREA_RATIO
            ) {
                return "detect_area_jump"
            }
            val detectionIou = rect.iou(previousRect)
            val detectionCenterDistance = centerDistanceBetweenRects(rect, previousRect)
            val fullScreenLikeDetection =
                rect.area() >= DANMAKU_AI_LARGE_MOTION_CANCEL_DETECTION_AREA_RATIO ||
                    rect.width >= DANMAKU_AI_LARGE_MOTION_CANCEL_DETECTION_WIDTH_RATIO ||
                    rect.height >= DANMAKU_AI_LARGE_MOTION_CANCEL_DETECTION_HEIGHT_RATIO
            if (
                fullScreenLikeDetection &&
                    (detectionIou < DANMAKU_AI_LARGE_MOTION_CANCEL_MIN_IOU ||
                        detectionAreaRatio > DANMAKU_AI_LARGE_MOTION_CANCEL_MAX_AREA_RATIO)
            ) {
                return "detect_fullscreen_jump"
            }
            if (
                detectionIou < DANMAKU_AI_LARGE_MOTION_CANCEL_MIN_IOU &&
                    detectionCenterDistance >= DANMAKU_AI_LARGE_MOTION_CANCEL_CENTER_DISTANCE &&
                    !relaxDetectionPositionJump
            ) {
                return "detect_position_jump"
            }
        }
        return null
    }

    private fun updateTrackingCadenceAfterInference(result: InferenceOutcome) {
        if (!shouldAllowMotionBurst() && motionBurstSamplesRemaining > 0) {
            clearMotionBurst()
        }
        when {
            result.detectionPerformed && result.primaryRect != null && result.maskResult != null -> {
                lastSuccessfulDetectionUptimeMs = SystemClock.uptimeMillis()
                consecutiveTrackedReuseSamples = 0
            }
            result.trackedRectReused && result.maskResult != null -> {
                consecutiveTrackedReuseSamples += 1
            }
            else -> {
                consecutiveTrackedReuseSamples = 0
            }
        }
        if (result.multiSmallMode && result.maskResult != null) {
            smallMultiStickySamplesRemaining = DANMAKU_AI_SMALL_MULTI_STICKY_SAMPLES
        } else if (smallMultiStickySamplesRemaining > 0) {
            smallMultiStickySamplesRemaining -= 1
        }
        consumePendingMotionBurstRequest()?.let(::requestMotionBurst)
    }

    private fun applySmallMultiTrackUpdate(result: InferenceOutcome) {
        result.nextSmallMultiTracks?.let { nextTracks ->
            smallMultiTracks = nextTracks
        }
        result.nextSmallMultiCoarseOnlySamples?.let { nextValue ->
            smallMultiCoarseOnlySamples = nextValue
        }
    }

    private fun ensurePersonTrackerRuntime(): PersonTrackerRuntime {
        synchronized(runtimeLock) {
            val existing = personTrackerRuntime
            if (existing != null) {
                return existing
            }
            return LumaTemplatePersonTrackerRuntime().also { personTrackerRuntime = it }
        }
    }

    private fun resetPersonTracker() {
        synchronized(runtimeLock) {
            personTrackerRuntime?.reset()
        }
        resetTrackerLifecycle(reason = "tracker_reset")
    }

    private fun initializePersonTracker(
        bitmap: Bitmap,
        rect: DanmakuNormalizedRect?,
    ): Boolean {
        val safeRect = rect ?: return false
        if (safeRect.area() < DANMAKU_AI_DETECTION_MIN_AREA_RATIO) {
            resetPersonTracker()
            return false
        }
        val initialized =
            runCatching {
            synchronized(runtimeLock) {
                ensurePersonTrackerRuntime().init(bitmap, safeRect)
            }
        }.getOrDefault(false)
        if (initialized) {
            trackerLifecycleState = TrackerLifecycleState.WARMUP
            trackerLifecycleReason = "init"
            trackerSuccessStreak = 0
            trackerFailureStreak = 0
            trackerWeakStreak = 0
            trackerStableSinceUptimeMs = 0L
            lastTrackerGeometryPenalty = 0f
        } else {
            resetTrackerLifecycle(reason = "init_failed")
        }
        return initialized
    }

    private fun updatePersonTracker(
        bitmap: Bitmap,
        frameContinuity: DanmakuFrameContinuity,
    ): PersonTrackingResult? {
        if (
            frameContinuity.sceneCut ||
                sceneCutRecoveryActive ||
                latestMaskValues == null ||
                trackingRectOrDisplayRect() == null ||
                latestMaskWidth <= 0 ||
                latestMaskHeight <= 0
        ) {
            return null
        }
        val tracker =
            synchronized(runtimeLock) {
                personTrackerRuntime
            } ?: return null
        return runCatching { tracker.update(bitmap) }.getOrElse {
            synchronized(runtimeLock) {
                tracker.reset()
            }
            resetTrackerLifecycle(reason = "update_exception")
            null
        }
    }

    private fun computeTrackerGeometryPenalty(
        trackedRect: DanmakuNormalizedRect?,
        referenceRect: DanmakuNormalizedRect?,
    ): Float {
        val nextRect = trackedRect ?: return 1f
        val previousRect = referenceRect ?: return 0f
        val areaRatio =
            (nextRect.area() / previousRect.area().coerceAtLeast(1e-4f))
                .coerceAtLeast(0.01f)
        val areaPenalty = abs(1f - areaRatio).coerceAtMost(1f)
        val centerPenalty =
            (centerDistanceBetweenRects(nextRect, previousRect) /
                DANMAKU_AI_TRACKER_REUSE_MAX_CENTER_DELTA).coerceIn(0f, 1.5f)
        val iouPenalty = 1f - nextRect.iou(previousRect).coerceIn(0f, 1f)
        return ((areaPenalty * 0.30f) + (centerPenalty * 0.35f) + (iouPenalty * 0.35f))
            .coerceIn(0f, 1f)
    }

    private fun updateTrackerLifecycleAfterUpdate(
        trackingResult: PersonTrackingResult?,
        trackedCandidate: DanmakuTrackedRectCandidate?,
    ) {
        val previousRect = trackingRectOrDisplayRect()
        val geometryPenalty = computeTrackerGeometryPenalty(trackedCandidate?.rect, previousRect)
        lastTrackerGeometryPenalty = geometryPenalty
        lastTrackerConfidence = trackingResult?.confidence ?: 0f
        val success = trackingResult?.success == true && trackedCandidate != null
        if (!success) {
            trackerSuccessStreak = 0
            trackerWeakStreak = 0
            trackerFailureStreak += 1
            if (trackerFailureStreak >= DANMAKU_AI_TRACKER_LOST_STREAK) {
                trackerLifecycleState = TrackerLifecycleState.LOST
                trackerLifecycleReason = trackingResult?.source ?: "tracker_lost"
                markMotionBurstRequested(trackerLifecycleReason)
            } else if (trackerLifecycleState != TrackerLifecycleState.LOST) {
                trackerLifecycleState = TrackerLifecycleState.WEAK
                trackerLifecycleReason = trackingResult?.source ?: "tracker_failed"
                markMotionBurstRequested(trackerLifecycleReason)
            }
            return
        }
        trackerFailureStreak = 0
        trackerSuccessStreak += 1
        val confidence = trackingResult?.confidence ?: 0f
        val weakSignal =
            confidence < DANMAKU_AI_TRACKER_WEAK_CONFIDENCE ||
                geometryPenalty >= DANMAKU_AI_TRACKER_GEOMETRY_WEAK_PENALTY
        when (trackerLifecycleState) {
            TrackerLifecycleState.LOST -> {
                trackerLifecycleState = TrackerLifecycleState.WARMUP
                trackerLifecycleReason = "recover_from_lost"
                trackerSuccessStreak = 1
            }
            TrackerLifecycleState.WARMUP -> {
                if (!weakSignal &&
                    trackerSuccessStreak >= DANMAKU_AI_TRACKER_WARMUP_STREAK &&
                    confidence >= DANMAKU_AI_TRACKER_STABLE_MIN_CONFIDENCE
                ) {
                    trackerLifecycleState = TrackerLifecycleState.STABLE
                    trackerLifecycleReason = "warmup_complete"
                    trackerStableSinceUptimeMs = SystemClock.uptimeMillis()
                    trackerWeakStreak = 0
                } else {
                    trackerLifecycleReason = if (weakSignal) "warmup_weak" else "warming"
                }
            }
            TrackerLifecycleState.STABLE -> {
                if (weakSignal) {
                    trackerWeakStreak += 1
                    if (trackerWeakStreak >= DANMAKU_AI_TRACKER_WEAK_STREAK) {
                        trackerLifecycleState = TrackerLifecycleState.WEAK
                        trackerLifecycleReason = "stable_weakened"
                        markMotionBurstRequested(trackerLifecycleReason)
                    }
                } else {
                    trackerWeakStreak = 0
                    trackerLifecycleReason = "stable"
                }
            }
            TrackerLifecycleState.WEAK -> {
                if (geometryPenalty >= DANMAKU_AI_TRACKER_GEOMETRY_LOST_PENALTY) {
                    trackerLifecycleState = TrackerLifecycleState.LOST
                    trackerLifecycleReason = "geometry_lost"
                    trackerFailureStreak = DANMAKU_AI_TRACKER_LOST_STREAK
                    markMotionBurstRequested(trackerLifecycleReason)
                } else if (!weakSignal) {
                    trackerWeakStreak += 1
                    if (trackerWeakStreak >= DANMAKU_AI_TRACKER_RECOVER_STREAK) {
                        trackerLifecycleState = TrackerLifecycleState.STABLE
                        trackerLifecycleReason = "weak_recovered"
                        trackerStableSinceUptimeMs = SystemClock.uptimeMillis()
                        trackerWeakStreak = 0
                    }
                } else {
                    trackerWeakStreak = 0
                    trackerLifecycleReason = "weak_tracking"
                }
            }
        }
    }

    private fun updateTrackerLifecycleAfterDetection(
        trackedCandidate: DanmakuTrackedRectCandidate?,
        detectionRect: DanmakuNormalizedRect?,
    ) {
        val trackerRect = trackedCandidate?.rect ?: return
        val targetRect = detectionRect ?: return
        val mismatch =
            trackerRect.iou(targetRect) < DANMAKU_AI_TRACKER_DETECTION_MISMATCH_IOU &&
                centerDistanceBetweenRects(trackerRect, targetRect) >=
                DANMAKU_AI_TRACKER_DETECTION_MISMATCH_CENTER_DISTANCE
        if (!mismatch) {
            return
        }
        trackerWeakStreak += 1
        if (trackerWeakStreak >= DANMAKU_AI_TRACKER_WEAK_STREAK) {
            trackerLifecycleState = TrackerLifecycleState.WEAK
            trackerLifecycleReason = "detect_mismatch"
            markMotionBurstRequested(trackerLifecycleReason)
        }
    }

    private fun buildTrackerRectCandidate(
        trackingResult: PersonTrackingResult?,
    ): DanmakuTrackedRectCandidate? {
        if (trackingResult?.success != true) {
            return null
        }
        val rect = trackingResult.rect ?: return null
        if (rect.area() < DANMAKU_AI_DETECTION_MIN_AREA_RATIO) {
            return null
        }
        val previousArea = trackingRectOrDisplayRect()?.area()?.takeIf { it > 0f }
        val predictedAreaRatio =
            previousArea?.let { (rect.area() / it).coerceAtLeast(0f) } ?: 1f
        val previousRect = trackingRectOrDisplayRect()
        val predictedScale =
            if (previousRect != null && previousRect.area() > 0f) {
                sqrt((rect.area() / previousRect.area()).coerceAtLeast(0.01f))
            } else {
                1f
            }
        return DanmakuTrackedRectCandidate(
            rect = rect,
            source = trackingResult.source,
            predictedScale = predictedScale,
            predictedAreaRatio = predictedAreaRatio,
            confidence = trackingResult.confidence,
        )
    }

    private fun shouldAttemptTrackerMaskReuse(
        frameContinuity: DanmakuFrameContinuity,
        trackedCandidate: DanmakuTrackedRectCandidate?,
    ): String? {
        if (frameContinuity.sceneCut || sceneCutRecoveryActive) {
            return "scene_cut"
        }
        if (motionBurstSamplesRemaining > 0) {
            return "motion_burst_reacquire"
        }
        if (trackerLifecycleState == TrackerLifecycleState.LOST) {
            return "tracker_lost"
        }
        val candidate = trackedCandidate ?: return "tracker_missing"
        if (!candidate.source.startsWith("tracker")) {
            return "tracker_unavailable"
        }
        if (
            trackerLifecycleState == TrackerLifecycleState.WARMUP &&
                consecutiveTrackedReuseSamples >= 1
        ) {
            return "tracker_warmup"
        }
        val confidence = candidate.confidence ?: return "tracker_unscored"
        if (confidence < DANMAKU_AI_TRACKER_REUSE_MIN_CONFIDENCE) {
            return "tracker_low_confidence"
        }
        if (!shouldAttemptTrackedRoi(frameContinuity, candidate)) {
            return "refresh_due"
        }
        val previousRect = trackingRectOrDisplayRect() ?: return "previous_rect_missing"
        val centerDistance = centerDistanceBetweenRects(candidate.rect, previousRect)
        if (centerDistance > DANMAKU_AI_TRACKER_REUSE_MAX_CENTER_DELTA) {
            return "tracker_center_jump"
        }
        val areaRatio =
            (candidate.rect.area() / previousRect.area().coerceAtLeast(1e-4f))
                .coerceAtLeast(0f)
        if (
            areaRatio < DANMAKU_AI_TRACKER_REUSE_MIN_AREA_RATIO ||
                areaRatio > DANMAKU_AI_TRACKER_REUSE_MAX_AREA_RATIO
        ) {
            return "tracker_area_jump"
        }
        return null
    }

    private fun computeMaskGeometryStats(
        values: FloatArray,
        width: Int,
        height: Int,
    ): MaskGeometryStats? {
        var left = width
        var top = height
        var right = -1
        var bottom = -1
        var totalWeight = 0f
        var weightedX = 0f
        var weightedY = 0f
        for (y in 0 until height) {
            val row = y * width
            for (x in 0 until width) {
                val value = values[row + x]
                if (value < DANMAKU_AI_RENDER_MASK_SUPPORT_THRESHOLD) {
                    continue
                }
                left = minOf(left, x)
                top = minOf(top, y)
                right = maxOf(right, x)
                bottom = maxOf(bottom, y)
                totalWeight += value
                weightedX += x.toFloat() * value
                weightedY += y.toFloat() * value
            }
        }
        if (right <= left || bottom <= top || totalWeight <= 0f) {
            return null
        }
        return MaskGeometryStats(
            boundingRect =
                DanmakuNormalizedRect(
                    x = left.toFloat() / width.toFloat(),
                    y = top.toFloat() / height.toFloat(),
                    width = (right - left + 1).toFloat() / width.toFloat(),
                    height = (bottom - top + 1).toFloat() / height.toFloat(),
                ),
            centroidX = (weightedX / totalWeight) / width.toFloat(),
            centroidY = (weightedY / totalWeight) / height.toFloat(),
        )
    }

    private fun estimateMaskReuseAdjustment(
        bitmap: Bitmap,
        previousRect: DanmakuNormalizedRect,
        trackedRect: DanmakuNormalizedRect,
        width: Int,
        height: Int,
        previousMaskStats: MaskGeometryStats,
    ): MaskReuseAdjustment? {
        if (trackedRect.area() < DANMAKU_AI_MASK_ADJUST_MIN_RECT_AREA) {
            return null
        }
        if (degradationStage > 0 || trackerLifecycleState == TrackerLifecycleState.LOST) {
            return null
        }
        if (trackerLifecycleState != TrackerLifecycleState.STABLE &&
            trackerLifecycleState != TrackerLifecycleState.WEAK
        ) {
            return null
        }
        val leftPx = (trackedRect.left * bitmap.width.toFloat()).roundToInt().coerceIn(0, bitmap.width - 1)
        val topPx = (trackedRect.top * bitmap.height.toFloat()).roundToInt().coerceIn(0, bitmap.height - 1)
        val rightPx = (trackedRect.right * bitmap.width.toFloat()).roundToInt().coerceIn(leftPx, bitmap.width - 1)
        val bottomPx = (trackedRect.bottom * bitmap.height.toFloat()).roundToInt().coerceIn(topPx, bitmap.height - 1)
        val roiWidth = rightPx - leftPx + 1
        val roiHeight = bottomPx - topPx + 1
        if (roiWidth < 8 || roiHeight < 8) {
            return null
        }
        val step = DANMAKU_AI_MASK_ADJUST_EDGE_SAMPLE_STEP
        var totalWeight = 0f
        var weightedX = 0f
        var weightedY = 0f
        var minSampleX = Int.MAX_VALUE
        var minSampleY = Int.MAX_VALUE
        var maxSampleX = Int.MIN_VALUE
        var maxSampleY = Int.MIN_VALUE
        var y = topPx
        while (y <= bottomPx) {
            var x = leftPx
            while (x <= rightPx) {
                val current = bitmap.getPixel(x, y)
                val right = bitmap.getPixel(minOf(x + step, rightPx), y)
                val bottom = bitmap.getPixel(x, minOf(y + step, bottomPx))
                val currentLuma = ((Color.red(current) * 77) + (Color.green(current) * 150) + (Color.blue(current) * 29)) shr 8
                val rightLuma = ((Color.red(right) * 77) + (Color.green(right) * 150) + (Color.blue(right) * 29)) shr 8
                val bottomLuma = ((Color.red(bottom) * 77) + (Color.green(bottom) * 150) + (Color.blue(bottom) * 29)) shr 8
                val edgeWeight =
                    (abs(currentLuma - rightLuma) + abs(currentLuma - bottomLuma)).toFloat()
                if (edgeWeight >= DANMAKU_AI_MASK_ADJUST_EDGE_WEIGHT_THRESHOLD) {
                    totalWeight += edgeWeight
                    weightedX += (x - leftPx).toFloat() * edgeWeight
                    weightedY += (y - topPx).toFloat() * edgeWeight
                    minSampleX = minOf(minSampleX, x - leftPx)
                    minSampleY = minOf(minSampleY, y - topPx)
                    maxSampleX = maxOf(maxSampleX, x - leftPx)
                    maxSampleY = maxOf(maxSampleY, y - topPx)
                }
                x += step
            }
            y += step
        }
        if (totalWeight < DANMAKU_AI_MASK_ADJUST_MIN_EDGE_WEIGHT || minSampleX >= maxSampleX || minSampleY >= maxSampleY) {
            return null
        }
        val roiCentroidX = (weightedX / totalWeight) / roiWidth.toFloat()
        val roiCentroidY = (weightedY / totalWeight) / roiHeight.toFloat()
        val maskCentroidLocalX =
            ((previousMaskStats.centroidX - previousRect.left) / previousRect.width.coerceAtLeast(1e-4f))
                .coerceIn(0f, 1f)
        val maskCentroidLocalY =
            ((previousMaskStats.centroidY - previousRect.top) / previousRect.height.coerceAtLeast(1e-4f))
                .coerceIn(0f, 1f)
        val dxPx =
            (((roiCentroidX - maskCentroidLocalX) * trackedRect.width * width.toFloat())
                .roundToInt())
                .coerceIn(
                    (-(trackedRect.width * width.toFloat() * DANMAKU_AI_MASK_ADJUST_MAX_DX_RATIO).roundToInt()),
                    (trackedRect.width * width.toFloat() * DANMAKU_AI_MASK_ADJUST_MAX_DX_RATIO).roundToInt(),
                )
        val dyPx =
            (((roiCentroidY - maskCentroidLocalY) * trackedRect.height * height.toFloat())
                .roundToInt())
                .coerceIn(
                    (-(trackedRect.height * height.toFloat() * DANMAKU_AI_MASK_ADJUST_MAX_DY_RATIO).roundToInt()),
                    (trackedRect.height * height.toFloat() * DANMAKU_AI_MASK_ADJUST_MAX_DY_RATIO).roundToInt(),
                )
        val edgeWidthRatio = (maxSampleX - minSampleX + step).toFloat() / roiWidth.toFloat()
        val edgeHeightRatio = (maxSampleY - minSampleY + step).toFloat() / roiHeight.toFloat()
        val previousMaskWidthRatio =
            (previousMaskStats.boundingRect.width / previousRect.width.coerceAtLeast(1e-4f)).coerceIn(0.2f, 1.4f)
        val previousMaskHeightRatio =
            (previousMaskStats.boundingRect.height / previousRect.height.coerceAtLeast(1e-4f)).coerceIn(0.2f, 1.4f)
        val spanScale =
            (((edgeWidthRatio / previousMaskWidthRatio) + (edgeHeightRatio / previousMaskHeightRatio)) * 0.5f)
                .coerceIn(1f - DANMAKU_AI_MASK_ADJUST_MAX_SCALE_DELTA, 1f + DANMAKU_AI_MASK_ADJUST_MAX_SCALE_DELTA)
        if (dxPx == 0 && dyPx == 0 && abs(spanScale - 1f) < 0.01f) {
            return null
        }
        return MaskReuseAdjustment(
            dxPx = dxPx,
            dyPx = dyPx,
            scale = spanScale,
            source = "roi_edge_envelope",
        )
    }

    private fun buildTrackerMaskReuseResult(
        bitmap: Bitmap,
        trackedRect: DanmakuNormalizedRect,
    ): Pair<DanmakuMaskResult, MaskReuseAdjustment?>? {
        val previousMask = latestMaskValues ?: return null
        val width = latestMaskWidth.takeIf { it > 0 } ?: return null
        val height = latestMaskHeight.takeIf { it > 0 } ?: return null
        val previousRect = trackingRectOrDisplayRect() ?: return null
        val baseDxPx =
            ((trackedRect.centerX - previousRect.centerX) * width.toFloat()).roundToInt()
        val baseDyPx =
            ((trackedRect.centerY - previousRect.centerY) * height.toFloat()).roundToInt()
        val baseScale =
            sqrt(
                (trackedRect.area() / previousRect.area().coerceAtLeast(1e-4f))
                    .coerceAtLeast(0.01f),
            )
        val previousMaskStats = computeMaskGeometryStats(previousMask, width, height)
        val adjustment =
            previousMaskStats?.let {
                estimateMaskReuseAdjustment(
                    bitmap = bitmap,
                    previousRect = previousRect,
                    trackedRect = trackedRect,
                    width = width,
                    height = height,
                    previousMaskStats = it,
                )
            }
        val dxPx = baseDxPx + (adjustment?.dxPx ?: 0)
        val dyPx = baseDyPx + (adjustment?.dyPx ?: 0)
        val scale =
            (baseScale * (adjustment?.scale ?: 1f))
                .coerceIn(
                    DANMAKU_AI_MOTION_PREDICTION_MIN_SCALE,
                    DANMAKU_AI_MOTION_PREDICTION_MAX_SCALE,
                )
        val anchorCenterX = previousRect.centerX * width.toFloat()
        val anchorCenterY = previousRect.centerY * height.toFloat()
        val maskValues =
            transformMaskValues(
                values = previousMask,
                width = width,
                height = height,
                dxPx = dxPx,
                dyPx = dyPx,
                scale = scale,
                anchorCenterX = anchorCenterX,
                anchorCenterY = anchorCenterY,
            )
        return DanmakuMaskResult(
            maskValues = maskValues,
            maskWidth = width,
            maskHeight = height,
            normalizedRect = trackedRect,
        ) to adjustment
    }

    private fun replaceRuntimeMaskBitmap(nextBitmap: Bitmap?) {
        if (latestRuntimeMaskBitmap === nextBitmap) {
            return
        }
        latestRuntimeMaskBitmap?.takeIf { it !== nextBitmap && !it.isRecycled }?.recycle()
        latestRuntimeMaskBitmap = nextBitmap
    }

    private fun createRuntimeMaskBitmap(
        width: Int,
        height: Int,
        maskValues: FloatArray,
    ): Bitmap {
        val pixels = IntArray(width * height)
        for (index in pixels.indices) {
            val alpha = (maskValues[index].coerceIn(0f, 1f) * 255f).toInt().coerceIn(0, 255)
            pixels[index] = Color.argb(alpha, 255, 255, 255)
        }
        return Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
    }

    private fun updateDegradationAfterSample(
        latencyMs: Long,
        occlusionMode: DanmakuOcclusionMode,
    ) {
        val budgetThresholdMs = preferredSampleIntervalMs()
        if (latencyMs > budgetThresholdMs) {
            overBudgetCount += 1
            stableRecoverySamples = 0
            if (overBudgetCount >= DANMAKU_AI_OVER_BUDGET_LIMIT && degradationStage < 3) {
                degradationStage += 1
                overBudgetCount = 0
                Log.d(
                    DANMAKU_AI_TAG,
                    "degrade stage=$degradationStage reason=latency latencyMs=$latencyMs budgetMs=$budgetThresholdMs",
                )
            }
            return
        }
        overBudgetCount = max(0, overBudgetCount - 1)
        if (occlusionMode != DanmakuOcclusionMode.MASK || averageLatencyMs <= 0.0) {
            stableRecoverySamples = 0
            return
        }
        val recoveryThresholdMs = budgetThresholdMs.toDouble() * DANMAKU_AI_DEGRADATION_RECOVERY_LATENCY_RATIO
        if (averageLatencyMs <= recoveryThresholdMs) {
            stableRecoverySamples += 1
            if (stableRecoverySamples >= DANMAKU_AI_DEGRADATION_RECOVERY_SAMPLES && degradationStage > 0) {
                degradationStage -= 1
                stableRecoverySamples = 0
                Log.d(
                    DANMAKU_AI_TAG,
                    "recover stage=$degradationStage avgLatencyMs=${"%.1f".format(Locale.US, averageLatencyMs)} budgetMs=$budgetThresholdMs",
                )
            }
        } else {
            stableRecoverySamples = 0
        }
    }

    private fun scheduleNextSample() {
        scheduleNextSample(delayMs = currentSampleIntervalMs())
    }

    private fun scheduleNextSample(delayMs: Long) {
        if (disposed || !shouldSample() || samplingScheduled) {
            return
        }
        val nowUptimeMs = SystemClock.uptimeMillis()
        val clampedDelayMs =
            max(
                delayMs.coerceAtLeast(0L),
                (nextEligibleSampleUptimeMs - nowUptimeMs).coerceAtLeast(0L),
            )
        samplingScheduled = true
        mainHandler.postDelayed(sampleRunnable, clampedDelayMs)
    }

    private fun scheduleImmediateSample() {
        scheduleNextSample(delayMs = 0L)
    }

    private fun stopSampling(clearPending: Boolean) {
        mainHandler.removeCallbacks(sampleRunnable)
        samplingScheduled = false
        activeCaptureRequestId?.let(videoOutputTarget::cancelBitmapCapture)
        activeCaptureRequestId = null
        captureInFlight = false
        nextEligibleSampleUptimeMs = 0L
        if (clearPending) {
            capturePending = false
        }
    }

    private fun captureFrameAndInfer() {
        // Live-capture path (network sources only — local sources are served by the
        // DanmakuMaskPrecomputePipeline and never reach here). Masks are for the current
        // frame, not a future PTS; clear any stale Plan B PTS so the overlay uses the
        // extrapolation fallback (not the PTS buffer). Aspect=0 → overlay maps to full
        // view (the rendered-surface mask already includes letterbox bars).
        latestMaskPtsMs = 0L
        currentPlanBVideoAspect = 0.0
        // Live-capture path (network sources): masks are for the current frame, not a
        // future PTS. Clear any stale Plan B PTS so the overlay uses the extrapolation
        // fallback (not the PTS buffer). Aspect=0 → overlay maps to full view (the
        // rendered-surface mask already includes letterbox bars).
        latestMaskPtsMs = 0L
        currentPlanBVideoAspect = 0.0
        val captureUnavailableReason = captureUnavailableReason()
        if (captureUnavailableReason != null) {
            stopSampling(clearPending = true)
            emitUnavailableState(
                backend = currentBackendOrFallback(),
                keepEnabled = config.enabled,
                backendWireValue = videoOutputTarget.backend.wireValue,
                unavailableReason = captureUnavailableReason,
            )
            return
        }
        val sampleId = ++sampleSequence
        nextEligibleSampleUptimeMs =
            max(
                nextEligibleSampleUptimeMs,
                SystemClock.uptimeMillis() + currentSampleIntervalMs(),
            )
        val captureStartedAt = SystemClock.elapsedRealtime()
        if (videoOutputTarget.supportsAsyncBitmapCapture) {
            captureInFlight = true
            val requestId =
                videoOutputTarget.requestBitmapCapture(
                    width = DANMAKU_AI_CAPTURE_WIDTH,
                    height = DANMAKU_AI_CAPTURE_HEIGHT,
                    sampleAreaRatio = config.sampleAreaRatio,
                ) { capturedFrame ->
                    activeCaptureRequestId = null
                    captureInFlight = false
                    if (disposed) {
                        capturedFrame?.bitmap?.takeIf { !it.isRecycled }?.recycle()
                        return@requestBitmapCapture
                    }
                    val captureLatencyMs = SystemClock.elapsedRealtime() - captureStartedAt
                    val bitmap = capturedFrame?.bitmap
                    if (bitmap == null) {
                        Log.w(
                            DANMAKU_AI_TAG,
                            "sample=$sampleId backend=${currentBackendOrFallback().wireValue} async capture failed size=${DANMAKU_AI_CAPTURE_WIDTH}x${DANMAKU_AI_CAPTURE_HEIGHT}",
                        )
                        emitUnavailableState(
                            backend = currentBackendOrFallback(),
                            keepEnabled = config.enabled,
                        )
                        finishSamplingCycle()
                        return@requestBitmapCapture
                    }
                    lastCaptureBackend = capturedFrame.captureBackend
                    maybeLogSamplingSlowPath(
                        sampleId = sampleId,
                        backend = currentBackendOrFallback(),
                        captureLatencyMs = captureLatencyMs,
                        inferenceLatencyMs = null,
                        totalLatencyMs = captureLatencyMs,
                        reason = "capture",
                    )
                    processing = true
                    inferenceHandler.post {
                        runInference(
                            bitmap = bitmap,
                            sampleId = sampleId,
                            captureLatencyMs = captureLatencyMs,
                            sampleAreaRatio = capturedFrame.sampleAreaRatio,
                        )
                    }
                }
            if (requestId == null) {
                captureInFlight = false
                emitUnavailableState(
                    backend = currentBackendOrFallback(),
                    keepEnabled = config.enabled,
                    unavailableReason = DANMAKU_AI_UNAVAILABLE_REASON_CAPTURE_UNSUPPORTED,
                )
                finishSamplingCycle()
                return
            }
            activeCaptureRequestId = requestId
            return
        }
        val capturedFrame =
            videoOutputTarget.captureBitmap(
                width = DANMAKU_AI_CAPTURE_WIDTH,
                height = DANMAKU_AI_CAPTURE_HEIGHT,
                sampleAreaRatio = config.sampleAreaRatio,
            )
        val captureLatencyMs = SystemClock.elapsedRealtime() - captureStartedAt
        val bitmap = capturedFrame?.bitmap
        if (bitmap == null) {
            Log.w(
                DANMAKU_AI_TAG,
                "sample=$sampleId backend=${currentBackendOrFallback().wireValue} capture failed size=${DANMAKU_AI_CAPTURE_WIDTH}x${DANMAKU_AI_CAPTURE_HEIGHT}",
            )
            emitUnavailableState(backend = currentBackendOrFallback(), keepEnabled = config.enabled)
            finishSamplingCycle()
            return
        }
        lastCaptureBackend = capturedFrame.captureBackend
        maybeLogSamplingSlowPath(
            sampleId = sampleId,
            backend = currentBackendOrFallback(),
            captureLatencyMs = captureLatencyMs,
            inferenceLatencyMs = null,
            totalLatencyMs = captureLatencyMs,
            reason = "capture",
        )
        processing = true
        inferenceHandler.post {
            runInference(
                bitmap = bitmap,
                sampleId = sampleId,
                captureLatencyMs = captureLatencyMs,
                sampleAreaRatio = capturedFrame.sampleAreaRatio,
            )
        }
    }

    // --- Global motion estimation for between-sample mask extrapolation ---
    private var prevMotionLumaGrid: IntArray? = null
    private var prevMotionLumaUptimeMs = 0L

    // Static-scene skip: the luma grid at the last frame we actually ran segmentation
    // on. If the current frame barely differs, the mask hasn't meaningfully changed —
    // skip the (CPU-heavy, throttling-inducing) seg and keep the last mask. Re-infer at
    // least every N skips so slow drift / a missed change can't freeze the mask forever.
    private var lastInferredLumaGrid: IntArray? = null
    private var consecutiveStaticSkips = 0

    @Volatile
    private var latestMaskVelocityX = 0.0

    @Volatile
    private var latestMaskVelocityY = 0.0

    private fun updateGlobalMotionVelocity(
        bitmap: Bitmap,
        nowUptimeMs: Long,
    ) {
        updateGlobalMotionVelocity(sampleMotionLumaGrid(bitmap), nowUptimeMs)
    }

    private fun updateGlobalMotionVelocity(
        grid: IntArray,
        nowUptimeMs: Long,
    ) {
        val prev = prevMotionLumaGrid
        val dt = nowUptimeMs - prevMotionLumaUptimeMs
        if (prev != null && prev.size == grid.size && dt in 1L..1500L) {
            val shift = estimateGlobalShift(prev, grid)
            // content motion in normalized units per ms (positive dx = moved right)
            val vx = (shift.first.toDouble() / DANMAKU_AI_MOTION_VEL_GRID_W.toDouble()) / dt.toDouble()
            val vy = (shift.second.toDouble() / DANMAKU_AI_MOTION_VEL_GRID_H.toDouble()) / dt.toDouble()
            latestMaskVelocityX = (latestMaskVelocityX * 0.4) + (vx * 0.6)
            latestMaskVelocityY = (latestMaskVelocityY * 0.4) + (vy * 0.6)
        } else {
            latestMaskVelocityX = 0.0
            latestMaskVelocityY = 0.0
        }
        prevMotionLumaGrid = grid
        prevMotionLumaUptimeMs = nowUptimeMs
    }

    // Mean absolute per-cell luma difference between two equal-length grids (0-255).
    private fun gridMeanAbsDiff(a: IntArray, b: IntArray): Float {
        if (a.size != b.size || a.isEmpty()) return Float.MAX_VALUE
        var sum = 0L
        for (i in a.indices) {
            sum += abs(a[i] - b[i])
        }
        return sum.toFloat() / a.size.toFloat()
    }

    private fun sampleMotionLumaGrid(bitmap: Bitmap): IntArray {
        val w = DANMAKU_AI_MOTION_VEL_GRID_W
        val h = DANMAKU_AI_MOTION_VEL_GRID_H
        val scaled =
            if (bitmap.width == w && bitmap.height == h) {
                bitmap
            } else {
                Bitmap.createScaledBitmap(bitmap, w, h, true)
            }
        val pixels = IntArray(w * h)
        scaled.getPixels(pixels, 0, w, 0, 0, w, h)
        if (scaled !== bitmap && !scaled.isRecycled) {
            scaled.recycle()
        }
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

    // Best (dx, dy) in grid samples aligning prev->curr content (positive dx = right).
    private fun estimateGlobalShift(
        prev: IntArray,
        curr: IntArray,
    ): Pair<Int, Int> {
        val w = DANMAKU_AI_MOTION_VEL_GRID_W
        val h = DANMAKU_AI_MOTION_VEL_GRID_H
        val search = DANMAKU_AI_MOTION_VEL_SEARCH
        var bestDx = 0
        var bestDy = 0
        var bestScore = Long.MAX_VALUE
        val minCount = (w * h) / 2
        for (dy in -search..search) {
            for (dx in -search..search) {
                var sad = 0L
                var count = 0
                var y = maxOf(0, -dy)
                val yEnd = minOf(h, h - dy)
                while (y < yEnd) {
                    val prevRow = y * w
                    val currRow = (y + dy) * w
                    var x = maxOf(0, -dx)
                    val xEnd = minOf(w, w - dx)
                    while (x < xEnd) {
                        val diff = prev[prevRow + x] - curr[currRow + (x + dx)]
                        sad += if (diff >= 0) diff.toLong() else (-diff).toLong()
                        count += 1
                        x += 1
                    }
                    y += 1
                }
                if (count < minCount) {
                    continue
                }
                val score = (sad * 256L / count.toLong()) + (abs(dx) + abs(dy)).toLong()
                if (score < bestScore) {
                    bestScore = score
                    bestDx = dx
                    bestDy = dy
                }
            }
        }
        return bestDx to bestDy
    }


    private fun recycleCaptureBitmapIfAsync(bitmap: Bitmap) {
        if (bitmap !== latestRuntimeMaskBitmap &&
            videoOutputTarget.supportsAsyncBitmapCapture &&
            !bitmap.isRecycled
        ) {
            bitmap.recycle()
        }
    }

    private fun buildFullFrameMaskResult(output: DanmakuSegmentationOutput): DanmakuMaskResult? {
        val w = output.width
        val h = output.height
        val values = output.maskValues
        if (w <= 0 || h <= 0 || values.size < w * h) {
            return null
        }
        var foreground = 0
        for (index in 0 until w * h) {
            if (values[index] >= DANMAKU_AI_MNN_MASK_THRESHOLD) {
                foreground += 1
            }
        }
        val ratio = foreground.toFloat() / (w * h).toFloat()
        if (ratio < DANMAKU_AI_MNN_MIN_FOREGROUND_RATIO) {
            // Almost empty — scenery / no subject. Treat as empty result.
            return null
        }
        if (ratio > DANMAKU_AI_MNN_MAX_FOREGROUND_RATIO) {
            // Subject fills most of the screen (big close-up). Masking would hide
            // nearly all danmaku — skip masking so danmaku stays readable.
            return null
        }
        // Keep the model's precise contour, but steepen the alpha so the subject
        // INTERIOR becomes fully opaque (the old soft 0.5-1.0 values only partially
        // erased danmaku → faint imprint on the person). A thin soft band at the very
        // edge ([LOW,HIGH]) is preserved so the outline stays precise, not dilated/blocky.
        val mask = FloatArray(w * h)
        val low = DANMAKU_AI_MNN_MASK_EDGE_LOW
        val span = (DANMAKU_AI_MNN_MASK_EDGE_HIGH - low).coerceAtLeast(1e-4f)
        for (index in 0 until w * h) {
            mask[index] = ((values[index] - low) / span).coerceIn(0f, 1f)
        }
        return DanmakuMaskResult(
            maskValues = mask,
            maskWidth = w,
            maskHeight = h,
            normalizedRect = DanmakuNormalizedRect(x = 0f, y = 0f, width = 1f, height = 1f),
            occlusionMode = DanmakuOcclusionMode.MASK,
        )
    }

    // --- Plan B mask metadata (shared by the producer pipeline + live-capture path) ---
    // PTS (video ms) the latest mask was computed for. The pipeline tags each mask so the
    // overlay PTS-syncs to it; the live-capture path sets 0 (no PTS sync).
    @Volatile
    private var latestMaskPtsMs = 0L

    // Video display aspect (w/h) attached to the most recent mask. >0 for pipeline masks
    // (raw-frame mask → overlay maps it to the letterboxed video rect); 0 for the
    // live-capture path (rendered surface already includes bars).
    @Volatile
    private var currentPlanBVideoAspect = 0.0

    private fun currentPlanBDecodeSource(): DanmakuPlanBDecodeSource? {
        val source = currentSource ?: return null
        return DanmakuPlanBSourcePolicy.resolve(
            url = source.url,
            headers = source.headers,
            networkEnabled = config.networkPrecomputeEnabled,
            failedUrl = failedPlanBSourceUrl,
        )
    }

    private fun planBActive(): Boolean = DANMAKU_AI_PLAN_B && currentPlanBDecodeSource() != null

    // --- Plan B v2: producer pipeline (dense decode-ahead masks) ---
    private var precomputePipeline: DanmakuMaskPrecomputePipeline? = null

    private fun ensurePrecomputePipeline(): DanmakuMaskPrecomputePipeline {
        precomputePipeline?.let { return it }
        val pipeline =
            DanmakuMaskPrecomputePipeline(
                runtimeFactory = runtimeFactory,
                configProvider = { config },
                positionMsProvider = positionProviderMs,
                playbackSpeedProvider = playbackSpeedProvider,
                decodeSourceProvider = { currentPlanBDecodeSource() },
                onStep = { step -> mainHandler.post { emitPipelineStep(step) } },
                onSourceFailure = { failedSource, reason ->
                    mainHandler.post { handlePlanBSourceFailure(failedSource, reason) }
                },
            )
        precomputePipeline = pipeline
        return pipeline
    }

    private fun handlePlanBSourceFailure(
        failedSource: DanmakuPlanBDecodeSource,
        reason: String,
    ) {
        if (disposed || currentSource?.url?.trim() != failedSource.sourceUrl) return
        failedPlanBSourceUrl = failedSource.sourceUrl
        Log.w(
            "FlyPlayerDanmaku",
            "planb2 source disabled reason=$reason source=${failedSource.url.substringBefore('?').take(120)}",
        )
        releasePrecomputePipeline()
        evaluateSamplingState(resetStaleMask = true)
    }

    private fun stopPrecomputePipeline() {
        precomputePipeline?.pause()
    }

    private fun releasePrecomputePipeline() {
        precomputePipeline?.release()
        precomputePipeline = null
    }

    private fun emitPipelineStep(step: DanmakuMaskPrecomputePipeline.MaskStep) {
        if (disposed) {
            step.mask?.takeIf { !it.isRecycled }?.recycle()
            return
        }
        val mask = step.mask
        if (mask == null || mask.isRecycled) {
            // Phase A: an empty step ages out via the overlay staleness guard. The
            // renderer-side "clear without grace" handling of empty PTS samples lands
            // in Phase B/C — for now we simply don't push it.
            return
        }
        cancelPendingMaskGrace()
        latestMaskPtsMs = step.ptsMs
        currentPlanBVideoAspect = step.videoAspect
        latestMaskVelocityX = step.vxPerMs
        latestMaskVelocityY = step.vyPerMs
        latestRect = DanmakuNormalizedRect(x = 0f, y = 0f, width = 1f, height = 1f)
        latestTrackingRect = null
        latestRectTrackingEligible = false
        latestMaskWidth = step.maskWidth
        latestMaskHeight = step.maskHeight
        latestMaskTimestampMs = System.currentTimeMillis()
        latestMaskAppliedAtUptimeMs = SystemClock.uptimeMillis()
        consecutiveEmptyFrames = 0
        replaceRuntimeMaskBitmap(mask)
        emitState(
            DanmakuDynamicOcclusionState(
                enabled = true,
                available = true,
                backend = DanmakuAiBackend.PADDLE.wireValue,
                occlusionMode = DanmakuOcclusionMode.MASK.wireValue,
                updatedAtMs = latestMaskTimestampMs,
                maskPath = null,
                maskSignature = null,
                maskWidth = step.maskWidth,
                maskHeight = step.maskHeight,
                framePath = null,
                cacheHit = false,
                captureAreaRatio = 1f,
                normalizedRect = latestRect,
                unavailableReason = null,
                captureBackend = lastCaptureBackend,
                degradationLevel = DanmakuOcclusionDegradationLevel.NONE.wireValue,
                effectiveSampleIntervalMs = step.stepMs,
                effectiveInputWidth = step.inputWidth,
                // Plan B always forwards per-step velocity: the renderer caps it to one
                // step (~280ms), so it can't over-slide. The "蒙版跟随运动"
                // (motionTrackingEnabled) toggle exists to tame the LIVE/network path's
                // stronger wall-clock extrapolation — it does not gate Plan B.
                maskVelocityX = step.vxPerMs,
                maskVelocityY = step.vyPerMs,
                maskPtsMs = step.ptsMs,
                maskSceneCut = step.sceneCut,
                videoAspect = step.videoAspect,
            ),
            mask,
        )
    }


    private fun runMnnFullFrameInference(
        bitmap: Bitmap,
        sampleId: Long,
        captureLatencyMs: Long,
    ) {
        val startedAt = SystemClock.elapsedRealtime()
        val runtime = ensureRuntime()
        if (runtime == null) {
            mainHandler.post {
                processing = false
                if (!disposed) {
                    stopSampling(clearPending = true)
                    emitUnavailableState(
                        backend = currentBackendOrFallback(),
                        keepEnabled = config.enabled,
                    )
                }
                recycleCaptureBitmapIfAsync(bitmap)
                finishSamplingCycle()
            }
            return
        }
        val inferenceBackend = runtime.backend
        // Estimate global frame motion (for between-sample mask extrapolation in the
        // renderer) before running segmentation, while we still hold the frame.
        val lumaGrid = sampleMotionLumaGrid(bitmap)
        updateGlobalMotionVelocity(lumaGrid, SystemClock.uptimeMillis())
        // Static-scene skip: if the frame barely changed since the last segmentation and
        // we already have a mask, skip the heavy seg and keep the current mask. This
        // cuts sustained CPU load (the main cause of thermal throttling → stutter) on
        // dialogue/static shots, which dominate.
        val baseline = lastInferredLumaGrid
        val isStatic =
            baseline != null &&
                latestMaskValues != null &&
                consecutiveStaticSkips < DANMAKU_AI_STATIC_SKIP_MAX_CONSECUTIVE &&
                gridMeanAbsDiff(baseline, lumaGrid) < DANMAKU_AI_STATIC_SKIP_LUMA_DIFF
        if (isStatic) {
            consecutiveStaticSkips += 1
            mainHandler.post {
                processing = false
                recycleCaptureBitmapIfAsync(bitmap)
                finishSamplingCycle()
            }
            return
        }
        consecutiveStaticSkips = 0
        lastInferredLumaGrid = lumaGrid
        val maskResult =
            runCatching { buildFullFrameMaskResult(runtime.run(bitmap)) }
                .getOrElse { error ->
                    Log.w(DANMAKU_AI_TAG, "sample=$sampleId MNN full-frame seg failed", error)
                    null
                }
        val inferenceLatencyMs = SystemClock.elapsedRealtime() - startedAt
        val totalLatencyMs = captureLatencyMs + inferenceLatencyMs
        maybeLogSamplingSlowPath(
            sampleId = sampleId,
            backend = inferenceBackend,
            captureLatencyMs = captureLatencyMs,
            inferenceLatencyMs = inferenceLatencyMs,
            totalLatencyMs = totalLatencyMs,
            reason = "mnn_full_frame",
        )
        if (Log.isLoggable(DANMAKU_AI_TAG, Log.DEBUG)) {
            Log.d(
                DANMAKU_AI_TAG,
                "sample=$sampleId backend=${inferenceBackend.wireValue} mode=mnn_full_frame " +
                    "captureMs=$captureLatencyMs inferenceMs=$inferenceLatencyMs totalMs=$totalLatencyMs " +
                    "mask=${maskResult != null} " +
                    "vx=${"%.5f".format(Locale.US, latestMaskVelocityX)} " +
                    "vy=${"%.5f".format(Locale.US, latestMaskVelocityY)}",
            )
        }
        mainHandler.post {
            processing = false
            if (disposed) {
                recycleCaptureBitmapIfAsync(bitmap)
                return@post
            }
            if (maskResult != null) {
                applyMaskResult(
                    backend = inferenceBackend,
                    result = maskResult,
                    trackingRect = null,
                    frameBitmap = bitmap,
                    latencyMs = totalLatencyMs,
                    motionLumaSamples = IntArray(0),
                    motionSampleWidth = 0,
                    motionSampleHeight = 0,
                    motionCompensation = null,
                    updateTrackingState = false,
                )
            } else {
                applyEmptyResult(
                    sampleId = sampleId,
                    backend = inferenceBackend,
                    motionCompensationAttempted = false,
                    allowMaskGrace = true,
                )
            }
            recycleCaptureBitmapIfAsync(bitmap)
            finishSamplingCycle()
        }
    }

    private fun runInference(
        bitmap: Bitmap,
        sampleId: Long,
        captureLatencyMs: Long,
        sampleAreaRatio: Float,
    ) {
        if (DANMAKU_AI_MNN_FULL_FRAME) {
            runMnnFullFrameInference(bitmap, sampleId, captureLatencyMs)
            return
        }
        val startedAt = SystemClock.elapsedRealtime()
        val detectionRuntime =
            ensureDetectionRuntime()
                ?: run {
                    mainHandler.post {
                        processing = false
                        if (!disposed) {
                            stopSampling(clearPending = true)
                            emitUnavailableState(
                                backend = DanmakuAiBackend.DISABLED,
                                keepEnabled = config.enabled,
                            )
                        }
                    }
                    return
                }
        val runtime = ensureRuntime()
        val inferenceBackend = runtime?.backend ?: detectionRuntime.backend
        val result =
            runCatching {
                val frameContinuity = analyzeFrameContinuity(bitmap)
                previousFrameLumaSignature = frameContinuity.signature
                val motionSampleWidth =
                    minOf(DANMAKU_AI_MOTION_SAMPLE_WIDTH, bitmap.width.coerceAtLeast(1))
                val motionSampleHeight =
                    minOf(DANMAKU_AI_MOTION_SAMPLE_HEIGHT, bitmap.height.coerceAtLeast(1))
                val motionLumaSamples =
                    sampleBitmapLuma(bitmap, motionSampleWidth, motionSampleHeight)
                val motionCompensationAttempted =
                    runtime != null &&
                        !frameContinuity.sceneCut &&
                        !sceneCutRecoveryActive &&
                        latestMotionReferenceFrame != null &&
                        trackingRectOrDisplayRect() != null &&
                        latestMaskValues != null
                val motionCompensation =
                    if (motionCompensationAttempted) {
                        estimateMotionCompensation(
                            currentLumaSamples = motionLumaSamples,
                            sampleWidth = motionSampleWidth,
                            sampleHeight = motionSampleHeight,
                            maskWidth = latestMaskWidth.takeIf { it > 0 } ?: runtime.outputWidth,
                            maskHeight = latestMaskHeight.takeIf { it > 0 } ?: runtime.outputHeight,
                        )
                    } else {
                        null
                    }
                val trackerStartedAt = SystemClock.elapsedRealtime()
                val trackerUpdate = updatePersonTracker(bitmap, frameContinuity)
                val trackerLatencyMs = SystemClock.elapsedRealtime() - trackerStartedAt
                val trackerCandidate = buildTrackerRectCandidate(trackerUpdate)
                updateTrackerLifecycleAfterUpdate(trackerUpdate, trackerCandidate)
                if (frameContinuity.sceneCut && !sceneCutRecoveryActive) {
                    mainHandler.post {
                        if (!disposed &&
                            (runtime == null || activeRuntime?.backend == runtime.backend) &&
                            activeDetectionRuntime?.backend == detectionRuntime.backend
                        ) {
                            beginSceneCutRecovery(inferenceBackend)
                        }
                    }
                }
                val trackedCandidate =
                    resolveTrackedRectCandidate(
                        trackerCandidate = trackerCandidate,
                        motionCompensation = motionCompensation,
                    )
                val trackedRect = trackedCandidate?.rect
                val relaxSmallMultiDetectionPositionJump =
                    smallMultiTracks.count {
                        it.hitCount >= 1 && it.missCount < DANMAKU_AI_SMALL_MULTI_TRACK_MAX_MISS_SAMPLES_WEAK
                    } >= DANMAKU_AI_SMALL_MULTI_MAX_PEOPLE
                val largeMotionSuppressionReason =
                    shouldCancelMaskForLargeMotion(
                        trackedCandidate = trackedCandidate,
                        motionCompensation = motionCompensation,
                        relaxDetectionPositionJump = relaxSmallMultiDetectionPositionJump,
                    )
                val forceMotionReacquire = largeMotionSuppressionReason != null
                if (forceMotionReacquire) {
                    markMotionBurstRequested(largeMotionSuppressionReason)
                    lastTrackerReuseFallbackReason = "motion_burst_reacquire"
                }
                var trackedScaleRescueApplied = false
                if (!forceMotionReacquire &&
                    shouldAttemptTrackedRoi(frameContinuity, trackedCandidate) &&
                    trackedRect != null
                ) {
                    val trackerReuseFallbackReason =
                        shouldAttemptTrackerMaskReuse(
                            frameContinuity = frameContinuity,
                            trackedCandidate = trackedCandidate,
                        )
                    if (trackerReuseFallbackReason == null) {
                        val reusedMask = buildTrackerMaskReuseResult(bitmap, trackedRect)
                        if (reusedMask != null) {
                            val reusedMaskResult = reusedMask.first
                            val maskAdjustment = reusedMask.second
                            lastTrackerReuseFallbackReason = null
                            return@runCatching InferenceOutcome(
                                maskResult = reusedMaskResult,
                                motionLumaSamples = motionLumaSamples,
                                motionSampleWidth = motionSampleWidth,
                                motionSampleHeight = motionSampleHeight,
                                motionCompensation = motionCompensation,
                                motionCompensationAttempted = motionCompensationAttempted,
                                detectLatencyMs = 0L,
                                refineLatencyMs = 0L,
                                occlusionMode = reusedMaskResult.occlusionMode,
                                detectionPerformed = false,
                                trackedRectReused = true,
                                primaryRect = trackedRect,
                                segmentationRoiMode = "tracker_reuse",
                                segmentationRoiRect = trackedRect,
                                segmentationInputWidth = latestMaskWidth,
                                segmentationInputHeight = latestMaskHeight,
                                predictedScale = trackedCandidate.predictedScale,
                                predictedAreaRatio = trackedCandidate.predictedAreaRatio,
                                trackedRectSource = trackedCandidate.source,
                                maskScaleApplied = shouldApplyMaskScaleCompensation(trackedCandidate.predictedScale),
                                maskScaleValue = trackedCandidate.predictedScale,
                                scaleRescueApplied = false,
                                trackerUsed = true,
                                trackerSuccessful = true,
                                trackerSource = trackerUpdate?.source ?: trackedCandidate.source,
                                trackerMaskReused = true,
                                trackerConfidence = trackerUpdate?.confidence ?: trackedCandidate.confidence,
                                trackerLatencyMs = trackerLatencyMs,
                                trackerState = trackerLifecycleState.wireValue,
                                trackerStateReason = trackerLifecycleReason,
                                detectionSkippedByStableTracker =
                                    trackerLifecycleState == TrackerLifecycleState.STABLE,
                                maskAdjustmentUsed = maskAdjustment != null,
                                maskAdjustmentSource = maskAdjustment?.source,
                                maskAdjustmentDelta = maskAdjustment?.deltaSummary(),
                            )
                        }
                    } else {
                        lastTrackerReuseFallbackReason = trackerReuseFallbackReason
                        if (
                            trackerReuseFallbackReason == "tracker_center_jump" ||
                                trackerReuseFallbackReason == "tracker_area_jump"
                        ) {
                            markMotionBurstRequested(trackerReuseFallbackReason)
                        }
                    }
                    val segmentationSkippedByStableTracker =
                        trackerLifecycleState == TrackerLifecycleState.STABLE &&
                            trackerReuseFallbackReason in setOf(
                                "refresh_due",
                                "tracker_warmup",
                                "tracker_center_jump",
                                "tracker_area_jump",
                            )
                    if (segmentationSkippedByStableTracker) {
                        lastTrackerReuseFallbackReason = trackerReuseFallbackReason
                    }
                    if (segmentationSkippedByStableTracker || !allowMaskRefinement() || runtime == null) {
                        return@runCatching InferenceOutcome(
                            maskResult = null,
                            motionLumaSamples = motionLumaSamples,
                            motionSampleWidth = motionSampleWidth,
                            motionSampleHeight = motionSampleHeight,
                            motionCompensation = motionCompensation,
                            motionCompensationAttempted = motionCompensationAttempted,
                            detectLatencyMs = 0L,
                            refineLatencyMs = 0L,
                            occlusionMode = DanmakuOcclusionMode.DISABLED,
                            detectionPerformed = false,
                            trackedRectReused = false,
                            primaryRect = trackedRect,
                            segmentationRoiMode = null,
                            segmentationRoiRect = null,
                            segmentationInputWidth = 0,
                            segmentationInputHeight = 0,
                            predictedScale = trackedCandidate.predictedScale,
                            predictedAreaRatio = trackedCandidate.predictedAreaRatio,
                            trackedRectSource = trackedCandidate.source,
                            maskScaleApplied = false,
                            maskScaleValue = 1f,
                            scaleRescueApplied = false,
                            trackerUsed = trackerUpdate != null,
                            trackerSuccessful = trackerUpdate?.success == true,
                            trackerSource = trackerUpdate?.source,
                            trackerConfidence = trackerUpdate?.confidence,
                            trackerLatencyMs = trackerLatencyMs,
                            trackerFallbackReason = lastTrackerReuseFallbackReason,
                            trackerState = trackerLifecycleState.wireValue,
                            trackerStateReason = trackerLifecycleReason,
                            detectionSkippedByStableTracker = segmentationSkippedByStableTracker,
                            segmentationSkippedByStableTracker = segmentationSkippedByStableTracker,
                        )
                    }
                    val trackedSegmentation =
                        runSegmentationForRect(
                            bitmap = bitmap,
                            sampleId = sampleId,
                            runtime = runtime,
                            targetRect = trackedRect,
                            roiMode = DanmakuSegmentationRoiMode.TRACKED,
                            sampleAreaRatio = sampleAreaRatio,
                            allowTemporalSmoothing =
                                !frameContinuity.sceneCut && !sceneCutRecoveryActive,
                            motionCompensation = motionCompensation,
                            motionCompensationAttempted = motionCompensationAttempted,
                            predictedScale = trackedCandidate.predictedScale,
                        )
                    trackedScaleRescueApplied = trackedSegmentation.scaleRescueApplied
                    if (trackedSegmentation.extraction != null) {
                        initializePersonTracker(
                            bitmap = bitmap,
                            rect = trackedSegmentation.extraction.maskResult.normalizedRect ?: trackedRect,
                        )
                        lastTrackerReuseFallbackReason = null
                        return@runCatching InferenceOutcome(
                            maskResult = trackedSegmentation.extraction.maskResult,
                            motionLumaSamples = motionLumaSamples,
                            motionSampleWidth = motionSampleWidth,
                            motionSampleHeight = motionSampleHeight,
                            motionCompensation =
                                trackedSegmentation.extraction.appliedMotionCompensation ?: motionCompensation,
                            motionCompensationAttempted = motionCompensationAttempted,
                            detectLatencyMs = 0L,
                            refineLatencyMs = trackedSegmentation.latencyMs,
                            occlusionMode = trackedSegmentation.extraction.maskResult.occlusionMode,
                            detectionPerformed = false,
                            trackedRectReused = true,
                            primaryRect = trackedRect,
                            segmentationRoiMode = trackedSegmentation.roiMode.wireValue,
                            segmentationRoiRect = trackedSegmentation.roiRect,
                            segmentationInputWidth = trackedSegmentation.inputWidth,
                            segmentationInputHeight = trackedSegmentation.inputHeight,
                            predictedScale = trackedCandidate.predictedScale,
                            predictedAreaRatio = trackedCandidate.predictedAreaRatio,
                            trackedRectSource = trackedCandidate.source,
                            maskScaleApplied = trackedSegmentation.extraction.maskScaleApplied,
                            maskScaleValue = trackedSegmentation.extraction.maskScaleValue,
                            scaleRescueApplied = trackedSegmentation.scaleRescueApplied,
                            trackerUsed = trackerUpdate != null,
                            trackerSuccessful = trackerUpdate?.success == true,
                            trackerSource = trackerUpdate?.source,
                            trackerConfidence = trackerUpdate?.confidence,
                            trackerLatencyMs = trackerLatencyMs,
                            trackerFallbackReason = lastTrackerReuseFallbackReason,
                            trackerState = trackerLifecycleState.wireValue,
                            trackerStateReason = trackerLifecycleReason,
                        )
                    }
                }
                val detectStartedAt = SystemClock.elapsedRealtime()
                val detections =
                    synchronized(runtimeLock) {
                        if (
                            disposed ||
                                activeDetectionRuntime !== detectionRuntime ||
                                (runtime != null && activeRuntime !== runtime)
                        ) {
                            return@runCatching null
                        }
                        detectionRuntime.run(bitmap, DANMAKU_AI_MULTI_DETECTION_SCORE_THRESHOLD)
                    } ?: return@runCatching null
                val detectLatencyMs = SystemClock.elapsedRealtime() - detectStartedAt
                val smallMultiSelection = selectSmallMultiDetections(detections)
                val primarySelection = selectPrimaryDetection(detections, trackingRectOrDisplayRect())
                val primaryDetection = primarySelection.detection
                updatePrimaryTargetMemory(primarySelection)
                val multiPrimaryRect = smallMultiSelection.targets.firstOrNull()?.rect ?: primaryDetection?.rect
                updateTrackerLifecycleAfterDetection(trackedCandidate, multiPrimaryRect)
                val stableSingleTargetPreferred =
                    trackerLifecycleState == TrackerLifecycleState.STABLE ||
                        (trackerLifecycleState == TrackerLifecycleState.WARMUP && primarySelection.stable) ||
                        primarySelection.stable
                val detectionSuppressionReason =
                    multiPrimaryRect?.let {
                        shouldCancelMaskForLargeMotion(
                            trackedCandidate = trackedCandidate,
                            motionCompensation = motionCompensation,
                            detectionRect = it,
                            relaxDetectionPositionJump =
                                forceMotionReacquire ||
                                smallMultiSelection.trackState.count {
                                    track ->
                                    track.hitCount >= 1 &&
                                        track.missCount < DANMAKU_AI_SMALL_MULTI_TRACK_MAX_MISS_SAMPLES_WEAK
                                } >= DANMAKU_AI_SMALL_MULTI_MAX_PEOPLE,
                        )
                    }
                val multiDropReason =
                    resolveSmallMultiDropReason(
                        selection = smallMultiSelection,
                        suppressed = detectionSuppressionReason != null,
                        stableSingleTargetPreferred = stableSingleTargetPreferred,
                    )
                val preferSmallMultiMode =
                    shouldPreferSmallMultiMode(
                        selection = smallMultiSelection,
                        dropReason = multiDropReason,
                    )
                val preserveSmallMultiTracks =
                    sceneCutRecoveryActive || degradationStage > 0
                val nextSmallMultiTracks =
                    if (detectionSuppressionReason != null) {
                        emptyList()
                    } else if (preserveSmallMultiTracks) {
                        smallMultiTracks
                    } else {
                        smallMultiSelection.trackState
                    }
                val nextSmallMultiCoarseOnlySamples =
                    if (nextSmallMultiTracks.isEmpty()) {
                        0
                    } else {
                        smallMultiSelection.coarseOnlySamples
                    }
                if (primaryDetection == null && !preferSmallMultiMode) {
                    resetPersonTracker()
                    return@runCatching InferenceOutcome(
                        maskResult = null,
                        motionLumaSamples = motionLumaSamples,
                        motionSampleWidth = motionSampleWidth,
                        motionSampleHeight = motionSampleHeight,
                        motionCompensation = motionCompensation,
                        motionCompensationAttempted = motionCompensationAttempted,
                        detectLatencyMs = detectLatencyMs,
                        refineLatencyMs = 0L,
                        occlusionMode = DanmakuOcclusionMode.DISABLED,
                        detectionPerformed = true,
                        trackedRectReused = false,
                        primaryRect = null,
                        segmentationRoiMode = null,
                        segmentationRoiRect = null,
                        segmentationInputWidth = 0,
                        segmentationInputHeight = 0,
                        predictedScale = trackedCandidate?.predictedScale ?: 1f,
                        predictedAreaRatio = trackedCandidate?.predictedAreaRatio ?: 1f,
                        trackedRectSource = trackedCandidate?.source,
                        maskScaleApplied = false,
                        maskScaleValue = 1f,
                        scaleRescueApplied = trackedScaleRescueApplied,
                        multiCandidateCount = smallMultiSelection.candidateCount,
                        multiViewportScale = smallMultiSelection.thresholdScale,
                        multiDropReason = smallMultiSelection.dropReason,
                        multiTrackCount = smallMultiSelection.trackCount,
                        multiTrackHits = smallMultiSelection.trackHits,
                        multiTrackMisses = smallMultiSelection.trackMisses,
                        multiTrackSource = smallMultiSelection.trackSource,
                        multiAssociation = smallMultiSelection.association,
                        nextSmallMultiTracks = nextSmallMultiTracks,
                        nextSmallMultiCoarseOnlySamples = nextSmallMultiCoarseOnlySamples,
                        trackerState = trackerLifecycleState.wireValue,
                        trackerStateReason = trackerLifecycleReason,
                        primaryTargetStable = primarySelection.stable,
                        primaryTargetSwitched = primarySelection.switched,
                        primaryTargetSwitchReason = primarySelection.switchReason,
                    )
                }
                if (detectionSuppressionReason != null) {
                    resetPersonTracker()
                    if (trackerLifecycleState == TrackerLifecycleState.LOST) {
                        resetPrimaryTargetMemory()
                    }
                    return@runCatching InferenceOutcome(
                        maskResult = null,
                        motionLumaSamples = motionLumaSamples,
                        motionSampleWidth = motionSampleWidth,
                        motionSampleHeight = motionSampleHeight,
                        motionCompensation = motionCompensation,
                        motionCompensationAttempted = motionCompensationAttempted,
                        detectLatencyMs = detectLatencyMs,
                        refineLatencyMs = 0L,
                        occlusionMode = DanmakuOcclusionMode.DISABLED,
                        detectionPerformed = true,
                        trackedRectReused = false,
                        primaryRect = multiPrimaryRect,
                        segmentationRoiMode = null,
                        segmentationRoiRect = null,
                        segmentationInputWidth = 0,
                        segmentationInputHeight = 0,
                        predictedScale = trackedCandidate?.predictedScale ?: 1f,
                        predictedAreaRatio = trackedCandidate?.predictedAreaRatio ?: 1f,
                        trackedRectSource = trackedCandidate?.source,
                        maskScaleApplied = false,
                        maskScaleValue = 1f,
                        scaleRescueApplied = trackedScaleRescueApplied,
                        multiCandidateCount = smallMultiSelection.candidateCount,
                        multiViewportScale = smallMultiSelection.thresholdScale,
                        multiDropReason = multiDropReason,
                        multiTrackCount = smallMultiSelection.trackCount,
                        multiTrackHits = smallMultiSelection.trackHits,
                        multiTrackMisses = smallMultiSelection.trackMisses,
                        multiTrackSource = smallMultiSelection.trackSource,
                        multiAssociation = smallMultiSelection.association,
                        nextSmallMultiTracks = emptyList(),
                        nextSmallMultiCoarseOnlySamples = 0,
                        suppressMaskGrace = true,
                        suppressionReason = detectionSuppressionReason,
                        trackerState = trackerLifecycleState.wireValue,
                        trackerStateReason = trackerLifecycleReason,
                        primaryTargetStable = primarySelection.stable,
                        primaryTargetSwitched = primarySelection.switched,
                        primaryTargetSwitchReason = primarySelection.switchReason,
                    )
                }
                if (!allowMaskRefinement() || runtime == null) {
                    return@runCatching InferenceOutcome(
                        maskResult = null,
                        motionLumaSamples = motionLumaSamples,
                        motionSampleWidth = motionSampleWidth,
                        motionSampleHeight = motionSampleHeight,
                        motionCompensation = motionCompensation,
                        motionCompensationAttempted = motionCompensationAttempted,
                        detectLatencyMs = detectLatencyMs,
                        refineLatencyMs = 0L,
                        occlusionMode = DanmakuOcclusionMode.DISABLED,
                        detectionPerformed = true,
                        trackedRectReused = false,
                        primaryRect = multiPrimaryRect,
                        segmentationRoiMode = null,
                        segmentationRoiRect = null,
                        segmentationInputWidth = 0,
                        segmentationInputHeight = 0,
                        predictedScale = trackedCandidate?.predictedScale ?: 1f,
                        predictedAreaRatio = trackedCandidate?.predictedAreaRatio ?: 1f,
                        trackedRectSource = trackedCandidate?.source,
                        maskScaleApplied = false,
                        maskScaleValue = 1f,
                        scaleRescueApplied = trackedScaleRescueApplied,
                        multiCandidateCount = smallMultiSelection.candidateCount,
                        multiViewportScale = smallMultiSelection.thresholdScale,
                        multiDropReason = multiDropReason,
                        multiTrackCount = smallMultiSelection.trackCount,
                        multiTrackHits = smallMultiSelection.trackHits,
                        multiTrackMisses = smallMultiSelection.trackMisses,
                        multiTrackSource = smallMultiSelection.trackSource,
                        multiAssociation = smallMultiSelection.association,
                        nextSmallMultiTracks = nextSmallMultiTracks,
                        nextSmallMultiCoarseOnlySamples = nextSmallMultiCoarseOnlySamples,
                        trackerState = trackerLifecycleState.wireValue,
                        trackerStateReason = trackerLifecycleReason,
                        primaryTargetStable = primarySelection.stable,
                        primaryTargetSwitched = primarySelection.switched,
                        primaryTargetSwitchReason = primarySelection.switchReason,
                    )
                }
                if (preferSmallMultiMode) {
                    resetPersonTracker()
                    resetPrimaryTargetMemory()
                    val multiSegmentation =
                        runSmallMultiSegmentation(
                            bitmap = bitmap,
                            sampleId = sampleId,
                            runtime = runtime,
                            targets = smallMultiSelection.targets,
                            sampleAreaRatio = sampleAreaRatio,
                            thresholds = currentSmallMultiThresholds(),
                        )
                    val mergedMultiDropReason =
                        mergeDropReasons(
                            smallMultiSelection.dropReason,
                            multiSegmentation.dropReason,
                        )
                    val updatedSmallMultiTracks =
                        applySmallMultiMaskAreas(
                            tracks = nextSmallMultiTracks,
                            maskAreaByTrackId = multiSegmentation.maskAreaByTrackId,
                        )
                    return@runCatching InferenceOutcome(
                        maskResult = multiSegmentation.maskResult,
                        motionLumaSamples = motionLumaSamples,
                        motionSampleWidth = motionSampleWidth,
                        motionSampleHeight = motionSampleHeight,
                        motionCompensation = null,
                        motionCompensationAttempted = false,
                        detectLatencyMs = detectLatencyMs,
                        refineLatencyMs = multiSegmentation.latencyMs,
                        occlusionMode = multiSegmentation.maskResult?.occlusionMode ?: DanmakuOcclusionMode.DISABLED,
                        detectionPerformed = true,
                        trackedRectReused = false,
                        primaryRect = multiPrimaryRect,
                        segmentationRoiMode = "detect_multi",
                        segmentationRoiRect = multiSegmentation.roiRect,
                        segmentationInputWidth = multiSegmentation.inputWidth,
                        segmentationInputHeight = multiSegmentation.inputHeight,
                        predictedScale = trackedCandidate?.predictedScale ?: 1f,
                        predictedAreaRatio = trackedCandidate?.predictedAreaRatio ?: 1f,
                        trackedRectSource = null,
                        maskScaleApplied = false,
                        maskScaleValue = 1f,
                        scaleRescueApplied = trackedScaleRescueApplied,
                        trackingStateEligible = false,
                        multiSmallMode = true,
                        multiCandidateCount = smallMultiSelection.candidateCount,
                        multiKeptCount = multiSegmentation.keptCount,
                        multiUnionAreaRatio = multiSegmentation.unionAreaRatio,
                        multiViewportScale = smallMultiSelection.thresholdScale,
                        multiDropReason = mergedMultiDropReason,
                        multiTrackCount = smallMultiSelection.trackCount,
                        multiTrackHits = smallMultiSelection.trackHits,
                        multiTrackMisses = smallMultiSelection.trackMisses,
                        multiTrackSource = smallMultiSelection.trackSource,
                        multiAssociation = smallMultiSelection.association,
                        nextSmallMultiTracks = updatedSmallMultiTracks,
                        nextSmallMultiCoarseOnlySamples = nextSmallMultiCoarseOnlySamples,
                        trackerState = trackerLifecycleState.wireValue,
                        trackerStateReason = trackerLifecycleReason,
                    )
                }
                val safePrimaryDetection =
                    primaryDetection ?: run {
                        resetPersonTracker()
                        if (trackerLifecycleState == TrackerLifecycleState.LOST) {
                            resetPrimaryTargetMemory()
                        }
                        return@runCatching InferenceOutcome(
                            maskResult = null,
                            motionLumaSamples = motionLumaSamples,
                            motionSampleWidth = motionSampleWidth,
                            motionSampleHeight = motionSampleHeight,
                            motionCompensation = motionCompensation,
                            motionCompensationAttempted = motionCompensationAttempted,
                            detectLatencyMs = detectLatencyMs,
                            refineLatencyMs = 0L,
                            occlusionMode = DanmakuOcclusionMode.DISABLED,
                            detectionPerformed = true,
                            trackedRectReused = false,
                            primaryRect = multiPrimaryRect,
                            segmentationRoiMode = null,
                            segmentationRoiRect = null,
                            segmentationInputWidth = 0,
                            segmentationInputHeight = 0,
                            predictedScale = trackedCandidate?.predictedScale ?: 1f,
                            predictedAreaRatio = trackedCandidate?.predictedAreaRatio ?: 1f,
                            trackedRectSource = trackedCandidate?.source,
                            maskScaleApplied = false,
                            maskScaleValue = 1f,
                            scaleRescueApplied = trackedScaleRescueApplied,
                            multiCandidateCount = smallMultiSelection.candidateCount,
                            multiViewportScale = smallMultiSelection.thresholdScale,
                            multiDropReason = multiDropReason,
                            multiTrackCount = smallMultiSelection.trackCount,
                            multiTrackHits = smallMultiSelection.trackHits,
                            multiTrackMisses = smallMultiSelection.trackMisses,
                            multiTrackSource = smallMultiSelection.trackSource,
                            multiAssociation = smallMultiSelection.association,
                            nextSmallMultiTracks = nextSmallMultiTracks,
                            nextSmallMultiCoarseOnlySamples = nextSmallMultiCoarseOnlySamples,
                            trackerState = trackerLifecycleState.wireValue,
                            trackerStateReason = trackerLifecycleReason,
                            primaryTargetStable = primarySelection.stable,
                            primaryTargetSwitched = primarySelection.switched,
                            primaryTargetSwitchReason = primarySelection.switchReason,
                        )
                    }
                val segmentationAttempt =
                    runSegmentationForRect(
                        bitmap = bitmap,
                        sampleId = sampleId,
                        runtime = runtime,
                        targetRect = safePrimaryDetection.rect,
                        roiMode = DanmakuSegmentationRoiMode.DETECT,
                        sampleAreaRatio = sampleAreaRatio,
                        allowTemporalSmoothing =
                            !frameContinuity.sceneCut && !sceneCutRecoveryActive,
                        motionCompensation = motionCompensation,
                        motionCompensationAttempted = motionCompensationAttempted,
                        predictedScale = trackedCandidate?.predictedScale,
                    )
                val nextMaskResult = segmentationAttempt.extraction?.maskResult
                if (nextMaskResult != null) {
                    initializePersonTracker(
                        bitmap = bitmap,
                        rect = nextMaskResult.normalizedRect ?: safePrimaryDetection.rect,
                    )
                    lastTrackerReuseFallbackReason = null
                } else {
                    resetPersonTracker()
                }
                InferenceOutcome(
                    maskResult = nextMaskResult,
                    motionLumaSamples = motionLumaSamples,
                    motionSampleWidth = motionSampleWidth,
                    motionSampleHeight = motionSampleHeight,
                    motionCompensation =
                        segmentationAttempt.extraction?.appliedMotionCompensation ?: motionCompensation,
                    motionCompensationAttempted = motionCompensationAttempted,
                    detectLatencyMs = detectLatencyMs,
                    refineLatencyMs = segmentationAttempt.latencyMs,
                    occlusionMode = nextMaskResult?.occlusionMode ?: DanmakuOcclusionMode.DISABLED,
                    detectionPerformed = true,
                    trackedRectReused = false,
                    primaryRect = safePrimaryDetection.rect,
                    segmentationRoiMode = segmentationAttempt.roiMode.wireValue,
                    segmentationRoiRect = segmentationAttempt.roiRect,
                    segmentationInputWidth = segmentationAttempt.inputWidth,
                    segmentationInputHeight = segmentationAttempt.inputHeight,
                    predictedScale = trackedCandidate?.predictedScale ?: 1f,
                    predictedAreaRatio = trackedCandidate?.predictedAreaRatio ?: 1f,
                    trackedRectSource = trackedCandidate?.source,
                    maskScaleApplied = segmentationAttempt.extraction?.maskScaleApplied == true,
                    maskScaleValue = segmentationAttempt.extraction?.maskScaleValue ?: 1f,
                    scaleRescueApplied = trackedScaleRescueApplied || segmentationAttempt.scaleRescueApplied,
                    multiCandidateCount = smallMultiSelection.candidateCount,
                    multiViewportScale = smallMultiSelection.thresholdScale,
                    multiDropReason = multiDropReason,
                    multiTrackCount = smallMultiSelection.trackCount,
                    multiTrackHits = smallMultiSelection.trackHits,
                    multiTrackMisses = smallMultiSelection.trackMisses,
                    multiTrackSource = smallMultiSelection.trackSource,
                    multiAssociation = smallMultiSelection.association,
                    nextSmallMultiTracks = nextSmallMultiTracks,
                    nextSmallMultiCoarseOnlySamples = nextSmallMultiCoarseOnlySamples,
                    trackerUsed = trackerUpdate != null,
                    trackerSuccessful = trackerUpdate?.success == true,
                    trackerSource = trackerUpdate?.source,
                    trackerConfidence = trackerUpdate?.confidence,
                    trackerLatencyMs = trackerLatencyMs,
                    trackerFallbackReason = lastTrackerReuseFallbackReason,
                    trackerState = trackerLifecycleState.wireValue,
                    trackerStateReason = trackerLifecycleReason,
                    primaryTargetStable = primarySelection.stable,
                    primaryTargetSwitched = primarySelection.switched,
                    primaryTargetSwitchReason = primarySelection.switchReason,
                )
            }.getOrElse { error ->
                Log.w(DANMAKU_AI_TAG, "backend=${inferenceBackend.wireValue} inference failed", error)
                handleBackendFailure(inferenceBackend)
                null
            }
        val inferenceLatencyMs = SystemClock.elapsedRealtime() - startedAt
        val totalLatencyMs = captureLatencyMs + inferenceLatencyMs
        maybeLogSamplingSlowPath(
            sampleId = sampleId,
            backend = inferenceBackend,
            captureLatencyMs = captureLatencyMs,
            inferenceLatencyMs = inferenceLatencyMs,
            totalLatencyMs = totalLatencyMs,
            reason =
                if (result?.maskResult == null) {
                    "empty"
                } else {
                    result.occlusionMode.wireValue
                },
        )
        if (result != null) {
            Log.d(
                DANMAKU_AI_TAG,
                buildString {
                    append("sample=")
                    append(sampleId)
                    append(" detectMs=")
                    append(result.detectLatencyMs)
                    append(" refineMs=")
                    append(result.refineLatencyMs)
                    append(" totalMs=")
                    append(totalLatencyMs)
                    append(" mode=")
                    append(result.occlusionMode.wireValue)
                    result.segmentationRoiMode?.let {
                        append(" seg_roi_mode=")
                        append(it)
                    }
                    result.segmentationRoiRect?.let {
                        append(" seg_roi_rect=")
                        append(it)
                    }
                    if (result.segmentationInputWidth > 0 && result.segmentationInputHeight > 0) {
                        append(" seg_input_size=")
                        append(result.segmentationInputWidth)
                        append('x')
                        append(result.segmentationInputHeight)
                    }
                    result.trackedRectSource?.let {
                        append(" tracked_rect_source=")
                        append(it)
                        append(" pred_scale=")
                        append("%.3f".format(Locale.US, result.predictedScale))
                        append(" pred_area_ratio=")
                        append("%.3f".format(Locale.US, result.predictedAreaRatio))
                    }
                    append(" mask_scale_applied=")
                    append(result.maskScaleApplied)
                    append(" mask_scale_value=")
                    append("%.3f".format(Locale.US, result.maskScaleValue))
                    append(" scale_rescue_applied=")
                    append(result.scaleRescueApplied)
                    if (result.trackerUsed || result.trackerFallbackReason != null) {
                        append(" tracker_used=")
                        append(result.trackerUsed)
                        append(" tracker_success=")
                        append(result.trackerSuccessful)
                        append(" tracker_mask_reused=")
                        append(result.trackerMaskReused)
                        append(" tracker_latency_ms=")
                        append(result.trackerLatencyMs)
                        result.trackerSource?.let {
                            append(" tracker_source=")
                            append(it)
                        }
                        result.trackerConfidence?.let {
                            append(" tracker_confidence=")
                            append("%.3f".format(Locale.US, it))
                        }
                        result.trackerFallbackReason?.let {
                            append(" tracker_fallback=")
                            append(it)
                        }
                        result.trackerState?.let {
                            append(" tracker_state=")
                            append(it)
                        }
                        result.trackerStateReason?.let {
                            append(" tracker_state_reason=")
                            append(it)
                        }
                    }
                    append(" detect_skipped_by_stable_tracker=")
                    append(result.detectionSkippedByStableTracker)
                    append(" seg_skipped_by_stable_tracker=")
                    append(result.segmentationSkippedByStableTracker)
                    append(" primary_target_stable=")
                    append(result.primaryTargetStable)
                    append(" primary_target_switched=")
                    append(result.primaryTargetSwitched)
                    result.primaryTargetSwitchReason?.let {
                        append(" primary_target_switch_reason=")
                        append(it)
                    }
                    append(" mask_adjustment_used=")
                    append(result.maskAdjustmentUsed)
                    result.maskAdjustmentSource?.let {
                        append(" mask_adjustment_source=")
                        append(it)
                    }
                    result.maskAdjustmentDelta?.let {
                        append(" mask_adjustment_delta=")
                        append(it)
                    }
                    if (result.multiSmallMode || result.multiCandidateCount > 0 || result.multiDropReason != null) {
                        append(" multi_small_mode=")
                        append(result.multiSmallMode)
                        append(" multi_candidate_count=")
                        append(result.multiCandidateCount)
                        append(" multi_kept_count=")
                        append(result.multiKeptCount)
                        append(" multi_union_area_ratio=")
                        append("%.4f".format(Locale.US, result.multiUnionAreaRatio))
                        append(" multi_viewport_scale=")
                        append("%.3f".format(Locale.US, result.multiViewportScale))
                        append(" multi_track_count=")
                        append(result.multiTrackCount)
                        result.multiTrackHits?.let {
                            append(" multi_track_hits=")
                            append(it)
                        }
                        result.multiTrackMisses?.let {
                            append(" multi_track_misses=")
                            append(it)
                        }
                        result.multiTrackSource?.let {
                            append(" multi_track_source=")
                            append(it)
                        }
                        result.multiAssociation?.let {
                            append(" multi_association=")
                            append(it)
                        }
                        result.multiDropReason?.let {
                            append(" multi_drop_reason=")
                            append(it)
                        }
                    }
                    result.suppressionReason?.let {
                        append(" suppression_reason=")
                        append(it)
                    }
                    append(" motion_burst_active=")
                    append(motionBurstSamplesRemaining > 0 || pendingMotionBurstReason != null)
                    motionBurstReason?.let {
                        append(" motion_burst_reason=")
                        append(it)
                    }
                    pendingMotionBurstReason?.let {
                        if (it != motionBurstReason) {
                            append(" motion_burst_pending=")
                            append(it)
                        }
                    }
                },
            )
        }
        mainHandler.post {
            processing = false
            if (disposed) {
                clearPendingMotionBurstRequest()
                if (bitmap !== latestRuntimeMaskBitmap &&
                    videoOutputTarget.supportsAsyncBitmapCapture &&
                    !bitmap.isRecycled
                ) {
                    bitmap.recycle()
                }
                return@post
            }
            if (result != null) {
                updateTrackingCadenceAfterInference(result)
            } else {
                clearPendingMotionBurstRequest()
            }
            result?.let(::applySmallMultiTrackUpdate)
            if (result?.maskResult != null) {
                applyMaskResult(
                    backend = inferenceBackend,
                    result = result.maskResult,
                    trackingRect =
                        if (result.trackingStateEligible) {
                            result.maskResult.normalizedRect
                        } else {
                            null
                        },
                    frameBitmap = bitmap,
                    latencyMs = totalLatencyMs,
                    motionLumaSamples = result.motionLumaSamples,
                    motionSampleWidth = result.motionSampleWidth,
                    motionSampleHeight = result.motionSampleHeight,
                    motionCompensation = result.motionCompensation,
                    updateTrackingState = result.trackingStateEligible,
                )
            } else if (
                (runtime != null && activeRuntime?.backend == runtime.backend) ||
                    (runtime == null && activeDetectionRuntime?.backend == detectionRuntime.backend)
            ) {
                applyEmptyResult(
                    sampleId = sampleId,
                    backend = inferenceBackend,
                    motionCompensationAttempted = result?.motionCompensationAttempted == true,
                    allowMaskGrace = result?.suppressMaskGrace != true,
                )
            }
            finishSamplingCycle()
        }
    }

    private fun buildPrimaryDetectionCandidates(
        detections: List<DanmakuDetectionCandidate>,
        minScore: Float = DANMAKU_AI_DETECTION_SCORE_THRESHOLD,
        minAreaRatio: Float = DANMAKU_AI_DETECTION_MIN_AREA_RATIO,
    ): List<DanmakuPrimaryDetection> =
        detections.mapNotNull { candidate ->
            val rect = candidate.rect
            if (candidate.score < minScore || rect.area() < minAreaRatio) {
                return@mapNotNull null
            }
            DanmakuPrimaryDetection(
                rect = rect,
                score = candidate.score,
            )
        }

    private fun continuityScoreForRect(
        rect: DanmakuNormalizedRect,
        memoryRect: DanmakuNormalizedRect?,
    ): Float {
        val baseline = memoryRect ?: return 0f
        val iouScore = rect.iou(baseline)
        val centerDistance =
            centerDistanceBetweenRects(rect, baseline) /
                DANMAKU_AI_PRIMARY_TARGET_CONTINUITY_MAX_CENTER_DISTANCE
        val centerScore = (1f - centerDistance).coerceIn(0f, 1f)
        val sizeRatio =
            (rect.area() / baseline.area().coerceAtLeast(1e-4f))
                .coerceAtLeast(0.01f)
        val sizeScore =
            when {
                sizeRatio < DANMAKU_AI_PRIMARY_TARGET_CONTINUITY_MIN_SIZE_RATIO -> 0f
                sizeRatio > DANMAKU_AI_PRIMARY_TARGET_CONTINUITY_MAX_SIZE_RATIO -> 0f
                else -> 1f - abs(1f - sizeRatio).coerceIn(0f, 1f)
            }
        return ((iouScore * 0.55f) + (centerScore * 0.30f) + (sizeScore * 0.15f)).coerceIn(0f, 1f)
    }

    private fun isContinuousPrimaryTarget(
        rect: DanmakuNormalizedRect,
        memoryRect: DanmakuNormalizedRect?,
    ): Boolean {
        val baseline = memoryRect ?: return false
        val iou = rect.iou(baseline)
        if (iou >= DANMAKU_AI_PRIMARY_TARGET_CONTINUITY_MIN_IOU) {
            return true
        }
        val centerDistance = centerDistanceBetweenRects(rect, baseline)
        val sizeRatio =
            (rect.area() / baseline.area().coerceAtLeast(1e-4f))
                .coerceAtLeast(0.01f)
        return centerDistance <= DANMAKU_AI_PRIMARY_TARGET_CONTINUITY_MAX_CENTER_DISTANCE &&
            sizeRatio in DANMAKU_AI_PRIMARY_TARGET_CONTINUITY_MIN_SIZE_RATIO..DANMAKU_AI_PRIMARY_TARGET_CONTINUITY_MAX_SIZE_RATIO
    }

    private fun updatePrimaryTargetMemory(
        selection: PrimaryTargetSelection,
    ) {
        val detection = selection.detection
        if (detection == null) {
            primaryTargetMemory =
                primaryTargetMemory?.copy(
                    ageSamples = (primaryTargetMemory?.ageSamples ?: 0) + 1,
                    cooldownSamples = max(0, (primaryTargetMemory?.cooldownSamples ?: 0) - 1),
                )
            return
        }
        primaryTargetMemory =
            PrimaryTargetMemory(
                rect = detection.rect,
                score = selection.continuityScore,
                ageSamples = 0,
                cooldownSamples =
                    if (selection.switched) {
                        DANMAKU_AI_PRIMARY_TARGET_SWITCH_COOLDOWN_SAMPLES
                    } else {
                        max(0, primaryTargetSwitchCooldownSamples - 1)
                    },
            )
        primaryTargetSwitchCooldownSamples = primaryTargetMemory?.cooldownSamples ?: 0
        if (selection.switched) {
            primaryTargetCandidateRect = null
            primaryTargetCandidateWins = 0
        }
        lastAcceptedTargetSource =
            if (selection.stable) {
                "memory"
            } else {
                "detector"
            }
    }

    private fun selectPrimaryDetection(
        detections: List<DanmakuDetectionCandidate>,
        previousRect: DanmakuNormalizedRect?,
    ): PrimaryTargetSelection {
        val candidates =
            buildPrimaryDetectionCandidates(
                detections = detections,
                minScore = DANMAKU_AI_DETECTION_SCORE_THRESHOLD,
                minAreaRatio = DANMAKU_AI_DETECTION_MIN_AREA_RATIO,
            ).takeIf { it.isNotEmpty() }
                ?: return PrimaryTargetSelection(
                    detection = null,
                    stable = false,
                    switched = false,
                    switchReason = "no_detection",
                    continuityScore = 0f,
                )
        if (previousRect != null) {
            val tracked =
                candidates.maxByOrNull { it.rect.iou(previousRect) }
                    ?.takeIf { it.rect.iou(previousRect) >= DANMAKU_AI_TRACKING_MIN_IOU }
            if (tracked != null) {
                val continuity = continuityScoreForRect(tracked.rect, primaryTargetMemory?.rect)
                return PrimaryTargetSelection(
                    detection = tracked,
                    stable = true,
                    switched = false,
                    switchReason = "tracked_iou",
                    continuityScore = continuity,
                )
            }
        }
        val memoryRect = primaryTargetMemory?.rect
        val ranked =
            candidates
                .map { candidate ->
                    candidate to (
                        scorePrimaryDetection(candidate) +
                            (continuityScoreForRect(candidate.rect, memoryRect) * 0.52f)
                        )
                }.sortedByDescending { it.second }
        val top = ranked.firstOrNull()?.first
        val topScore = ranked.firstOrNull()?.second ?: 0f
        val memoryCandidate =
            candidates.firstOrNull { candidate ->
                isContinuousPrimaryTarget(candidate.rect, memoryRect)
            }
        if (memoryCandidate != null) {
            primaryTargetCandidateRect = null
            primaryTargetCandidateWins = 0
            primaryTargetSwitchCooldownSamples = max(0, primaryTargetSwitchCooldownSamples - 1)
            return PrimaryTargetSelection(
                detection = memoryCandidate,
                stable = true,
                switched = false,
                switchReason = "memory_continuity",
                continuityScore = continuityScoreForRect(memoryCandidate.rect, memoryRect),
            )
        }
        val currentMemoryCandidate =
            memoryRect?.let { rememberedRect ->
                candidates.maxByOrNull { continuityScoreForRect(it.rect, rememberedRect) }
            }
        val currentMemoryScore =
            currentMemoryCandidate?.let {
                scorePrimaryDetection(it) + (continuityScoreForRect(it.rect, memoryRect) * 0.52f)
            } ?: Float.NEGATIVE_INFINITY
        val margin = topScore - currentMemoryScore
        val cooldownActive = primaryTargetSwitchCooldownSamples > 0
        val shouldHoldMemory =
            currentMemoryCandidate != null &&
                (cooldownActive || margin < DANMAKU_AI_PRIMARY_TARGET_SWITCH_SCORE_MARGIN)
        if (shouldHoldMemory) {
            primaryTargetCandidateRect = null
            primaryTargetCandidateWins = 0
            primaryTargetSwitchCooldownSamples = max(0, primaryTargetSwitchCooldownSamples - 1)
            return PrimaryTargetSelection(
                detection = currentMemoryCandidate,
                stable = true,
                switched = false,
                switchReason = if (cooldownActive) "switch_cooldown" else "memory_hold",
                continuityScore = continuityScoreForRect(currentMemoryCandidate.rect, memoryRect),
            )
        }
        val topCandidate = top
        if (topCandidate == null) {
            return PrimaryTargetSelection(
                detection = null,
                stable = false,
                switched = false,
                switchReason = "no_ranked_candidate",
                continuityScore = 0f,
            )
        }
        if (memoryRect == null) {
            primaryTargetCandidateRect = null
            primaryTargetCandidateWins = 0
            return PrimaryTargetSelection(
                detection = topCandidate,
                stable = false,
                switched = false,
                switchReason = "initial_target",
                continuityScore = 0f,
            )
        }
        if (primaryTargetCandidateRect != null && topCandidate.rect.iou(primaryTargetCandidateRect!!) > 0.82f) {
            primaryTargetCandidateWins += 1
        } else {
            primaryTargetCandidateRect = topCandidate.rect
            primaryTargetCandidateWins = 1
        }
        val switched =
            primaryTargetCandidateWins >= DANMAKU_AI_PRIMARY_TARGET_SWITCH_CONFIRM_SAMPLES
        if (switched) {
            primaryTargetSwitchCooldownSamples = DANMAKU_AI_PRIMARY_TARGET_SWITCH_COOLDOWN_SAMPLES
            primaryTargetCandidateRect = null
            primaryTargetCandidateWins = 0
        }
        return PrimaryTargetSelection(
            detection = if (switched) topCandidate else currentMemoryCandidate ?: topCandidate,
            stable = false,
            switched = switched,
            switchReason =
                if (switched) {
                    "switch_confirmed"
                } else {
                    "switch_pending"
                },
            continuityScore = continuityScoreForRect(topCandidate.rect, memoryRect),
        )
    }

    private fun scorePrimaryDetection(candidate: DanmakuPrimaryDetection): Float {
        val rect = candidate.rect
        val centerX = rect.x + (rect.width / 2f)
        val centerY = rect.y + (rect.height / 2f)
        val dx = centerX - DANMAKU_AI_TARGET_CENTER_X
        val dy = centerY - DANMAKU_AI_TARGET_CENTER_Y
        val distancePenalty = (dx * dx) + (dy * dy)
        return (candidate.score * DANMAKU_AI_DETECTION_WEIGHT_SCORE) +
            (rect.area() * DANMAKU_AI_DETECTION_WEIGHT_AREA) -
            (distancePenalty * DANMAKU_AI_DETECTION_WEIGHT_DISTANCE)
    }

    private fun currentSmallMultiThresholds(): DanmakuSmallMultiThresholds {
        val resources = context.resources
        val density = resources.displayMetrics.density.takeIf { it > 0f } ?: 1f
        val viewWidthPx = videoOutputTarget.view.width
        val viewHeightPx = videoOutputTarget.view.height
        val configuredShortSideDp =
            resources.configuration.smallestScreenWidthDp
                .takeIf { it > 0 }
                ?.toFloat()
                ?: minOf(
                    resources.configuration.screenWidthDp.takeIf { it > 0 } ?: DANMAKU_AI_SMALL_MULTI_BASE_SHORT_SIDE_DP.toInt(),
                    resources.configuration.screenHeightDp.takeIf { it > 0 } ?: DANMAKU_AI_SMALL_MULTI_BASE_SHORT_SIDE_DP.toInt(),
                ).toFloat()
        val viewportShortSideDp =
            if (viewWidthPx > 0 && viewHeightPx > 0) {
                minOf(viewWidthPx, viewHeightPx).toFloat() / density
            } else {
                configuredShortSideDp
            }.coerceAtLeast(240f)
        val shortSideRatio = viewportShortSideDp / DANMAKU_AI_SMALL_MULTI_BASE_SHORT_SIDE_DP
        val dimensionScale =
            sqrt(shortSideRatio)
                .coerceIn(
                    DANMAKU_AI_SMALL_MULTI_MIN_DIMENSION_SCALE,
                    DANMAKU_AI_SMALL_MULTI_MAX_DIMENSION_SCALE,
                )
        val areaScale =
            (dimensionScale * dimensionScale)
                .coerceIn(
                    DANMAKU_AI_SMALL_MULTI_MIN_AREA_SCALE,
                    DANMAKU_AI_SMALL_MULTI_MAX_AREA_SCALE,
                )
        return DanmakuSmallMultiThresholds(
            thresholdScale = areaScale,
            viewportShortSideDp = viewportShortSideDp,
            maxAreaRatio = DANMAKU_AI_SMALL_MULTI_MAX_AREA_RATIO * areaScale,
            maxWidthRatio = DANMAKU_AI_SMALL_MULTI_MAX_WIDTH_RATIO * dimensionScale,
            maxHeightRatio = DANMAKU_AI_SMALL_MULTI_MAX_HEIGHT_RATIO * dimensionScale,
            singleMaskMaxAreaRatio = DANMAKU_AI_SMALL_MULTI_SINGLE_MASK_MAX_AREA_RATIO * areaScale,
            unionMaxAreaRatio = DANMAKU_AI_SMALL_MULTI_UNION_MAX_AREA_RATIO * areaScale,
        )
    }

    private fun isSmallMultiDetection(
        candidate: DanmakuPrimaryDetection,
        thresholds: DanmakuSmallMultiThresholds,
    ): Boolean {
        val rect = candidate.rect
        return candidate.score >= DANMAKU_AI_SMALL_MULTI_MIN_SCORE &&
            rect.area() in DANMAKU_AI_SMALL_MULTI_MIN_AREA_RATIO..thresholds.maxAreaRatio &&
            rect.width <= thresholds.maxWidthRatio &&
            rect.height <= thresholds.maxHeightRatio &&
            !isCoarseDetectionRect(rect)
    }

    private fun isRelaxedSmallMultiDetection(
        candidate: DanmakuPrimaryDetection,
        thresholds: DanmakuSmallMultiThresholds,
    ): Boolean {
        val rect = candidate.rect
        return candidate.score >= DANMAKU_AI_MULTI_DETECTION_SCORE_THRESHOLD &&
            rect.area() in DANMAKU_AI_SMALL_MULTI_MIN_AREA_RATIO..(thresholds.maxAreaRatio * DANMAKU_AI_SMALL_MULTI_RELAXED_MAX_AREA_MULTIPLIER) &&
            rect.width <= (thresholds.maxWidthRatio * DANMAKU_AI_SMALL_MULTI_RELAXED_MAX_WIDTH_MULTIPLIER) &&
            rect.height <= (thresholds.maxHeightRatio * DANMAKU_AI_SMALL_MULTI_RELAXED_MAX_HEIGHT_MULTIPLIER) &&
            !isCoarseDetectionRect(rect)
    }

    private fun isWeakSmallMultiDetection(
        candidate: DanmakuPrimaryDetection,
        thresholds: DanmakuSmallMultiThresholds,
    ): Boolean {
        val rect = candidate.rect
        return candidate.score >= DANMAKU_AI_SMALL_MULTI_WEAK_MIN_SCORE &&
            rect.area() in DANMAKU_AI_SMALL_MULTI_MIN_AREA_RATIO..(thresholds.maxAreaRatio * DANMAKU_AI_SMALL_MULTI_WEAK_MAX_AREA_MULTIPLIER) &&
            rect.width <= (thresholds.maxWidthRatio * DANMAKU_AI_SMALL_MULTI_WEAK_MAX_WIDTH_MULTIPLIER) &&
            rect.height <= (thresholds.maxHeightRatio * DANMAKU_AI_SMALL_MULTI_WEAK_MAX_HEIGHT_MULTIPLIER) &&
            !isCoarseDetectionRect(rect)
    }

    private fun pickDistinctSmallMultiDetections(
        candidates: List<DanmakuPrimaryDetection>,
        initial: List<DanmakuPrimaryDetection> = emptyList(),
    ): List<DanmakuPrimaryDetection> {
        val selected = initial.toMutableList()
        for (candidate in candidates) {
            if (selected.any { existing ->
                    candidate.rect.iou(existing.rect) > DANMAKU_AI_SMALL_MULTI_MAX_IOU
                }
            ) {
                continue
            }
            selected += candidate
            if (selected.size >= DANMAKU_AI_SMALL_MULTI_MAX_PEOPLE) {
                break
            }
        }
        return selected
    }

    private fun scoreSmallMultiTrackAssociation(
        track: DanmakuSmallMultiTrack,
        candidate: DanmakuPrimaryDetection,
    ): Float? {
        val iou = track.rect.iou(candidate.rect)
        val centerDistance =
            sqrt(
                ((track.rect.centerX - candidate.rect.centerX).pow(2)) +
                    ((track.rect.centerY - candidate.rect.centerY).pow(2)),
            )
        val trackArea = track.rect.area().coerceAtLeast(1e-4f)
        val candidateArea = candidate.rect.area().coerceAtLeast(1e-4f)
        val areaRatio = candidateArea / trackArea
        if (areaRatio !in DANMAKU_AI_SMALL_MULTI_TRACK_ASSOCIATION_MIN_AREA_RATIO..DANMAKU_AI_SMALL_MULTI_TRACK_ASSOCIATION_MAX_AREA_RATIO) {
            return null
        }
        if (iou < DANMAKU_AI_SMALL_MULTI_TRACK_ASSOCIATION_MIN_IOU &&
            centerDistance > DANMAKU_AI_SMALL_MULTI_TRACK_ASSOCIATION_MAX_CENTER_DISTANCE
        ) {
            return null
        }
        val areaPenalty = abs(areaRatio - 1f)
        return (iou * 2.8f) +
            (candidate.score * 0.8f) -
            (centerDistance * 1.35f) -
            (areaPenalty * 0.55f)
    }

    private fun matchSmallMultiTrackWithCandidates(
        track: DanmakuSmallMultiTrack,
        candidates: List<DanmakuPrimaryDetection>,
        usedIndices: Set<Int>,
        association: String,
    ): DanmakuSmallMultiMatchedCandidate? {
        var bestMatch: DanmakuSmallMultiMatchedCandidate? = null
        var bestScore = Float.NEGATIVE_INFINITY
        for ((index, candidate) in candidates.withIndex()) {
            if (index in usedIndices) {
                continue
            }
            val associationScore = scoreSmallMultiTrackAssociation(track, candidate) ?: continue
            if (associationScore <= bestScore) {
                continue
            }
            bestScore = associationScore
            bestMatch =
                DanmakuSmallMultiMatchedCandidate(
                    candidate = candidate,
                    candidateIndex = index,
                    association = association,
                )
        }
        return bestMatch
    }

    private fun splitCoarseDetectionForSecondaryTarget(
        coarseCandidate: DanmakuPrimaryDetection,
        anchorRect: DanmakuNormalizedRect,
    ): DanmakuPrimaryDetection? {
        val coarseRect = coarseCandidate.rect
        if (coarseRect.iou(anchorRect) <= 0f) {
            return null
        }
        val coarseLeft = coarseRect.left
        val coarseTop = coarseRect.top
        val coarseRight = coarseRect.right
        val coarseBottom = coarseRect.bottom
        val anchorLeft = anchorRect.left.coerceIn(coarseLeft, coarseRight)
        val anchorRight = anchorRect.right.coerceIn(coarseLeft, coarseRight)
        val anchorTop = anchorRect.top.coerceIn(coarseTop, coarseBottom)
        val anchorBottom = anchorRect.bottom.coerceIn(coarseTop, coarseBottom)

        val horizontalRemainders =
            listOf(
                DanmakuNormalizedRect(
                    x = coarseLeft,
                    y = coarseTop,
                    width = (anchorLeft - coarseLeft).coerceAtLeast(0f),
                    height = coarseRect.height,
                ),
                DanmakuNormalizedRect(
                    x = anchorRight,
                    y = coarseTop,
                    width = (coarseRight - anchorRight).coerceAtLeast(0f),
                    height = coarseRect.height,
                ),
            )
        val verticalRemainders =
            listOf(
                DanmakuNormalizedRect(
                    x = coarseLeft,
                    y = coarseTop,
                    width = coarseRect.width,
                    height = (anchorTop - coarseTop).coerceAtLeast(0f),
                ),
                DanmakuNormalizedRect(
                    x = coarseLeft,
                    y = anchorBottom,
                    width = coarseRect.width,
                    height = (coarseBottom - anchorBottom).coerceAtLeast(0f),
                ),
            )
        val candidateRect =
            (horizontalRemainders + verticalRemainders)
                .filter {
                    it.width >= DANMAKU_AI_SMALL_MULTI_COARSE_SPLIT_MIN_REMAINDER_WIDTH &&
                        it.height >= DANMAKU_AI_SMALL_MULTI_COARSE_SPLIT_MIN_REMAINDER_HEIGHT &&
                        it.area() >= DANMAKU_AI_SMALL_MULTI_COARSE_SPLIT_MIN_REMAINDER_AREA
                }.maxByOrNull { it.area() }
                ?: return null
        return DanmakuPrimaryDetection(
            rect = candidateRect,
            score = (coarseCandidate.score * 0.92f).coerceAtLeast(DANMAKU_AI_SMALL_MULTI_WEAK_MIN_SCORE),
        )
    }

    private fun summarizeTrackMetric(
        tracks: List<DanmakuSmallMultiTrack>,
        metric: (DanmakuSmallMultiTrack) -> Int,
    ): String? =
        tracks
            .takeIf { it.isNotEmpty() }
            ?.joinToString("|") { metric(it).toString() }

    private fun summarizeTrackTargets(
        targets: List<DanmakuSmallMultiTrackTarget>,
        metric: (DanmakuSmallMultiTrackTarget) -> String,
    ): String? =
        targets
            .takeIf { it.isNotEmpty() }
            ?.joinToString("|") { metric(it) }

    private fun sortSmallMultiTrackTargets(
        targets: List<DanmakuSmallMultiTrackTarget>,
    ): List<DanmakuSmallMultiTrackTarget> =
        targets.sortedWith(
            compareByDescending<DanmakuSmallMultiTrackTarget> { it.hitCount }
                .thenBy { it.missCount }
                .thenByDescending { it.score },
        )

    private fun nextSmallMultiTrackId(): Int {
        val nextId = smallMultiNextTrackId
        smallMultiNextTrackId += 1
        return nextId
    }

    private fun selectSmallMultiDetections(
        detections: List<DanmakuDetectionCandidate>,
    ): DanmakuSmallMultiSelection {
        val thresholds = currentSmallMultiThresholds()
        val rankedCandidates =
            buildPrimaryDetectionCandidates(
                detections = detections,
                minScore = DANMAKU_AI_MULTI_DETECTION_SCORE_THRESHOLD,
                minAreaRatio = DANMAKU_AI_SMALL_MULTI_MIN_AREA_RATIO,
            )
                .sortedByDescending(::scorePrimaryDetection)
        if (rankedCandidates.isEmpty()) {
            return DanmakuSmallMultiSelection(
                targets = emptyList(),
                candidateCount = 0,
                thresholdScale = thresholds.thresholdScale,
                viewportShortSideDp = thresholds.viewportShortSideDp,
                trackState = emptyList(),
                trackCount = 0,
                coarseOnlySamples = 0,
            )
        }
        val smallCandidates = rankedCandidates.filter { isSmallMultiDetection(it, thresholds) }
        val dominantCoarseCount = rankedCandidates.count { isCoarseDetectionRect(it.rect) }
        val relaxedCandidates =
            rankedCandidates.filter { candidate ->
                candidate !in smallCandidates && isRelaxedSmallMultiDetection(candidate, thresholds)
            }
        val weakCandidates =
            rankedCandidates.filter { candidate ->
                candidate !in smallCandidates &&
                    candidate !in relaxedCandidates &&
                    isWeakSmallMultiDetection(candidate, thresholds)
            }
        val coarseCandidates = rankedCandidates.filter { isCoarseDetectionRect(it.rect) }
        val existingTracks =
            smallMultiTracks
                .sortedWith(
                    compareByDescending<DanmakuSmallMultiTrack> { it.hitCount }
                        .thenBy { it.missCount }
                        .thenByDescending { it.score },
                ).take(DANMAKU_AI_SMALL_MULTI_TRACK_MAX_COUNT)
        val hasStableExistingTrack =
            existingTracks.any { it.hitCount >= DANMAKU_AI_SMALL_MULTI_TRACK_MIN_HIT_SAMPLES }
        val stableAnchorTrack =
            existingTracks
                .filter { it.hitCount >= 1 }
                .maxWithOrNull(
                    compareByDescending<DanmakuSmallMultiTrack> { it.hitCount }
                        .thenBy { it.missCount }
                        .thenByDescending { it.score },
                )
        val hasReusableExistingTracks =
            existingTracks.count { it.hitCount >= 1 && it.missCount < DANMAKU_AI_SMALL_MULTI_TRACK_MAX_MISS_SAMPLES_WEAK } >=
                DANMAKU_AI_SMALL_MULTI_MAX_PEOPLE
        val coarseSplitCandidate =
            if (!hasReusableExistingTracks && stableAnchorTrack != null) {
                coarseCandidates
                    .asSequence()
                    .mapNotNull { splitCoarseDetectionForSecondaryTarget(it, stableAnchorTrack.rect) }
                    .filter { it.rect.iou(stableAnchorTrack.rect) <= DANMAKU_AI_SMALL_MULTI_MAX_IOU }
                    .maxByOrNull { it.rect.area() * it.score }
            } else {
                null
            }
        val newCoarseOnlySamples =
            if (smallCandidates.isEmpty() && relaxedCandidates.isEmpty() && dominantCoarseCount > 0) {
                (smallMultiCoarseOnlySamples + 1).coerceAtMost(DANMAKU_AI_SMALL_MULTI_COARSE_ONLY_CLEAR_SAMPLES)
            } else {
                0
            }
        if (newCoarseOnlySamples >= DANMAKU_AI_SMALL_MULTI_COARSE_ONLY_CLEAR_SAMPLES &&
            !hasStableExistingTrack &&
            !hasReusableExistingTracks &&
            smallMultiStickySamplesRemaining <= 0
        ) {
            return DanmakuSmallMultiSelection(
                targets = emptyList(),
                candidateCount = rankedCandidates.size,
                thresholdScale = thresholds.thresholdScale,
                viewportShortSideDp = thresholds.viewportShortSideDp,
                dropReason = "coarse_ignored,insufficient_small_candidates",
                trackState = emptyList(),
                trackCount = 0,
                coarseOnlySamples = newCoarseOnlySamples,
            )
        }
        val strictSelected = pickDistinctSmallMultiDetections(smallCandidates)
        val usedHighIndices = mutableSetOf<Int>()
        val usedLowIndices = mutableSetOf<Int>()
        val nextTracks = mutableListOf<DanmakuSmallMultiTrack>()
        val matureTrackTargets = mutableListOf<DanmakuSmallMultiTrackTarget>()
        val freshTrackTargets = mutableListOf<DanmakuSmallMultiTrackTarget>()
        for (track in existingTracks) {
            val highMatch =
                matchSmallMultiTrackWithCandidates(
                    track = track,
                    candidates = smallCandidates,
                    usedIndices = usedHighIndices,
                    association = "high",
                )
            val lowMatch =
                if (highMatch == null) {
                    matchSmallMultiTrackWithCandidates(
                        track = track,
                        candidates = relaxedCandidates,
                        usedIndices = usedLowIndices,
                        association = "low",
                    )
                } else {
                    null
                }
            val matched = highMatch ?: lowMatch
            if (matched != null) {
                if (matched.association == "high") {
                    usedHighIndices += matched.candidateIndex
                } else {
                    usedLowIndices += matched.candidateIndex
                }
                val updatedTrack =
                    track.copy(
                        rect = matched.candidate.rect,
                        score = matched.candidate.score,
                        age = track.age + 1,
                        missCount = 0,
                        hitCount = track.hitCount + 1,
                        lastMatchedSampleId = sampleSequence + 1L,
                    )
                nextTracks += updatedTrack
                if (updatedTrack.hitCount >= DANMAKU_AI_SMALL_MULTI_TRACK_MIN_HIT_SAMPLES) {
                    matureTrackTargets +=
                        DanmakuSmallMultiTrackTarget(
                            trackId = updatedTrack.trackId,
                            rect = updatedTrack.rect,
                            score = updatedTrack.score,
                            missCount = 0,
                            hitCount = updatedTrack.hitCount,
                            source = "detected",
                            association = matched.association,
                        )
                }
                continue
            }
            val missedTrack =
                track.copy(
                    age = track.age + 1,
                    missCount = track.missCount + 1,
                    score = (track.score * 0.96f).coerceAtLeast(0f),
                )
            val allowedMissSamples =
                if (track.hitCount >= 1) {
                    DANMAKU_AI_SMALL_MULTI_TRACK_MAX_MISS_SAMPLES_WEAK
                } else {
                    DANMAKU_AI_SMALL_MULTI_TRACK_MAX_MISS_SAMPLES
                }
            if (missedTrack.missCount > allowedMissSamples) {
                continue
            }
            nextTracks += missedTrack
            if (missedTrack.hitCount >= DANMAKU_AI_SMALL_MULTI_TRACK_MIN_HIT_SAMPLES &&
                missedTrack.missCount < allowedMissSamples
            ) {
                matureTrackTargets +=
                    DanmakuSmallMultiTrackTarget(
                        trackId = missedTrack.trackId,
                        rect = missedTrack.rect,
                        score = missedTrack.score,
                        missCount = missedTrack.missCount,
                        hitCount = missedTrack.hitCount,
                        source = "recovered",
                        association = "unmatched",
                    )
            }
        }
        val remainingHighCandidates =
            smallCandidates.filterIndexed { index, _ -> index !in usedHighIndices }
        for (candidate in remainingHighCandidates) {
            if (nextTracks.size >= DANMAKU_AI_SMALL_MULTI_TRACK_MAX_COUNT) {
                break
            }
            if (nextTracks.any { it.rect.iou(candidate.rect) > DANMAKU_AI_SMALL_MULTI_MAX_IOU }) {
                continue
            }
            nextTracks +=
                DanmakuSmallMultiTrack(
                    trackId = nextSmallMultiTrackId(),
                    rect = candidate.rect,
                    score = candidate.score,
                    age = 1,
                    missCount = 0,
                    hitCount = 1,
                    lastMatchedSampleId = sampleSequence + 1L,
                    lastMaskAreaRatio = 0f,
                )
            val newTrack = nextTracks.last()
            freshTrackTargets +=
                DanmakuSmallMultiTrackTarget(
                    trackId = newTrack.trackId,
                    rect = newTrack.rect,
                    score = newTrack.score,
                    missCount = 0,
                    hitCount = 1,
                    source = "detected",
                    association = "high",
                )
        }
        if ((hasStableExistingTrack ||
                hasReusableExistingTracks ||
                matureTrackTargets.isNotEmpty() ||
                compactTrackTargetsWouldBenefitFromRelaxedPartner(
                    matureTrackTargets = matureTrackTargets,
                    freshTrackTargets = freshTrackTargets,
                ) ||
                smallMultiStickySamplesRemaining > 0) &&
            nextTracks.size < DANMAKU_AI_SMALL_MULTI_TRACK_MAX_COUNT
        ) {
            val remainingRelaxedCandidates =
                relaxedCandidates.filterIndexed { index, _ -> index !in usedLowIndices }
            for (candidate in remainingRelaxedCandidates) {
                if (nextTracks.size >= DANMAKU_AI_SMALL_MULTI_TRACK_MAX_COUNT) {
                    break
                }
                if (nextTracks.any { it.rect.iou(candidate.rect) > DANMAKU_AI_SMALL_MULTI_MAX_IOU }) {
                    continue
                }
                nextTracks +=
                    DanmakuSmallMultiTrack(
                        trackId = nextSmallMultiTrackId(),
                        rect = candidate.rect,
                        score = candidate.score,
                        age = 1,
                        missCount = 0,
                        hitCount = 1,
                        lastMatchedSampleId = sampleSequence + 1L,
                        lastMaskAreaRatio = 0f,
                    )
                val newTrack = nextTracks.last()
                freshTrackTargets +=
                    DanmakuSmallMultiTrackTarget(
                        trackId = newTrack.trackId,
                        rect = newTrack.rect,
                        score = newTrack.score,
                        missCount = 0,
                        hitCount = 1,
                        source = "detected",
                        association = "low",
                    )
                usedLowIndices += remainingRelaxedCandidates.indexOf(candidate)
            }
        }
        if ((hasStableExistingTrack || matureTrackTargets.isNotEmpty() || compactFreshTrackTargetsWouldBenefitFromWeakPartner(freshTrackTargets)) &&
            nextTracks.size < DANMAKU_AI_SMALL_MULTI_TRACK_MAX_COUNT
        ) {
            val weakCandidatePool =
                buildList {
                    addAll(weakCandidates)
                    coarseSplitCandidate?.let { add(it) }
                }
            for (candidate in weakCandidatePool) {
                if (nextTracks.size >= DANMAKU_AI_SMALL_MULTI_TRACK_MAX_COUNT) {
                    break
                }
                if (nextTracks.any { it.rect.iou(candidate.rect) > DANMAKU_AI_SMALL_MULTI_MAX_IOU }) {
                    continue
                }
                nextTracks +=
                    DanmakuSmallMultiTrack(
                        trackId = nextSmallMultiTrackId(),
                        rect = candidate.rect,
                        score = candidate.score,
                        age = 1,
                        missCount = 0,
                        hitCount = 1,
                        lastMatchedSampleId = sampleSequence + 1L,
                        lastMaskAreaRatio = 0f,
                    )
                val newTrack = nextTracks.last()
                freshTrackTargets +=
                    DanmakuSmallMultiTrackTarget(
                        trackId = newTrack.trackId,
                        rect = newTrack.rect,
                        score = newTrack.score,
                        missCount = 0,
                        hitCount = 1,
                        source = "detected",
                        association = if (candidate == coarseSplitCandidate) "split" else "weak",
                    )
            }
        }
        val compactTracks =
            nextTracks
                .sortedWith(
                    compareByDescending<DanmakuSmallMultiTrack> { it.hitCount }
                        .thenBy { it.missCount }
                        .thenByDescending { it.score },
                ).take(DANMAKU_AI_SMALL_MULTI_TRACK_MAX_COUNT)
        val compactMatureTrackTargets =
            sortSmallMultiTrackTargets(
                matureTrackTargets.filter { target -> compactTracks.any { it.trackId == target.trackId } },
            )
        val compactFreshTrackTargets =
            sortSmallMultiTrackTargets(
                freshTrackTargets.filter { target -> compactTracks.any { it.trackId == target.trackId } },
            )
        val compactAllTrackTargets =
            sortSmallMultiTrackTargets(compactMatureTrackTargets + compactFreshTrackTargets)
        val compactTrackTargets =
            when {
                compactMatureTrackTargets.size >= DANMAKU_AI_SMALL_MULTI_MAX_PEOPLE ->
                    compactMatureTrackTargets.take(DANMAKU_AI_SMALL_MULTI_MAX_PEOPLE)
                compactMatureTrackTargets.size == 1 -> {
                    val stableTarget = compactMatureTrackTargets.first()
                    val partner =
                        compactAllTrackTargets.firstOrNull { it.trackId != stableTarget.trackId }
                    if (partner != null) {
                        listOf(stableTarget, partner)
                    } else {
                        emptyList()
                    }
                }
                compactFreshTrackTargets.size >= DANMAKU_AI_SMALL_MULTI_MAX_PEOPLE ->
                    compactFreshTrackTargets.take(DANMAKU_AI_SMALL_MULTI_MAX_PEOPLE)
                else -> emptyList()
            }
        val dropReasons = mutableListOf<String>()
        if (dominantCoarseCount > 0 && (smallCandidates.isNotEmpty() || relaxedCandidates.isNotEmpty())) {
            dropReasons += "coarse_ignored"
        }
        if (strictSelected.size in 1 until DANMAKU_AI_SMALL_MULTI_MAX_PEOPLE) {
            dropReasons += "insufficient_small_candidates"
        }
        if (compactTrackTargets.any { it.association == "low" }) {
            dropReasons += "relaxed"
        }
        if (compactTrackTargets.any { it.association == "weak" }) {
            dropReasons += "weak"
        }
        if (compactTrackTargets.any { it.association == "split" }) {
            dropReasons += "split"
        }
        return DanmakuSmallMultiSelection(
            targets =
                if (compactTrackTargets.size >= DANMAKU_AI_SMALL_MULTI_MAX_PEOPLE) {
                    compactTrackTargets
                } else {
                    emptyList()
                },
            candidateCount = rankedCandidates.size,
            thresholdScale = thresholds.thresholdScale,
            viewportShortSideDp = thresholds.viewportShortSideDp,
            dropReason = dropReasons.distinct().joinToString(",").takeIf { it.isNotEmpty() },
            trackState = compactTracks,
            trackCount = compactTracks.size,
            trackHits = summarizeTrackMetric(compactTracks, DanmakuSmallMultiTrack::hitCount),
            trackMisses = summarizeTrackMetric(compactTracks, DanmakuSmallMultiTrack::missCount),
            trackSource = summarizeTrackTargets(compactTrackTargets, DanmakuSmallMultiTrackTarget::source),
            association = summarizeTrackTargets(compactTrackTargets, DanmakuSmallMultiTrackTarget::association),
            coarseOnlySamples = newCoarseOnlySamples,
        )
    }

    private fun resolveSmallMultiDropReason(
        selection: DanmakuSmallMultiSelection,
        suppressed: Boolean,
        stableSingleTargetPreferred: Boolean,
    ): String? {
        if (selection.targets.size < DANMAKU_AI_SMALL_MULTI_MAX_PEOPLE) {
            return selection.dropReason
        }
        val dropReasonTokens =
            selection.dropReason
                ?.split(',')
                ?.map { it.trim() }
                ?.filter { it.isNotEmpty() }
                ?.toSet()
                ?: emptySet()
        val hasReusableTracks =
            selection.trackState.count {
                it.hitCount >= 1 && it.missCount < DANMAKU_AI_SMALL_MULTI_TRACK_MAX_MISS_SAMPLES_WEAK
            } >= DANMAKU_AI_SMALL_MULTI_MAX_PEOPLE
        val usesRelaxedOrWeakPartner =
            dropReasonTokens.any { it == "relaxed" || it == "weak" || it == "split" }
        if (
            "insufficient_small_candidates" in dropReasonTokens &&
                (!hasReusableTracks || usesRelaxedOrWeakPartner || stableSingleTargetPreferred)
        ) {
            return mergeDropReasons(
                selection.dropReason,
                if (stableSingleTargetPreferred) "single_target_priority" else null,
            )
        }
        if (stableSingleTargetPreferred && usesRelaxedOrWeakPartner) {
            return mergeDropReasons(selection.dropReason, "single_target_priority")
        }
        if (suppressed) {
            return "suppressed"
        }
        if (sceneCutRecoveryActive || degradationStage > 0) {
            return "latency"
        }
        val latencyRatio =
            if (hasReusableTracks || smallMultiStickySamplesRemaining > 0) {
                DANMAKU_AI_SMALL_MULTI_MODE_LATENCY_HOLD_RATIO
            } else {
                DANMAKU_AI_SMALL_MULTI_MODE_LATENCY_HEADROOM_RATIO
            }
        val budgetThresholdMs = preferredSampleIntervalMs().toDouble() * latencyRatio
        if (averageLatencyMs > 0.0 && averageLatencyMs > budgetThresholdMs) {
            return "latency"
        }
        return null
    }

    private fun shouldPreferSmallMultiMode(
        selection: DanmakuSmallMultiSelection,
        dropReason: String?,
    ): Boolean {
        if (selection.targets.size < DANMAKU_AI_SMALL_MULTI_MAX_PEOPLE) {
            return false
        }
        if (dropReason == null) {
            return true
        }
        if (dropReason.contains("single_target_priority")) {
            return false
        }
        val hasReusableTracks =
            selection.trackState.count {
                it.hitCount >= 1 && it.missCount < DANMAKU_AI_SMALL_MULTI_TRACK_MAX_MISS_SAMPLES_WEAK
            } >= DANMAKU_AI_SMALL_MULTI_MAX_PEOPLE
        return dropReason == "latency" && (smallMultiStickySamplesRemaining > 0 || hasReusableTracks)
    }

    private fun compactTrackTargetsWouldBenefitFromRelaxedPartner(
        matureTrackTargets: List<DanmakuSmallMultiTrackTarget>,
        freshTrackTargets: List<DanmakuSmallMultiTrackTarget>,
    ): Boolean = matureTrackTargets.size == 1 || freshTrackTargets.isNotEmpty()

    private fun compactFreshTrackTargetsWouldBenefitFromWeakPartner(
        freshTrackTargets: List<DanmakuSmallMultiTrackTarget>,
    ): Boolean = freshTrackTargets.size == 1

    private fun effectiveSmallMultiInputWidth(): Int =
        max(
            DANMAKU_AI_REDUCED_INPUT_WIDTH,
            effectiveInputWidth() - DANMAKU_AI_SMALL_MULTI_INPUT_WIDTH_REDUCTION,
        ).coerceAtMost(effectiveInputWidth())

    private fun segmentationTargetAspectRatio(): Float {
        val configuredAspectRatio =
            if (config.inputHeight > 0) {
                config.inputWidth.toFloat() / config.inputHeight.toFloat()
            } else {
                DANMAKU_AI_SEGMENTATION_TARGET_ASPECT_RATIO
            }
        return configuredAspectRatio
            .takeIf { it.isFinite() && it > 0f }
            ?.coerceIn(1.2f, 2.4f)
            ?: DANMAKU_AI_SEGMENTATION_TARGET_ASPECT_RATIO
    }

    private fun expandRectForSegmentation(
        rect: DanmakuNormalizedRect,
        roiMode: DanmakuSegmentationRoiMode,
    ): DanmakuNormalizedRect {
        val horizontalRatio =
            if (roiMode == DanmakuSegmentationRoiMode.TRACKED) {
                DANMAKU_AI_TRACKED_ROI_EXPAND_HORIZONTAL_RATIO
            } else {
                DANMAKU_AI_DETECTION_EXPAND_HORIZONTAL_RATIO
            }
        val verticalRatio =
            if (roiMode == DanmakuSegmentationRoiMode.TRACKED) {
                DANMAKU_AI_TRACKED_ROI_EXPAND_VERTICAL_RATIO
            } else {
                DANMAKU_AI_DETECTION_EXPAND_VERTICAL_RATIO
            }
        return rect.expanded(
            horizontalRatio = horizontalRatio,
            verticalRatio = verticalRatio,
        )
    }

    private fun createSegmentationRoi(
        bitmap: Bitmap,
        detectionRect: DanmakuNormalizedRect,
        roiMode: DanmakuSegmentationRoiMode,
        inputWidthOverride: Int? = null,
    ): DanmakuSegmentationRoi {
        val focusRect = resolveSegmentationFocusRect(detectionRect, roiMode)
        val sourceRect = expandRectForSegmentation(focusRect, roiMode)
        val left = (sourceRect.x * bitmap.width).toInt().coerceIn(0, bitmap.width - 1)
        val top = (sourceRect.y * bitmap.height).toInt().coerceIn(0, bitmap.height - 1)
        val right =
            ((sourceRect.x + sourceRect.width) * bitmap.width)
                .roundToInt()
                .coerceIn(left + 1, bitmap.width)
        val bottom =
            ((sourceRect.y + sourceRect.height) * bitmap.height)
                .roundToInt()
                .coerceIn(top + 1, bitmap.height)
        val cropWidth = (right - left).coerceAtLeast(1)
        val cropHeight = (bottom - top).coerceAtLeast(1)
        val rawCrop = Bitmap.createBitmap(bitmap, left, top, cropWidth, cropHeight)
        val targetWidth =
            (inputWidthOverride ?: effectiveInputWidth()).coerceIn(
                DANMAKU_AI_DEGRADED_INPUT_WIDTH,
                DANMAKU_AI_REFINE_MAX_WIDTH,
            )
        val targetHeight =
            (targetWidth.toFloat() / segmentationTargetAspectRatio())
                .roundToInt()
                .coerceIn(96, 512)
        val targetBitmap: Bitmap
        val contentRect: DanmakuNormalizedRect
        if (rawCrop.width == targetWidth && rawCrop.height == targetHeight) {
            targetBitmap = rawCrop
            contentRect =
                DanmakuNormalizedRect(
                    x = 0f,
                    y = 0f,
                    width = 1f,
                    height = 1f,
                )
        } else {
            val cropAspectRatio = rawCrop.width.toFloat() / rawCrop.height.toFloat()
            val targetAspectRatio = targetWidth.toFloat() / targetHeight.toFloat()
            val contentWidth: Int
            val contentHeight: Int
            val offsetX: Int
            val offsetY: Int
            if (cropAspectRatio >= targetAspectRatio) {
                contentWidth = targetWidth
                contentHeight =
                    (targetWidth.toFloat() / cropAspectRatio)
                        .roundToInt()
                        .coerceIn(1, targetHeight)
                offsetX = 0
                offsetY = ((targetHeight - contentHeight) / 2).coerceAtLeast(0)
            } else {
                contentHeight = targetHeight
                contentWidth =
                    (targetHeight.toFloat() * cropAspectRatio)
                        .roundToInt()
                        .coerceIn(1, targetWidth)
                offsetX = ((targetWidth - contentWidth) / 2).coerceAtLeast(0)
                offsetY = 0
            }
            targetBitmap = Bitmap.createBitmap(targetWidth, targetHeight, Bitmap.Config.ARGB_8888)
            targetBitmap.eraseColor(Color.BLACK)
            Canvas(targetBitmap).drawBitmap(
                rawCrop,
                null,
                Rect(offsetX, offsetY, offsetX + contentWidth, offsetY + contentHeight),
                Paint(Paint.FILTER_BITMAP_FLAG),
            )
            if (!rawCrop.isRecycled) {
                rawCrop.recycle()
            }
            contentRect =
                DanmakuNormalizedRect(
                    x = offsetX.toFloat() / targetWidth.toFloat(),
                    y = offsetY.toFloat() / targetHeight.toFloat(),
                    width = contentWidth.toFloat() / targetWidth.toFloat(),
                    height = contentHeight.toFloat() / targetHeight.toFloat(),
                )
        }
        return DanmakuSegmentationRoi(
            bitmap = targetBitmap,
            rect =
                DanmakuNormalizedRect(
                    x = left.toFloat() / bitmap.width.toFloat(),
                    y = top.toFloat() / bitmap.height.toFloat(),
                    width = cropWidth.toFloat() / bitmap.width.toFloat(),
                    height = cropHeight.toFloat() / bitmap.height.toFloat(),
                ),
            contentRect = contentRect,
            mode = roiMode.wireValue,
            inputWidth = targetWidth,
            inputHeight = targetHeight,
        )
    }

    private fun resolveSegmentationFocusRect(
        rect: DanmakuNormalizedRect,
        roiMode: DanmakuSegmentationRoiMode,
    ): DanmakuNormalizedRect {
        if (roiMode != DanmakuSegmentationRoiMode.DETECT || sceneCutRecoveryActive) {
            return rect
        }
        val previousRect = trackingRectOrDisplayRect() ?: return rect
        if (!isCoarseDetectionRect(rect)) {
            return rect
        }
        if (previousRect.area() < DANMAKU_AI_DETECTION_MIN_AREA_RATIO) {
            return rect
        }
        val centerDistance =
            sqrt(
                ((rect.centerX - previousRect.centerX).pow(2)) +
                    ((rect.centerY - previousRect.centerY).pow(2)),
            )
        if (rect.iou(previousRect) < 0.02f && centerDistance > DANMAKU_AI_DETECTION_STABILIZE_MAX_CENTER_DISTANCE) {
            return rect
        }
        return rectFromCenter(
            centerX =
                previousRect.centerX +
                    ((rect.centerX - previousRect.centerX) * DANMAKU_AI_DETECTION_STABILIZE_BLEND_ALPHA),
            centerY =
                previousRect.centerY +
                    ((rect.centerY - previousRect.centerY) * DANMAKU_AI_DETECTION_STABILIZE_BLEND_ALPHA),
            width = minOf(rect.width, previousRect.width * DANMAKU_AI_DETECTION_STABILIZE_MAX_GROWTH),
            height = minOf(rect.height, previousRect.height * DANMAKU_AI_DETECTION_STABILIZE_MAX_GROWTH),
        )
    }

    private fun isCoarseDetectionRect(rect: DanmakuNormalizedRect): Boolean {
        if (rect.area() >= DANMAKU_AI_COARSE_DETECTION_AREA_RATIO) {
            return true
        }
        if (
            rect.width >= DANMAKU_AI_COARSE_DETECTION_WIDTH_RATIO &&
                rect.height >= DANMAKU_AI_COARSE_DETECTION_HEIGHT_RATIO
        ) {
            return true
        }
        val hugsHorizontalEdges =
            rect.left <= DANMAKU_AI_COARSE_DETECTION_EDGE_THRESHOLD &&
                rect.right >= (1f - DANMAKU_AI_COARSE_DETECTION_EDGE_THRESHOLD)
        val hugsVerticalEdges =
            rect.top <= DANMAKU_AI_COARSE_DETECTION_EDGE_THRESHOLD &&
                rect.bottom >= (1f - DANMAKU_AI_COARSE_DETECTION_EDGE_THRESHOLD)
        return hugsHorizontalEdges || hugsVerticalEdges
    }

    private fun trackingRectOrDisplayRect(): DanmakuNormalizedRect? =
        latestTrackingRect ?: latestRect?.takeIf { latestRectTrackingEligible }

    private fun sanitizeTrackingRect(candidate: DanmakuNormalizedRect?): DanmakuNormalizedRect? {
        candidate ?: return null
        val previousRect = latestTrackingRect ?: return candidate
        val requiresStabilization =
            isCoarseDetectionRect(candidate) ||
                candidate.width > previousRect.width * DANMAKU_AI_TRACKING_RECT_MAX_GROWTH ||
                candidate.height > previousRect.height * DANMAKU_AI_TRACKING_RECT_MAX_GROWTH
        if (!requiresStabilization) {
            return candidate
        }
        val centerDistance =
            sqrt(
                ((candidate.centerX - previousRect.centerX).pow(2)) +
                    ((candidate.centerY - previousRect.centerY).pow(2)),
            )
        if (candidate.iou(previousRect) < 0.02f &&
            centerDistance > DANMAKU_AI_TRACKING_RECT_MAX_CENTER_DISTANCE
        ) {
            return previousRect
        }
        return rectFromCenter(
            centerX =
                previousRect.centerX +
                    ((candidate.centerX - previousRect.centerX) * DANMAKU_AI_TRACKING_RECT_STABILIZE_BLEND_ALPHA),
            centerY =
                previousRect.centerY +
                    ((candidate.centerY - previousRect.centerY) * DANMAKU_AI_TRACKING_RECT_STABILIZE_BLEND_ALPHA),
            width =
                if (candidate.width > previousRect.width) {
                    minOf(candidate.width, previousRect.width * DANMAKU_AI_TRACKING_RECT_MAX_GROWTH)
                } else {
                    candidate.width
                },
            height =
                if (candidate.height > previousRect.height) {
                    minOf(candidate.height, previousRect.height * DANMAKU_AI_TRACKING_RECT_MAX_GROWTH)
                } else {
                    candidate.height
                },
        )
    }

    private fun shouldAttemptScaleRescue(
        predictedScale: Float?,
        rejectReason: String?,
    ): Boolean {
        if (degradationStage > 1) {
            return false
        }
        if (rejectReason != "primary_component_empty" && rejectReason != "coverage_too_low") {
            return false
        }
        val scale = predictedScale ?: return false
        if (abs(scale - 1f) < DANMAKU_AI_SCALE_RESCUE_MIN_DELTA) {
            return false
        }
        val budgetThresholdMs = preferredSampleIntervalMs().toDouble()
        return averageLatencyMs <= 0.0 ||
            averageLatencyMs <= (budgetThresholdMs * DANMAKU_AI_SCALE_RESCUE_LATENCY_HEADROOM_RATIO)
    }

    private fun buildScaleRescueTargetRect(targetRect: DanmakuNormalizedRect): DanmakuNormalizedRect =
        rectFromCenter(
            centerX = targetRect.centerX,
            centerY = targetRect.centerY,
            width = targetRect.width * (1f + DANMAKU_AI_SCALE_RESCUE_EXPAND_RATIO),
            height = targetRect.height * (1f + DANMAKU_AI_SCALE_RESCUE_EXPAND_RATIO),
        )

    private fun runSegmentationForRect(
        bitmap: Bitmap,
        sampleId: Long,
        runtime: DanmakuSegmentationRuntime,
        targetRect: DanmakuNormalizedRect,
        roiMode: DanmakuSegmentationRoiMode,
        sampleAreaRatio: Float,
        allowTemporalSmoothing: Boolean,
        motionCompensation: DanmakuMotionCompensation?,
        motionCompensationAttempted: Boolean,
        predictedScale: Float? = null,
        inputWidthOverride: Int? = null,
        relaxValidationForSecondaryMultiTarget: Boolean = false,
        rejectLogContext: String? = null,
    ): DanmakuSegmentationAttempt {
        val primaryPass =
            runSegmentationPass(
                bitmap = bitmap,
                sampleId = sampleId,
                runtime = runtime,
                targetRect = targetRect,
                roiMode = roiMode,
                allowTemporalSmoothing = allowTemporalSmoothing,
                motionCompensation = motionCompensation,
                motionCompensationAttempted = motionCompensationAttempted,
                inputWidthOverride = inputWidthOverride,
                relaxValidationForSecondaryMultiTarget = relaxValidationForSecondaryMultiTarget,
                rejectLogContext = rejectLogContext,
            )
        var totalLatencyMs = primaryPass.latencyMs
        var selectedPass = primaryPass
        var scaleRescueApplied = false
        if (roiMode == DanmakuSegmentationRoiMode.TRACKED &&
            shouldAttemptScaleRescue(
                predictedScale = predictedScale,
                rejectReason = primaryPass.rejectReason,
            )
        ) {
            val rescuePass =
                runSegmentationPass(
                    bitmap = bitmap,
                    sampleId = sampleId,
                    runtime = runtime,
                    targetRect = buildScaleRescueTargetRect(targetRect),
                    roiMode = roiMode,
                    allowTemporalSmoothing = allowTemporalSmoothing,
                    motionCompensation = motionCompensation,
                    motionCompensationAttempted = motionCompensationAttempted,
                    inputWidthOverride = inputWidthOverride,
                    relaxValidationForSecondaryMultiTarget = relaxValidationForSecondaryMultiTarget,
                    rejectLogContext = rejectLogContext,
                )
            totalLatencyMs += rescuePass.latencyMs
            selectedPass = rescuePass
            scaleRescueApplied = true
        }
        val mappedExtraction =
            selectedPass.extraction?.let { rawExtraction ->
                val mappedResult =
                    if (sampleAreaRatio < 0.999f) {
                        remapMaskResultToFullFrame(rawExtraction.maskResult, sampleAreaRatio)
                    } else {
                        rawExtraction.maskResult
                    }
                DanmakuMaskExtraction(
                    maskResult = mappedResult,
                    appliedMotionCompensation = rawExtraction.appliedMotionCompensation,
                    maskScaleApplied = rawExtraction.maskScaleApplied,
                    maskScaleValue = rawExtraction.maskScaleValue,
                )
            }
        return DanmakuSegmentationAttempt(
            extraction = mappedExtraction,
            latencyMs = totalLatencyMs,
            roiRect = selectedPass.roiRect,
            roiMode = roiMode,
            inputWidth = selectedPass.inputWidth,
            inputHeight = selectedPass.inputHeight,
            rejectReason = selectedPass.rejectReason,
            scaleRescueApplied = scaleRescueApplied,
        )
    }

    private fun runSegmentationPass(
        bitmap: Bitmap,
        sampleId: Long,
        runtime: DanmakuSegmentationRuntime,
        targetRect: DanmakuNormalizedRect,
        roiMode: DanmakuSegmentationRoiMode,
        allowTemporalSmoothing: Boolean,
        motionCompensation: DanmakuMotionCompensation?,
        motionCompensationAttempted: Boolean,
        inputWidthOverride: Int? = null,
        relaxValidationForSecondaryMultiTarget: Boolean = false,
        rejectLogContext: String? = null,
    ): DanmakuSegmentationPassResult {
        val refineStartedAt = SystemClock.elapsedRealtime()
        val roi = createSegmentationRoi(bitmap, targetRect, roiMode, inputWidthOverride)
        val extractionResult =
            run {
                try {
                    val roiOutput =
                        synchronized(runtimeLock) {
                            if (disposed || activeRuntime !== runtime) {
                                null
                            } else {
                                runtime.run(roi.bitmap)
                            }
                        } ?: return@run DanmakuMaskExtractionResult(extraction = null, rejectReason = null)
                    extractMaskResultFromDetectedRoi(
                        sampleId = sampleId,
                        outputValues = roiOutput.maskValues,
                        outputWidth = roiOutput.width,
                        outputHeight = roiOutput.height,
                        fullWidth = bitmap.width,
                        fullHeight = bitmap.height,
                        detectionRect = targetRect,
                        roiRect = roi.rect,
                        roiContentRect = roi.contentRect,
                        allowTemporalSmoothing = allowTemporalSmoothing,
                        motionCompensation = motionCompensation,
                        motionCompensationAttempted = motionCompensationAttempted,
                        relaxValidationForSecondaryMultiTarget = relaxValidationForSecondaryMultiTarget,
                        rejectLogContext = rejectLogContext,
                    )
                } catch (error: Throwable) {
                    Log.w(
                        DANMAKU_AI_TAG,
                        "sample=$sampleId roi extraction failed detection=$targetRect roi=${roi.rect}",
                        error,
                    )
                    DanmakuMaskExtractionResult(extraction = null, rejectReason = null)
                } finally {
                    if (!roi.bitmap.isRecycled) {
                        roi.bitmap.recycle()
                    }
                }
            }
        val refineLatencyMs = SystemClock.elapsedRealtime() - refineStartedAt
        return DanmakuSegmentationPassResult(
            extraction = extractionResult.extraction,
            rejectReason = extractionResult.rejectReason,
            roiRect = roi.rect,
            inputWidth = roi.inputWidth,
            inputHeight = roi.inputHeight,
            latencyMs = refineLatencyMs,
        )
    }

    private fun extractMaskResultFromDetectedRoi(
        sampleId: Long,
        outputValues: FloatArray,
        outputWidth: Int,
        outputHeight: Int,
        fullWidth: Int,
        fullHeight: Int,
        detectionRect: DanmakuNormalizedRect,
        roiRect: DanmakuNormalizedRect,
        roiContentRect: DanmakuNormalizedRect,
        allowTemporalSmoothing: Boolean,
        motionCompensation: DanmakuMotionCompensation?,
        motionCompensationAttempted: Boolean,
        relaxValidationForSecondaryMultiTarget: Boolean = false,
        rejectLogContext: String? = null,
    ): DanmakuMaskExtractionResult {
        val hardThreshold =
            if (relaxValidationForSecondaryMultiTarget) {
                DANMAKU_AI_MULTI_SECONDARY_OUTPUT_MASK_HARD_THRESHOLD
            } else {
                DANMAKU_AI_OUTPUT_MASK_HARD_THRESHOLD
            }
        val keepThreshold =
            if (relaxValidationForSecondaryMultiTarget) {
                DANMAKU_AI_MULTI_SECONDARY_OUTPUT_MASK_KEEP_THRESHOLD
            } else {
                DANMAKU_AI_OUTPUT_MASK_KEEP_THRESHOLD
            }
        val minForegroundRatio =
            if (relaxValidationForSecondaryMultiTarget) {
                DANMAKU_AI_MULTI_SECONDARY_REFINE_MIN_FOREGROUND_RATIO
            } else {
                DANMAKU_AI_REFINE_MIN_FOREGROUND_RATIO
            }
        val minBoxCoverage =
            if (relaxValidationForSecondaryMultiTarget) {
                DANMAKU_AI_MULTI_SECONDARY_REFINE_MIN_BOX_COVERAGE
            } else {
                DANMAKU_AI_REFINE_MIN_BOX_COVERAGE
            }
        val minBoxIou =
            if (relaxValidationForSecondaryMultiTarget) {
                DANMAKU_AI_MULTI_SECONDARY_REFINE_MIN_BOX_IOU
            } else {
                DANMAKU_AI_REFINE_MIN_BOX_IOU
            }
        fun rejected(
            reason: String,
            mappedRect: DanmakuNormalizedRect? = null,
            coverage: Float? = null,
            iou: Float? = null,
            foregroundRatio: Float? = null,
        ): DanmakuMaskExtractionResult {
            logRoiMaskReject(
                sampleId = sampleId,
                reason = reason,
                detectionRect = detectionRect,
                roiRect = roiRect,
                mappedRect = mappedRect,
                coverage = coverage,
                iou = iou,
                foregroundRatio = foregroundRatio,
                context = rejectLogContext,
            )
            return DanmakuMaskExtractionResult(
                extraction = null,
                rejectReason = reason,
            )
        }
        val roiMaskPlane = cropMaskToContentRect(outputValues, outputWidth, outputHeight, roiContentRect)
        val roiMaskValues = roiMaskPlane.values
        val roiMaskWidth = roiMaskPlane.width
        val roiMaskHeight = roiMaskPlane.height
        val blurred = FloatArray(roiMaskValues.size)
        blurMask(roiMaskValues, blurred, roiMaskWidth, roiMaskHeight)
        val normalized = normalizeMask(blurred)
        val refined = refineMaskAlpha(normalized)
        val coreMask =
            buildThresholdMask(
                values = refined,
                threshold = hardThreshold,
            )
        val primaryCoreComponent =
            retainPrimaryMaskComponent(coreMask, roiMaskWidth, roiMaskHeight)
                ?: return rejected(reason = "primary_component_empty")
        val softCandidateMask =
            buildThresholdMask(
                values = refined,
                threshold = keepThreshold,
            )
        val grownMask =
            growMaskFromSeedWithinCandidate(
                seedMask = primaryCoreComponent.maskValues,
                candidateMask = softCandidateMask,
                width = roiMaskWidth,
                height = roiMaskHeight,
            )
        val primaryMaskComponent =
            retainPrimaryMaskComponent(grownMask, roiMaskWidth, roiMaskHeight) ?: primaryCoreComponent
        val maskedForegroundRatio =
            foregroundRatio(
                applyPrimaryMask(refined, primaryMaskComponent.maskValues),
                keepThreshold,
            )
        val maskedRefined =
            applyPrimaryMask(refined, primaryMaskComponent.maskValues).takeIf {
                maskedForegroundRatio >= minForegroundRatio
            } ?: return rejected(
                reason = "masked_foreground_ratio_too_low",
                foregroundRatio = maskedForegroundRatio,
            )
        val mappedRect = mapRectFromRoiToFullFrame(primaryMaskComponent.component.rect, roiRect)
        val validationMetrics =
            evaluateRoiMaskReasonableness(
                detectionRect = detectionRect,
                mappedRect = mappedRect,
                maskValues = primaryMaskComponent.maskValues,
            )
        if (validationMetrics.coverage < minBoxCoverage) {
            return rejected(
                reason = "coverage_too_low",
                mappedRect = mappedRect,
                coverage = validationMetrics.coverage,
                iou = validationMetrics.iou,
                foregroundRatio = validationMetrics.foregroundRatio,
            )
        }
        if (validationMetrics.iou < minBoxIou) {
            return rejected(
                reason = "iou_too_low",
                mappedRect = mappedRect,
                coverage = validationMetrics.coverage,
                iou = validationMetrics.iou,
                foregroundRatio = validationMetrics.foregroundRatio,
            )
        }
        if (validationMetrics.foregroundRatio < minForegroundRatio) {
            return rejected(
                reason = "final_foreground_ratio_too_low",
                mappedRect = mappedRect,
                coverage = validationMetrics.coverage,
                iou = validationMetrics.iou,
                foregroundRatio = validationMetrics.foregroundRatio,
            )
        }
        val fullMask =
            embedRoiMaskInFullFrame(
                maskedRefined,
                roiMaskWidth,
                roiMaskHeight,
                fullWidth,
                fullHeight,
                roiRect,
            )
        val appliedMotionCompensation =
            motionCompensation?.takeIf {
                shouldApplyMotionCompensation(
                    nextRect = mappedRect,
                    motionCompensation = it,
                )
            }
        val compensatedPreviousMask =
            buildCompensatedPreviousMask(appliedMotionCompensation, fullWidth, fullHeight)
        val compensatedPreviousRect = buildCompensatedPreviousRect(appliedMotionCompensation)
        val temporalSmoothingMinIou =
            if (motionCompensationAttempted && appliedMotionCompensation == null) {
                DANMAKU_AI_MOTION_MISS_TEMPORAL_FALLBACK_MIN_IOU
            } else {
                DANMAKU_AI_TEMPORAL_SMOOTHING_MIN_IOU
            }
        val shouldSmoothTemporally =
            allowTemporalSmoothing &&
                shouldUseTemporalSmoothing(
                    nextRect = mappedRect,
                    previousRectOverride = compensatedPreviousRect,
                    minIou = temporalSmoothingMinIou,
                )
        val finalMask =
            if (shouldSmoothTemporally) {
                smoothMaskOverTime(
                    nextMask = fullMask,
                    width = fullWidth,
                    height = fullHeight,
                    previousMaskOverride = compensatedPreviousMask,
                )
            } else {
                fullMask
            }
        val finalRect =
            if (shouldSmoothTemporally) {
                smoothRectOverTime(
                    nextRect = mappedRect,
                    previousRectOverride = compensatedPreviousRect,
                )
            } else {
                mappedRect
            }
        val constrainedMask =
            constrainMaskForOcclusionRender(
                maskValues = finalMask,
                width = fullWidth,
                height = fullHeight,
                detectionRect = detectionRect,
                previousRect = compensatedPreviousRect ?: trackingRectOrDisplayRect(),
            )
        val renderReadyMask = prepareMaskForOcclusionRender(constrainedMask, fullWidth, fullHeight)
        val renderReadyRect = extractPrimaryRect(renderReadyMask, fullWidth, fullHeight) ?: finalRect
        val maskScaleApplied = appliedMotionCompensation?.let { shouldApplyMaskScaleCompensation(it.scale) } == true
        val maskScaleValue = if (maskScaleApplied) appliedMotionCompensation?.scale ?: 1f else 1f
        return DanmakuMaskExtractionResult(
            extraction =
                DanmakuMaskExtraction(
                    maskResult =
                        DanmakuMaskResult(
                            maskValues = renderReadyMask,
                            maskWidth = fullWidth,
                            maskHeight = fullHeight,
                            normalizedRect = finalRect,
                            occlusionMode = DanmakuOcclusionMode.MASK,
                        ),
                    appliedMotionCompensation = appliedMotionCompensation,
                    maskScaleApplied = maskScaleApplied,
                    maskScaleValue = maskScaleValue,
                ),
            rejectReason = null,
        )
    }

    private fun constrainMaskForOcclusionRender(
        maskValues: FloatArray,
        width: Int,
        height: Int,
        detectionRect: DanmakuNormalizedRect,
        previousRect: DanmakuNormalizedRect?,
    ): FloatArray {
        val supportMask = FloatArray(maskValues.size)
        for (index in maskValues.indices) {
            supportMask[index] =
                if (maskValues[index] >= DANMAKU_AI_RENDER_MASK_SUPPORT_THRESHOLD) {
                    1f
                } else {
                    0f
                }
        }
        val closed =
            if (DANMAKU_AI_RENDER_MASK_CLOSING_RADIUS > 0) {
                FloatArray(supportMask.size).also { output ->
                    closeBinaryMask(
                        input = supportMask,
                        output = output,
                        width = width,
                        height = height,
                        radius = DANMAKU_AI_RENDER_MASK_CLOSING_RADIUS,
                    )
                }
            } else {
                supportMask
            }
        val filteredBinary =
            keepDetectionAlignedComponents(
                maskValues = closed,
                width = width,
                height = height,
                detectionRect = detectionRect,
                previousRect = previousRect,
            )
        return FloatArray(maskValues.size).also { output ->
            for (index in maskValues.indices) {
                output[index] =
                    if (filteredBinary[index] > 0.5f) {
                        max(maskValues[index], DANMAKU_AI_RENDER_MASK_SUPPORT_THRESHOLD)
                    } else {
                        0f
                    }
            }
        }
    }

    private fun prepareMaskForOcclusionRender(
        maskValues: FloatArray,
        width: Int,
        height: Int,
    ): FloatArray {
        val expanded =
            if (DANMAKU_AI_RENDER_MASK_EXPAND_RADIUS > 0) {
                FloatArray(maskValues.size).also { output ->
                    expandSoftMask(
                        input = maskValues,
                        output = output,
                        width = width,
                        height = height,
                        radius = DANMAKU_AI_RENDER_MASK_EXPAND_RADIUS,
                    )
                }
            } else {
                maskValues.copyOf()
            }
        val softened =
            FloatArray(expanded.size).also { output ->
                blurMask(expanded, output, width, height)
            }
        return FloatArray(softened.size).also { output ->
            for (index in softened.indices) {
                val value = softened[index].coerceIn(0f, 1f)
                if (value <= DANMAKU_AI_RENDER_MASK_MIN_VISIBLE_ALPHA) {
                    output[index] = 0f
                    continue
                }
                val boosted =
                    value
                        .toDouble()
                        .pow(DANMAKU_AI_RENDER_MASK_ALPHA_GAMMA.toDouble())
                        .toFloat()
                        .coerceIn(0f, 1f)
                output[index] =
                    ((boosted - DANMAKU_AI_RENDER_MASK_MIN_VISIBLE_ALPHA) /
                        (1f - DANMAKU_AI_RENDER_MASK_MIN_VISIBLE_ALPHA))
                        .coerceIn(0f, 1f)
            }
        }
    }

    private fun buildThresholdMask(
        values: FloatArray,
        threshold: Float,
    ): FloatArray {
        val output = FloatArray(values.size)
        for (index in values.indices) {
            output[index] =
                if (values[index] >= threshold) {
                    1f
                } else {
                    0f
                }
        }
        return output
    }

    private fun growMaskFromSeedWithinCandidate(
        seedMask: FloatArray,
        candidateMask: FloatArray,
        width: Int,
        height: Int,
    ): FloatArray {
        val totalPixels = width * height
        val output = FloatArray(totalPixels)
        val visited = BooleanArray(totalPixels)
        val queue = IntArray(totalPixels)
        var head = 0
        var tail = 0
        for (index in 0 until totalPixels) {
            if (seedMask[index] <= 0.5f || candidateMask[index] <= 0.5f) {
                continue
            }
            visited[index] = true
            output[index] = 1f
            queue[tail++] = index
        }
        while (head < tail) {
            val current = queue[head++]
            val x = current % width
            val y = current / width
            val neighbors =
                intArrayOf(
                    if (x > 0) current - 1 else -1,
                    if (x < width - 1) current + 1 else -1,
                    if (y > 0) current - width else -1,
                    if (y < height - 1) current + width else -1,
                    if (x > 0 && y > 0) current - width - 1 else -1,
                    if (x < width - 1 && y > 0) current - width + 1 else -1,
                    if (x > 0 && y < height - 1) current + width - 1 else -1,
                    if (x < width - 1 && y < height - 1) current + width + 1 else -1,
                )
            for (neighbor in neighbors) {
                if (neighbor < 0 || visited[neighbor] || candidateMask[neighbor] <= 0.5f) {
                    continue
                }
                visited[neighbor] = true
                output[neighbor] = 1f
                queue[tail++] = neighbor
            }
        }
        return output
    }

    private fun applyPrimaryMask(
        refinedMask: FloatArray,
        componentMask: FloatArray,
    ): FloatArray {
        val output = FloatArray(refinedMask.size)
        for (index in refinedMask.indices) {
            output[index] =
                if (componentMask[index] > 0f) {
                    refinedMask[index]
                } else {
                    0f
                }
        }
        return output
    }

    private fun foregroundRatio(
        values: FloatArray,
        threshold: Float,
    ): Float {
        if (values.isEmpty()) {
            return 0f
        }
        var count = 0
        for (value in values) {
            if (value >= threshold) {
                count += 1
            }
        }
        return count.toFloat() / values.size.toFloat()
    }

    private fun effectiveDanmakuMaskCoverageRatio(
        width: Int,
        height: Int,
    ): Float {
        val displayArea = config.displayAreaRatio.coerceIn(0.1f, 1.0f)
        val captureArea = config.sampleAreaRatio.coerceIn(0.1f, 1.0f)
        return minOf(displayArea, captureArea).coerceIn(0.1f, 1.0f)
    }

    private fun renderMaskAreaRatio(
        maskValues: FloatArray,
        width: Int,
        height: Int,
        coverageRatio: Float = effectiveDanmakuMaskCoverageRatio(width, height),
    ): Float {
        if (maskValues.isEmpty() || width <= 0 || height <= 0) {
            return 0f
        }
        val effectiveHeight =
            max(1, (height.toFloat() * coverageRatio.coerceIn(0.1f, 1.0f)).roundToInt())
                .coerceAtMost(height)
        var count = 0
        for (y in 0 until effectiveHeight) {
            val row = y * width
            for (x in 0 until width) {
                if (maskValues[row + x] >= DANMAKU_AI_RENDER_MASK_SUPPORT_THRESHOLD) {
                    count += 1
                }
            }
        }
        return count.toFloat() / (width * height).toFloat()
    }

    private fun mergeDropReasons(vararg reasons: String?): String? {
        val tokens = linkedSetOf<String>()
        for (reason in reasons) {
            reason
                ?.split(',')
                ?.map { it.trim() }
                ?.filter { it.isNotEmpty() }
                ?.forEach(tokens::add)
        }
        return tokens.joinToString(",").takeIf { tokens.isNotEmpty() }
    }

    private fun normalizeDropReasonToken(reason: String?): String =
        reason
            ?.lowercase(Locale.US)
            ?.map { character ->
                if (character.isLetterOrDigit()) {
                    character
                } else {
                    '_'
                }
            }?.joinToString("")
            ?.trim('_')
            ?.takeIf { it.isNotEmpty() }
            ?: "unknown"

    private fun buildSmallMultiShapeDropReason(
        targetIndex: Int,
        reason: String?,
    ): String {
        val targetLabel =
            if (targetIndex <= 0) {
                "primary"
            } else {
                "secondary"
            }
        return "shape_${targetLabel}_${normalizeDropReasonToken(reason)}"
    }

    private fun unionNormalizedRects(rects: List<DanmakuNormalizedRect>): DanmakuNormalizedRect? {
        if (rects.isEmpty()) {
            return null
        }
        val left = rects.minOf { it.left }
        val top = rects.minOf { it.top }
        val right = rects.maxOf { it.right }
        val bottom = rects.maxOf { it.bottom }
        return DanmakuNormalizedRect(
            x = left.coerceIn(0f, 1f),
            y = top.coerceIn(0f, 1f),
            width = (right - left).coerceIn(0f, 1f),
            height = (bottom - top).coerceIn(0f, 1f),
        )
    }

    private fun mergeSmallMultiMaskCandidates(
        keptCandidates: List<DanmakuSmallMultiMaskCandidate>,
    ): DanmakuSmallMultiSegmentationResult {
        if (keptCandidates.isEmpty()) {
            return DanmakuSmallMultiSegmentationResult(
                maskResult = null,
                latencyMs = 0L,
                keptCount = 0,
                unionAreaRatio = 0f,
                dropReason = null,
                roiRect = null,
                inputWidth = 0,
                inputHeight = 0,
                maskAreaByTrackId = emptyMap(),
            )
        }
        val keptMaskResults = keptCandidates.map { it.maskResult }
        val baseMask = keptMaskResults.first()
        val mergedMaskValues = FloatArray(baseMask.maskValues.size)
        for (candidate in keptMaskResults) {
            val values = candidate.maskValues
            for (index in mergedMaskValues.indices) {
                mergedMaskValues[index] = maxOf(mergedMaskValues[index], values[index])
            }
        }
        val unionAreaRatio =
            renderMaskAreaRatio(
                maskValues = mergedMaskValues,
                width = baseMask.maskWidth,
                height = baseMask.maskHeight,
            )
        return DanmakuSmallMultiSegmentationResult(
            maskResult =
                DanmakuMaskResult(
                    maskValues = mergedMaskValues,
                    maskWidth = baseMask.maskWidth,
                    maskHeight = baseMask.maskHeight,
                    normalizedRect = unionNormalizedRects(keptMaskResults.mapNotNull { it.normalizedRect }),
                    occlusionMode = DanmakuOcclusionMode.MASK,
                ),
            latencyMs = keptCandidates.sumOf { it.attempt.latencyMs },
            keptCount = keptCandidates.size,
            unionAreaRatio = unionAreaRatio,
            dropReason = null,
            roiRect = unionNormalizedRects(keptCandidates.map { it.attempt.roiRect }),
            inputWidth = keptCandidates.first().attempt.inputWidth,
            inputHeight = keptCandidates.first().attempt.inputHeight,
            maskAreaByTrackId = keptCandidates.associate { it.trackId to it.areaRatio },
        )
    }

    private fun runSmallMultiSegmentation(
        bitmap: Bitmap,
        sampleId: Long,
        runtime: DanmakuSegmentationRuntime,
        targets: List<DanmakuSmallMultiTrackTarget>,
        sampleAreaRatio: Float,
        thresholds: DanmakuSmallMultiThresholds = currentSmallMultiThresholds(),
    ): DanmakuSmallMultiSegmentationResult {
        val segmentedCandidates = mutableListOf<DanmakuSmallMultiMaskCandidate>()
        val droppedReasons = linkedSetOf<String>()
        var totalLatencyMs = 0L
        val multiInputWidth = effectiveSmallMultiInputWidth()
        for ((targetIndex, target) in targets.take(DANMAKU_AI_SMALL_MULTI_MAX_PEOPLE).withIndex()) {
            val relaxValidationForSecondary = targetIndex > 0
            val attempt =
                runSegmentationForRect(
                    bitmap = bitmap,
                    sampleId = sampleId,
                    runtime = runtime,
                    targetRect = target.rect,
                    roiMode = DanmakuSegmentationRoiMode.DETECT,
                    sampleAreaRatio = sampleAreaRatio,
                    allowTemporalSmoothing = false,
                    motionCompensation = null,
                    motionCompensationAttempted = false,
                    inputWidthOverride = multiInputWidth,
                    relaxValidationForSecondaryMultiTarget = relaxValidationForSecondary,
                    rejectLogContext =
                        if (relaxValidationForSecondary) {
                            "multi_secondary_${targetIndex + 1}"
                        } else {
                            "multi_primary_${targetIndex + 1}"
                        },
                )
            totalLatencyMs += attempt.latencyMs
            val maskResult = attempt.extraction?.maskResult
            if (maskResult == null) {
                droppedReasons += buildSmallMultiShapeDropReason(targetIndex, attempt.rejectReason)
                continue
            }
            val areaRatio =
                renderMaskAreaRatio(
                    maskValues = maskResult.maskValues,
                    width = maskResult.maskWidth,
                    height = maskResult.maskHeight,
                )
            val maxMaskAreaRatio =
                if (relaxValidationForSecondary) {
                    thresholds.singleMaskMaxAreaRatio * DANMAKU_AI_SMALL_MULTI_SECONDARY_MASK_MAX_AREA_MULTIPLIER
                } else {
                    thresholds.singleMaskMaxAreaRatio
                }
            if (areaRatio > maxMaskAreaRatio) {
                droppedReasons += buildSmallMultiShapeDropReason(targetIndex, "area_limit")
                continue
            }
            segmentedCandidates +=
                DanmakuSmallMultiMaskCandidate(
                    trackId = target.trackId,
                    rect = target.rect,
                    attempt = attempt,
                    maskResult = maskResult,
                    priorityScore =
                        scorePrimaryDetection(
                            DanmakuPrimaryDetection(
                                rect = target.rect,
                                score = target.score,
                            ),
                        ),
                    areaRatio = areaRatio,
                )
        }
        if (segmentedCandidates.isEmpty()) {
            return DanmakuSmallMultiSegmentationResult(
                maskResult = null,
                latencyMs = totalLatencyMs,
                keptCount = 0,
                unionAreaRatio = 0f,
                dropReason = mergeDropReasons(droppedReasons.joinToString(",")),
                roiRect = null,
                inputWidth = 0,
                inputHeight = 0,
                maskAreaByTrackId = emptyMap(),
            )
        }
        val keptCandidates =
            segmentedCandidates
                .sortedByDescending { it.priorityScore }
                .toMutableList()
        var merged = mergeSmallMultiMaskCandidates(keptCandidates)
        while (keptCandidates.isNotEmpty() && merged.unionAreaRatio > thresholds.unionMaxAreaRatio) {
            droppedReasons += "area_budget"
            keptCandidates.removeLast()
            merged = mergeSmallMultiMaskCandidates(keptCandidates)
        }
        if (keptCandidates.isEmpty() || merged.maskResult == null) {
            return DanmakuSmallMultiSegmentationResult(
                maskResult = null,
                latencyMs = totalLatencyMs,
                keptCount = 0,
                unionAreaRatio = 0f,
                dropReason = mergeDropReasons(droppedReasons.joinToString(",")),
                roiRect = null,
                inputWidth = 0,
                inputHeight = 0,
                maskAreaByTrackId = emptyMap(),
            )
        }
        return merged.copy(
            latencyMs = totalLatencyMs,
            dropReason = mergeDropReasons(droppedReasons.joinToString(",")),
        )
    }

    private fun applySmallMultiMaskAreas(
        tracks: List<DanmakuSmallMultiTrack>,
        maskAreaByTrackId: Map<Int, Float>,
    ): List<DanmakuSmallMultiTrack> {
        if (tracks.isEmpty() || maskAreaByTrackId.isEmpty()) {
            return tracks
        }
        return tracks.map { track ->
            track.copy(
                lastMaskAreaRatio = maskAreaByTrackId[track.trackId] ?: track.lastMaskAreaRatio,
            )
        }
    }

    private fun mapRectFromRoiToFullFrame(
        rectInRoi: DanmakuNormalizedRect,
        roiRect: DanmakuNormalizedRect,
    ): DanmakuNormalizedRect {
        return DanmakuNormalizedRect(
            x = (roiRect.x + (rectInRoi.x * roiRect.width)).coerceIn(0f, 1f),
            y = (roiRect.y + (rectInRoi.y * roiRect.height)).coerceIn(0f, 1f),
            width = (rectInRoi.width * roiRect.width).coerceIn(0f, 1f),
            height = (rectInRoi.height * roiRect.height).coerceIn(0f, 1f),
        )
    }

    private fun cropMaskToContentRect(
        maskValues: FloatArray,
        maskWidth: Int,
        maskHeight: Int,
        contentRect: DanmakuNormalizedRect,
    ): DanmakuMaskPlane {
        val left = (contentRect.x * maskWidth).roundToInt().coerceIn(0, maskWidth - 1)
        val top = (contentRect.y * maskHeight).roundToInt().coerceIn(0, maskHeight - 1)
        val right =
            ((contentRect.x + contentRect.width) * maskWidth)
                .roundToInt()
                .coerceIn(left + 1, maskWidth)
        val bottom =
            ((contentRect.y + contentRect.height) * maskHeight)
                .roundToInt()
                .coerceIn(top + 1, maskHeight)
        val croppedWidth = (right - left).coerceAtLeast(1)
        val croppedHeight = (bottom - top).coerceAtLeast(1)
        if (left == 0 && top == 0 && croppedWidth == maskWidth && croppedHeight == maskHeight) {
            return DanmakuMaskPlane(
                values = maskValues,
                width = maskWidth,
                height = maskHeight,
            )
        }
        val croppedValues = FloatArray(croppedWidth * croppedHeight)
        for (y in 0 until croppedHeight) {
            System.arraycopy(
                maskValues,
                ((top + y) * maskWidth) + left,
                croppedValues,
                y * croppedWidth,
                croppedWidth,
            )
        }
        return DanmakuMaskPlane(
            values = croppedValues,
            width = croppedWidth,
            height = croppedHeight,
        )
    }

    private fun evaluateRoiMaskReasonableness(
        detectionRect: DanmakuNormalizedRect,
        mappedRect: DanmakuNormalizedRect,
        maskValues: FloatArray,
    ): RoiMaskValidationMetrics {
        val coverage =
            if (detectionRect.area() > 0f) {
                mappedRect.area() / detectionRect.area()
            } else {
                0f
            }
        val iou = mappedRect.iou(detectionRect)
        val finalForegroundRatio = foregroundRatio(maskValues, 1f)
        return RoiMaskValidationMetrics(
            coverage = coverage,
            iou = iou,
            foregroundRatio = finalForegroundRatio,
        )
    }

    private fun logRoiMaskReject(
        sampleId: Long,
        reason: String,
        detectionRect: DanmakuNormalizedRect,
        roiRect: DanmakuNormalizedRect,
        mappedRect: DanmakuNormalizedRect? = null,
        coverage: Float? = null,
        iou: Float? = null,
        foregroundRatio: Float? = null,
        context: String? = null,
    ) {
        val metrics =
            buildList {
                coverage?.let { add("coverage=${"%.3f".format(Locale.US, it)}") }
                iou?.let { add("iou=${"%.3f".format(Locale.US, it)}") }
                foregroundRatio?.let { add("fg=${"%.4f".format(Locale.US, it)}") }
            }.joinToString(" ")
        Log.d(
            DANMAKU_AI_TAG,
            buildString {
                append("sample=")
                append(sampleId)
                context?.let {
                    append(" context=")
                    append(it)
                }
                append(" roi_reject=")
                append(reason)
                append(" detection=")
                append(detectionRect)
                append(" roi=")
                append(roiRect)
                mappedRect?.let {
                    append(" mapped=")
                    append(it)
                }
                if (metrics.isNotEmpty()) {
                    append(' ')
                    append(metrics)
                }
            },
        )
    }

    private fun embedRoiMaskInFullFrame(
        roiMaskValues: FloatArray,
        roiMaskWidth: Int,
        roiMaskHeight: Int,
        fullWidth: Int,
        fullHeight: Int,
        roiRect: DanmakuNormalizedRect,
    ): FloatArray {
        val fullMask = FloatArray(fullWidth * fullHeight)
        val left = (roiRect.x * fullWidth).toInt().coerceIn(0, fullWidth - 1)
        val top = (roiRect.y * fullHeight).toInt().coerceIn(0, fullHeight - 1)
        val right =
            ((roiRect.x + roiRect.width) * fullWidth)
                .roundToInt()
                .coerceIn(left + 1, fullWidth)
        val bottom =
            ((roiRect.y + roiRect.height) * fullHeight)
                .roundToInt()
                .coerceIn(top + 1, fullHeight)
        val targetWidth = (right - left).coerceAtLeast(1)
        val targetHeight = (bottom - top).coerceAtLeast(1)
        for (y in 0 until targetHeight) {
            val targetRow = (top + y) * fullWidth
            for (x in 0 until targetWidth) {
                val sourceX =
                    (((x + 0.5f) * roiMaskWidth.toFloat()) / targetWidth.toFloat()) - 0.5f
                val sourceY =
                    (((y + 0.5f) * roiMaskHeight.toFloat()) / targetHeight.toFloat()) - 0.5f
                fullMask[targetRow + left + x] =
                    bilinearSampleMask(
                        values = roiMaskValues,
                        width = roiMaskWidth,
                        height = roiMaskHeight,
                        x = sourceX,
                        y = sourceY,
                    )
            }
        }
        return fullMask
    }

    private fun extractMaskResult(
        outputValues: FloatArray,
        outputWidth: Int,
        outputHeight: Int,
        allowTemporalSmoothing: Boolean,
        motionCompensation: DanmakuMotionCompensation?,
        motionCompensationAttempted: Boolean,
    ): DanmakuMaskExtraction? {
        val width = outputWidth
        val height = outputHeight
        val total = width * height

        val dilated = FloatArray(total)
        dilateMask(outputValues, dilated, width, height)
        val blurred = FloatArray(total)
        blurMask(dilated, blurred, width, height)
        val normalized = normalizeMask(blurred)
        val baseComponent = extractPrimaryComponent(normalized, width, height) ?: return null
        if (!isLikelyForegroundSubject(baseComponent)) {
            return null
        }
        val baseRect = baseComponent.rect
        val appliedMotionCompensation =
            motionCompensation?.takeIf {
                shouldApplyMotionCompensation(
                    nextRect = baseRect,
                    motionCompensation = it,
                )
            }
        val compensatedPreviousMask =
            buildCompensatedPreviousMask(appliedMotionCompensation, width, height)
        val compensatedPreviousRect = buildCompensatedPreviousRect(appliedMotionCompensation)
        val temporalSmoothingMinIou =
            if (motionCompensationAttempted && appliedMotionCompensation == null) {
                DANMAKU_AI_MOTION_MISS_TEMPORAL_FALLBACK_MIN_IOU
            } else {
                DANMAKU_AI_TEMPORAL_SMOOTHING_MIN_IOU
            }
        val shouldSmoothTemporally =
            allowTemporalSmoothing &&
                shouldUseTemporalSmoothing(
                    nextRect = baseRect,
                    previousRectOverride = compensatedPreviousRect,
                    minIou = temporalSmoothingMinIou,
                )
        val smoothed =
            if (shouldSmoothTemporally) {
                smoothMaskOverTime(
                    nextMask = normalized,
                    width = width,
                    height = height,
                    previousMaskOverride = compensatedPreviousMask,
                )
            } else {
                normalized.copyOf()
            }
        val refined = refineMaskAlpha(smoothed)
        if (shouldRejectAmbiguousForeground(refined, width, height)) {
            return null
        }
        val hardened = hardenMaskForOcclusion(refined, width, height)
        val primaryMaskComponent =
            retainPrimaryMaskComponent(hardened, width, height) ?: return null
        if (shouldRejectWeirdPrimaryMask(primaryMaskComponent.maskValues, width, height)) {
            return null
        }
        val helperComponent =
            primaryMaskComponent.component.takeIf(::isLikelyForegroundSubject)
                ?: extractPrimaryComponent(refined, width, height)
                ?: baseComponent
        val helperRect =
            if (isLikelyForegroundSubject(helperComponent)) {
                helperComponent.rect
            } else {
                baseRect
            }
        val finalRect =
            if (shouldSmoothTemporally) {
                smoothRectOverTime(
                    nextRect = helperRect,
                    previousRectOverride = compensatedPreviousRect,
                )
            } else {
                helperRect
            }
        val maskScaleApplied = appliedMotionCompensation?.let { shouldApplyMaskScaleCompensation(it.scale) } == true
        val maskScaleValue = if (maskScaleApplied) appliedMotionCompensation?.scale ?: 1f else 1f
        return DanmakuMaskExtraction(
            maskResult =
                DanmakuMaskResult(
                    maskValues = primaryMaskComponent.maskValues,
                    maskWidth = width,
                    maskHeight = height,
                    normalizedRect = finalRect,
                ),
            appliedMotionCompensation = appliedMotionCompensation,
            maskScaleApplied = maskScaleApplied,
            maskScaleValue = maskScaleValue,
        )
    }

    private fun dilateMask(
        input: FloatArray,
        output: FloatArray,
        width: Int,
        height: Int,
    ) {
        for (y in 0 until height) {
            for (x in 0 until width) {
                var value = 0f
                val top = max(0, y - 1)
                val bottom = minOf(height - 1, y + 1)
                val left = max(0, x - 1)
                val right = minOf(width - 1, x + 1)
                for (sampleY in top..bottom) {
                    for (sampleX in left..right) {
                        val sample = input[(sampleY * width) + sampleX]
                        if (sample > value) {
                            value = sample
                        }
                    }
                }
                output[(y * width) + x] = value
            }
        }
    }

    private fun expandSoftMask(
        input: FloatArray,
        output: FloatArray,
        width: Int,
        height: Int,
        radius: Int,
    ) {
        val safeRadius = radius.coerceAtLeast(0)
        if (safeRadius == 0) {
            input.copyInto(output)
            return
        }
        for (y in 0 until height) {
            val top = max(0, y - safeRadius)
            val bottom = minOf(height - 1, y + safeRadius)
            for (x in 0 until width) {
                val left = max(0, x - safeRadius)
                val right = minOf(width - 1, x + safeRadius)
                var value = 0f
                for (sampleY in top..bottom) {
                    for (sampleX in left..right) {
                        value = max(value, input[(sampleY * width) + sampleX])
                    }
                }
                output[(y * width) + x] = value
            }
        }
    }

    private fun blurMask(
        input: FloatArray,
        output: FloatArray,
        width: Int,
        height: Int,
    ) {
        for (y in 0 until height) {
            for (x in 0 until width) {
                var total = 0f
                var samples = 0
                val top = max(0, y - 1)
                val bottom = minOf(height - 1, y + 1)
                val left = max(0, x - 1)
                val right = minOf(width - 1, x + 1)
                for (sampleY in top..bottom) {
                    for (sampleX in left..right) {
                        total += input[(sampleY * width) + sampleX]
                        samples += 1
                    }
                }
                output[(y * width) + x] = total / samples.toFloat()
            }
        }
    }

    private fun normalizeMask(values: FloatArray): FloatArray {
        val normalized = FloatArray(values.size)
        var foregroundPixels = 0
        for (index in values.indices) {
            val value =
                ((values[index] - DANMAKU_AI_MASK_THRESHOLD) / (1f - DANMAKU_AI_MASK_THRESHOLD))
                    .coerceIn(0f, 1f)
            normalized[index] = value
            if (value >= DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                foregroundPixels += 1
            }
        }
        val minForegroundPixels =
            max(32, (values.size * DANMAKU_AI_MIN_FOREGROUND_RATIO).toInt())
        return if (foregroundPixels >= minForegroundPixels) normalized else FloatArray(values.size)
    }

    private fun smoothMaskOverTime(
        nextMask: FloatArray,
        width: Int,
        height: Int,
        previousMaskOverride: FloatArray? = null,
    ): FloatArray {
        val previousMask = previousMaskOverride ?: latestMaskValues
        if (previousMask == null || latestMaskWidth != width || latestMaskHeight != height) {
            return nextMask.copyOf()
        }
        val smoothed = FloatArray(nextMask.size)
        val previousWeight = 1f - DANMAKU_AI_MASK_SMOOTHING_ALPHA
        for (index in nextMask.indices) {
            smoothed[index] =
                ((previousMask[index] * previousWeight) +
                    (nextMask[index] * DANMAKU_AI_MASK_SMOOTHING_ALPHA))
                    .coerceIn(0f, 1f)
        }
        return smoothed
    }

    private fun shouldUseTemporalSmoothing(
        nextRect: DanmakuNormalizedRect,
        previousRectOverride: DanmakuNormalizedRect? = null,
        minIou: Float = DANMAKU_AI_TEMPORAL_SMOOTHING_MIN_IOU,
    ): Boolean {
        val previousRect = previousRectOverride ?: trackingRectOrDisplayRect() ?: return false
        return previousRect.iou(nextRect) >= minIou
    }

    private fun smoothRectOverTime(
        nextRect: DanmakuNormalizedRect,
        previousRectOverride: DanmakuNormalizedRect? = null,
    ): DanmakuNormalizedRect {
        val previousRect = previousRectOverride ?: trackingRectOrDisplayRect() ?: return nextRect
        return if (previousRect.iou(nextRect) >= DANMAKU_AI_TEMPORAL_SMOOTHING_MIN_IOU) {
            previousRect.lerp(nextRect, DANMAKU_AI_RECT_SMOOTHING_ALPHA)
        } else {
            nextRect
        }
    }

    private fun analyzeFrameContinuity(bitmap: Bitmap): DanmakuFrameContinuity {
        val sampleWidth = DANMAKU_AI_SCENE_CUT_SAMPLE_WIDTH.coerceAtMost(bitmap.width)
        val sampleHeight = DANMAKU_AI_SCENE_CUT_SAMPLE_HEIGHT.coerceAtMost(bitmap.height)
        val signature = sampleBitmapLuma(bitmap, sampleWidth, sampleHeight)
        val previous = previousFrameLumaSignature
        if (previous == null || previous.size != signature.size) {
            return DanmakuFrameContinuity(sceneCut = false, signature = signature)
        }
        var totalDelta = 0L
        var changedPixels = 0
        for (i in signature.indices) {
            val delta = kotlin.math.abs(signature[i] - previous[i])
            totalDelta += delta.toLong()
            if (delta >= DANMAKU_AI_SCENE_CUT_CHANGED_PIXEL_DELTA) {
                changedPixels += 1
            }
        }
        val averageDelta = totalDelta.toDouble() / signature.size.toDouble()
        val changedRatio = changedPixels.toDouble() / signature.size.toDouble()
        return DanmakuFrameContinuity(
            sceneCut =
                averageDelta >= DANMAKU_AI_SCENE_CUT_AVERAGE_DELTA_THRESHOLD ||
                    changedRatio >= DANMAKU_AI_SCENE_CUT_CHANGED_RATIO_THRESHOLD,
            signature = signature,
        )
    }

    private fun sampleBitmapLuma(
        bitmap: Bitmap,
        sampleWidth: Int,
        sampleHeight: Int,
    ): IntArray {
        val signature = IntArray(sampleWidth * sampleHeight)
        val stepX = bitmap.width.toFloat() / sampleWidth.toFloat()
        val stepY = bitmap.height.toFloat() / sampleHeight.toFloat()
        var index = 0
        for (sampleY in 0 until sampleHeight) {
            val bitmapY =
                ((sampleY + 0.5f) * stepY).toInt().coerceIn(0, bitmap.height - 1)
            for (sampleX in 0 until sampleWidth) {
                val bitmapX =
                    ((sampleX + 0.5f) * stepX).toInt().coerceIn(0, bitmap.width - 1)
                val color = bitmap.getPixel(bitmapX, bitmapY)
                val red = Color.red(color)
                val green = Color.green(color)
                val blue = Color.blue(color)
                signature[index++] = ((red * 77) + (green * 150) + (blue * 29)) shr 8
            }
        }
        return signature
    }

    private fun predictTrackedTransform(
        sampleWidth: Int,
        sampleHeight: Int,
    ): DanmakuPredictedTransform? {
        if (sceneCutRecoveryActive || consecutiveEmptyFrames > 0) {
            return null
        }
        val latest = latestMotionReferenceFrame ?: return null
        val previous = previousMotionReferenceFrame ?: return null
        val latestArea = latest.normalizedRect.area()
        val previousArea = previous.normalizedRect.area()
        if (
            latestArea < DANMAKU_AI_MOTION_MIN_RECT_AREA ||
                previousArea < DANMAKU_AI_MOTION_MIN_RECT_AREA
        ) {
            return null
        }
        val deltaMs = (latest.timestampMs - previous.timestampMs).coerceAtLeast(1L)
        if (deltaMs > DANMAKU_AI_MOTION_PREDICTION_MAX_GAP_MS) {
            return null
        }
        val elapsedSinceLatestMs =
            (SystemClock.uptimeMillis() - latest.timestampMs)
                .coerceAtLeast(0L)
                .coerceAtMost(max(currentSampleIntervalMs(), deltaMs))
        if (elapsedSinceLatestMs <= 0L) {
            return null
        }
        val rawDxNormalized =
            ((latest.normalizedRect.centerX - previous.normalizedRect.centerX) / deltaMs.toFloat()) *
                elapsedSinceLatestMs.toFloat() * DANMAKU_AI_MOTION_PREDICTION_DAMPING
        val rawDyNormalized =
            ((latest.normalizedRect.centerY - previous.normalizedRect.centerY) / deltaMs.toFloat()) *
                elapsedSinceLatestMs.toFloat() * DANMAKU_AI_MOTION_PREDICTION_DAMPING
        val dxNormalized =
            rawDxNormalized.coerceIn(
                -DANMAKU_AI_MOTION_PREDICTION_MAX_DX_NORMALIZED,
                DANMAKU_AI_MOTION_PREDICTION_MAX_DX_NORMALIZED,
            )
        val dyNormalized =
            rawDyNormalized.coerceIn(
                -DANMAKU_AI_MOTION_PREDICTION_MAX_DY_NORMALIZED,
                DANMAKU_AI_MOTION_PREDICTION_MAX_DY_NORMALIZED,
            )
        val dxSamplePx = (dxNormalized * sampleWidth.toFloat()).roundToInt()
        val dySamplePx = (dyNormalized * sampleHeight.toFloat()).roundToInt()
        val areaRatio = (latestArea / previousArea).coerceAtLeast(0.01f)
        val predictedLogAreaRatio =
            ((ln(areaRatio.toDouble()) / deltaMs.toDouble()) *
                elapsedSinceLatestMs.toDouble() *
                DANMAKU_AI_MOTION_PREDICTION_DAMPING.toDouble())
        val scale =
            exp(predictedLogAreaRatio / 2.0)
                .toFloat()
                .coerceIn(
                    DANMAKU_AI_MOTION_PREDICTION_MIN_SCALE,
                    DANMAKU_AI_MOTION_PREDICTION_MAX_SCALE,
                )
        val predictedAreaRatio = (scale * scale).coerceAtLeast(0f)
        return DanmakuPredictedTransform(
            dxNormalized = dxNormalized,
            dyNormalized = dyNormalized,
            dxSamplePx = dxSamplePx,
            dySamplePx = dySamplePx,
            scale = scale,
            predictedAreaRatio = predictedAreaRatio,
        )
    }

    private fun buildPredictedTrackedRect(
        predictedTransform: DanmakuPredictedTransform?,
    ): DanmakuNormalizedRect? {
        val previousRect = trackingRectOrDisplayRect() ?: return null
        val transform = predictedTransform ?: return null
        return transformRect(
            rect = previousRect,
            dxNormalized = transform.dxNormalized,
            dyNormalized = transform.dyNormalized,
            scale = transform.scale,
        )
    }

    private fun estimateMotionCompensation(
        currentLumaSamples: IntArray,
        sampleWidth: Int,
        sampleHeight: Int,
        maskWidth: Int,
        maskHeight: Int,
    ): DanmakuMotionCompensation? {
        if (sceneCutRecoveryActive) {
            return null
        }
        val reference = latestMotionReferenceFrame ?: return null
        val previousRect = trackingRectOrDisplayRect() ?: return null
        val previousMask = latestMaskValues ?: return null
        if (previousMask.isEmpty() || previousRect.area() < DANMAKU_AI_MOTION_MIN_RECT_AREA) {
            return null
        }
        if (
            reference.sampleWidth != sampleWidth ||
                reference.sampleHeight != sampleHeight ||
                latestMaskWidth != maskWidth ||
                latestMaskHeight != maskHeight
        ) {
            return null
        }
        val predictedTransform = predictTrackedTransform(sampleWidth, sampleHeight)
        val roi = resolveMotionRoi(reference.normalizedRect, sampleWidth, sampleHeight) ?: return null
        val searchCenterDx = predictedTransform?.dxSamplePx ?: 0
        val searchCenterDy = predictedTransform?.dySamplePx ?: 0
        val maxTotalShiftX =
            max(1, (sampleWidth * DANMAKU_AI_MOTION_MAX_TRANSLATION_RATIO).roundToInt())
        val maxTotalShiftY =
            max(1, (sampleHeight * DANMAKU_AI_MOTION_MAX_TRANSLATION_RATIO).roundToInt())
        val maxShiftX =
            minOf(
                DANMAKU_AI_MOTION_SEARCH_RADIUS_PX,
                maxTotalShiftX,
            )
        val maxShiftY =
            minOf(
                DANMAKU_AI_MOTION_SEARCH_RADIUS_PX,
                maxTotalShiftY,
            )
        var bestDx = 0
        var bestDy = 0
        var bestScore = Double.MAX_VALUE
        val searchStartDy = max(-maxTotalShiftY, searchCenterDy - maxShiftY)
        val searchEndDy = minOf(maxTotalShiftY, searchCenterDy + maxShiftY)
        val searchStartDx = max(-maxTotalShiftX, searchCenterDx - maxShiftX)
        val searchEndDx = minOf(maxTotalShiftX, searchCenterDx + maxShiftX)
        for (dy in searchStartDy..searchEndDy) {
            for (dx in searchStartDx..searchEndDx) {
                var totalDelta = 0L
                var overlapSamples = 0
                for (y in roi.top..roi.bottom) {
                    val shiftedY = y + dy
                    if (shiftedY !in 0 until sampleHeight) {
                        continue
                    }
                    val previousRow = y * sampleWidth
                    val currentRow = shiftedY * sampleWidth
                    for (x in roi.left..roi.right) {
                        val shiftedX = x + dx
                        if (shiftedX !in 0 until sampleWidth) {
                            continue
                        }
                        totalDelta +=
                            abs(reference.lumaSamples[previousRow + x] - currentLumaSamples[currentRow + shiftedX]).toLong()
                        overlapSamples += 1
                    }
                }
                if (overlapSamples < DANMAKU_AI_MOTION_MIN_OVERLAP_SAMPLES) {
                    continue
                }
                val averageDelta = totalDelta.toDouble() / overlapSamples.toDouble()
                if (averageDelta < bestScore) {
                    bestScore = averageDelta
                    bestDx = dx
                    bestDy = dy
                }
            }
        }
        if (bestScore == Double.MAX_VALUE || bestScore > DANMAKU_AI_MOTION_MAX_AVERAGE_DELTA) {
            return null
        }
        val dxMaskPx =
            ((bestDx.toFloat() / sampleWidth.toFloat()) * maskWidth.toFloat()).roundToInt()
        val dyMaskPx =
            ((bestDy.toFloat() / sampleHeight.toFloat()) * maskHeight.toFloat()).roundToInt()
        return DanmakuMotionCompensation(
            dxSamplePx = bestDx,
            dySamplePx = bestDy,
            dxMaskPx = dxMaskPx,
            dyMaskPx = dyMaskPx,
            dxNormalized = dxMaskPx.toFloat() / maskWidth.toFloat(),
            dyNormalized = dyMaskPx.toFloat() / maskHeight.toFloat(),
            scale = predictedTransform?.scale ?: 1f,
            score = bestScore,
        )
    }

    private fun shouldApplyMotionCompensation(
        nextRect: DanmakuNormalizedRect,
        motionCompensation: DanmakuMotionCompensation,
    ): Boolean {
        if (sceneCutRecoveryActive) {
            return false
        }
        if (consecutiveCompensatedFrames >= DANMAKU_AI_MOTION_MAX_CONSECUTIVE_COMPENSATED_FRAMES) {
            return false
        }
        val previousRect = trackingRectOrDisplayRect() ?: return false
        val previousArea = previousRect.area()
        val nextArea = nextRect.area()
        if (previousArea <= 0f || nextArea <= 0f) {
            return false
        }
        if (motionCompensation.score > DANMAKU_AI_MOTION_GATE_MAX_AVERAGE_DELTA) {
            return false
        }
        if (abs(motionCompensation.dxNormalized) > DANMAKU_AI_MOTION_GATE_MAX_DX_NORMALIZED) {
            return false
        }
        if (abs(motionCompensation.dyNormalized) > DANMAKU_AI_MOTION_GATE_MAX_DY_NORMALIZED) {
            return false
        }
        val areaRatio = nextArea / previousArea
        if (
            areaRatio < DANMAKU_AI_MOTION_GATE_MIN_AREA_RATIO ||
                areaRatio > DANMAKU_AI_MOTION_GATE_MAX_AREA_RATIO
        ) {
            return false
        }
        val compensatedPreviousRect = buildCompensatedPreviousRect(motionCompensation) ?: return false
        return compensatedPreviousRect.iou(nextRect) >= DANMAKU_AI_MOTION_GATE_MIN_IOU
    }

    private fun resolveMotionRoi(
        rect: DanmakuNormalizedRect,
        sampleWidth: Int,
        sampleHeight: Int,
    ): DanmakuMotionRoi? {
        val expandedRect =
            rect.expanded(
                horizontalRatio = DANMAKU_AI_MOTION_ROI_EXPAND_HORIZONTAL_RATIO,
                verticalRatio = DANMAKU_AI_MOTION_ROI_EXPAND_VERTICAL_RATIO,
            )
        val expandedRoi = normalizedRectToMotionRoi(expandedRect, sampleWidth, sampleHeight)
        if (expandedRoi != null && expandedRoi.area >= DANMAKU_AI_MOTION_MIN_OVERLAP_SAMPLES) {
            return expandedRoi
        }
        val fallbackWidth =
            max(4, (sampleWidth * DANMAKU_AI_MOTION_FALLBACK_CENTER_WIDTH_RATIO).roundToInt())
        val fallbackHeight =
            max(4, (sampleHeight * DANMAKU_AI_MOTION_FALLBACK_CENTER_HEIGHT_RATIO).roundToInt())
        val left = ((sampleWidth - fallbackWidth) / 2).coerceIn(0, sampleWidth - 1)
        val top = ((sampleHeight - fallbackHeight) / 2).coerceIn(0, sampleHeight - 1)
        val right = (left + fallbackWidth - 1).coerceIn(left, sampleWidth - 1)
        val bottom = (top + fallbackHeight - 1).coerceIn(top, sampleHeight - 1)
        return DanmakuMotionRoi(left = left, top = top, right = right, bottom = bottom)
    }

    private fun normalizedRectToMotionRoi(
        rect: DanmakuNormalizedRect,
        sampleWidth: Int,
        sampleHeight: Int,
    ): DanmakuMotionRoi? {
        val width = rect.width.coerceIn(0f, 1f)
        val height = rect.height.coerceIn(0f, 1f)
        if (width <= 0f || height <= 0f) {
            return null
        }
        val left =
            (rect.left.coerceIn(0f, 1f) * sampleWidth.toFloat())
                .toInt()
                .coerceIn(0, sampleWidth - 1)
        val top =
            (rect.top.coerceIn(0f, 1f) * sampleHeight.toFloat())
                .toInt()
                .coerceIn(0, sampleHeight - 1)
        val right =
            ((rect.right.coerceIn(0f, 1f) * sampleWidth.toFloat()).roundToInt() - 1)
                .coerceIn(left, sampleWidth - 1)
        val bottom =
            ((rect.bottom.coerceIn(0f, 1f) * sampleHeight.toFloat()).roundToInt() - 1)
                .coerceIn(top, sampleHeight - 1)
        return DanmakuMotionRoi(left = left, top = top, right = right, bottom = bottom)
    }

    private fun buildCompensatedPreviousMask(
        motionCompensation: DanmakuMotionCompensation?,
        width: Int,
        height: Int,
    ): FloatArray? {
        val previousMask = latestMaskValues ?: return null
        if (latestMaskWidth != width || latestMaskHeight != height) {
            return null
        }
        val compensation = motionCompensation ?: return previousMask
        if (!shouldApplyMaskScaleCompensation(compensation.scale)) {
            return shiftMaskValues(
                values = previousMask,
                width = width,
                height = height,
                dxPx = compensation.dxMaskPx,
                dyPx = compensation.dyMaskPx,
            )
        }
        val previousRect = trackingRectOrDisplayRect()
        val anchorCenterX =
            previousRect?.centerX?.times(width.toFloat()) ?: (width.toFloat() / 2f)
        val anchorCenterY =
            previousRect?.centerY?.times(height.toFloat()) ?: (height.toFloat() / 2f)
        return transformMaskValues(
            values = previousMask,
            width = width,
            height = height,
            dxPx = compensation.dxMaskPx,
            dyPx = compensation.dyMaskPx,
            scale = compensation.scale,
            anchorCenterX = anchorCenterX,
            anchorCenterY = anchorCenterY,
        )
    }

    private fun shiftMaskValues(
        values: FloatArray,
        width: Int,
        height: Int,
        dxPx: Int,
        dyPx: Int,
    ): FloatArray {
        if (dxPx == 0 && dyPx == 0) {
            return values.copyOf()
        }
        val shifted = FloatArray(values.size)
        for (y in 0 until height) {
            val sourceY = y - dyPx
            if (sourceY !in 0 until height) {
                continue
            }
            val destinationRow = y * width
            val sourceRow = sourceY * width
            for (x in 0 until width) {
                val sourceX = x - dxPx
                if (sourceX !in 0 until width) {
                    continue
                }
                shifted[destinationRow + x] = values[sourceRow + sourceX]
            }
        }
        return shifted
    }

    private fun buildCompensatedPreviousRect(
        motionCompensation: DanmakuMotionCompensation?,
    ): DanmakuNormalizedRect? {
        val previousRect = trackingRectOrDisplayRect() ?: return null
        val compensation = motionCompensation ?: return previousRect
        return transformRect(
            rect = previousRect,
            dxNormalized = compensation.dxNormalized,
            dyNormalized = compensation.dyNormalized,
            scale = compensation.scale,
        )
    }

    private fun translateRect(
        rect: DanmakuNormalizedRect,
        dxNormalized: Float,
        dyNormalized: Float,
    ): DanmakuNormalizedRect {
        return transformRect(
            rect = rect,
            dxNormalized = dxNormalized,
            dyNormalized = dyNormalized,
            scale = 1f,
        )
    }

    private fun blendTrackedRectCandidate(
        predictedRect: DanmakuNormalizedRect,
        compensatedRect: DanmakuNormalizedRect,
    ): DanmakuNormalizedRect =
        rectFromCenter(
            centerX =
                predictedRect.centerX +
                    ((compensatedRect.centerX - predictedRect.centerX) * 0.68f),
            centerY =
                predictedRect.centerY +
                    ((compensatedRect.centerY - predictedRect.centerY) * 0.68f),
            width = predictedRect.width,
            height = predictedRect.height,
        )

    private fun transformRect(
        rect: DanmakuNormalizedRect,
        dxNormalized: Float,
        dyNormalized: Float,
        scale: Float,
    ): DanmakuNormalizedRect {
        val safeScale =
            if (scale.isFinite()) {
                scale.coerceIn(0.05f, 4f)
            } else {
                1f
            }
        return rectFromCenter(
            centerX = rect.centerX + dxNormalized,
            centerY = rect.centerY + dyNormalized,
            width = rect.width * safeScale,
            height = rect.height * safeScale,
        )
    }

    private fun rectFromCenter(
        centerX: Float,
        centerY: Float,
        width: Float,
        height: Float,
    ): DanmakuNormalizedRect {
        val safeWidth = width.coerceIn(0f, 1f)
        val safeHeight = height.coerceIn(0f, 1f)
        val maxLeft = (1f - safeWidth).coerceAtLeast(0f)
        val maxTop = (1f - safeHeight).coerceAtLeast(0f)
        return DanmakuNormalizedRect(
            x = (centerX - (safeWidth / 2f)).coerceIn(0f, maxLeft),
            y = (centerY - (safeHeight / 2f)).coerceIn(0f, maxTop),
            width = safeWidth,
            height = safeHeight,
        )
    }

    private fun shouldApplyMaskScaleCompensation(scale: Float): Boolean =
        abs(scale - 1f) >= DANMAKU_AI_MASK_SCALE_APPLY_THRESHOLD

    private fun transformMaskValues(
        values: FloatArray,
        width: Int,
        height: Int,
        dxPx: Int,
        dyPx: Int,
        scale: Float,
        anchorCenterX: Float,
        anchorCenterY: Float,
    ): FloatArray {
        if (dxPx == 0 && dyPx == 0 && !shouldApplyMaskScaleCompensation(scale)) {
            return values.copyOf()
        }
        val safeScale =
            if (scale.isFinite()) {
                scale.coerceIn(
                    DANMAKU_AI_MOTION_PREDICTION_MIN_SCALE,
                    DANMAKU_AI_MOTION_PREDICTION_MAX_SCALE,
                )
            } else {
                1f
            }
        val output = FloatArray(values.size)
        for (y in 0 until height) {
            val translatedY = y.toFloat() - dyPx.toFloat()
            val sourceY = ((translatedY - anchorCenterY) / safeScale) + anchorCenterY
            if (sourceY < 0f || sourceY > (height - 1).toFloat()) {
                continue
            }
            val targetRow = y * width
            for (x in 0 until width) {
                val translatedX = x.toFloat() - dxPx.toFloat()
                val sourceX = ((translatedX - anchorCenterX) / safeScale) + anchorCenterX
                if (sourceX < 0f || sourceX > (width - 1).toFloat()) {
                    continue
                }
                output[targetRow + x] = bilinearSampleMask(values, width, height, sourceX, sourceY)
            }
        }
        return output
    }

    private fun bilinearSampleMask(
        values: FloatArray,
        width: Int,
        height: Int,
        x: Float,
        y: Float,
    ): Float {
        val x0 = x.toInt().coerceIn(0, width - 1)
        val y0 = y.toInt().coerceIn(0, height - 1)
        val x1 = minOf(x0 + 1, width - 1)
        val y1 = minOf(y0 + 1, height - 1)
        val fx = (x - x0.toFloat()).coerceIn(0f, 1f)
        val fy = (y - y0.toFloat()).coerceIn(0f, 1f)
        val topLeft = values[y0 * width + x0]
        val topRight = values[y0 * width + x1]
        val bottomLeft = values[y1 * width + x0]
        val bottomRight = values[y1 * width + x1]
        val top = topLeft + ((topRight - topLeft) * fx)
        val bottom = bottomLeft + ((bottomRight - bottomLeft) * fx)
        return (top + ((bottom - top) * fy)).coerceIn(0f, 1f)
    }

    private fun remapMaskResultToFullFrame(
        result: DanmakuMaskResult,
        sampleAreaRatio: Float,
    ): DanmakuMaskResult {
        val clampedRatio = sampleAreaRatio.coerceIn(0.1f, 1.0f)
        if (clampedRatio >= 0.999f) {
            return result
        }
        val remappedMaskValues = FloatArray(result.maskValues.size)
        val targetHeight =
            max(1, (result.maskHeight.toFloat() * clampedRatio).roundToInt())
                .coerceAtMost(result.maskHeight)
        if (targetHeight > 0) {
            for (targetY in 0 until targetHeight) {
                val sourceY =
                    ((targetY + 0.5f) * result.maskHeight.toFloat() / targetHeight.toFloat())
                        .toInt()
                        .coerceIn(0, result.maskHeight - 1)
                val sourceRow = sourceY * result.maskWidth
                val targetRow = targetY * result.maskWidth
                for (x in 0 until result.maskWidth) {
                    remappedMaskValues[targetRow + x] = result.maskValues[sourceRow + x]
                }
            }
        }
        val rect =
            result.normalizedRect?.let {
                DanmakuNormalizedRect(
                    x = it.x,
                    y = (it.y * clampedRatio).coerceIn(0f, 1f),
                    width = it.width,
                    height = (it.height * clampedRatio).coerceIn(0f, 1f),
                )
        }
        return DanmakuMaskResult(
            maskValues = remappedMaskValues,
            maskWidth = result.maskWidth,
            maskHeight = result.maskHeight,
            normalizedRect = rect,
        )
    }

    private fun refineMaskAlpha(values: FloatArray): FloatArray {
        val refined = FloatArray(values.size)
        for (index in values.indices) {
            val value = values[index].coerceIn(0f, 1f)
            refined[index] =
                when {
                    value <= DANMAKU_AI_MASK_SOFT_EDGE_START -> 0f
                    value >= DANMAKU_AI_MASK_SOLID_CORE_START -> 1f
                    else -> {
                        val t =
                            ((value - DANMAKU_AI_MASK_SOFT_EDGE_START) /
                                (DANMAKU_AI_MASK_SOLID_CORE_START -
                                    DANMAKU_AI_MASK_SOFT_EDGE_START))
                                .coerceIn(0f, 1f)
                        t * t * (3f - (2f * t))
                    }
                }
        }
        return refined
    }

    private fun hardenMaskForOcclusion(
        values: FloatArray,
        width: Int,
        height: Int,
    ): FloatArray {
        val previousMask =
            latestMaskValues?.takeIf { latestMaskWidth == width && latestMaskHeight == height }
        val binary = FloatArray(values.size)
        for (index in values.indices) {
            val threshold =
                if (previousMask?.get(index)?.let { it >= 0.5f } == true) {
                    DANMAKU_AI_OUTPUT_MASK_KEEP_THRESHOLD
                } else {
                    DANMAKU_AI_OUTPUT_MASK_HARD_THRESHOLD
                }
            binary[index] =
                if (values[index] >= threshold) {
                    1f
                } else {
                    0f
                }
        }
        val stabilized =
            if (DANMAKU_AI_OUTPUT_MASK_DILATION_RADIUS > 0) {
                FloatArray(values.size).also { dilated ->
                    dilateBinaryMask(
                        input = binary,
                        output = dilated,
                        width = width,
                        height = height,
                        radius = DANMAKU_AI_OUTPUT_MASK_DILATION_RADIUS,
                    )
                }
            } else {
                binary
            }
        return FloatArray(values.size).also { filled ->
            fillEnclosedBinaryMaskHoles(
                input = stabilized,
                output = filled,
                width = width,
                height = height,
            )
        }
    }

    private fun dilateBinaryMask(
        input: FloatArray,
        output: FloatArray,
        width: Int,
        height: Int,
        radius: Int,
    ) {
        for (y in 0 until height) {
            for (x in 0 until width) {
                var value = 0f
                val top = max(0, y - radius)
                val bottom = minOf(height - 1, y + radius)
                val left = max(0, x - radius)
                val right = minOf(width - 1, x + radius)
                loop@ for (sampleY in top..bottom) {
                    for (sampleX in left..right) {
                        if (input[(sampleY * width) + sampleX] > 0.5f) {
                            value = 1f
                            break@loop
                        }
                    }
                }
                output[(y * width) + x] = value
            }
        }
    }

    private fun closeBinaryMask(
        input: FloatArray,
        output: FloatArray,
        width: Int,
        height: Int,
        radius: Int,
    ) {
        val dilated = FloatArray(input.size)
        dilateBinaryMask(
            input = input,
            output = dilated,
            width = width,
            height = height,
            radius = radius,
        )
        erodeBinaryMask(
            input = dilated,
            output = output,
            width = width,
            height = height,
            radius = radius,
        )
        fillEnclosedBinaryMaskHoles(
            input = output.copyOf(),
            output = output,
            width = width,
            height = height,
        )
    }

    private fun fillEnclosedBinaryMaskHoles(
        input: FloatArray,
        output: FloatArray,
        width: Int,
        height: Int,
    ) {
        val total = width * height
        val visited = BooleanArray(total)
        val queue = IntArray(total)
        var head = 0
        var tail = 0

        fun enqueueIfBackground(index: Int) {
            if (index < 0 || index >= total || visited[index] || input[index] > 0.5f) {
                return
            }
            visited[index] = true
            queue[tail++] = index
        }

        for (x in 0 until width) {
            enqueueIfBackground(x)
            enqueueIfBackground(((height - 1) * width) + x)
        }
        for (y in 1 until (height - 1).coerceAtLeast(1)) {
            enqueueIfBackground(y * width)
            enqueueIfBackground((y * width) + width - 1)
        }

        while (head < tail) {
            val current = queue[head++]
            val x = current % width
            val y = current / width
            if (x > 0) {
                enqueueIfBackground(current - 1)
            }
            if (x < width - 1) {
                enqueueIfBackground(current + 1)
            }
            if (y > 0) {
                enqueueIfBackground(current - width)
            }
            if (y < height - 1) {
                enqueueIfBackground(current + width)
            }
        }

        for (index in 0 until total) {
            output[index] =
                if (input[index] > 0.5f || !visited[index]) {
                    1f
                } else {
                    0f
                }
        }
    }

    private fun retainPrimaryMaskComponent(
        maskValues: FloatArray,
        width: Int,
        height: Int,
    ): DanmakuPrimaryMaskComponent? {
        val totalPixels = width * height
        val visited = BooleanArray(totalPixels)
        val queue = IntArray(totalPixels)
        val componentPixels = IntArray(totalPixels)
        val bestPixels = IntArray(totalPixels)
        var bestCount = 0

        for (index in 0 until totalPixels) {
            if (visited[index] || maskValues[index] <= 0.5f) {
                continue
            }
            var count = 0
            var head = 0
            var tail = 0
            visited[index] = true
            queue[tail++] = index
            while (head < tail) {
                val current = queue[head++]
                componentPixels[count++] = current
                val x = current % width
                val y = current / width
                val leftIndex = if (x > 0) current - 1 else -1
                val rightIndex = if (x < width - 1) current + 1 else -1
                val topIndex = if (y > 0) current - width else -1
                val bottomIndex = if (y < height - 1) current + width else -1
                val topLeftIndex = if (x > 0 && y > 0) current - width - 1 else -1
                val topRightIndex = if (x < width - 1 && y > 0) current - width + 1 else -1
                val bottomLeftIndex = if (x > 0 && y < height - 1) current + width - 1 else -1
                val bottomRightIndex = if (x < width - 1 && y < height - 1) current + width + 1 else -1
                if (leftIndex >= 0 && !visited[leftIndex] && maskValues[leftIndex] > 0.5f) {
                    visited[leftIndex] = true
                    queue[tail++] = leftIndex
                }
                if (rightIndex >= 0 && !visited[rightIndex] && maskValues[rightIndex] > 0.5f) {
                    visited[rightIndex] = true
                    queue[tail++] = rightIndex
                }
                if (topIndex >= 0 && !visited[topIndex] && maskValues[topIndex] > 0.5f) {
                    visited[topIndex] = true
                    queue[tail++] = topIndex
                }
                if (bottomIndex >= 0 && !visited[bottomIndex] && maskValues[bottomIndex] > 0.5f) {
                    visited[bottomIndex] = true
                    queue[tail++] = bottomIndex
                }
                if (topLeftIndex >= 0 && !visited[topLeftIndex] && maskValues[topLeftIndex] > 0.5f) {
                    visited[topLeftIndex] = true
                    queue[tail++] = topLeftIndex
                }
                if (topRightIndex >= 0 && !visited[topRightIndex] && maskValues[topRightIndex] > 0.5f) {
                    visited[topRightIndex] = true
                    queue[tail++] = topRightIndex
                }
                if (bottomLeftIndex >= 0 && !visited[bottomLeftIndex] && maskValues[bottomLeftIndex] > 0.5f) {
                    visited[bottomLeftIndex] = true
                    queue[tail++] = bottomLeftIndex
                }
                if (bottomRightIndex >= 0 && !visited[bottomRightIndex] && maskValues[bottomRightIndex] > 0.5f) {
                    visited[bottomRightIndex] = true
                    queue[tail++] = bottomRightIndex
                }
            }
            if (count > bestCount) {
                bestCount = count
                componentPixels.copyInto(bestPixels, destinationOffset = 0, startIndex = 0, endIndex = count)
            }
        }

        if (bestCount <= 0) {
            return null
        }
        val output = FloatArray(totalPixels)
        for (i in 0 until bestCount) {
            output[bestPixels[i]] = 1f
        }
        val component = extractPrimaryComponent(output, width, height) ?: return null
        return DanmakuPrimaryMaskComponent(
            maskValues = output,
            component = component,
        )
    }

    private fun shouldRejectAmbiguousForeground(
        maskValues: FloatArray,
        width: Int,
        height: Int,
    ): Boolean {
        val complexity = analyzeForegroundComplexity(maskValues, width, height)
        if (complexity.significantComponentCount <= 1) {
            return false
        }
        val secondRatio =
            if (complexity.largestPixelCount > 0) {
                complexity.secondLargestPixelCount.toFloat() / complexity.largestPixelCount.toFloat()
            } else {
                0f
            }
        val largestShare =
            if (complexity.totalForegroundPixels > 0) {
                complexity.largestPixelCount.toFloat() / complexity.totalForegroundPixels.toFloat()
            } else {
                1f
            }
        if (secondRatio >= DANMAKU_AI_AMBIGUOUS_SECOND_COMPONENT_RATIO) {
            return true
        }
        if (
            complexity.significantComponentCount >= DANMAKU_AI_AMBIGUOUS_MULTI_COMPONENT_COUNT &&
                largestShare <= DANMAKU_AI_AMBIGUOUS_LARGEST_FOREGROUND_SHARE
        ) {
            return true
        }
        return false
    }

    private fun analyzeForegroundComplexity(
        maskValues: FloatArray,
        width: Int,
        height: Int,
    ): DanmakuForegroundComplexity {
        val totalPixels = width * height
        val visited = BooleanArray(totalPixels)
        val queue = IntArray(totalPixels)
        var significantComponentCount = 0
        var totalForegroundPixels = 0
        var largestPixelCount = 0
        var secondLargestPixelCount = 0

        for (index in 0 until totalPixels) {
            if (visited[index] || maskValues[index] < DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                continue
            }
            var count = 0
            var head = 0
            var tail = 0
            visited[index] = true
            queue[tail++] = index
            while (head < tail) {
                val current = queue[head++]
                count += 1
                val x = current % width
                val y = current / width
                val leftIndex = if (x > 0) current - 1 else -1
                val rightIndex = if (x < width - 1) current + 1 else -1
                val topIndex = if (y > 0) current - width else -1
                val bottomIndex = if (y < height - 1) current + width else -1
                val topLeftIndex = if (x > 0 && y > 0) current - width - 1 else -1
                val topRightIndex = if (x < width - 1 && y > 0) current - width + 1 else -1
                val bottomLeftIndex = if (x > 0 && y < height - 1) current + width - 1 else -1
                val bottomRightIndex = if (x < width - 1 && y < height - 1) current + width + 1 else -1
                if (leftIndex >= 0 && !visited[leftIndex] && maskValues[leftIndex] >= DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                    visited[leftIndex] = true
                    queue[tail++] = leftIndex
                }
                if (rightIndex >= 0 && !visited[rightIndex] && maskValues[rightIndex] >= DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                    visited[rightIndex] = true
                    queue[tail++] = rightIndex
                }
                if (topIndex >= 0 && !visited[topIndex] && maskValues[topIndex] >= DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                    visited[topIndex] = true
                    queue[tail++] = topIndex
                }
                if (bottomIndex >= 0 && !visited[bottomIndex] && maskValues[bottomIndex] >= DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                    visited[bottomIndex] = true
                    queue[tail++] = bottomIndex
                }
                if (topLeftIndex >= 0 && !visited[topLeftIndex] && maskValues[topLeftIndex] >= DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                    visited[topLeftIndex] = true
                    queue[tail++] = topLeftIndex
                }
                if (topRightIndex >= 0 && !visited[topRightIndex] && maskValues[topRightIndex] >= DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                    visited[topRightIndex] = true
                    queue[tail++] = topRightIndex
                }
                if (bottomLeftIndex >= 0 && !visited[bottomLeftIndex] && maskValues[bottomLeftIndex] >= DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                    visited[bottomLeftIndex] = true
                    queue[tail++] = bottomLeftIndex
                }
                if (bottomRightIndex >= 0 && !visited[bottomRightIndex] && maskValues[bottomRightIndex] >= DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                    visited[bottomRightIndex] = true
                    queue[tail++] = bottomRightIndex
                }
            }
            if (count < DANMAKU_AI_AMBIGUOUS_COMPONENT_MIN_PIXELS) {
                continue
            }
            significantComponentCount += 1
            totalForegroundPixels += count
            if (count > largestPixelCount) {
                secondLargestPixelCount = largestPixelCount
                largestPixelCount = count
            } else if (count > secondLargestPixelCount) {
                secondLargestPixelCount = count
            }
        }

        return DanmakuForegroundComplexity(
            significantComponentCount = significantComponentCount,
            largestPixelCount = largestPixelCount,
            secondLargestPixelCount = secondLargestPixelCount,
            totalForegroundPixels = totalForegroundPixels,
        )
    }

    private fun shouldRejectWeirdPrimaryMask(
        maskValues: FloatArray,
        width: Int,
        height: Int,
    ): Boolean {
        val bounds = findMaskBounds(maskValues, width, height) ?: return true
        val boxWidth = bounds.right - bounds.left + 1
        val boxHeight = bounds.bottom - bounds.top + 1
        if (boxWidth <= 0 || boxHeight <= 0) {
            return true
        }
        val boxWidthRatio = boxWidth.toFloat() / width.toFloat()
        val boxHeightRatio = boxHeight.toFloat() / height.toFloat()
        val boxAspectRatio = boxHeight.toFloat() / boxWidth.toFloat()

        val coreLeft = bounds.left + max(1, (boxWidth * 0.22f).roundToInt())
        val coreRight = bounds.right - max(1, (boxWidth * 0.22f).roundToInt())
        val coreTop = bounds.top + max(1, (boxHeight * 0.18f).roundToInt())
        val coreBottom = bounds.bottom - max(1, (boxHeight * 0.18f).roundToInt())
        var corePixels = 0
        var coreForegroundPixels = 0
        for (y in coreTop..coreBottom.coerceAtLeast(coreTop)) {
            for (x in coreLeft..coreRight.coerceAtLeast(coreLeft)) {
                if (x < 0 || x >= width || y < 0 || y >= height) {
                    continue
                }
                corePixels += 1
                if (maskValues[(y * width) + x] > 0.5f) {
                    coreForegroundPixels += 1
                }
            }
        }
        if (corePixels > 0) {
            val coreFillRatio = coreForegroundPixels.toFloat() / corePixels.toFloat()
            if (coreFillRatio < DANMAKU_AI_MASK_SHAPE_MIN_CORE_FILL_RATIO) {
                return true
            }
        }

        val originalForegroundPixels = maskValues.count { it > 0.5f }
        if (originalForegroundPixels <= 0) {
            return true
        }
        val totalPixels = (width * height).coerceAtLeast(1)
        val overallAreaRatio = originalForegroundPixels.toFloat() / totalPixels.toFloat()
        if (
            boxWidthRatio <= DANMAKU_AI_MASK_SHAPE_MAX_THIN_TOWER_WIDTH_RATIO &&
            boxHeightRatio >= DANMAKU_AI_MASK_SHAPE_MIN_THIN_TOWER_HEIGHT_RATIO &&
            boxAspectRatio >= DANMAKU_AI_MASK_SHAPE_MIN_THIN_TOWER_ASPECT_RATIO &&
            overallAreaRatio <= DANMAKU_AI_MASK_SHAPE_MAX_THIN_TOWER_AREA_RATIO
        ) {
            return true
        }
        if (overallAreaRatio > DANMAKU_AI_MASK_SHAPE_MAX_OVERALL_AREA_RATIO) {
            return true
        }
        if (boxWidthRatio > DANMAKU_AI_MASK_SHAPE_MAX_BOUNDING_WIDTH_RATIO) {
            return true
        }
        if (boxHeightRatio > DANMAKU_AI_MASK_SHAPE_MAX_BOUNDING_HEIGHT_RATIO) {
            return true
        }
        val holeStats = analyzeMaskHoles(maskValues, width, height, bounds)
        val boundingArea = (boxWidth * boxHeight).coerceAtLeast(1)
        val holeAreaRatio = holeStats.totalHolePixels.toFloat() / boundingArea.toFloat()
        if (holeStats.holeCount > DANMAKU_AI_MASK_SHAPE_MAX_HOLE_COUNT) {
            return true
        }
        if (holeAreaRatio > DANMAKU_AI_MASK_SHAPE_MAX_HOLE_AREA_RATIO) {
            return true
        }
        val topBandWidth =
            measureMaskBandWidth(
                maskValues = maskValues,
                width = width,
                left = bounds.left,
                right = bounds.right,
                top = bounds.top,
                bottom = bounds.top + max(0, (boxHeight * 0.24f).roundToInt()),
            )
        val middleBandCenter = bounds.top + (boxHeight / 2)
        val middleBandHalfHeight = max(1, (boxHeight * 0.12f).roundToInt())
        val middleBandWidth =
            measureMaskBandWidth(
                maskValues = maskValues,
                width = width,
                left = bounds.left,
                right = bounds.right,
                top = (middleBandCenter - middleBandHalfHeight).coerceAtLeast(bounds.top),
                bottom = (middleBandCenter + middleBandHalfHeight).coerceAtMost(bounds.bottom),
            )
        val bottomBandWidth =
            measureMaskBandWidth(
                maskValues = maskValues,
                width = width,
                left = bounds.left,
                right = bounds.right,
                top = (bounds.bottom - max(0, (boxHeight * 0.24f).roundToInt())).coerceAtLeast(bounds.top),
                bottom = bounds.bottom,
            )
        if (middleBandWidth > 0) {
            val taperedSideRatio =
                minOf(topBandWidth, bottomBandWidth).toFloat() / middleBandWidth.toFloat()
            if (
                boxAspectRatio >= DANMAKU_AI_MASK_SHAPE_MIN_THIN_TOWER_ASPECT_RATIO &&
                taperedSideRatio <= DANMAKU_AI_MASK_SHAPE_MAX_TAPERED_SIDE_RATIO
            ) {
                return true
            }
        }
        val eroded = FloatArray(maskValues.size)
        erodeBinaryMask(
            input = maskValues,
            output = eroded,
            width = width,
            height = height,
            radius = DANMAKU_AI_MASK_SHAPE_EROSION_RADIUS,
        )
        val erodedForegroundPixels = eroded.count { it > 0.5f }
        val erodedRatio = erodedForegroundPixels.toFloat() / originalForegroundPixels.toFloat()
        return erodedRatio < DANMAKU_AI_MASK_SHAPE_MIN_ERODED_RATIO
    }

    private data class MaskBounds(
        val left: Int,
        val top: Int,
        val right: Int,
        val bottom: Int,
    )

    private fun findMaskBounds(
        maskValues: FloatArray,
        width: Int,
        height: Int,
    ): MaskBounds? {
        var left = width
        var top = height
        var right = -1
        var bottom = -1
        for (y in 0 until height) {
            for (x in 0 until width) {
                if (maskValues[(y * width) + x] <= 0.5f) {
                    continue
                }
                if (x < left) left = x
                if (x > right) right = x
                if (y < top) top = y
                if (y > bottom) bottom = y
            }
        }
        if (right < left || bottom < top) {
            return null
        }
        return MaskBounds(left = left, top = top, right = right, bottom = bottom)
    }

    private fun measureMaskBandWidth(
        maskValues: FloatArray,
        width: Int,
        left: Int,
        right: Int,
        top: Int,
        bottom: Int,
    ): Int {
        var bandLeft = right
        var bandRight = left
        for (y in top..bottom.coerceAtLeast(top)) {
            for (x in left..right.coerceAtLeast(left)) {
                if (maskValues[(y * width) + x] <= 0.5f) {
                    continue
                }
                if (x < bandLeft) bandLeft = x
                if (x > bandRight) bandRight = x
            }
        }
        if (bandRight < bandLeft) {
            return 0
        }
        return bandRight - bandLeft + 1
    }

    private fun analyzeMaskHoles(
        maskValues: FloatArray,
        width: Int,
        height: Int,
        bounds: MaskBounds,
    ): MaskHoleStats {
        val boxWidth = bounds.right - bounds.left + 1
        val boxHeight = bounds.bottom - bounds.top + 1
        val total = (boxWidth * boxHeight).coerceAtLeast(1)
        val visited = BooleanArray(total)
        val queue = IntArray(total)
        var holeCount = 0
        var largestHolePixels = 0
        var totalHolePixels = 0

        fun localIndex(localX: Int, localY: Int): Int = (localY * boxWidth) + localX

        for (localY in 0 until boxHeight) {
            for (localX in 0 until boxWidth) {
                val index = localIndex(localX, localY)
                if (visited[index]) {
                    continue
                }
                val globalX = bounds.left + localX
                val globalY = bounds.top + localY
                if (maskValues[(globalY * width) + globalX] > 0.5f) {
                    visited[index] = true
                    continue
                }
                var head = 0
                var tail = 0
                var backgroundPixels = 0
                var touchesBoundary = false
                visited[index] = true
                queue[tail++] = index
                while (head < tail) {
                    val current = queue[head++]
                    val currentLocalX = current % boxWidth
                    val currentLocalY = current / boxWidth
                    backgroundPixels += 1
                    if (
                        currentLocalX == 0 ||
                        currentLocalX == boxWidth - 1 ||
                        currentLocalY == 0 ||
                        currentLocalY == boxHeight - 1
                    ) {
                        touchesBoundary = true
                    }
                    val leftIndex = if (currentLocalX > 0) current - 1 else -1
                    val rightIndex = if (currentLocalX < boxWidth - 1) current + 1 else -1
                    val topIndex = if (currentLocalY > 0) current - boxWidth else -1
                    val bottomIndex = if (currentLocalY < boxHeight - 1) current + boxWidth else -1
                    val neighborIndexes = intArrayOf(leftIndex, rightIndex, topIndex, bottomIndex)
                    for (neighbor in neighborIndexes) {
                        if (neighbor < 0 || visited[neighbor]) {
                            continue
                        }
                        val neighborLocalX = neighbor % boxWidth
                        val neighborLocalY = neighbor / boxWidth
                        val neighborGlobalX = bounds.left + neighborLocalX
                        val neighborGlobalY = bounds.top + neighborLocalY
                        if (maskValues[(neighborGlobalY * width) + neighborGlobalX] > 0.5f) {
                            visited[neighbor] = true
                            continue
                        }
                        visited[neighbor] = true
                        queue[tail++] = neighbor
                    }
                }
                if (!touchesBoundary) {
                    holeCount += 1
                    totalHolePixels += backgroundPixels
                    if (backgroundPixels > largestHolePixels) {
                        largestHolePixels = backgroundPixels
                    }
                }
            }
        }
        return MaskHoleStats(
            holeCount = holeCount,
            largestHolePixels = largestHolePixels,
            totalHolePixels = totalHolePixels,
        )
    }

    private fun erodeBinaryMask(
        input: FloatArray,
        output: FloatArray,
        width: Int,
        height: Int,
        radius: Int,
    ) {
        for (y in 0 until height) {
            for (x in 0 until width) {
                var value = 1f
                val top = max(0, y - radius)
                val bottom = minOf(height - 1, y + radius)
                val left = max(0, x - radius)
                val right = minOf(width - 1, x + radius)
                loop@ for (sampleY in top..bottom) {
                    for (sampleX in left..right) {
                        if (input[(sampleY * width) + sampleX] <= 0.5f) {
                            value = 0f
                            break@loop
                        }
                    }
                }
                output[(y * width) + x] = value
            }
        }
    }

    private fun extractPrimaryComponent(
        maskValues: FloatArray,
        width: Int,
        height: Int,
    ): DanmakuPrimaryComponent? {
        val totalPixels = width * height
        val minForegroundPixels = max(32, (totalPixels * DANMAKU_AI_MIN_FOREGROUND_RATIO).toInt())
        val visited = BooleanArray(totalPixels)
        val queue = IntArray(totalPixels)
        var largestCount = 0
        var bestLeft = 0
        var bestTop = 0
        var bestRight = 0
        var bestBottom = 0

        for (index in 0 until totalPixels) {
            if (visited[index] || maskValues[index] < DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                continue
            }
            var count = 0
            var left = index % width
            var right = left
            var top = index / width
            var bottom = top
            var head = 0
            var tail = 0
            visited[index] = true
            queue[tail++] = index
            while (head < tail) {
                val current = queue[head++]
                val x = current % width
                val y = current / width
                count += 1
                if (x < left) left = x
                if (x > right) right = x
                if (y < top) top = y
                if (y > bottom) bottom = y
                val leftIndex = if (x > 0) current - 1 else -1
                val rightIndex = if (x < width - 1) current + 1 else -1
                val topIndex = if (y > 0) current - width else -1
                val bottomIndex = if (y < height - 1) current + width else -1
                val topLeftIndex = if (x > 0 && y > 0) current - width - 1 else -1
                val topRightIndex = if (x < width - 1 && y > 0) current - width + 1 else -1
                val bottomLeftIndex = if (x > 0 && y < height - 1) current + width - 1 else -1
                val bottomRightIndex = if (x < width - 1 && y < height - 1) current + width + 1 else -1
                if (leftIndex >= 0 && !visited[leftIndex] && maskValues[leftIndex] >= DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                    visited[leftIndex] = true
                    queue[tail++] = leftIndex
                }
                if (rightIndex >= 0 && !visited[rightIndex] && maskValues[rightIndex] >= DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                    visited[rightIndex] = true
                    queue[tail++] = rightIndex
                }
                if (topIndex >= 0 && !visited[topIndex] && maskValues[topIndex] >= DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                    visited[topIndex] = true
                    queue[tail++] = topIndex
                }
                if (bottomIndex >= 0 && !visited[bottomIndex] && maskValues[bottomIndex] >= DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                    visited[bottomIndex] = true
                    queue[tail++] = bottomIndex
                }
                if (topLeftIndex >= 0 && !visited[topLeftIndex] && maskValues[topLeftIndex] >= DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                    visited[topLeftIndex] = true
                    queue[tail++] = topLeftIndex
                }
                if (topRightIndex >= 0 && !visited[topRightIndex] && maskValues[topRightIndex] >= DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                    visited[topRightIndex] = true
                    queue[tail++] = topRightIndex
                }
                if (bottomLeftIndex >= 0 && !visited[bottomLeftIndex] && maskValues[bottomLeftIndex] >= DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                    visited[bottomLeftIndex] = true
                    queue[tail++] = bottomLeftIndex
                }
                if (bottomRightIndex >= 0 && !visited[bottomRightIndex] && maskValues[bottomRightIndex] >= DANMAKU_AI_RECT_HELPER_THRESHOLD) {
                    visited[bottomRightIndex] = true
                    queue[tail++] = bottomRightIndex
                }
            }
            if (count > largestCount) {
                largestCount = count
                bestLeft = left
                bestTop = top
                bestRight = right
                bestBottom = bottom
            }
        }

        if (largestCount < minForegroundPixels) {
            return null
        }
        val candidateRect =
            DanmakuNormalizedRect(
                x = bestLeft.toFloat() / width.toFloat(),
                y = bestTop.toFloat() / height.toFloat(),
                width = (bestRight - bestLeft + 1).toFloat() / width.toFloat(),
                height = (bestBottom - bestTop + 1).toFloat() / height.toFloat(),
            ).expanded(horizontalRatio = 0.10f, verticalRatio = 0.12f)
        val bboxPixelCount = (bestRight - bestLeft + 1) * (bestBottom - bestTop + 1)
        val fillRatio =
            if (bboxPixelCount > 0) {
                largestCount.toFloat() / bboxPixelCount.toFloat()
            } else {
                0f
            }
        return DanmakuPrimaryComponent(
            rect = candidateRect,
            pixelCount = largestCount,
            fillRatio = fillRatio,
        )
    }

    private fun keepDetectionAlignedComponents(
        maskValues: FloatArray,
        width: Int,
        height: Int,
        detectionRect: DanmakuNormalizedRect,
        previousRect: DanmakuNormalizedRect?,
    ): FloatArray {
        val totalPixels = width * height
        val visited = BooleanArray(totalPixels)
        val queue = IntArray(totalPixels)
        val componentPixels = IntArray(totalPixels)
        val kept = FloatArray(totalPixels)
        val detectionArea = detectionRect.area().coerceAtLeast(0.0001f)
        val minComponentArea = detectionArea * DANMAKU_AI_RENDER_MASK_MIN_COMPONENT_AREA_RATIO
        val maxAllowedArea = detectionArea * DANMAKU_AI_RENDER_MASK_MAX_AREA_MULTIPLIER

        for (index in 0 until totalPixels) {
            if (visited[index] || maskValues[index] <= 0.5f) {
                continue
            }
            var count = 0
            var left = index % width
            var right = left
            var top = index / width
            var bottom = top
            var head = 0
            var tail = 0
            visited[index] = true
            queue[tail++] = index
            while (head < tail) {
                val current = queue[head++]
                componentPixels[count++] = current
                val x = current % width
                val y = current / width
                if (x < left) left = x
                if (x > right) right = x
                if (y < top) top = y
                if (y > bottom) bottom = y
                val leftIndex = if (x > 0) current - 1 else -1
                val rightIndex = if (x < width - 1) current + 1 else -1
                val topIndex = if (y > 0) current - width else -1
                val bottomIndex = if (y < height - 1) current + width else -1
                val topLeftIndex = if (x > 0 && y > 0) current - width - 1 else -1
                val topRightIndex = if (x < width - 1 && y > 0) current - width + 1 else -1
                val bottomLeftIndex = if (x > 0 && y < height - 1) current + width - 1 else -1
                val bottomRightIndex = if (x < width - 1 && y < height - 1) current + width + 1 else -1
                val neighbors =
                    intArrayOf(
                        leftIndex,
                        rightIndex,
                        topIndex,
                        bottomIndex,
                        topLeftIndex,
                        topRightIndex,
                        bottomLeftIndex,
                        bottomRightIndex,
                    )
                for (neighbor in neighbors) {
                    if (neighbor < 0 || visited[neighbor] || maskValues[neighbor] <= 0.5f) {
                        continue
                    }
                    visited[neighbor] = true
                    queue[tail++] = neighbor
                }
            }

            val componentRect =
                DanmakuNormalizedRect(
                    x = left.toFloat() / width.toFloat(),
                    y = top.toFloat() / height.toFloat(),
                    width = (right - left + 1).toFloat() / width.toFloat(),
                    height = (bottom - top + 1).toFloat() / height.toFloat(),
                )
            val componentArea = componentRect.area()
            val overlapsDetection = componentRect.iou(detectionRect) >= 0.02f
            val overlapsPrevious = previousRect?.let { componentRect.iou(it) >= 0.02f } == true
            val areaValid = componentArea in minComponentArea..maxAllowedArea
            if ((!overlapsDetection && !overlapsPrevious) || !areaValid) {
                continue
            }
            for (i in 0 until count) {
                kept[componentPixels[i]] = 1f
            }
        }
        return kept
    }

    private fun extractPrimaryRect(
        maskValues: FloatArray,
        width: Int,
        height: Int,
    ): DanmakuNormalizedRect? {
        return extractPrimaryComponent(maskValues, width, height)?.rect
    }

    private fun isLikelyForegroundSubject(component: DanmakuPrimaryComponent): Boolean {
        val rect = component.rect
        val areaRatio = rect.area()
        val aspectRatio =
            if (rect.height > 0f) {
                rect.width / rect.height
            } else {
                0f
            }
        if (component.fillRatio < DANMAKU_AI_SUBJECT_MIN_FILL_RATIO) {
            return false
        }
        if (areaRatio > DANMAKU_AI_SUBJECT_MAX_AREA_RATIO) {
            return false
        }
        if (rect.width > DANMAKU_AI_SUBJECT_MAX_WIDTH_RATIO) {
            return false
        }
        if (rect.height > DANMAKU_AI_SUBJECT_MAX_HEIGHT_RATIO) {
            return false
        }
        if (aspectRatio < DANMAKU_AI_SUBJECT_MIN_ASPECT_RATIO &&
            areaRatio >= DANMAKU_AI_SUBJECT_MAX_SPARSE_AREA_RATIO &&
            rect.height >= DANMAKU_AI_SUBJECT_MAX_SPARSE_HEIGHT_RATIO
        ) {
            return false
        }
        return true
    }

    private fun applyMaskResult(
        backend: DanmakuAiBackend,
        result: DanmakuMaskResult,
        trackingRect: DanmakuNormalizedRect?,
        frameBitmap: Bitmap,
        latencyMs: Long,
        motionLumaSamples: IntArray,
        motionSampleWidth: Int,
        motionSampleHeight: Int,
        motionCompensation: DanmakuMotionCompensation?,
        updateTrackingState: Boolean = true,
    ) {
        cancelPendingMaskGrace()
        val nextMaskSignature =
            if (result.occlusionMode == DanmakuOcclusionMode.MASK) {
                buildMaskSignature(result)
            } else {
                null
            }
        val normalizedRectChanged =
            result.occlusionMode == DanmakuOcclusionMode.MASK &&
                result.normalizedRect != latestRect
        val maskChanged =
            result.occlusionMode == DanmakuOcclusionMode.MASK &&
                (latestMaskSignature != nextMaskSignature ||
                    latestMaskPath == null ||
                    normalizedRectChanged)
        val runtimeMaskBitmap =
            if (result.occlusionMode == DanmakuOcclusionMode.MASK) {
                if (
                    latestRuntimeMaskBitmap == null ||
                        latestRuntimeMaskBitmap?.isRecycled == true ||
                        maskChanged ||
                        latestMaskWidth != result.maskWidth ||
                        latestMaskHeight != result.maskHeight
                ) {
                    createRuntimeMaskBitmap(result.maskWidth, result.maskHeight, result.maskValues)
                } else {
                    latestRuntimeMaskBitmap
                }
            } else {
                null
            }
        val cacheEntry =
            if (result.occlusionMode == DanmakuOcclusionMode.MASK && maskChanged) {
                persistMaskCache(
                    source = currentSource,
                    backend = backend,
                    result = result,
                    frameBitmap = frameBitmap,
                    updatedAtMs = System.currentTimeMillis(),
                    maskSignature = nextMaskSignature,
                )
            } else if (result.occlusionMode == DanmakuOcclusionMode.MASK) {
                latestMaskPath?.let { currentPath ->
                    DanmakuOcclusionCacheEntry(
                        backend = backend.wireValue,
                        updatedAtMs = latestMaskTimestampMs,
                        maskPath = currentPath,
                        maskSignature = latestMaskSignature,
                        maskWidth = latestMaskWidth.takeIf { it > 0 } ?: result.maskWidth,
                        maskHeight = latestMaskHeight.takeIf { it > 0 } ?: result.maskHeight,
                        framePath = latestFramePath,
                        normalizedRect = result.normalizedRect,
                    )
                }
            } else {
                null
            }
        warmStartDelayUntilUptimeMs = 0L
        val now =
            if (result.occlusionMode == DanmakuOcclusionMode.MASK && maskChanged) {
                cacheEntry?.updatedAtMs ?: System.currentTimeMillis()
            } else {
                latestMaskTimestampMs.takeIf { it > 0L } ?: System.currentTimeMillis()
            }
        latestRect = result.normalizedRect
        latestRectTrackingEligible = updateTrackingState && result.normalizedRect != null
        latestTrackingRect =
            if (updateTrackingState) {
                trackingRect ?: result.normalizedRect
            } else {
                null
            }
        latestMaskValues = result.maskValues.copyOf()
        latestMaskWidth = result.maskWidth
        latestMaskHeight = result.maskHeight
        latestMaskSignature = nextMaskSignature
        latestMaskTimestampMs = now
        latestMaskAppliedAtUptimeMs = SystemClock.uptimeMillis()
        consecutiveEmptyFrames = 0
        averageLatencyMs =
            if (averageLatencyMs <= 0.0) {
                latencyMs.toDouble()
            } else {
                (averageLatencyMs * 0.72) + (latencyMs.toDouble() * 0.28)
            }
        updateDegradationAfterSample(
            latencyMs = latencyMs,
            occlusionMode = result.occlusionMode,
        )
        if (sceneCutRecoveryActive) {
            stableMaskFramesSinceSceneCut += 1
            if (sceneCutBurstSamplesRemaining > 0) {
                sceneCutBurstSamplesRemaining -= 1
            }
            if (stableMaskFramesSinceSceneCut >= DANMAKU_AI_SCENE_CUT_STABLE_MASK_FRAMES) {
                sceneCutRecoveryActive = false
                sceneCutBurstSamplesRemaining = 0
                stableMaskFramesSinceSceneCut = 0
            }
        }
        consumeMotionBurstSample()
        latestMaskPath = cacheEntry?.maskPath
        latestFramePath = cacheEntry?.framePath
        replaceRuntimeMaskBitmap(
            runtimeMaskBitmap?.takeIf { result.occlusionMode == DanmakuOcclusionMode.MASK },
        )
        if (updateTrackingState) {
            previousMotionReferenceFrame = latestMotionReferenceFrame
            latestMotionReferenceFrame =
                latestTrackingRect?.let { rect ->
                    DanmakuMotionReferenceFrame(
                        lumaSamples = motionLumaSamples.copyOf(),
                        sampleWidth = motionSampleWidth,
                        sampleHeight = motionSampleHeight,
                        normalizedRect = rect,
                        timestampMs = SystemClock.uptimeMillis(),
                    )
                }
            lastMotionCompensation = motionCompensation
            consecutiveMotionCompensationFailures = 0
            consecutiveCompensatedFrames =
                if (motionCompensation != null) {
                    consecutiveCompensatedFrames + 1
                } else {
                    0
                }
        } else {
            previousMotionReferenceFrame = null
            latestMotionReferenceFrame = null
            lastMotionCompensation = null
            consecutiveMotionCompensationFailures = 0
            consecutiveCompensatedFrames = 0
        }
        emitState(
            DanmakuDynamicOcclusionState(
                enabled = true,
                available =
                    if (result.occlusionMode == DanmakuOcclusionMode.MASK) {
                        cacheEntry != null
                    } else {
                        true
                    },
                backend = backend.wireValue,
                occlusionMode = result.occlusionMode.wireValue,
                updatedAtMs = now,
                maskPath = cacheEntry?.maskPath,
                maskSignature = nextMaskSignature,
                maskWidth =
                    if (result.occlusionMode == DanmakuOcclusionMode.MASK) {
                        cacheEntry?.maskWidth ?: result.maskWidth
                    } else {
                        0
                    },
                maskHeight =
                    if (result.occlusionMode == DanmakuOcclusionMode.MASK) {
                        cacheEntry?.maskHeight ?: result.maskHeight
                    } else {
                        0
                    },
                framePath = cacheEntry?.framePath,
                cacheHit = false,
                captureAreaRatio = config.sampleAreaRatio,
                normalizedRect = result.normalizedRect,
                unavailableReason = null,
                captureBackend = lastCaptureBackend,
                degradationLevel = currentDegradationLevel().wireValue,
                effectiveSampleIntervalMs = currentSampleIntervalMs(),
                effectiveInputWidth = effectiveInputWidth(),
                maskVelocityX = if (config.motionTrackingEnabled) latestMaskVelocityX else 0.0,
                maskVelocityY = if (config.motionTrackingEnabled) latestMaskVelocityY else 0.0,
                maskPtsMs = latestMaskPtsMs,
                videoAspect = currentPlanBVideoAspect,
            ),
            runtimeMaskBitmap?.takeIf { result.occlusionMode == DanmakuOcclusionMode.MASK },
        )
    }

    private fun applyEmptyResult(
        sampleId: Long,
        backend: DanmakuAiBackend,
        motionCompensationAttempted: Boolean,
        allowMaskGrace: Boolean = true,
    ) {
        consecutiveEmptyFrames += 1
        val nowUptimeMs = SystemClock.uptimeMillis()
        if (motionCompensationAttempted) {
            lastMotionCompensation = null
            consecutiveMotionCompensationFailures += 1
            if (consecutiveMotionCompensationFailures >= DANMAKU_AI_MOTION_MAX_FAILURES) {
                latestMotionReferenceFrame = null
                previousMotionReferenceFrame = null
                consecutiveMotionCompensationFailures = 0
            }
        } else {
            lastMotionCompensation = null
        }
        consecutiveCompensatedFrames = 0
        if (sceneCutRecoveryActive) {
            stableMaskFramesSinceSceneCut = 0
            if (sceneCutBurstSamplesRemaining > 0) {
                sceneCutBurstSamplesRemaining -= 1
            }
        }
        consumeMotionBurstSample()
        if (allowMaskGrace && tryHoldPreviousMaskAfterEmptyResult(sampleId, backend, nowUptimeMs)) {
            return
        }
        cancelPendingMaskGrace()
        if (!allowMaskGrace || consecutiveEmptyFrames >= DANMAKU_AI_MAX_EMPTY_FRAMES) {
            clearRuntimeMaskState()
        }
        emitUnavailableState(backend = backend, keepEnabled = true)
    }

    private fun tryHoldPreviousMaskAfterEmptyResult(
        sampleId: Long,
        backend: DanmakuAiBackend,
        nowUptimeMs: Long,
    ): Boolean {
        val maskAgeMs =
            if (latestMaskAppliedAtUptimeMs > 0L) {
                (nowUptimeMs - latestMaskAppliedAtUptimeMs).coerceAtLeast(0L)
            } else {
                -1L
            }
        if (sceneCutRecoveryActive) {
            Log.d(
                DANMAKU_AI_TAG,
                "sample=$sampleId mask_grace_applied=false mask_grace_age_ms=$maskAgeMs",
            )
            return false
        }
        if (latestState.occlusionMode != DanmakuOcclusionMode.MASK.wireValue) {
            Log.d(
                DANMAKU_AI_TAG,
                "sample=$sampleId mask_grace_applied=false mask_grace_age_ms=$maskAgeMs",
            )
            return false
        }
        if (!latestState.enabled || !latestState.available) {
            Log.d(
                DANMAKU_AI_TAG,
                "sample=$sampleId mask_grace_applied=false mask_grace_age_ms=$maskAgeMs",
            )
            return false
        }
        cancelPendingMaskGrace()
        pendingMaskGraceBackend = backend
        pendingMaskGraceClearAtUptimeMs = nowUptimeMs + DANMAKU_AI_EMPTY_RESULT_GRACE_MS
        mainHandler.postAtTime(maskGraceExpireRunnable, pendingMaskGraceClearAtUptimeMs)
        Log.d(
            DANMAKU_AI_TAG,
            "sample=$sampleId mask_grace_applied=true mask_grace_age_ms=$maskAgeMs",
        )
        return true
    }

    private fun clearMaskGraceByVisibilityChange() {
        if (pendingMaskGraceBackend == null && pendingMaskGraceClearAtUptimeMs <= 0L) {
            return
        }
        cancelPendingMaskGrace()
    }

    private fun emitUnavailableState(
        backend: DanmakuAiBackend,
        keepEnabled: Boolean,
        backendWireValue: String? = null,
        unavailableReason: String? = null,
    ) {
        clearMaskGraceByVisibilityChange()
        emitState(
            DanmakuDynamicOcclusionState(
                enabled = keepEnabled,
                available = false,
                backend = backendWireValue ?: backend.wireValue,
                occlusionMode = DanmakuOcclusionMode.DISABLED.wireValue,
                updatedAtMs = latestMaskTimestampMs,
                maskPath = null,
                maskSignature = null,
                maskWidth = 0,
                maskHeight = 0,
                framePath = null,
                cacheHit = false,
                captureAreaRatio = config.sampleAreaRatio,
                normalizedRect = latestRect,
                unavailableReason = unavailableReason,
                captureBackend = lastCaptureBackend,
                degradationLevel =
                    if (unavailableReason == DANMAKU_AI_UNAVAILABLE_REASON_CAPTURE_BUDGET_UNSUPPORTED) {
                        DanmakuOcclusionDegradationLevel.DISABLED.wireValue
                    } else {
                        currentDegradationLevel().wireValue
                    },
                effectiveSampleIntervalMs = currentSampleIntervalMs(),
                effectiveInputWidth = effectiveInputWidth(),
            ),
            null,
        )
    }

    private fun emitLatestMaskStateIfAvailable() {
        if (!latestState.available) {
            return
        }
        val backendWireValue =
            latestState.backend.takeIf { it.isNotBlank() } ?: currentBackendOrFallback().wireValue
        emitState(
            DanmakuDynamicOcclusionState(
                enabled = config.enabled,
                available = true,
                backend = backendWireValue,
                occlusionMode = latestState.occlusionMode,
                updatedAtMs = latestMaskTimestampMs,
                maskPath = latestMaskPath,
                maskSignature = latestMaskSignature,
                maskWidth = if (latestState.occlusionMode == DanmakuOcclusionMode.MASK.wireValue) latestMaskWidth else 0,
                maskHeight = if (latestState.occlusionMode == DanmakuOcclusionMode.MASK.wireValue) latestMaskHeight else 0,
                framePath = latestFramePath,
                cacheHit = latestState.cacheHit,
                captureAreaRatio = config.sampleAreaRatio,
                normalizedRect = latestRect,
                unavailableReason = null,
                captureBackend = lastCaptureBackend,
                degradationLevel = currentDegradationLevel().wireValue,
                effectiveSampleIntervalMs = currentSampleIntervalMs(),
                effectiveInputWidth = effectiveInputWidth(),
            ),
            latestRuntimeMaskBitmap,
        )
    }

    private fun emitState(
        next: DanmakuDynamicOcclusionState,
        runtimeMaskBitmap: Bitmap? = latestRuntimeMaskBitmap,
    ) {
        if (disposed) {
            return
        }
        if (latestState == next) {
            return
        }
        latestState = next
        stateListener(next, runtimeMaskBitmap?.takeIf { !it.isRecycled })
    }

    private fun ensureRuntime(): DanmakuSegmentationRuntime? {
        synchronized(runtimeLock) {
            activeRuntime?.let { return it }
            while (activeBackendIndex < config.preferredBackendOrder.size) {
                val backend = config.preferredBackendOrder[activeBackendIndex]
                if (!runtimeFactory.shouldAttempt(backend)) {
                    Log.d(
                        DANMAKU_AI_TAG,
                        "backend=${backend.wireValue} skipped device=${runtimeFactory.deviceSummary()}",
                    )
                    activeBackendIndex += 1
                    continue
                }
                val runtime =
                    runCatching { runtimeFactory.create(backend, config) }.getOrElse { error ->
                        Log.w(DANMAKU_AI_TAG, "backend=${backend.wireValue} init failed", error)
                        activeBackendIndex += 1
                        null
                    }
                if (runtime != null) {
                    activeRuntime = runtime
                    Log.d(
                        DANMAKU_AI_TAG,
                        "backend=${backend.wireValue} init success device=${runtimeFactory.deviceSummary()}",
                    )
                    return runtime
                }
            }
        }
        return null
    }

    private fun ensureDetectionRuntime(): DanmakuDetectionRuntime? {
        synchronized(runtimeLock) {
            activeDetectionRuntime?.let { return it }
            while (activeBackendIndex < config.preferredBackendOrder.size) {
                val backend = config.preferredBackendOrder[activeBackendIndex]
                if (!detectionRuntimeFactory.shouldAttempt(backend)) {
                    return null
                }
                val runtime =
                    runCatching { detectionRuntimeFactory.create(backend) }.getOrNull()
                if (runtime != null) {
                    activeDetectionRuntime = runtime
                    return runtime
                }
                activeBackendIndex += 1
            }
        }
        return null
    }

    private fun beginSceneCutRecovery(backend: DanmakuAiBackend) {
        sceneCutRecoveryActive = true
        sceneCutBurstSamplesRemaining = DANMAKU_AI_SCENE_CUT_BURST_SAMPLE_COUNT
        stableMaskFramesSinceSceneCut = 0
        pendingMaskGraceBackend = backend
    }

    private fun handleBackendFailure(backend: DanmakuAiBackend) {
        synchronized(runtimeLock) {
            activeRuntime?.takeIf { it.backend == backend }?.close()
            if (activeRuntime?.backend == backend) activeRuntime = null
            activeDetectionRuntime?.takeIf { it.backend == backend }?.close()
            if (activeDetectionRuntime?.backend == backend) activeDetectionRuntime = null
        }
        activeBackendIndex += 1
    }

    private fun releaseRuntime() {
        synchronized(runtimeLock) {
            activeRuntime?.close()
            activeRuntime = null
            activeDetectionRuntime?.close()
            activeDetectionRuntime = null
            personTrackerRuntime?.close()
            personTrackerRuntime = null
        }
    }

    private fun restoreCachedState() {
        cacheRestoreEligible = false
        val source = currentSource ?: return
        val cached = cacheStore.load(source) ?: return
        if (!config.enabled) {
            return
        }
        latestRect = cached.normalizedRect
        latestRectTrackingEligible = cached.normalizedRect != null
        latestTrackingRect = cached.normalizedRect
        latestMaskValues = null
        latestMaskWidth = cached.maskWidth
        latestMaskHeight = cached.maskHeight
        latestMaskPath = cached.maskPath
        latestMaskSignature = cached.maskSignature
        latestFramePath = cached.framePath
        latestMaskTimestampMs = cached.updatedAtMs
        latestMaskAppliedAtUptimeMs = SystemClock.uptimeMillis()
        warmStartDelayUntilUptimeMs = SystemClock.uptimeMillis() + DANMAKU_AI_CACHE_WARM_START_DELAY_MS
        emitState(
            DanmakuDynamicOcclusionState(
                enabled = true,
                available = true,
                backend = cached.backend,
                occlusionMode = DanmakuOcclusionMode.MASK.wireValue,
                updatedAtMs = cached.updatedAtMs,
                maskPath = cached.maskPath,
                maskSignature = cached.maskSignature,
                maskWidth = cached.maskWidth,
                maskHeight = cached.maskHeight,
                framePath = cached.framePath,
                cacheHit = true,
                captureAreaRatio = config.sampleAreaRatio,
                normalizedRect = cached.normalizedRect,
                unavailableReason = null,
                captureBackend = lastCaptureBackend,
                degradationLevel = currentDegradationLevel().wireValue,
                effectiveSampleIntervalMs = currentSampleIntervalMs(),
                effectiveInputWidth = effectiveInputWidth(),
            ),
            null,
        )
    }

    private fun persistMaskCache(
        source: MpvSource?,
        backend: DanmakuAiBackend,
        result: DanmakuMaskResult,
        frameBitmap: Bitmap,
        updatedAtMs: Long,
        maskSignature: String?,
    ): DanmakuOcclusionCacheEntry? {
        val safeSource = source ?: return null
        val includeFrameBitmap =
            updatedAtMs - lastFrameCacheWriteAtMs >= DANMAKU_AI_CACHE_FRAME_WRITE_INTERVAL_MS
        if (includeFrameBitmap) {
            lastFrameCacheWriteAtMs = updatedAtMs
        }
        return runCatching {
            cacheStore.save(
                source = safeSource,
                backend = backend.wireValue,
                updatedAtMs = updatedAtMs,
                maskSignature = maskSignature,
                normalizedRect = result.normalizedRect,
                frameBitmap = if (includeFrameBitmap) frameBitmap else null,
                maskWidth = result.maskWidth,
                maskHeight = result.maskHeight,
                maskValues = result.maskValues,
            )
        }.getOrElse { error ->
            Log.w(DANMAKU_AI_TAG, "cache persist failed", error)
            null
        }
    }

    private fun buildMaskSignature(result: DanmakuMaskResult): String {
        var hash = 17
        val step = max(1, result.maskValues.size / 160)
        var index = 0
        while (index < result.maskValues.size) {
            val quantized = (result.maskValues[index].coerceIn(0f, 1f) * 15f).roundToInt()
            hash = (hash * 31) + quantized
            index += step
        }
        val rectSignature =
            result.normalizedRect?.let { rect ->
                val x = (rect.x.coerceIn(0f, 1f) * 10_000f).roundToInt()
                val y = (rect.y.coerceIn(0f, 1f) * 10_000f).roundToInt()
                val width = (rect.width.coerceIn(0f, 1f) * 10_000f).roundToInt()
                val height = (rect.height.coerceIn(0f, 1f) * 10_000f).roundToInt()
                "$x,$y,$width,$height"
            } ?: "no_rect"
        return "${result.maskWidth}x${result.maskHeight}|${hash.toUInt().toString(16)}|$rectSignature"
    }

    private fun maybeLogSamplingSlowPath(
        sampleId: Long,
        backend: DanmakuAiBackend,
        captureLatencyMs: Long,
        inferenceLatencyMs: Long?,
        totalLatencyMs: Long,
        reason: String,
    ) {
        val inferenceMs = inferenceLatencyMs ?: -1L
        val shouldLog =
            captureLatencyMs >= DANMAKU_AI_CAPTURE_SLOW_LOG_THRESHOLD_MS ||
                (inferenceLatencyMs != null &&
                    inferenceLatencyMs >= DANMAKU_AI_INFERENCE_SLOW_LOG_THRESHOLD_MS) ||
                totalLatencyMs >= DANMAKU_AI_TOTAL_SLOW_LOG_THRESHOLD_MS
        if (!shouldLog) {
            return
        }
        Log.d(
            DANMAKU_AI_TAG,
            "sample=$sampleId backend=${backend.wireValue} captureMs=$captureLatencyMs inferenceMs=$inferenceMs totalMs=$totalLatencyMs intervalMs=${currentSampleIntervalMs()} reason=$reason",
        )
    }

    private fun currentBackendOrFallback(): DanmakuAiBackend {
        return activeRuntime?.backend
            ?: config.preferredBackendOrder.getOrNull(activeBackendIndex)
            ?: DanmakuAiBackend.DISABLED
    }

    private fun currentSampleIntervalMs(): Long {
        if (sceneCutRecoveryActive && sceneCutBurstSamplesRemaining > 0) {
            return max(
                DANMAKU_AI_SCENE_CUT_BURST_INTERVAL_MS,
                recommendedSamplingFloorMs() / 3L,
            )
        }
        if (motionBurstSamplesRemaining > 0 && shouldAllowMotionBurst()) {
            return currentMotionBurstIntervalMs()
        }
        val runtimeFloorInterval = preferredSampleIntervalMs()
        if (averageLatencyMs <= 0.0) {
            return runtimeFloorInterval
        }
        val latencyBackoff =
            max(
                averageLatencyMs
                    .roundToInt()
                    .toLong() + DANMAKU_AI_SAMPLE_INTERVAL_BACKOFF_HEADROOM_MS,
                (averageLatencyMs * DANMAKU_AI_SAMPLE_INTERVAL_LATENCY_MULTIPLIER)
                    .roundToInt()
                    .toLong(),
            )
        val targetInterval =
            max(
                runtimeFloorInterval,
                latencyBackoff.coerceIn(
                    DANMAKU_AI_MIN_SAMPLE_INTERVAL_MS,
                    DANMAKU_AI_MAX_SAMPLE_INTERVAL_MS,
                ),
            )
        return targetInterval
    }

    private fun recommendedSamplingFloorMs(): Long {
        val targetFrameRateHz = config.renderTargetFrameRateHz
        return when {
            targetFrameRateHz >= 110 -> DANMAKU_AI_HIGH_REFRESH_SAMPLE_INTERVAL_120HZ_MS
            targetFrameRateHz >= 90 -> DANMAKU_AI_HIGH_REFRESH_SAMPLE_INTERVAL_90HZ_MS
            targetFrameRateHz >= 72 -> DANMAKU_AI_HIGH_REFRESH_SAMPLE_INTERVAL_72HZ_MS
            else -> DANMAKU_AI_MIN_SAMPLE_INTERVAL_MS
        }
    }

}
