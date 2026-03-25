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
    private const val DETAIL_HOST_CHANNEL = "fly_player/detail_host"
    private const val PLACEHOLDER_ROUTE = "/parallel/placeholder"
    private const val LARGE_SCREEN_SMALLEST_WIDTH_DP = 600

    @Volatile
    private var engineGroup: FlutterEngineGroup? = null

    fun warmIfEligible(context: Context) {
        detailEngine(context)
    }

    fun detailEngine(context: Context): FlutterEngine? {
        if (!shouldWarmDetailEngine(context)) {
            return null
        }
        synchronized(this) {
            val cache = FlutterEngineCache.getInstance()
            cache.get(DETAIL_ENGINE_ID)?.let { return it }

            val appContext = context.applicationContext
            val group = engineGroup ?: FlutterEngineGroup(appContext).also { engineGroup = it }
            val engine =
                group.createAndRunEngine(
                    appContext,
                    DartExecutor.DartEntrypoint.createDefault(),
                    detailHostInitialRoute(),
                )
            GeneratedPluginRegistrant.registerWith(engine)
            cache.put(DETAIL_ENGINE_ID, engine)
            return engine
        }
    }

    fun hasDetailEngine(): Boolean = FlutterEngineCache.getInstance().contains(DETAIL_ENGINE_ID)

    fun isDetailEngine(engine: FlutterEngine?): Boolean {
        if (engine == null) return false
        return engine === FlutterEngineCache.getInstance().get(DETAIL_ENGINE_ID)
    }

    fun prepareDetailRoute(
        context: Context,
        routeName: String,
    ) {
        val normalizedRoute = routeName.trim()
        if (normalizedRoute.isEmpty()) {
            return
        }
        val engine = detailEngine(context) ?: return
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
