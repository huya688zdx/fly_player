package com.geqian.flyplayer.fly_player

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivityLaunchConfigs
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import org.json.JSONObject

class DetailActivity : FlutterHostActivity() {
    private fun wrappedInitialRoute(routeName: String): String {
        return Uri
            .Builder()
            .path("/detail/host")
            .appendQueryParameter("route", routeName.trim())
            .build()
            .toString()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        ParallelFlutterEngineRegistry.prepareDetailRoute(
            applicationContext,
            intentToInitialRoute(intent),
        )
        super.onCreate(savedInstanceState)
        ParallelWindowCoordinator.updateCurrentDetailRoute(intentToInitialRoute(intent))
        ParallelWindowCoordinator.attachDetailHost(this)
        ParallelWindowCoordinator.attachRightPaneHost(this)
    }

    override fun onNewIntent(intent: Intent) {
        ParallelFlutterEngineRegistry.prepareDetailRoute(
            applicationContext,
            intentToInitialRoute(intent),
        )
        super.onNewIntent(intent)
        setIntent(intent)
        ParallelWindowCoordinator.updateCurrentDetailRoute(intentToInitialRoute(intent))
    }

    override fun onResume() {
        ParallelFlutterEngineRegistry.resumeDetailEngine()
        super.onResume()
    }

    override fun getInitialRoute(): String {
        return wrappedInitialRoute(intentToInitialRoute(intent))
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return ParallelFlutterEngineRegistry.detailEngine(context) ?: super.provideFlutterEngine(context)
    }

    override fun shouldDestroyEngineWithHost(): Boolean {
        return !ParallelFlutterEngineRegistry.hasDetailEngine()
    }

    override fun getRenderMode(): RenderMode = RenderMode.texture

    override fun getBackgroundMode(): FlutterActivityLaunchConfigs.BackgroundMode =
        FlutterActivityLaunchConfigs.BackgroundMode.opaque

    override fun shouldSkipBaseFlutterEngineConfiguration(
        flutterEngine: FlutterEngine,
    ): Boolean = ParallelFlutterEngineRegistry.isDetailEngine(flutterEngine)

    override fun hostSurface(): String = "detail"

    override fun hostPaneSide(): ParallelPaneSide =
        if (ParallelWindowCoordinator.isSplitPlayerVisible()) {
            ParallelWindowCoordinator.activePlayerSecondaryPaneSide()
        } else {
            ParallelWindowCoordinator.preferredSecondaryPaneSide()
        }

    override fun hostRoleOverride(): ParallelHostRole? =
        if (ParallelWindowCoordinator.isSplitPlayerVisible()) {
            ParallelHostRole.SECONDARY
        } else {
            null
        }

    override fun onDestroy() {
        if (isFinishing) {
            ParallelWindowCoordinator.detachDetailHost(this)
            ParallelWindowCoordinator.detachRightPaneHost(this)
            ParallelWindowCoordinator.clearRightPane()
            ParallelFlutterEngineRegistry.resetDetailRouteToPlaceholder()
        }
        super.onDestroy()
    }

    fun replaceRouteInPlace(routeName: String): Boolean {
        val normalizedRoute = routeName.trim()
        if (normalizedRoute.isEmpty()) return false
        ParallelWindowCoordinator.updateCurrentDetailRoute(normalizedRoute)
        val parsedUri = Uri.parse(normalizedRoute)
        parsedUri.getQueryParameter("itemGuid")?.trim()?.takeIf { it.isNotEmpty() }?.let { itemGuid ->
            ParallelWindowCoordinator.updateCurrentDetailItemGuid(itemGuid)
        }
        parsedUri.getQueryParameter("personGuid")?.trim()?.takeIf { it.isNotEmpty() }?.let { personGuid ->
            ParallelWindowCoordinator.updateCurrentDetailItemGuid(personGuid)
        }
        Log.d("DetailActivity", "replaceRouteInPlace route=$normalizedRoute")
        detailHostChannel?.invokeMethod(
            "replaceRoute",
            mapOf(
                "routeName" to normalizedRoute,
                "resetStack" to false,
            ),
        )
        return true
    }

    fun launchSplitPlayer(
        title: String,
        source: HashMap<String, Any?>,
        initialPlayInfo: HashMap<String, Any?>? = null,
        startSource: String = "manual",
    ) {
        startActivity(
            PlayerActivity.createIntent(
                context = this,
                title = title,
                source = source,
                initialPlayInfo = initialPlayInfo?.let { HashMap(it) },
                startSource = startSource,
                fromParallelHost = true,
                hostContext = getParallelHostContext(),
                layoutMode = PlayerLaunchContract.MODE_SPLIT,
            ),
        )
    }

    companion object {
        private const val EXTRA_INITIAL_ROUTE = "initial_route"

        fun createIntent(
            context: Context,
            itemGuid: String,
        ): Intent {
            return createRouteIntent(
                context,
                Uri
                    .Builder()
                    .path("/detail/item")
                    .appendQueryParameter("itemGuid", itemGuid.trim())
                    .build()
                    .toString(),
            )
        }

        fun createRouteIntent(
            context: Context,
            routeName: String,
        ): Intent {
            return Intent(context, DetailActivity::class.java).apply {
                putExtra(EXTRA_INITIAL_ROUTE, routeName.trim())
            }
        }

        fun createResumeIntent(
            context: Context,
            routeName: String,
        ): Intent {
            return createRouteIntent(context, routeName).apply {
                addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
        }

        fun createAttachToPlayerIntent(
            context: Context,
            routeName: String,
        ): Intent {
            return createResumeIntent(context, routeName).apply {
                action = PlayerLaunchContract.ACTION_ATTACH_DETAIL_TO_PLAYER
            }
        }

        fun createSeasonIntent(
            context: Context,
            parentGuid: String,
            seriesTitle: String,
            backdropPath: String,
            seasonItem: HashMap<String, Any?>,
        ): Intent {
            return createRouteIntent(
                context,
                Uri
                    .Builder()
                    .path("/detail/season")
                    .appendQueryParameter("parentGuid", parentGuid.trim())
                    .appendQueryParameter("seriesTitle", seriesTitle.trim())
                    .appendQueryParameter("backdropPath", backdropPath.trim())
                    .appendQueryParameter(
                        "seasonItem",
                        JSONObject(seasonItem as Map<*, *>).toString(),
                    ).build()
                    .toString(),
            )
        }

        private fun intentToInitialRoute(intent: Intent?): String {
            return intent?.getStringExtra(EXTRA_INITIAL_ROUTE)?.trim().orEmpty().ifEmpty { "/" }
        }
    }
}
