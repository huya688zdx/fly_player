package com.geqian.flyplayer.fly_player

import android.content.ComponentName
import android.content.Context
import android.util.Log
import androidx.window.embedding.ActivityFilter
import androidx.window.embedding.ActivityRule
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
        val preferredPlaybackPrimaryOnRight =
            ParallelWindowCoordinator.preferredPlaybackPrimaryPaneSide() == ParallelPaneSide.RIGHT
        val browsePrimaryRatio = ParallelWindowCoordinator.browsePrimaryRatio()
        val playerPrimaryRatio = ParallelWindowCoordinator.playerPrimaryRatio()
        val standardLayoutDirection =
            if (preferredPrimaryOnRight) {
                SplitAttributes.LayoutDirection.RIGHT_TO_LEFT
            } else {
                SplitAttributes.LayoutDirection.LOCALE
            }
        val attachPlayerLayoutDirection =
            if (preferredPlaybackPrimaryOnRight) {
                SplitAttributes.LayoutDirection.LOCALE
            } else {
                SplitAttributes.LayoutDirection.RIGHT_TO_LEFT
            }

        val splitAttributes =
            SplitAttributes
                .Builder()
                .setSplitType(SplitAttributes.SplitType.ratio(browsePrimaryRatio))
                .setLayoutDirection(standardLayoutDirection)
                .build()

        val attachPlayerSplitAttributes =
            SplitAttributes
                .Builder()
                .setSplitType(SplitAttributes.SplitType.ratio(playerPrimaryRatio))
                .setLayoutDirection(attachPlayerLayoutDirection)
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
                .setMinWidthDp(840)
                .setMinSmallestWidthDp(600)
                .setMaxAspectRatioInPortrait(EmbeddingAspectRatio.ratio(1.5f))
                .setFinishPrimaryWithSecondary(SplitRule.FinishBehavior.NEVER)
                .setFinishSecondaryWithPrimary(SplitRule.FinishBehavior.ALWAYS)
                .setClearTop(false)
                .build()

        val playerSplitRule =
            SplitPairRule
                .Builder(
                    setOf(
                        SplitPairFilter(
                            ComponentName(context, DetailActivity::class.java),
                            ComponentName(context, PlayerActivity::class.java),
                            PlayerLaunchContract.ACTION_SPLIT_PLAYER,
                        ),
                    ),
                ).setDefaultSplitAttributes(splitAttributes)
                .setMinWidthDp(840)
                .setMinSmallestWidthDp(600)
                .setMaxAspectRatioInPortrait(EmbeddingAspectRatio.ratio(1.5f))
                .setFinishPrimaryWithSecondary(SplitRule.FinishBehavior.NEVER)
                .setFinishSecondaryWithPrimary(SplitRule.FinishBehavior.NEVER)
                .setClearTop(false)
                .build()

        val homePlayerSplitRule =
            SplitPairRule
                .Builder(
                    setOf(
                        SplitPairFilter(
                            ComponentName(context, MainActivity::class.java),
                            ComponentName(context, PlayerActivity::class.java),
                            PlayerLaunchContract.ACTION_SPLIT_PLAYER,
                        ),
                    ),
                ).setDefaultSplitAttributes(splitAttributes)
                .setMinWidthDp(840)
                .setMinSmallestWidthDp(600)
                .setMaxAspectRatioInPortrait(EmbeddingAspectRatio.ratio(1.5f))
                .setFinishPrimaryWithSecondary(SplitRule.FinishBehavior.NEVER)
                .setFinishSecondaryWithPrimary(SplitRule.FinishBehavior.NEVER)
                .setClearTop(false)
                .build()

        val playerDetailSplitRule =
            SplitPairRule
                .Builder(
                    setOf(
                        SplitPairFilter(
                            ComponentName(context, PlayerActivity::class.java),
                            ComponentName(context, DetailActivity::class.java),
                            PlayerLaunchContract.ACTION_ATTACH_DETAIL_TO_PLAYER,
                        ),
                    ),
                ).setDefaultSplitAttributes(attachPlayerSplitAttributes)
                .setMinWidthDp(840)
                .setMinSmallestWidthDp(600)
                .setMaxAspectRatioInPortrait(EmbeddingAspectRatio.ratio(1.5f))
                .setFinishPrimaryWithSecondary(SplitRule.FinishBehavior.NEVER)
                .setFinishSecondaryWithPrimary(SplitRule.FinishBehavior.ALWAYS)
                .setClearTop(false)
                .build()

        val playerHomeSplitRule =
            SplitPairRule
                .Builder(
                    setOf(
                        SplitPairFilter(
                            ComponentName(context, PlayerActivity::class.java),
                            ComponentName(context, HomePaneActivity::class.java),
                            "com.geqian.flyplayer.fly_player.action.ATTACH_HOME_TO_PLAYER",
                        ),
                    ),
                ).setDefaultSplitAttributes(attachPlayerSplitAttributes)
                .setMinWidthDp(840)
                .setMinSmallestWidthDp(600)
                .setMaxAspectRatioInPortrait(EmbeddingAspectRatio.ratio(1.5f))
                .setFinishPrimaryWithSecondary(SplitRule.FinishBehavior.NEVER)
                .setFinishSecondaryWithPrimary(SplitRule.FinishBehavior.ALWAYS)
                .setClearTop(false)
                .build()

        val fullscreenPlayerRule =
            ActivityRule
                .Builder(
                    setOf(
                        androidx.window.embedding.ActivityFilter(
                            ComponentName(context, PlayerActivity::class.java),
                            PlayerLaunchContract.ACTION_FULLSCREEN_PLAYER,
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
                        playerSplitRule,
                        homePlayerSplitRule,
                        playerDetailSplitRule,
                        playerHomeSplitRule,
                        fullscreenPlayerRule,
                    ),
                )
        }.onFailure { error ->
            installed.set(false)
            Log.w(TAG, "Failed to install activity embedding rules", error)
        }
    }
}
