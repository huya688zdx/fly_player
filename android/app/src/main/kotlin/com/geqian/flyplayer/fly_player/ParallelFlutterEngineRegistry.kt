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

    // 副栏第二引擎当前已构建的目标路由。用于「再次进分屏时若目标条目未变 → 保留已加载的
    // 导航栈、不重建」，从而避免每次进分屏副栏都重新加载/闪烁。引擎被销毁(注销/低内存)后
    // 会在重建分支重新落值。
    @Volatile
    private var lastSplitDetailRoute: String = ""

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
            registerBootstrapSecretStoreChannel(appContext, engine)
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
            lastSplitDetailRoute = normalizedRoute
            engineFor(
                context,
                SPLIT_DETAIL_ENGINE_ID,
                splitDetailHostInitialRoute(normalizedRoute),
                force = true,
            )
            return
        }
        resumeEngine(existing)
        // 目标条目未变：副栏已加载的导航栈(首页+详情，含此前的浏览)还活着(退分屏只暂停不重置)，
        // 直接复用、不重建 → 不重新加载、不闪。仅 resume 让其重新上屏即可。
        if (isSameSplitTarget(lastSplitDetailRoute, normalizedRoute)) {
            return
        }
        // 目标条目变了(在播条目不同/换片)：重建整条栈为 [首页, 详情]，Navigator 两页可逐层回退
        // (详情→首页→收分屏)，与首次新建一致；避免只设单页 [详情] 导致返回直接收掉分屏。
        lastSplitDetailRoute = normalizedRoute
        MethodChannel(
            existing.dartExecutor.binaryMessenger,
            DETAIL_HOST_CHANNEL,
        ).invokeMethod(
            "setRouteStack",
            mapOf("routeNames" to listOf(SPLIT_DETAIL_ROOT_ROUTE, normalizedRoute)),
        )
    }

    /** 两条副栏目标路由是否指向同一条目：优先比 itemGuid/parentGuid/personGuid，回退整串比较。 */
    private fun isSameSplitTarget(
        previous: String,
        next: String,
    ): Boolean {
        val prev = previous.trim()
        val cur = next.trim()
        if (prev.isEmpty() || cur.isEmpty()) return false
        if (prev == cur) return true
        val prevUri = runCatching { Uri.parse(prev) }.getOrNull() ?: return false
        val curUri = runCatching { Uri.parse(cur) }.getOrNull() ?: return false
        if (prevUri.path?.trim() != curUri.path?.trim()) return false
        for (key in listOf("itemGuid", "parentGuid", "personGuid", "seasonGuid")) {
            val a = prevUri.getQueryParameter(key)?.trim().orEmpty()
            val b = curUri.getQueryParameter(key)?.trim().orEmpty()
            if (a.isNotEmpty() || b.isNotEmpty()) {
                return a == b
            }
        }
        return false
    }

    /**
     * 注销/重置时调用：把副栏第二引擎重置成占位页并清空目标跟踪，丢弃上一账号已加载的详情，
     * 避免 [pauseSplitDetailEngine] 的保活把旧会话内容残留到下次进分屏。
     */
    fun resetSplitDetailRouteToPlaceholder() {
        lastSplitDetailRoute = ""
        resetRouteToPlaceholder(SPLIT_DETAIL_ENGINE_ID)
    }

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

    /**
     * 退分屏时调用：仅暂停副栏第二引擎、**保留其导航栈与已加载页面**(不重置成占位页)，
     * 下次进分屏若目标条目未变即可零重建复用([prepareSplitDetailRoute] 会跳过 setRouteStack)。
     */
    fun pauseSplitDetailEngine() {
        FlutterEngineCache.getInstance().get(SPLIT_DETAIL_ENGINE_ID)?.let(::pauseEngine)
    }

    /**
     * 引擎创建即注册 secret_store：createAndRunEngine 后 Dart 立刻开跑，会话
     * Provider 的启动加载会在宿主 Activity attach（configureFlutterEngine）之前
     * 读写凭证——通道缺席时 delete 抛 MissingPlugin 炸掉整次会话加载，分屏详情
     * 首开直接落在「加载失败」（真机实锤）。此处注册与主线程同一连续段内完成，
     * Dart 消息不可能先于它被派发；attach 后宿主的同名 handler 原位替换，语义一致。
     */
    private fun registerBootstrapSecretStoreChannel(
        appContext: Context,
        engine: FlutterEngine,
    ) {
        val danDanPlaySecretStore = DanDanPlaySecretStore(appContext)
        val secureCredentialStore = SecureCredentialStore(appContext)
        MethodChannel(
            engine.dartExecutor.binaryMessenger,
            "fly_player/secret_store",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDanDanPlayConfig" -> result.success(danDanPlaySecretStore.getConfig())
                "clearDanDanPlayConfig" -> result.success(danDanPlaySecretStore.clearConfig())
                "readCredential" -> {
                    val key = call.argument<String>("key").orEmpty()
                    result.success(secureCredentialStore.read(key))
                }
                "writeCredential" -> {
                    val key = call.argument<String>("key").orEmpty()
                    val value = call.argument<String>("value").orEmpty()
                    result.success(secureCredentialStore.write(key, value))
                }
                "deleteCredential" -> {
                    val key = call.argument<String>("key").orEmpty()
                    result.success(secureCredentialStore.delete(key))
                }
                else -> result.notImplemented()
            }
        }
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
