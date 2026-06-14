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
    /** 本实例是否为原生壳分屏副栏（用第二引擎）。由启动 Intent 的 extra 决定，全生命周期不变。 */
    private val useSplitEngine: Boolean
        get() = intent?.getBooleanExtra(EXTRA_USE_SPLIT_ENGINE, false) == true

    private fun wrappedInitialRoute(routeName: String): String {
        return Uri
            .Builder()
            .path("/detail/host")
            .appendQueryParameter("route", routeName.trim())
            .build()
            .toString()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        if (useSplitEngine) {
            ParallelFlutterEngineRegistry.prepareSplitDetailRoute(
                applicationContext,
                intentToInitialRoute(intent),
            )
            super.onCreate(savedInstanceState)
            // 分屏副栏：只登记到 split host，不污染浏览详情/右栏的跟踪。
            ParallelWindowCoordinator.attachSplitDetailHost(this)
            Log.d("NativePlayerSplit", "detail onCreate SPLIT branch attach this=${System.identityHashCode(this)}")
            return
        }
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
        if (useSplitEngine) {
            ParallelFlutterEngineRegistry.prepareSplitDetailRoute(
                applicationContext,
                intentToInitialRoute(intent),
            )
            super.onNewIntent(intent)
            setIntent(intent)
            return
        }
        ParallelFlutterEngineRegistry.prepareDetailRoute(
            applicationContext,
            intentToInitialRoute(intent),
        )
        super.onNewIntent(intent)
        setIntent(intent)
        ParallelWindowCoordinator.updateCurrentDetailRoute(intentToInitialRoute(intent))
    }

    override fun onResume() {
        if (useSplitEngine) {
            ParallelFlutterEngineRegistry.resumeSplitDetailEngine()
        } else {
            ParallelFlutterEngineRegistry.resumeDetailEngine()
        }
        super.onResume()
    }

    override fun getInitialRoute(): String {
        return wrappedInitialRoute(intentToInitialRoute(intent))
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return if (useSplitEngine) {
            ParallelFlutterEngineRegistry.splitDetailEngine(context) ?: super.provideFlutterEngine(context)
        } else {
            ParallelFlutterEngineRegistry.detailEngine(context) ?: super.provideFlutterEngine(context)
        }
    }

    override fun shouldDestroyEngineWithHost(): Boolean {
        return if (useSplitEngine) {
            !ParallelFlutterEngineRegistry.hasSplitDetailEngine()
        } else {
            !ParallelFlutterEngineRegistry.hasDetailEngine()
        }
    }

    override fun getRenderMode(): RenderMode = RenderMode.texture

    override fun getBackgroundMode(): FlutterActivityLaunchConfigs.BackgroundMode =
        FlutterActivityLaunchConfigs.BackgroundMode.opaque

    override fun shouldSkipBaseFlutterEngineConfiguration(
        flutterEngine: FlutterEngine,
    ): Boolean =
        ParallelFlutterEngineRegistry.isDetailEngine(flutterEngine) ||
            ParallelFlutterEngineRegistry.isSplitDetailEngine(flutterEngine)

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
            if (useSplitEngine) {
                // 保留副栏第二引擎(热)，仅重置为占位并暂停；下次进分屏复用、不冷启黑屏。
                ParallelWindowCoordinator.detachSplitDetailHost(this)
                ParallelFlutterEngineRegistry.resetSplitDetailRouteToPlaceholder()
            } else {
                ParallelWindowCoordinator.detachDetailHost(this)
                ParallelWindowCoordinator.detachRightPaneHost(this)
                ParallelWindowCoordinator.clearRightPane()
                ParallelFlutterEngineRegistry.resetDetailRouteToPlaceholder()
            }
        }
        super.onDestroy()
    }

    /** 分屏副栏：点条目时在本副栏 host 内就地 push（不启动新 Activity、不污染浏览详情状态）。 */
    override fun handleSplitSecondaryInPlace(routeName: String): Boolean {
        if (!useSplitEngine) return false
        val normalizedRoute = routeName.trim()
        if (normalizedRoute.isEmpty()) return false
        Log.d("DetailActivity", "split secondary in-place route=$normalizedRoute")
        detailHostChannel?.invokeMethod(
            "replaceRoute",
            mapOf("routeName" to normalizedRoute, "resetStack" to false),
        )
        return true
    }

    /** 分屏副栏：请求副栏在自己的导航栈里回退一层；回调 true=已回退，false=已在根(首页)。 */
    fun requestPopInPane(onResult: (Boolean) -> Unit) {
        val channel = detailHostChannel
        if (channel == null) {
            onResult(false)
            return
        }
        channel.invokeMethod(
            "popInPane",
            null,
            object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) = onResult(result == true)

                override fun error(code: String, message: String?, details: Any?) = onResult(false)

                override fun notImplemented() = onResult(false)
            },
        )
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
        // true → 用分屏副栏专用的第二个 Flutter 引擎（原生壳分屏用），与浏览详情引擎物理隔离。
        const val EXTRA_USE_SPLIT_ENGINE = "use_split_engine"

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

        /** 原生壳分屏副栏：用第二引擎承载详情，避免抢占浏览详情引擎。 */
        fun createSplitIntent(
            context: Context,
            routeName: String,
        ): Intent {
            return createRouteIntent(context, routeName).apply {
                putExtra(EXTRA_USE_SPLIT_ENGINE, true)
            }
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
