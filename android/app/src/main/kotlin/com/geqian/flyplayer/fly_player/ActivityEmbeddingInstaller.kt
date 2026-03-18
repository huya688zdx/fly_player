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
                        ActivityFilter(
                            ComponentName(context, PlayerActivity::class.java),
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
                        fullscreenPlayerRule,
                    ),
                )
        }.onFailure { error ->
            installed.set(false)
            Log.w(TAG, "Failed to install activity embedding rules", error)
        }
    }
}
