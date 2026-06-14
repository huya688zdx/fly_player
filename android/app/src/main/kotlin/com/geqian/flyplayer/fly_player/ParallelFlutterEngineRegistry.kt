package com.geqian.flyplayer.fly_player

import android.content.Context
import android.content.res.Configuration
import android.net.Uri
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

object ParallelFlutterEngineRegistry {
    private const val DETAIL_ENGINE_ID = "parallel_detail_engine"
    // 原生壳分屏副栏专用的第二个详情引擎：与浏览详情引擎物理隔离，避免两个 DetailActivity
    // 实例抢同一个引擎导致其中一侧黑屏（详见原生壳分屏调试）。
    private const val SPLIT_DETAIL_ENGINE_ID = "parallel_split_detail_engine"
    private const val DETAIL_HOST_CHANNEL = "fly_player/detail_host"
    private const val PLACEHOLDER_ROUTE = "/parallel/placeholder"
    // 副栏可回退到的根（首页浏览），返回键到此再按才收分屏。
    private const val SPLIT_DETAIL_ROOT_ROUTE = "/screen/home"
    private const val LARGE_SCREEN_SMALLEST_WIDTH_DP = 600

    @Volatile
    private var engineGroup: FlutterEngineGroup? = null

    fun warmIfEligible(context: Context) {
        detailEngine(context)
    }

    // ---- 参数化内核（按 engineId 复用同一套创建/路由/生命周期逻辑） ----

    private fun engineFor(
        context: Context,
        engineId: String,
        initialRoute: String,
        force: Boolean = false,
    ): FlutterEngine? {
        // 浏览详情引擎按屏幕尺寸预热（手机不预热）；副栏引擎 force=true 跳过该闸门——
        // 能走到分屏副栏说明播放器侧已用 splitSupported() 确认分屏可用，此时若再用
        // smallestWidthDp>=600 二次否决会自相矛盾：分屏后每半屏 dp 天然 <600，会把
        // 副栏引擎挡成 null → 副栏拿不到引擎 → 黑屏（真机已踩，error.log smallestWidthDp=489）。
        if (!force && !shouldWarmDetailEngine(context)) {
            return null
        }
        synchronized(this) {
            val cache = FlutterEngineCache.getInstance()
            cache.get(engineId)?.let { return it }

            val appContext = context.applicationContext
            val group = engineGroup ?: FlutterEngineGroup(appContext).also { engineGroup = it }
            val engine =
                group.createAndRunEngine(
                    appContext,
                    DartExecutor.DartEntrypoint.createDefault(),
                    initialRoute,
                )
            GeneratedPluginRegistrant.registerWith(engine)
            cache.put(engineId, engine)
            return engine
        }
    }

    private fun prepareRoute(
        context: Context,
        engineId: String,
        routeName: String,
    ) {
        val normalizedRoute = routeName.trim()
        if (normalizedRoute.isEmpty()) {
            return
        }
        // prepareRoute 仅浏览详情引擎在用（副栏走 prepareSplitDetailRoute），故初始路由用通用 host。
        val engine = engineFor(context, engineId, detailHostInitialRoute()) ?: return
        resumeEngine(engine)
        MethodChannel(
            engine.dartExecutor.binaryMessenger,
            DETAIL_HOST_CHANNEL,
        ).invokeMethod(
            "replaceRoute",
            mapOf(
                "routeName" to normalizedRoute,
                "resetStack" to true,
            ),
        )
    }

    private fun resetRouteToPlaceholder(engineId: String) {
        val engine = FlutterEngineCache.getInstance().get(engineId) ?: return
        MethodChannel(
            engine.dartExecutor.binaryMessenger,
            DETAIL_HOST_CHANNEL,
        ).invokeMethod(
            "replaceRoute",
            mapOf(
                "routeName" to PLACEHOLDER_ROUTE,
                "resetStack" to true,
            ),
            object : MethodChannel.Result {
                override fun success(result: Any?) = pauseEngine(engine)

                override fun error(
                    errorCode: String,
                    errorMessage: String?,
                    errorDetails: Any?,
                ) = pauseEngine(engine)

                override fun notImplemented() = pauseEngine(engine)
            },
        )
    }

    // ---- 浏览详情引擎（原有公开 API，保持不变，委派内核） ----

    fun detailEngine(context: Context): FlutterEngine? =
        engineFor(context, DETAIL_ENGINE_ID, detailHostInitialRoute())

    fun hasDetailEngine(): Boolean = FlutterEngineCache.getInstance().contains(DETAIL_ENGINE_ID)

    fun isDetailEngine(engine: FlutterEngine?): Boolean {
        if (engine == null) return false
        return engine === FlutterEngineCache.getInstance().get(DETAIL_ENGINE_ID)
    }

    fun prepareDetailRoute(
        context: Context,
        routeName: String,
    ) = prepareRoute(context, DETAIL_ENGINE_ID, routeName)

    fun resetDetailRouteToPlaceholder() = resetRouteToPlaceholder(DETAIL_ENGINE_ID)

    fun resumeDetailEngine() {
        FlutterEngineCache.getInstance().get(DETAIL_ENGINE_ID)?.let(::resumeEngine)
    }

    // ---- 分屏副栏详情引擎（第二引擎，独立于浏览详情） ----

    fun splitDetailEngine(context: Context): FlutterEngine? =
        engineFor(
            context,
            SPLIT_DETAIL_ENGINE_ID,
            splitDetailHostInitialRoute(PLACEHOLDER_ROUTE),
            force = true,
        )

    fun hasSplitDetailEngine(): Boolean =
        FlutterEngineCache.getInstance().contains(SPLIT_DETAIL_ENGINE_ID)

    fun isSplitDetailEngine(engine: FlutterEngine?): Boolean {
        if (engine == null) return false
        return engine === FlutterEngineCache.getInstance().get(SPLIT_DETAIL_ENGINE_ID)
    }

    /**
     * 副栏（第二引擎）路由：首次直接以"详情 + root=/screen/home"作为引擎初始路由，
     * 这样初始栈即 [首页, 详情]，返回键可先回首页再收分屏；且避开 createAndRunEngine 后
     * 立刻 replaceRoute 时 Dart handler 未就绪丢消息的竞态。引擎已存在则走 replaceRoute。
     */
    fun prepareSplitDetailRoute(
        context: Context,
        routeName: String,
    ) {
        val normalizedRoute = routeName.trim()
        if (normalizedRoute.isEmpty()) return
        val existing = FlutterEngineCache.getInstance().get(SPLIT_DETAIL_ENGINE_ID)
        if (existing == null) {
            engineFor(
                context,
                SPLIT_DETAIL_ENGINE_ID,
                splitDetailHostInitialRoute(normalizedRoute),
                force = true,
            )
            return
        }
        resumeEngine(existing)
        // 复用引擎时显式重建整条栈为 [首页, 详情]：Navigator 有两页，返回逐层回退(详情→首页→收分屏)，
        // 与首次新建的初始栈一致；避免只设单页 [详情] 导致返回直接收掉分屏。
        MethodChannel(
            existing.dartExecutor.binaryMessenger,
            DETAIL_HOST_CHANNEL,
        ).invokeMethod(
            "setRouteStack",
            mapOf("routeNames" to listOf(SPLIT_DETAIL_ROOT_ROUTE, normalizedRoute)),
        )
    }

    fun resetSplitDetailRouteToPlaceholder() = resetRouteToPlaceholder(SPLIT_DETAIL_ENGINE_ID)

    /** 副栏 host 初始路由：把子路由包进 /detail/host，并带 root=/screen/home（可回退到首页）。 */
    private fun splitDetailHostInitialRoute(childRoute: String): String =
        Uri
            .Builder()
            .path("/detail/host")
            .appendQueryParameter("route", childRoute.trim())
            .appendQueryParameter("root", SPLIT_DETAIL_ROOT_ROUTE)
            .build()
            .toString()

    fun resumeSplitDetailEngine() {
        FlutterEngineCache.getInstance().get(SPLIT_DETAIL_ENGINE_ID)?.let(::resumeEngine)
    }

    private fun resumeEngine(engine: FlutterEngine) {
        engine.lifecycleChannel.appIsResumed()
    }

    private fun pauseEngine(engine: FlutterEngine) {
        engine.lifecycleChannel.appIsPaused()
    }

    fun detailHostInitialRoute(): String =
        Uri
            .Builder()
            .path("/detail/host")
            .appendQueryParameter("route", PLACEHOLDER_ROUTE)
            .build()
            .toString()

    private fun shouldWarmDetailEngine(context: Context): Boolean {
        val configuration = context.applicationContext.resources.configuration
        return configuration.smallestScreenWidthDp >= LARGE_SCREEN_SMALLEST_WIDTH_DP ||
            configuration.screenLayout and Configuration.SCREENLAYOUT_SIZE_MASK >=
            Configuration.SCREENLAYOUT_SIZE_LARGE
    }
}
