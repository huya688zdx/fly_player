package com.geqian.flyplayer.fly_player

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import io.flutter.embedding.android.FlutterActivityLaunchConfigs
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import org.json.JSONObject

class DetailActivity : FlutterHostActivity() {
    /** 本实例是否为原生壳分屏副栏（用第二引擎）。由启动 Intent 的 extra 决定，全生命周期不变。 */
    private val useSplitEngine: Boolean
        get() = intent?.getBooleanExtra(EXTRA_USE_SPLIT_ENGINE, false) == true

    // 预测式返回(API33+/targetSdk35)回调；用 Any? 持有，旧设备不加载该 API 类型。
    private var backInvokedCallback: Any? = null

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
        registerBackHandler()
    }

    // 详情/副栏的系统返回：先委派 Flutter 在本 pane 导航栈内逐层回退(详情→…→首页/root)，
    // 弹不动了才 finish(收掉本详情/分屏副栏)。否则在 targetSdk35 预测式返回下，系统会直接
    // finish 本 Activity、绕过 Flutter 的 PopScope，导致"分屏里一按返回就收掉副栏"。
    private fun handleDetailBack() {
        requestPopInPane { popped ->
            if (!popped && !isFinishing) {
                finish()
            }
        }
    }

    /** 旧设备(API<33 或未启用预测式返回)走经典 onBackPressed。 */
    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        handleDetailBack()
    }

    private fun registerBackHandler() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (backInvokedCallback != null) return
        val callback = OnBackInvokedCallback { handleDetailBack() }
        backInvokedCallback = callback
        onBackInvokedDispatcher.registerOnBackInvokedCallback(
            OnBackInvokedDispatcher.PRIORITY_DEFAULT,
            callback,
        )
    }

    private fun unregisterBackHandler() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        (backInvokedCallback as? OnBackInvokedCallback)?.let {
            onBackInvokedDispatcher.unregisterOnBackInvokedCallback(it)
        }
        backInvokedCallback = null
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
        if (ParallelWindowCoordinator.isNativeSplitPlayerVisible()) {
            ParallelWindowCoordinator.activePlayerSecondaryPaneSide()
        } else {
            ParallelWindowCoordinator.preferredSecondaryPaneSide()
        }

    override fun hostRoleOverride(): ParallelHostRole? =
        if (ParallelWindowCoordinator.isNativeSplitPlayerVisible()) {
            ParallelHostRole.SECONDARY
        } else {
            null
        }

    override fun onDestroy() {
        unregisterBackHandler()
        if (isFinishing) {
            if (useSplitEngine) {
                // 保留副栏第二引擎(热)**及其导航栈/已加载页面**，仅暂停；下次进分屏若目标条目
                // 未变即零重建复用(不再重新加载/闪烁)，条目变了才由 prepareSplitDetailRoute 重建。
                ParallelWindowCoordinator.detachSplitDetailHost(this)
                ParallelFlutterEngineRegistry.pauseSplitDetailEngine()
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
