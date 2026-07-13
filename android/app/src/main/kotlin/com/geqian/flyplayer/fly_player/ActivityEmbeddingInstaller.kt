package com.geqian.flyplayer.fly_player

import android.content.ComponentName
import android.content.Context
import android.util.Log
import androidx.window.embedding.ActivityFilter
import androidx.window.embedding.ActivityRule
import androidx.window.embedding.EmbeddingAnimationBackground
import androidx.window.embedding.EmbeddingAnimationParams
import androidx.window.embedding.EmbeddingAspectRatio
import androidx.window.embedding.RuleController
import androidx.window.embedding.SplitAttributes
import androidx.window.embedding.SplitPairFilter
import androidx.window.embedding.SplitPairRule
import androidx.window.embedding.SplitRule
import java.util.concurrent.atomic.AtomicBoolean

object ActivityEmbeddingInstaller {
    private const val TAG = "ActivityEmbedding"
    private val installed = AtomicBoolean(false)

    // 分屏规则的宽度阈值：AE 仅当「容器宽 ≥ MIN_WIDTH_DP 且 最小宽 ≥ MIN_SMALLEST_WIDTH_DP」
    // 时才真正并排。NativePlayerActivity.splitSupported() 必须用同一组阈值 gate，否则手机/
    // 折叠屏外屏/窄多窗口下宽度不足时 AE 不分屏，startActivity(detail) 会把副栏盖在播放器上、
    // 播放退后台（手机端实测 bug）。两处同源，避免漂移。
    const val MIN_WIDTH_DP = 840
    const val MIN_SMALLEST_WIDTH_DP = 600

    fun install(
        context: Context,
        force: Boolean = false,
    ) {
        if (!force && !installed.compareAndSet(false, true)) return
        if (force) {
            installed.set(true)
        }

        val preferredPrimaryOnRight =
            ParallelWindowCoordinator.preferredPrimaryPaneSide() == ParallelPaneSide.RIGHT
        val browsePrimaryRatio = ParallelWindowCoordinator.browsePrimaryRatio()
        val standardLayoutDirection =
            if (preferredPrimaryOnRight) {
                SplitAttributes.LayoutDirection.RIGHT_TO_LEFT
            } else {
                SplitAttributes.LayoutDirection.LOCALE
            }

        val splitAttributes =
            SplitAttributes
                .Builder()
                .setSplitType(SplitAttributes.SplitType.ratio(browsePrimaryRatio))
                .setLayoutDirection(standardLayoutDirection)
                .build()

        val splitPairRule =
            SplitPairRule
                .Builder(
                    setOf(
                        SplitPairFilter(
                            ComponentName(context, MainActivity::class.java),
                            ComponentName(context, DetailActivity::class.java),
                            null,
                        ),
                    ),
                ).setDefaultSplitAttributes(splitAttributes)
                .setMinWidthDp(MIN_WIDTH_DP)
                .setMinSmallestWidthDp(MIN_SMALLEST_WIDTH_DP)
                .setMaxAspectRatioInPortrait(EmbeddingAspectRatio.ratio(1.5f))
                .setFinishPrimaryWithSecondary(SplitRule.FinishBehavior.NEVER)
                .setFinishSecondaryWithPrimary(SplitRule.FinishBehavior.ALWAYS)
                .setClearTop(false)
                .build()

        // 原生壳分屏：NativePlayerActivity(primary, 占播放主侧) + DetailActivity(secondary, 浏览栏)。
        val playbackPrimaryOnRight =
            ParallelWindowCoordinator.preferredPlaybackPrimaryPaneSide() == ParallelPaneSide.RIGHT
        val playbackLayoutDirection =
            if (playbackPrimaryOnRight) {
                SplitAttributes.LayoutDirection.RIGHT_TO_LEFT
            } else {
                SplitAttributes.LayoutDirection.LOCALE
            }
        val nativePlayerSplitAttributes =
            SplitAttributes
                .Builder()
                .setSplitType(
                    SplitAttributes.SplitType.ratio(ParallelWindowCoordinator.playerPrimaryRatio()),
                ).setLayoutDirection(playbackLayoutDirection)
                // 禁用分屏开/关/变更动画(JUMP_CUT 零时长)，彻底去掉全屏↔分屏切换时的"先黑+滑入"；
                // 背景仍设黑兜底。需 androidx.window 1.5.0+。
                .setAnimationParams(
                    EmbeddingAnimationParams
                        .Builder()
                        .setAnimationBackground(
                            EmbeddingAnimationBackground.createColorBackground(0xFF000000.toInt()),
                        ).setOpenAnimation(EmbeddingAnimationParams.AnimationSpec.JUMP_CUT)
                        .setCloseAnimation(EmbeddingAnimationParams.AnimationSpec.JUMP_CUT)
                        .setChangeAnimation(EmbeddingAnimationParams.AnimationSpec.JUMP_CUT)
                        .build(),
                ).build()
        val nativePlayerSplitRule =
            SplitPairRule
                .Builder(
                    setOf(
                        SplitPairFilter(
                            ComponentName(context, NativePlayerActivity::class.java),
                            ComponentName(context, DetailActivity::class.java),
                            null,
                        ),
                    ),
                ).setDefaultSplitAttributes(nativePlayerSplitAttributes)
                .setMinWidthDp(MIN_WIDTH_DP)
                .setMinSmallestWidthDp(MIN_SMALLEST_WIDTH_DP)
                .setMaxAspectRatioInPortrait(EmbeddingAspectRatio.ratio(1.5f))
                // 关副栏(secondary)不收播放栏 → 回退全屏；退播放栏(primary)一并收副栏。
                .setFinishPrimaryWithSecondary(SplitRule.FinishBehavior.NEVER)
                .setFinishSecondaryWithPrimary(SplitRule.FinishBehavior.ALWAYS)
                .setClearTop(false)
                .build()

        val fullscreenScreenshotRule =
            ActivityRule
                .Builder(
                    setOf(
                        ActivityFilter(
                            ComponentName(context, FullscreenScreenshotActivity::class.java),
                            null,
                        ),
                    ),
                ).setAlwaysExpand(true)
                .build()

        runCatching {
            RuleController
                .getInstance(context)
                .setRules(
                    setOf(
                        splitPairRule,
                        nativePlayerSplitRule,
                        fullscreenScreenshotRule,
                    ),
                )
        }.onFailure { error ->
            installed.set(false)
            Log.w(TAG, "Failed to install activity embedding rules", error)
        }
    }
}
