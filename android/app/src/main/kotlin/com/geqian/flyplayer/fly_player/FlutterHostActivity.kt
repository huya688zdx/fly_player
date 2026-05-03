package com.geqian.flyplayer.fly_player

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.content.IntentFilter
import android.os.Environment
import android.os.SystemClock
import android.provider.DocumentsContract
import android.provider.Settings
import android.util.Log
import android.view.Display
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.window.embedding.SplitController
import com.geqian.flyplayer.fly_player.mpv.MpvPlayerViewFactory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.HashMap
import kotlin.concurrent.thread
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Android 侧 Flutter 宿主基类。
 * 这里统一负责 MethodChannel 注册、播放器/分屏宿主协同，以及系统权限和存储能力桥接。
 */
abstract class FlutterHostActivity : FlutterActivity() {
    private val logTag: String
        get() = javaClass.simpleName

    private var pendingStoragePermissionResult: MethodChannel.Result? = null
    private var pendingScopedTreeAccessResult: MethodChannel.Result? = null
    private var pendingScreenshotTreeAccessResult: MethodChannel.Result? = null
    private var awaitingManageStorageAccessResult = false
    private var pendingPlayerResult: MethodChannel.Result? = null
    private val scopedTreeAccessController by lazy {
        ScopedTreeAccessController(applicationContext)
    }
    private val screenshotDirectoryAccessController by lazy {
        ScreenshotDirectoryAccessController(applicationContext)
    }
    private val storageManagementController by lazy {
        StorageManagementController(applicationContext)
    }
    private val screenshotLibraryController by lazy {
        ScreenshotLibraryController(applicationContext, screenshotDirectoryAccessController)
    }
    private val danDanPlaySecretStore by lazy {
        DanDanPlaySecretStore(applicationContext)
    }
    protected var systemChannel: MethodChannel? = null
    protected var detailHostChannel: MethodChannel? = null
    protected var playerHostStateChannel: MethodChannel? = null
    protected var mainHostChannel: MethodChannel? = null
    protected var runtimeThemeSyncChannel: MethodChannel? = null
    protected var sessionStateChannel: MethodChannel? = null
    private var playerImmersiveSystemBarsEnabled = false
    private var lastAppliedDecorFitsSystemWindows: Boolean? = null
    private var lastAppliedSystemBarsMode: Int? = null
    private var lastReportedSystemMultiWindowActive: Boolean? = null
    private var lastEmbeddingDecisionLog: String? = null
    private var lastEmbeddingDecisionLogAtMs: Long = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ParallelWindowCoordinator.restoreFromPreferences(this)
        ActivityEmbeddingInstaller.install(this)
        applyPreferredHostDisplayMode(reason = "create")
        applyParallelWindowImmersiveMode()
        notifyPlayerHostSystemWindowMode()
    }

    override fun onResume() {
        super.onResume()
        applyPreferredHostDisplayMode(reason = "resume")
        applyParallelWindowImmersiveMode()
        notifyPlayerHostSystemWindowMode()
        if (awaitingManageStorageAccessResult) {
            awaitingManageStorageAccessResult = false
            pendingStoragePermissionResult?.success(hasFileAccess())
            pendingStoragePermissionResult = null
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            applyPreferredHostDisplayMode(reason = "focus")
            applyParallelWindowImmersiveMode(force = true)
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        applyPreferredHostDisplayMode(reason = "configuration")
        applyParallelWindowImmersiveMode()
        notifyPlayerHostSystemWindowMode()
    }

    override fun onDestroy() {
        PlaybackSessionCoordinator.detachHost(this)
        clearMethodChannelReferences()
        super.onDestroy()
    }

    override fun getRenderMode(): RenderMode = RenderMode.texture

    private fun applyPreferredHostDisplayMode(reason: String) {
        if (!shouldApplyHostPreferredDisplayMode()) {
            return
        }
        val currentDisplay = resolveActivityDisplay() ?: return
        val bestMode =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                currentDisplay.supportedModes.maxByOrNull { it.refreshRate }
            } else {
                null
            }
        val preferredRefreshRateHz =
            (bestMode?.refreshRate ?: currentDisplayRefreshRate(currentDisplay)).coerceAtLeast(60f)
        val params = window.attributes
        var changed = false
        if (abs(params.preferredRefreshRate - preferredRefreshRateHz) > 0.1f) {
            params.preferredRefreshRate = preferredRefreshRateHz
            changed = true
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val preferredModeId = bestMode?.modeId ?: 0
            if (preferredModeId != 0 && params.preferredDisplayModeId != preferredModeId) {
                params.preferredDisplayModeId = preferredModeId
                changed = true
            }
        }
        if (changed) {
            window.attributes = params
        }
        val modeRefreshRate =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                currentDisplay.mode?.refreshRate ?: preferredRefreshRateHz
            } else {
                currentDisplayRefreshRate(currentDisplay)
            }
        Log.d(
            logTag,
            "applyPreferredHostDisplayMode reason=$reason " +
                "displayHz=${"%.1f".format(modeRefreshRate)} " +
                "requestedHz=${"%.1f".format(preferredRefreshRateHz)} " +
                "modeId=${if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) params.preferredDisplayModeId else 0}",
        )
    }

    private fun resolveActivityDisplay(): Display? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay
        }
    }

    private fun currentDisplayRefreshRate(display: Display): Float {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            display.mode?.refreshRate ?: display.refreshRate
        } else {
            @Suppress("DEPRECATION")
            display.refreshRate
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        if (!shouldSkipBaseFlutterEngineConfiguration(flutterEngine)) {
            super.configureFlutterEngine(flutterEngine)
        }
        // 按能力分组注册 channel，避免单个方法持续膨胀。
        registerSystemChannel(flutterEngine)
        registerStorageChannel(flutterEngine)
        registerSecretStoreChannel(flutterEngine)
        registerThemeSamplerChannel(flutterEngine)
        registerRuntimeThemeSyncChannel(flutterEngine)
        registerSessionStateChannel(flutterEngine)
        registerMainHostChannel(flutterEngine)
        registerEmbeddingChannel(flutterEngine)
        registerPlayerHostChannel(flutterEngine)
        registerPlayerHostStateChannel(flutterEngine)
        registerDetailHostChannel(flutterEngine)
        registerPlatformViewFactories(flutterEngine)
    }

    private fun clearMethodChannelReferences() {
        systemChannel = null
        detailHostChannel = null
        playerHostStateChannel = null
        mainHostChannel = null
        runtimeThemeSyncChannel = null
        sessionStateChannel = null
    }

    private fun registerSystemChannel(flutterEngine: FlutterEngine) {
        systemChannel =
            createMethodChannel(flutterEngine, "fly_player/system").also { channel ->
                channel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "setPlayerOrientation" -> {
                            val mode = call.argument<String>("mode").orEmpty()
                            requestedOrientation =
                                when (mode) {
                                    "landscape" -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                                    "portrait" -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                                    "system" -> ActivityInfo.SCREEN_ORIENTATION_FULL_USER
                                    else -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                                }
                            result.success(null)
                        }

                        "setPlayerImmersiveMode" -> {
                            playerImmersiveSystemBarsEnabled =
                                call.argument<Boolean>("enabled") ?: false
                            applyParallelWindowImmersiveMode()
                            result.success(null)
                        }

                        "getPlaybackSystemState" -> {
                            result.success(
                                mapOf(
                                    "brightness" to currentBrightness(),
                                    "volume" to currentVolumeRatio(),
                                ),
                            )
                        }

                        "getPlayerStatusSnapshot" -> {
                            result.success(
                                mapOf(
                                    "batteryLevel" to currentBatteryLevel(),
                                    "charging" to isBatteryCharging(),
                                    "networkType" to currentNetworkType(),
                                ),
                            )
                        }

                        "getRuntimeThemeSessionId" -> {
                            result.success(RuntimeThemeSessionRegistry.sessionId)
                        }

                        "setPlaybackBrightness" -> {
                            val value = call.argument<Double>("value")
                            result.success(setPlaybackBrightness(value))
                        }

                        "setPlaybackVolume" -> {
                            val value = call.argument<Double>("value")
                            result.success(setPlaybackVolume(value))
                        }

                        "playerSessionStart",
                        "playerSessionUpdate",
                        -> {
                            if (PlaybackSessionCoordinator.areSessionUpdatesBlocked()) {
                                Log.d(logTag, "ignore ${call.method} because session updates are blocked")
                                result.success(false)
                                return@setMethodCallHandler
                            }
                            val payload = PlaybackSessionPayload.fromArguments(call.arguments)
                            if (payload == null) {
                                result.success(false)
                            } else {
                                PlaybackSessionCoordinator.attachHost(this)
                                PlayerNotificationService.startOrUpdate(applicationContext, payload)
                                result.success(true)
                            }
                        }

                        "playerSessionStop" -> {
                            PlaybackSessionCoordinator.detachHost(this)
                            PlayerNotificationService.stop(applicationContext)
                            result.success(true)
                        }

                        else -> result.notImplemented()
                    }
                }
            }
    }

    private fun registerStorageChannel(flutterEngine: FlutterEngine) {
        createMethodChannel(flutterEngine, "fly_player/storage").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasFileAccess" -> result.success(hasFileAccess())
                "requestFileAccess" -> requestFileAccess(result)
                "openFileAccessSettings" -> result.success(openFileAccessSettings())
                "getPrimaryStorageRoot" -> result.success(primaryStorageRoot())
                "getScopedTreeRoot" -> result.success(scopedTreeAccessController.grantedRoot())
                "requestScopedTreeAccess" -> requestScopedTreeAccess(result)
                "listScopedTreeEntries" -> {
                    @Suppress("UNCHECKED_CAST")
                    val allowedExtensions =
                        (call.argument<List<*>>("allowedExtensions") ?: emptyList<Any?>())
                            .mapNotNull { it?.toString() }
                    result.success(
                        scopedTreeAccessController.listEntries(
                            directoryId = call.argument<String>("directoryId"),
                            allowedExtensions = allowedExtensions,
                        ),
                    )
                }
                "readScopedFileBytes" -> {
                    val identifier = call.argument<String>("identifier").orEmpty()
                    result.success(scopedTreeAccessController.readFileBytes(identifier))
                }
                "readLocalVideoMetadata" -> {
                    val path = call.argument<String>("path").orEmpty()
                    thread(name = "fly-local-video-metadata") {
                        val payload = LocalVideoMetadataReader.read(path)
                        runOnUiThread {
                            result.success(payload)
                        }
                    }
                }
                "getScreenshotCustomDirectory" -> {
                    result.success(screenshotDirectoryAccessController.currentDirectorySummary())
                }
                "requestScreenshotCustomDirectory" -> {
                    requestScreenshotCustomDirectory(result)
                }
                "clearScreenshotCustomDirectory" -> {
                    screenshotDirectoryAccessController.clearPersistedTree()
                    result.success(true)
                }
                "listScreenshotLibrary" -> {
                    result.success(screenshotLibraryController.listLibrary(hasFileAccess()))
                }
                "readScreenshotFileBytes" -> {
                    val sourceKind = call.argument<String>("sourceKind").orEmpty()
                    val pathOrIdentifier = call.argument<String>("pathOrIdentifier").orEmpty()
                    result.success(
                        screenshotLibraryController.readFileBytes(
                            sourceKind = sourceKind,
                            pathOrIdentifier = pathOrIdentifier,
                        ),
                    )
                }
                "deleteScreenshotFiles" -> {
                    val items =
                        (call.argument<List<*>>("items") ?: emptyList<Any?>())
                            .mapNotNull { entry ->
                                val map = entry as? Map<*, *> ?: return@mapNotNull null
                                val sourceKind = map["sourceKind"]?.toString()?.trim().orEmpty()
                                val pathOrIdentifier =
                                    map["pathOrIdentifier"]?.toString()?.trim().orEmpty()
                                if (sourceKind.isEmpty() || pathOrIdentifier.isEmpty()) {
                                    return@mapNotNull null
                                }
                                mapOf(
                                    "sourceKind" to sourceKind,
                                    "pathOrIdentifier" to pathOrIdentifier,
                                )
                            }
                    result.success(
                        mapOf(
                            "deletedCount" to screenshotLibraryController.deleteEntries(items),
                        ),
                    )
                }
                "getStorageOverview" -> {
                    result.success(storageManagementController.loadOverview(hasFileAccess()))
                }
                "clearStorageAction" -> {
                    val action = call.argument<String>("action").orEmpty()
                    result.success(storageManagementController.clear(action, hasFileAccess()))
                }
                "queryCachedDownloadable" -> {
                    result.success(
                        storageManagementController.queryCachedDownloadable(
                            itemGuid = call.argument<String>("itemGuid").orEmpty(),
                            mediaGuid = call.argument<String>("mediaGuid").orEmpty(),
                            videoGuid = call.argument<String>("videoGuid").orEmpty(),
                            resourceKey = call.argument<String>("resourceKey").orEmpty(),
                        ),
                    )
                }
                "promoteCachedMedia" -> {
                    val itemGuid = call.argument<String>("itemGuid").orEmpty()
                    val mediaGuid = call.argument<String>("mediaGuid").orEmpty()
                    val videoGuid = call.argument<String>("videoGuid").orEmpty()
                    val resourceKey = call.argument<String>("resourceKey").orEmpty()
                    val targetMode = call.argument<String>("targetMode").orEmpty()
                    val hasFileAccess = hasFileAccess()
                    thread(name = "FlyPlayer-PromoteCachedMedia", isDaemon = true) {
                        val promoteResult =
                            runCatching {
                                storageManagementController.promoteCachedMedia(
                                    itemGuid = itemGuid,
                                    mediaGuid = mediaGuid,
                                    videoGuid = videoGuid,
                                    resourceKey = resourceKey,
                                    targetMode = targetMode,
                                    hasFileAccess = hasFileAccess,
                                )
                            }.getOrElse {
                                mapOf(
                                    "success" to false,
                                    "code" to "copy_failed",
                                )
                            }
                        runOnUiThread {
                            result.success(promoteResult)
                        }
                    }
                }
                "listPlaybackCacheEntries" -> {
                    result.success(storageManagementController.listPlaybackCacheEntries())
                }
                "clearPlaybackCacheEntries" -> {
                    @Suppress("UNCHECKED_CAST")
                    val resourceKeys =
                        (call.argument<List<*>>("resourceKeys") ?: emptyList<Any?>())
                            .mapNotNull { it?.toString() }
                    result.success(storageManagementController.clearPlaybackCacheEntries(resourceKeys))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun registerSecretStoreChannel(flutterEngine: FlutterEngine) {
        createMethodChannel(flutterEngine, "fly_player/secret_store").setMethodCallHandler { call, result ->
            when (call.method) {
                "getDanDanPlayConfig" -> {
                    result.success(danDanPlaySecretStore.getConfig())
                }
                "clearDanDanPlayConfig" -> {
                    result.success(danDanPlaySecretStore.clearConfig())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun registerThemeSamplerChannel(flutterEngine: FlutterEngine) {
        createMethodChannel(flutterEngine, "fly_player/theme_sampler").setMethodCallHandler { call, result ->
            when (call.method) {
                "extractDynamicThemeSeed" -> {
                    val imageUrl = call.argument<String>("imageUrl").orEmpty().trim()
                    val token = call.argument<String>("token").orEmpty()
                    if (imageUrl.isEmpty()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    ThemeColorSampler.sample(imageUrl, token) { seed ->
                        result.success(seed)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun registerRuntimeThemeSyncChannel(flutterEngine: FlutterEngine) {
        runtimeThemeSyncChannel =
            createMethodChannel(flutterEngine, "fly_player/runtime_theme_sync").also { channel ->
                channel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "pushRuntimeThemeToMain" -> {
                            result.success(
                                pushRuntimeThemeToMain(
                                    copyStringKeyedMapOrEmpty(call.arguments),
                                ),
                            )
                        }
                        "clearRuntimeThemeOnMain" -> {
                            val pageKey = call.argument<String>("pageKey").orEmpty()
                            result.success(clearRuntimeThemeOnMain(pageKey))
                        }
                        "getActiveRuntimeTheme" -> {
                            result.success(activeRuntimeThemePayload)
                        }
                        else -> result.notImplemented()
                    }
                }
            }
    }

    private fun registerSessionStateChannel(flutterEngine: FlutterEngine) {
        sessionStateChannel = createMethodChannel(flutterEngine, "fly_player/session_state")
    }

    private fun registerMainHostChannel(flutterEngine: FlutterEngine) {
        mainHostChannel =
            createMethodChannel(flutterEngine, "fly_player/main_host").also { channel ->
                channel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "switchPrimaryTab" -> {
                            val tabId = call.argument<String>("tabId").orEmpty()
                            result.success(switchPrimaryTab(tabId))
                        }
                        "openPrimarySettings" -> {
                            val destinationRoute = call.argument<String>("destinationRoute")
                            result.success(openPrimarySettings(destinationRoute))
                        }
                        else -> result.notImplemented()
                    }
                }
            }
    }

    private fun registerEmbeddingChannel(flutterEngine: FlutterEngine) {
        createMethodChannel(flutterEngine, "fly_player/embedding").setMethodCallHandler { call, result ->
            when (call.method) {
                "canOpenEmbeddedDetail" -> result.success(canOpenEmbeddedDetail())
                "isParallelWindowSupported" -> result.success(isParallelWindowSupported())
                "openItemDetail" -> {
                    val itemGuid = call.argument<String>("itemGuid").orEmpty()
                    val seriesGuid = call.argument<String>("seriesGuid").orEmpty()
                    val initialItemDetail =
                        call.argument<HashMap<String, Any?>>("initialItemDetail")
                    result.success(
                        openEmbeddedDetail(
                            itemGuid = itemGuid,
                            seriesGuid = seriesGuid,
                            initialItemDetail = initialItemDetail,
                        ),
                    )
                }
                "openSecondaryRoute" -> {
                    val routeName = call.argument<String>("routeName").orEmpty()
                    result.success(openEmbeddedRoute(routeName))
                }
                "openSeasonDetail" -> {
                    val parentGuid = call.argument<String>("parentGuid").orEmpty()
                    val seriesTitle = call.argument<String>("seriesTitle").orEmpty()
                    val backdropPath = call.argument<String>("backdropPath").orEmpty()
                    val seasonItem = call.argument<HashMap<String, Any?>>("seasonItem")
                    result.success(
                        openEmbeddedSeasonDetail(
                            parentGuid = parentGuid,
                            seriesTitle = seriesTitle,
                            backdropPath = backdropPath,
                            seasonItem = seasonItem,
                        ),
                    )
                }
                "openFullscreenPlayer" -> {
                    val title = call.argument<String>("title").orEmpty()
                    val source = call.argument<HashMap<String, Any?>>("source")
                    val initialPlayInfo =
                        call.argument<HashMap<String, Any?>>("initialPlayInfo")
                    val startSource = call.argument<String>("startSource").orEmpty()
                    openFullscreenPlayer(title, source, initialPlayInfo, startSource, result)
                }
                "openFullscreenScreenshot" -> {
                    val rawItems = call.argument<List<*>>("items") ?: emptyList<Any?>()
                    val initialIndex = call.argument<Int>("initialIndex") ?: 0
                    result.success(
                        openFullscreenScreenshot(
                            items = copyStringKeyedMapList(rawItems),
                            initialIndex = initialIndex,
                        ),
                    )
                }
                "consumeFullscreenScreenshotPayload" -> {
                    val token = call.argument<String>("token").orEmpty()
                    result.success(FullscreenScreenshotPayloadStore.consume(token))
                }
                "readDetailRoutePayload" -> {
                    val token = call.argument<String>("token").orEmpty()
                    result.success(DetailRoutePayloadStore.read(token))
                }
                "getParallelHostContext" -> result.success(getParallelHostContext())
                "getParallelWindowSettings" -> {
                    result.success(ParallelWindowCoordinator.settingsMap())
                }
                "updateParallelWindowSettings" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    val preferredPaneSide =
                        when (call.argument<String>("preferredPrimaryPaneSide").orEmpty()) {
                            ParallelPaneSide.RIGHT.wireValue -> ParallelPaneSide.RIGHT
                            else -> ParallelPaneSide.LEFT
                        }
                    val preferredPlaybackPaneSide =
                        when (call.argument<String>("preferredPlaybackPrimaryPaneSide").orEmpty()) {
                            ParallelPaneSide.LEFT.wireValue -> ParallelPaneSide.LEFT
                            else -> ParallelPaneSide.RIGHT
                        }
                    val splitRatioPreset =
                        call.argument<String>("splitRatioPreset").orEmpty().ifBlank { "balanced" }
                    val defaultPlaybackFullscreen =
                        call.argument<Boolean>("defaultPlaybackFullscreen") ?: true
                    val immersiveStatusBar =
                        call.argument<Boolean>("immersiveStatusBar") ?: true
                    ParallelWindowCoordinator.persistSettings(
                        context = this,
                        enabled = enabled,
                        paneSide = preferredPaneSide,
                        playbackPaneSide = preferredPlaybackPaneSide,
                        splitRatioPreset = splitRatioPreset,
                        defaultPlaybackFullscreen = defaultPlaybackFullscreen,
                        immersiveStatusBar = immersiveStatusBar,
                    )
                    ActivityEmbeddingInstaller.install(this, force = true)
                    applyParallelWindowImmersiveMode()
                    result.success(ParallelWindowCoordinator.settingsMap())
                }
                "closeRightPane" -> result.success(closeRightPane())
                "logoutAndResetParallelUi" -> result.success(logoutAndResetParallelUi())
                "reportBrowseSnapshot" -> {
                    result.success(reportBrowseSnapshot(copyStringKeyedMap(call.arguments)))
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun registerPlayerHostChannel(flutterEngine: FlutterEngine) {
        createMethodChannel(flutterEngine, "fly_player/player_host").setMethodCallHandler { call, result ->
            when (call.method) {
                "consumeInitialPlayerArgs" -> result.success(consumeInitialPlayerArgs())
                "finishPlayerActivity" -> {
                    val payload = call.argument<HashMap<String, Any?>>("result")
                    result.success(finishPlayerActivity(payload))
                }
                "switchPlayerLayoutMode" -> {
                    val title = call.argument<String>("title").orEmpty()
                    val source = call.argument<HashMap<String, Any?>>("source")
                    val initialPlayInfo =
                        call.argument<HashMap<String, Any?>>("initialPlayInfo")
                    val startSource = call.argument<String>("startSource").orEmpty()
                    val targetMode = call.argument<String>("targetMode").orEmpty()
                    val resultPayload = call.argument<HashMap<String, Any?>>("result")
                    result.success(
                        switchPlayerLayoutMode(
                            title = title,
                            source = source,
                            initialPlayInfo = initialPlayInfo,
                            startSource = startSource,
                            targetMode = targetMode,
                            resultPayload = resultPayload,
                        ),
                    )
                }
                "syncPlayerLaunchState" -> {
                    val title = call.argument<String>("title").orEmpty()
                    val source = call.argument<HashMap<String, Any?>>("source")
                    val initialPlayInfo =
                        call.argument<HashMap<String, Any?>>("initialPlayInfo")
                    val startSource = call.argument<String>("startSource").orEmpty()
                    result.success(
                        syncPlayerLaunchState(
                            title = title,
                            source = source,
                            initialPlayInfo = initialPlayInfo,
                            startSource = startSource,
                        ),
                    )
                }
                "isSystemMultiWindowActive" -> {
                    result.success(isSystemMultiWindowActive())
                }
                "isPictureInPictureSupported" -> {
                    result.success(isPictureInPictureSupported())
                }
                "enterPictureInPicture" -> {
                    result.success(enterPictureInPicture())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun registerPlayerHostStateChannel(flutterEngine: FlutterEngine) {
        playerHostStateChannel =
            createMethodChannel(flutterEngine, "fly_player/player_host_state")
        notifyPlayerHostSystemWindowMode()
    }

    private fun registerDetailHostChannel(flutterEngine: FlutterEngine) {
        detailHostChannel = createMethodChannel(flutterEngine, "fly_player/detail_host")
    }

    private fun registerPlatformViewFactories(flutterEngine: FlutterEngine) {
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "fly_player/mpv_view",
                MpvPlayerViewFactory(flutterEngine.dartExecutor.binaryMessenger),
            )
    }

    private fun createMethodChannel(
        flutterEngine: FlutterEngine,
        channelName: String,
    ): MethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)

    private fun copyStringKeyedMap(arguments: Any?): HashMap<String, Any?>? =
        (arguments as? Map<*, *>)?.let(::copyStringKeyedMap)

    private fun copyStringKeyedMap(raw: Map<*, *>): HashMap<String, Any?> =
        HashMap<String, Any?>().apply {
            raw.forEach { (key, value) ->
                put(key?.toString().orEmpty(), value)
            }
        }

    private fun copyStringKeyedMapOrEmpty(arguments: Any?): HashMap<String, Any?> =
        copyStringKeyedMap(arguments) ?: hashMapOf()

    private fun copyStringKeyedMapList(rawItems: List<*>): List<HashMap<String, Any?>> =
        rawItems.mapNotNull { raw ->
            (raw as? Map<*, *>)?.let(::copyStringKeyedMap)
        }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != STORAGE_PERMISSION_REQUEST_CODE) return
        val granted =
            grantResults.isNotEmpty() &&
                grantResults.all { value -> value == PackageManager.PERMISSION_GRANTED }
        pendingStoragePermissionResult?.success(granted)
        pendingStoragePermissionResult = null
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SCREENSHOT_TREE_ACCESS_REQUEST_CODE) {
            val callback = pendingScreenshotTreeAccessResult
            pendingScreenshotTreeAccessResult = null
            handleDocumentTreeActivityResult(
                resultCode = resultCode,
                data = data,
                callback = callback,
            ) { treeUri, grantFlags ->
                screenshotDirectoryAccessController.persistGrantedTree(
                    treeUri = treeUri,
                    grantFlags = grantFlags,
                )
            }
            return
        }
        if (requestCode == SCOPED_TREE_ACCESS_REQUEST_CODE) {
            val callback = pendingScopedTreeAccessResult
            pendingScopedTreeAccessResult = null
            handleDocumentTreeActivityResult(
                resultCode = resultCode,
                data = data,
                callback = callback,
            ) { treeUri, grantFlags ->
                scopedTreeAccessController.persistGrantedTree(
                    treeUri = treeUri,
                    grantFlags = grantFlags,
                )
            }
            return
        }
        if (requestCode != PLAYER_ACTIVITY_REQUEST_CODE) return
        val callback = pendingPlayerResult ?: return
        pendingPlayerResult = null
        callback.success(PlayerLaunchContract.readResultPayload(data))
    }

    protected open fun canOpenEmbeddedDetail(): Boolean {
        if (!ParallelWindowCoordinator.isParallelWindowEnabled()) {
            logEmbeddingDecision("canOpenEmbeddedDetail=false disabledBySettings")
            return false
        }
        if (ParallelWindowCoordinator.isSplitPlayerVisible() && this !is PlayerActivity) {
            logEmbeddingDecision("canOpenEmbeddedDetail=false splitPlayerVisible")
            return false
        }
        if (Build.VERSION.SDK_INT < 32) return false
        val splitSupportStatus = SplitController.getInstance(this).splitSupportStatus
        if (splitSupportStatus != SplitController.SplitSupportStatus.SPLIT_AVAILABLE) {
            logEmbeddingDecision("canOpenEmbeddedDetail=false splitSupportStatus=$splitSupportStatus")
            return false
        }

        if (ParallelWindowCoordinator.hasRightPaneHost()) {
            logEmbeddingDecision(
                "canOpenEmbeddedDetail=true reusedExistingSplit rightPaneHost=${ParallelWindowCoordinator.hasRightPaneHost()}",
            )
            return true
        }

        val configuration = resources.configuration
        val canOpen =
            configuration.orientation == Configuration.ORIENTATION_LANDSCAPE &&
            configuration.screenWidthDp >= MIN_EMBEDDED_WIDTH_DP &&
            configuration.smallestScreenWidthDp >= MIN_EMBEDDED_SMALLEST_WIDTH_DP
        logEmbeddingDecision(
            "canOpenEmbeddedDetail=$canOpen splitSupportStatus=$splitSupportStatus orientation=${configuration.orientation} widthDp=${configuration.screenWidthDp} smallestWidthDp=${configuration.smallestScreenWidthDp}",
        )
        return canOpen
    }

    protected open fun isParallelWindowSupported(): Boolean {
        if (Build.VERSION.SDK_INT < 32) return false
        val splitSupportStatus = SplitController.getInstance(this).splitSupportStatus
        if (splitSupportStatus != SplitController.SplitSupportStatus.SPLIT_AVAILABLE) {
            logEmbeddingDecision("isParallelWindowSupported=false splitSupportStatus=$splitSupportStatus")
            return false
        }
        val configuration = resources.configuration
        val supported = configuration.smallestScreenWidthDp >= MIN_EMBEDDED_SMALLEST_WIDTH_DP
        logEmbeddingDecision(
            "isParallelWindowSupported=$supported splitSupportStatus=$splitSupportStatus smallestWidthDp=${configuration.smallestScreenWidthDp}",
        )
        return supported
    }

    private fun logEmbeddingDecision(message: String) {
        val nowMs = SystemClock.uptimeMillis()
        if (
            message == lastEmbeddingDecisionLog &&
            nowMs - lastEmbeddingDecisionLogAtMs < EMBEDDING_DECISION_LOG_REPEAT_MS
        ) {
            return
        }
        lastEmbeddingDecisionLog = message
        lastEmbeddingDecisionLogAtMs = nowMs
        Log.d(logTag, message)
    }

    protected open fun openEmbeddedDetail(
        itemGuid: String,
        seriesGuid: String = "",
        initialItemDetail: HashMap<String, Any?>? = null,
    ): Boolean {
        val normalizedGuid = itemGuid.trim()
        val normalizedSeriesGuid = seriesGuid.trim()
        if (normalizedGuid.isEmpty() || !canOpenEmbeddedDetail()) return false
        val routeBuilder =
            Uri
                .Builder()
                .path("/detail/item")
                .appendQueryParameter("itemGuid", normalizedGuid)
        if (normalizedSeriesGuid.isNotEmpty()) {
            routeBuilder.appendQueryParameter("seriesGuid", normalizedSeriesGuid)
        }
        initialItemDetail?.takeIf { it.isNotEmpty() }?.let { payload ->
            routeBuilder.appendQueryParameter(
                "payloadToken",
                DetailRoutePayloadStore.putItem(HashMap(payload)),
            )
        }
        val route = routeBuilder.build().toString()
        if (ParallelWindowCoordinator.isSplitPlayerVisible()) {
            ParallelWindowCoordinator.updateCurrentDetailItemGuid(normalizedGuid)
            ParallelWindowCoordinator.updateCurrentDetailRoute(route)
            val playerHost = ParallelWindowCoordinator.currentPlayerHost() ?: return false
            return playerHost.replaceRightPaneRouteInPlace(route)
        }
        val detailHost = ParallelWindowCoordinator.currentDetailHost()
        if (detailHost != null) {
            ParallelWindowCoordinator.updateCurrentDetailItemGuid(normalizedGuid)
            return detailHost.replaceRouteInPlace(route)
        }
        if (replaceCurrentDetailRouteIfSamePath(route)) {
            ParallelWindowCoordinator.updateCurrentDetailItemGuid(normalizedGuid)
            return true
        }
        ParallelWindowCoordinator.updateCurrentDetailItemGuid(normalizedGuid)
        ParallelFlutterEngineRegistry.prepareDetailRoute(this, route)
        startActivity(DetailActivity.createRouteIntent(this, route))
        return true
    }

    protected open fun openEmbeddedRoute(routeName: String): Boolean {
        val normalizedRoute = routeName.trim()
        if (normalizedRoute.isEmpty() || !canOpenEmbeddedDetail()) return false
        if (ParallelWindowCoordinator.isSplitPlayerVisible()) {
            ParallelWindowCoordinator.updateCurrentDetailRoute(normalizedRoute)
            updateTrackedDetailFromRoute(normalizedRoute)
            val playerHost = ParallelWindowCoordinator.currentPlayerHost() ?: return false
            return playerHost.replaceRightPaneRouteInPlace(normalizedRoute)
        }
        val detailHost = ParallelWindowCoordinator.currentDetailHost()
        if (detailHost != null) {
            updateTrackedDetailFromRoute(normalizedRoute)
            return detailHost.replaceRouteInPlace(normalizedRoute)
        }
        if (replaceCurrentDetailRouteIfSamePath(normalizedRoute)) {
            ParallelWindowCoordinator.updateCurrentDetailRoute(normalizedRoute)
            return true
        }
        ParallelWindowCoordinator.clearRightPane()
        ParallelFlutterEngineRegistry.prepareDetailRoute(this, normalizedRoute)
        startActivity(DetailActivity.createRouteIntent(this, normalizedRoute))
        return true
    }

    protected open fun switchPrimaryTab(tabId: String): Boolean {
        val normalizedTabId = tabId.trim()
        if (normalizedTabId.isEmpty()) return false
        val browseHost = ParallelWindowCoordinator.currentBrowseHost() ?: return false
        browseHost.dispatchMainHostMethod(
            method = "switchPrimaryTab",
            arguments = hashMapOf("tabId" to normalizedTabId),
        )
        return true
    }

    protected open fun openPrimarySettings(destinationRoute: String?): Boolean {
        val browseHost = ParallelWindowCoordinator.currentBrowseHost() ?: return false
        browseHost.dispatchMainHostMethod(
            method = "openPrimarySettings",
            arguments = hashMapOf("tabId" to "settings"),
        )
        val normalizedRoute = destinationRoute?.trim().orEmpty()
        if (normalizedRoute.isEmpty()) {
            return true
        }
        if (ParallelWindowCoordinator.isSplitPlayerVisible()) {
            ParallelWindowCoordinator.updateCurrentDetailRoute(normalizedRoute)
            updateTrackedDetailFromRoute(normalizedRoute)
            val playerHost = ParallelWindowCoordinator.currentPlayerHost() ?: return false
            return playerHost.replaceRightPaneRouteInPlace(normalizedRoute)
        }
        return browseHost.openEmbeddedRoute(normalizedRoute)
    }

    protected fun updateTrackedDetailFromRoute(routeName: String) {
        val parsedUri = Uri.parse(routeName)
        parsedUri.getQueryParameter("itemGuid")?.trim()?.takeIf { it.isNotEmpty() }?.let {
            ParallelWindowCoordinator.updateCurrentDetailItemGuid(it)
        }
        parsedUri.getQueryParameter("personGuid")?.trim()?.takeIf { it.isNotEmpty() }?.let {
            ParallelWindowCoordinator.updateCurrentDetailItemGuid(it)
        }
    }

    protected open fun openEmbeddedSeasonDetail(
        parentGuid: String,
        seriesTitle: String,
        backdropPath: String,
        seasonItem: HashMap<String, Any?>?,
    ): Boolean {
        val normalizedParentGuid = parentGuid.trim()
        val normalizedSeasonItem = seasonItem ?: hashMapOf()
        val seasonGuid = normalizedSeasonItem["guid"]?.toString()?.trim().orEmpty()
        if (normalizedParentGuid.isEmpty() || seasonGuid.isEmpty() || !canOpenEmbeddedDetail()) {
            return false
        }
        val route =
            Uri
                .Builder()
                .path("/detail/season")
                .appendQueryParameter("parentGuid", normalizedParentGuid)
                .appendQueryParameter("seriesTitle", seriesTitle.trim())
                .appendQueryParameter("backdropPath", backdropPath.trim())
                .appendQueryParameter("seasonGuid", seasonGuid)
                .appendQueryParameter(
                    "payloadToken",
                    DetailRoutePayloadStore.putSeason(HashMap(normalizedSeasonItem)),
                ).build()
                .toString()
        if (ParallelWindowCoordinator.isSplitPlayerVisible()) {
            ParallelWindowCoordinator.updateCurrentDetailItemGuid(seasonGuid)
            ParallelWindowCoordinator.updateCurrentDetailRoute(route)
            val playerHost = ParallelWindowCoordinator.currentPlayerHost() ?: return false
            return playerHost.replaceRightPaneRouteInPlace(route)
        }
        val detailHost = ParallelWindowCoordinator.currentDetailHost()
        if (detailHost != null) {
            ParallelWindowCoordinator.updateCurrentDetailItemGuid(seasonGuid)
            return detailHost.replaceRouteInPlace(route)
        }
        if (replaceCurrentDetailRouteIfSamePath(route)) {
            ParallelWindowCoordinator.updateCurrentDetailItemGuid(seasonGuid)
            return true
        }
        ParallelWindowCoordinator.updateCurrentDetailItemGuid(seasonGuid)
        ParallelFlutterEngineRegistry.prepareDetailRoute(this, route)
        startActivity(DetailActivity.createRouteIntent(this, route))
        return true
    }

    protected open fun replaceCurrentDetailRouteIfSamePath(routeName: String): Boolean {
        val normalizedRoute = routeName.trim()
        if (normalizedRoute.isEmpty()) return false
        val currentRoute = ParallelWindowCoordinator.currentDetailRoute().trim()
        if (currentRoute.isEmpty()) return false
        val currentPath = Uri.parse(currentRoute).path?.trim().orEmpty()
        val nextPath = Uri.parse(normalizedRoute).path?.trim().orEmpty()
        if (currentPath.isEmpty() || currentPath != nextPath) return false
        val detailHost = ParallelWindowCoordinator.currentDetailHost() ?: return false
        return detailHost.replaceRouteInPlace(normalizedRoute)
    }

    protected open fun openFullscreenScreenshot(
        items: List<HashMap<String, Any?>>,
        initialIndex: Int,
    ): Boolean {
        if (items.isEmpty()) return false
        val token =
            FullscreenScreenshotPayloadStore.put(
                items = items,
                initialIndex = initialIndex,
            )
        val routeName = ScreenshotLightboxActivityContract.buildRouteName(token)
        startActivity(
            FullscreenScreenshotActivity.createIntent(
                context = this,
                routeName = routeName,
            ),
        )
        overridePendingTransition(
            R.anim.screenshot_activity_enter,
            R.anim.screenshot_activity_exit,
        )
        return true
    }

    protected open fun closeRightPane(): Boolean {
        if (this is DetailActivity || this is PlaceholderActivity) {
            Log.d(
                logTag,
                "closeRightPane host=${javaClass.simpleName} splitPlayerVisible=${ParallelWindowCoordinator.isSplitPlayerVisible()} currentDetailRoute=${ParallelWindowCoordinator.currentDetailRoute()}",
            )
            ParallelWindowCoordinator.clearRightPane()
            if (this is DetailActivity && ParallelWindowCoordinator.isSplitPlayerVisible()) {
                Log.d(logTag, "closeRightPane restoring MainActivity while split player visible")
                startActivity(
                    Intent(this, MainActivity::class.java).apply {
                        addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                        addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    },
                )
            }
            finish()
            return true
        }
        return false
    }

    protected open fun reportBrowseSnapshot(snapshot: HashMap<String, Any?>?): Boolean {
        if (snapshot == null) return false
        ParallelWindowCoordinator.updateBrowseSnapshot(snapshot)
        return true
    }

    protected open fun logoutAndResetParallelUi(): Boolean {
        ParallelWindowCoordinator.clearSessionUiState()
        ParallelWindowCoordinator.setSplitPlayerVisible(false)
        val rightPaneHosts = ParallelWindowCoordinator.rightPaneHostsSnapshot()

        ParallelWindowCoordinator.currentMainHost()?.dispatchSessionState("loggedOut")
        ParallelWindowCoordinator.currentHomePaneHost()?.dispatchSessionState("loggedOut")
        ParallelWindowCoordinator.currentDetailHost()?.dispatchSessionState("loggedOut")
        ParallelWindowCoordinator.currentPlaceholderHost()?.dispatchSessionState("loggedOut")
        ParallelWindowCoordinator.currentPlayerHost()?.dispatchSessionState("loggedOut")
        ParallelWindowCoordinator.currentBrowseHost()?.dispatchSessionState("loggedOut")

        ParallelWindowCoordinator.currentPlayerHost()?.let { playerHost ->
            if (playerHost !== this) {
                playerHost.finish()
            }
        }

        rightPaneHosts.forEach { rightPaneHost ->
            if (rightPaneHost !== this) {
                rightPaneHost.finish()
            }
        }

        if (
            this is DetailActivity ||
                this is PlaceholderActivity ||
                this is PlayerActivity ||
                this is HomePaneActivity
        ) {
            startActivity(
                Intent(this, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                    addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                },
            )
            finish()
        }
        return true
    }

    open fun dispatchSessionState(method: String) {
        runOnUiThread {
            sessionStateChannel?.invokeMethod(method, null)
        }
    }

    protected open fun shouldUseParallelWindowImmersiveMode(): Boolean {
        if (!ParallelWindowCoordinator.isParallelWindowEnabled()) return false
        if (!ParallelWindowCoordinator.immersiveStatusBar()) return false
        return ParallelWindowCoordinator.hasRightPaneHost() ||
            ParallelWindowCoordinator.isSplitPlayerVisible()
    }

    protected fun applyParallelWindowImmersiveMode(force: Boolean = false) {
        val parallelImmersive = shouldUseParallelWindowImmersiveMode()
        val playerImmersive = playerImmersiveSystemBarsEnabled
        val immersive = parallelImmersive || playerImmersive
        val decorFitsSystemWindows = !immersive
        if (force || lastAppliedDecorFitsSystemWindows != decorFitsSystemWindows) {
            WindowCompat.setDecorFitsSystemWindows(window, decorFitsSystemWindows)
            lastAppliedDecorFitsSystemWindows = decorFitsSystemWindows
        }
        val controller = WindowInsetsControllerCompat(window, window.decorView)
        controller.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        val systemBarsMode =
            when {
                playerImmersive -> 2
                parallelImmersive -> 1
                else -> 0
            }
        if (force || lastAppliedSystemBarsMode != systemBarsMode) {
            when (systemBarsMode) {
                2 -> controller.hide(WindowInsetsCompat.Type.systemBars())
                1 -> controller.hide(WindowInsetsCompat.Type.statusBars())
                else -> controller.show(WindowInsetsCompat.Type.systemBars())
            }
            lastAppliedSystemBarsMode = systemBarsMode
        }
    }

    protected open fun hostSurface(): String = "standalone"

    protected open fun hostPaneSide(): ParallelPaneSide = ParallelPaneSide.FULLSCREEN

    protected open fun hostRoleOverride(): ParallelHostRole? = null

    protected open fun shouldSkipBaseFlutterEngineConfiguration(
        flutterEngine: FlutterEngine,
    ): Boolean = false

    protected open fun shouldApplyHostPreferredDisplayMode(): Boolean = true

    protected open fun getParallelHostContext(): HashMap<String, Any?> {
        val context =
            ParallelWindowCoordinator.buildHostContext(
            surface = hostSurface(),
            paneSide = hostPaneSide(),
        )
        hostRoleOverride()?.let { role ->
            context["hostRole"] = role.wireValue
        }
        return context
    }

    protected fun isSystemMultiWindowActive(): Boolean {
        return isInMultiWindowMode ||
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                isInPictureInPictureMode
            } else {
                false
            }
    }

    protected fun notifyPlayerHostSystemWindowMode() {
        val active = isSystemMultiWindowActive()
        if (lastReportedSystemMultiWindowActive == active) {
            return
        }
        lastReportedSystemMultiWindowActive = active
        playerHostStateChannel?.invokeMethod(
            "systemMultiWindowModeChanged",
            hashMapOf("active" to active),
        )
    }

    protected fun runAfterMethodReply(action: () -> Unit) {
        val decorView = window?.decorView
        if (decorView != null) {
            decorView.post {
                if (!isDestroyed) {
                    action()
                }
            }
            return
        }
        runOnUiThread {
            if (!isDestroyed) {
                action()
            }
        }
    }

    protected open fun resolvePlayerInitialRightPaneRoute(): String {
        val currentRoute = ParallelWindowCoordinator.currentDetailRoute().trim()
        if (currentRoute.isNotEmpty() && currentRoute != "/") {
            return currentRoute
        }
        val rememberedRoute = ParallelWindowCoordinator.rememberedDetailRoute().trim()
        if (rememberedRoute.isNotEmpty() && rememberedRoute != "/") {
            return rememberedRoute
        }
        return "/screen/home"
    }

    protected open fun consumeInitialPlayerArgs(): HashMap<String, Any?>? = null

    protected open fun finishPlayerActivity(result: HashMap<String, Any?>?): Boolean = false

    protected open fun switchPlayerLayoutMode(
        title: String,
        source: HashMap<String, Any?>?,
        initialPlayInfo: HashMap<String, Any?>?,
        startSource: String,
        targetMode: String,
        resultPayload: HashMap<String, Any?>?,
    ): Boolean = false

    protected open fun syncPlayerLaunchState(
        title: String,
        source: HashMap<String, Any?>?,
        initialPlayInfo: HashMap<String, Any?>?,
        startSource: String,
    ): Boolean = false

    protected open fun isPictureInPictureSupported(): Boolean = false

    protected open fun enterPictureInPicture(): Boolean = false

    open fun dispatchSystemPlaybackCommand(
        method: String,
        arguments: HashMap<String, Any?> = hashMapOf(),
    ) {
        runOnUiThread {
            val payload: Any? = if (arguments.isEmpty()) null else arguments
            systemChannel?.invokeMethod(method, payload)
        }
    }

    open fun dispatchMainHostMethod(
        method: String,
        arguments: HashMap<String, Any?> = hashMapOf(),
    ) {
        runOnUiThread {
            val payload: Any? = if (arguments.isEmpty()) null else arguments
            mainHostChannel?.invokeMethod(method, payload)
        }
    }

    private fun pushRuntimeThemeToMain(payload: HashMap<String, Any?>): Boolean {
        val pageKey = payload["pageKey"]?.toString()?.trim().orEmpty()
        if (pageKey.isEmpty()) {
            return false
        }
        val normalizedPayload = HashMap(payload)
        normalizedPayload["pageKey"] = pageKey
        activeRuntimeThemePageKey = pageKey
        activeRuntimeThemePayload = normalizedPayload
        val mainHost = ParallelWindowCoordinator.currentMainHost() ?: return false
        Log.d(logTag, "pushRuntimeThemeToMain page=$pageKey mainHost=${mainHost.javaClass.simpleName}")
        mainHost.dispatchRuntimeThemeSync("applyRuntimeDynamicTheme", normalizedPayload)
        return true
    }

    private fun clearRuntimeThemeOnMain(pageKey: String): Boolean {
        val normalizedPageKey = pageKey.trim()
        if (normalizedPageKey.isEmpty()) {
            return false
        }
        if (activeRuntimeThemePageKey.isNotEmpty() && normalizedPageKey != activeRuntimeThemePageKey) {
            Log.d(
                logTag,
                "ignore clearRuntimeThemeOnMain page=$normalizedPageKey active=$activeRuntimeThemePageKey",
            )
            return true
        }
        activeRuntimeThemePageKey = ""
        activeRuntimeThemePayload = null
        val mainHost = ParallelWindowCoordinator.currentMainHost() ?: return false
        Log.d(logTag, "clearRuntimeThemeOnMain page=$normalizedPageKey mainHost=${mainHost.javaClass.simpleName}")
        mainHost.dispatchRuntimeThemeSync(
            "clearRuntimeDynamicTheme",
            hashMapOf("pageKey" to normalizedPageKey),
        )
        return true
    }

    open fun dispatchRuntimeThemeSync(
        method: String,
        arguments: HashMap<String, Any?> = hashMapOf(),
    ) {
        runOnUiThread {
            Log.d(logTag, "dispatchRuntimeThemeSync method=$method page=${arguments["pageKey"]}")
            val payload: Any? = if (arguments.isEmpty()) null else arguments
            runtimeThemeSyncChannel?.invokeMethod(method, payload)
        }
    }

    private fun openFullscreenPlayer(
        title: String,
        source: HashMap<String, Any?>?,
        initialPlayInfo: HashMap<String, Any?>?,
        startSource: String,
        result: MethodChannel.Result,
    ) {
        val normalizedTitle = title.trim()
        val playerSource = source ?: hashMapOf()
        if (normalizedTitle.isEmpty() || playerSource.isEmpty()) {
            result.error("invalid_args", "missing player arguments", null)
            return
        }
        PlaybackSessionCoordinator.allowSessionUpdates()
        if (ParallelWindowCoordinator.isSplitPlayerVisible() && this !is PlayerActivity) {
            ParallelWindowCoordinator.currentPlayerHost()?.let { playerHost ->
                Log.d(
                    logTag,
                    "openFullscreenPlayer reusingSplitPlayer itemGuid=${playerSource["itemGuid"]}",
                )
                playerHost.replaceSourceInPlace(
                    normalizedTitle,
                    HashMap(playerSource),
                    initialPlayInfo?.let { HashMap(it) },
                    startSource,
                )
                result.success(null)
                return
            }
            runCatching {
                startActivity(
                    PlayerActivity.createIntent(
                        context = this,
                        title = normalizedTitle,
                        source = HashMap(playerSource),
                        initialPlayInfo = initialPlayInfo?.let { HashMap(it) },
                        startSource = startSource,
                        fromParallelHost = true,
                        hostContext = getParallelHostContext(),
                        layoutMode = PlayerLaunchContract.MODE_SPLIT,
                        initialRightPaneRoute = resolvePlayerInitialRightPaneRoute(),
                    ).apply {
                        addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                        addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    },
                )
            }.onSuccess {
                result.success(null)
            }.onFailure { error ->
                result.error("launch_failed", error.message, null)
            }
            return
        }
        if (pendingPlayerResult != null) {
            result.error("busy", "player activity already pending", null)
            return
        }
        pendingPlayerResult = result
        val preferFullscreen =
            !canOpenEmbeddedDetail() || ParallelWindowCoordinator.defaultPlaybackFullscreen()
        val launchIntent =
            if (preferFullscreen) {
                PlayerActivity.createIntent(
                    context = this,
                    title = normalizedTitle,
                    source = HashMap(playerSource),
                    initialPlayInfo = initialPlayInfo?.let { HashMap(it) },
                    startSource = startSource,
                    fromParallelHost = this is DetailActivity && ParallelWindowCoordinator.hasRightPaneHost(),
                    hostContext = getParallelHostContext(),
                    layoutMode = PlayerLaunchContract.MODE_FULLSCREEN,
                )
            } else {
                PlayerActivity.createIntent(
                    context = this,
                    title = normalizedTitle,
                    source = HashMap(playerSource),
                    initialPlayInfo = initialPlayInfo?.let { HashMap(it) },
                    startSource = startSource,
                    fromParallelHost = this is DetailActivity && ParallelWindowCoordinator.hasRightPaneHost(),
                    hostContext = getParallelHostContext(),
                    layoutMode = PlayerLaunchContract.MODE_SPLIT,
                    initialRightPaneRoute = resolvePlayerInitialRightPaneRoute(),
                )
            }
        runCatching {
            startActivityForResult(
                launchIntent,
                PLAYER_ACTIVITY_REQUEST_CODE,
            )
        }.onFailure { error ->
            pendingPlayerResult = null
            result.error("launch_failed", error.message, null)
        }
    }

    private fun currentBrightness(): Double {
        val current = window.attributes.screenBrightness
        if (current >= 0f) {
            return current.coerceIn(0.0f, 1.0f).toDouble()
        }
        val systemBrightness =
            runCatching {
                Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS)
            }.getOrDefault(128)
        return (systemBrightness / 255.0).coerceIn(0.0, 1.0)
    }

    private fun setPlaybackBrightness(value: Double?): Double {
        val normalized = (value ?: currentBrightness()).coerceIn(0.02, 1.0)
        val attributes = window.attributes
        attributes.screenBrightness = normalized.toFloat()
        window.attributes = attributes
        return normalized
    }

    private fun currentVolumeRatio(): Double {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        if (max <= 0) return 0.0
        val current = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
        return (current.toDouble() / max.toDouble()).coerceIn(0.0, 1.0)
    }

    private fun setPlaybackVolume(value: Double?): Double {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        if (max <= 0) return 0.0
        val normalized = (value ?: currentVolumeRatio()).coerceIn(0.0, 1.0)
        val targetVolume = (normalized * max.toDouble()).roundToInt().coerceIn(0, max)
        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, targetVolume, 0)
        return currentVolumeRatio()
    }

    private fun hasFileAccess(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_EXTERNAL_STORAGE,
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestFileAccess(result: MethodChannel.Result) {
        if (hasFileAccess()) {
            result.success(true)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            pendingStoragePermissionResult?.success(false)
            pendingStoragePermissionResult = result
            awaitingManageStorageAccessResult = true
            val launched = openFileAccessSettings()
            if (!launched) {
                awaitingManageStorageAccessResult = false
                pendingStoragePermissionResult?.success(false)
                pendingStoragePermissionResult = null
            }
            return
        }
        pendingStoragePermissionResult?.success(false)
        pendingStoragePermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE),
            STORAGE_PERMISSION_REQUEST_CODE,
        )
    }

    private fun currentBatteryLevel(): Int {
        val batteryManager = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
        val directLevel =
            batteryManager
                ?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                ?.takeIf { it in 0..100 }
        if (directLevel != null) {
            return directLevel
        }
        val batteryStatus = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = batteryStatus?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = batteryStatus?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        if (level >= 0 && scale > 0) {
            return ((level * 100f) / scale).roundToInt().coerceIn(0, 100)
        }
        return -1
    }

    private fun isBatteryCharging(): Boolean {
        val batteryStatus = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val status = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        return status == BatteryManager.BATTERY_STATUS_CHARGING ||
            status == BatteryManager.BATTERY_STATUS_FULL
    }

    private fun currentNetworkType(): String {
        val connectivityManager =
            getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return "unknown"
        val activeNetwork = connectivityManager.activeNetwork ?: return "offline"
        val capabilities =
            connectivityManager.getNetworkCapabilities(activeNetwork) ?: return "offline"
        return when {
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH) -> "bluetooth"
            else -> "online"
        }
    }

    private fun openFileAccessSettings(): Boolean {
        return runCatching {
            val intent =
                Intent(
                    Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                    Uri.parse("package:$packageName"),
                )
            startActivity(intent)
            true
        }.recoverCatching {
            val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
            startActivity(intent)
            true
        }.recoverCatching {
            val intent =
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName"),
                )
            startActivity(intent)
            true
        }.getOrElse { false }
    }

    private fun primaryStorageRoot(): String {
        return Environment.getExternalStorageDirectory().absolutePath
    }

    private fun requestScopedTreeAccess(result: MethodChannel.Result) {
        pendingScopedTreeAccessResult?.success(null)
        pendingScopedTreeAccessResult = result
        if (
            !launchDocumentTreePicker(
                scopedTreeAccessController.currentTreeUri(),
                SCOPED_TREE_ACCESS_REQUEST_CODE,
            )
        ) {
            pendingScopedTreeAccessResult = null
            result.success(null)
        }
    }

    private fun requestScreenshotCustomDirectory(result: MethodChannel.Result) {
        pendingScreenshotTreeAccessResult?.success(null)
        pendingScreenshotTreeAccessResult = result
        if (
            !launchDocumentTreePicker(
                screenshotDirectoryAccessController.currentTreeUri(),
                SCREENSHOT_TREE_ACCESS_REQUEST_CODE,
            )
        ) {
            pendingScreenshotTreeAccessResult = null
            result.success(null)
        }
    }

    private fun launchDocumentTreePicker(
        initialUri: Uri?,
        requestCode: Int,
    ): Boolean =
        runCatching {
            startActivityForResult(buildDocumentTreeIntent(initialUri), requestCode)
            true
        }.getOrElse { false }

    private fun buildDocumentTreeIntent(initialUri: Uri?): Intent =
        Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                initialUri?.let { uri ->
                    putExtra(DocumentsContract.EXTRA_INITIAL_URI, uri)
                }
            }
        }

    private fun handleDocumentTreeActivityResult(
        resultCode: Int,
        data: Intent?,
        callback: MethodChannel.Result?,
        persistGrantedTree: (Uri, Int) -> Any?,
    ) {
        // SAF 目录授权的结果处理统一走这里，避免请求端和回调端出现分叉逻辑。
        if (callback == null) {
            return
        }
        val treeUri = data?.data
        if (resultCode != RESULT_OK || treeUri == null) {
            callback.success(null)
            return
        }
        val grantFlags =
            data.flags and
                (Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        callback.success(
            persistGrantedTree(
                treeUri,
                grantFlags,
            ),
        )
    }

    private companion object {
        var activeRuntimeThemePageKey: String = ""
        var activeRuntimeThemePayload: HashMap<String, Any?>? = null
        const val PLAYER_ACTIVITY_REQUEST_CODE = 2072
        const val STORAGE_PERMISSION_REQUEST_CODE = 2071
        const val SCOPED_TREE_ACCESS_REQUEST_CODE = 2073
        const val SCREENSHOT_TREE_ACCESS_REQUEST_CODE = 2074
        const val MIN_EMBEDDED_WIDTH_DP = 840
        const val MIN_EMBEDDED_SMALLEST_WIDTH_DP = 600
        const val EMBEDDING_DECISION_LOG_REPEAT_MS = 2000L
    }
}
