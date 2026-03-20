package com.geqian.flyplayer.fly_player

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.window.embedding.SplitController
import com.geqian.flyplayer.fly_player.mpv.MpvPlayerViewFactory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.HashMap
import kotlin.math.roundToInt

abstract class FlutterHostActivity : FlutterActivity() {
    private val logTag: String
        get() = javaClass.simpleName

    private var pendingStoragePermissionResult: MethodChannel.Result? = null
    private var pendingScopedTreeAccessResult: MethodChannel.Result? = null
    private var awaitingManageStorageAccessResult = false
    private var pendingPlayerResult: MethodChannel.Result? = null
    private val scopedTreeAccessController by lazy {
        ScopedTreeAccessController(applicationContext)
    }
    protected var systemChannel: MethodChannel? = null
    protected var detailHostChannel: MethodChannel? = null
    protected var playerHostStateChannel: MethodChannel? = null
    protected var runtimeThemeSyncChannel: MethodChannel? = null
    protected var sessionStateChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ParallelWindowCoordinator.restoreFromPreferences(this)
        ActivityEmbeddingInstaller.install(this)
        applyParallelWindowImmersiveMode()
        notifyPlayerHostSystemWindowMode()
    }

    override fun onResume() {
        super.onResume()
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
            applyParallelWindowImmersiveMode()
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        applyParallelWindowImmersiveMode()
        notifyPlayerHostSystemWindowMode()
    }

    override fun onDestroy() {
        PlaybackSessionCoordinator.detachHost(this)
        systemChannel = null
        runtimeThemeSyncChannel = null
        sessionStateChannel = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        systemChannel =
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "fly_player/system",
            )
        systemChannel?.setMethodCallHandler { call, result ->
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

                "getPlaybackSystemState" -> {
                    result.success(
                        mapOf(
                            "brightness" to currentBrightness(),
                            "volume" to currentVolumeRatio(),
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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "fly_player/storage",
        ).setMethodCallHandler { call, result ->
            val storageController = StorageManagementController(applicationContext)
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
                "getStorageOverview" -> {
                    result.success(storageController.loadOverview(hasFileAccess()))
                }
                "clearStorageAction" -> {
                    val action = call.argument<String>("action").orEmpty()
                    result.success(storageController.clear(action, hasFileAccess()))
                }
                "queryCachedDownloadable" -> {
                    result.success(
                        storageController.queryCachedDownloadable(
                            itemGuid = call.argument<String>("itemGuid").orEmpty(),
                            mediaGuid = call.argument<String>("mediaGuid").orEmpty(),
                            videoGuid = call.argument<String>("videoGuid").orEmpty(),
                            resourceKey = call.argument<String>("resourceKey").orEmpty(),
                        ),
                    )
                }
                "promoteCachedMedia" -> {
                    result.success(
                        storageController.promoteCachedMedia(
                            itemGuid = call.argument<String>("itemGuid").orEmpty(),
                            mediaGuid = call.argument<String>("mediaGuid").orEmpty(),
                            videoGuid = call.argument<String>("videoGuid").orEmpty(),
                            resourceKey = call.argument<String>("resourceKey").orEmpty(),
                            targetMode = call.argument<String>("targetMode").orEmpty(),
                            hasFileAccess = hasFileAccess(),
                        ),
                    )
                }
                "listPlaybackCacheEntries" -> {
                    result.success(storageController.listPlaybackCacheEntries())
                }
                "clearPlaybackCacheEntries" -> {
                    @Suppress("UNCHECKED_CAST")
                    val resourceKeys =
                        (call.argument<List<*>>("resourceKeys") ?: emptyList<Any?>())
                            .mapNotNull { it?.toString() }
                    result.success(storageController.clearPlaybackCacheEntries(resourceKeys))
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "fly_player/theme_sampler",
        ).setMethodCallHandler { call, result ->
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

        runtimeThemeSyncChannel =
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "fly_player/runtime_theme_sync",
            ).also { channel ->
                channel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "pushRuntimeThemeToMain" -> {
                            val payload =
                                (call.arguments as? Map<*, *>)?.let { raw ->
                                    HashMap<String, Any?>().apply {
                                        raw.forEach { (key, value) ->
                                            put(key?.toString().orEmpty(), value)
                                        }
                                    }
                                } ?: hashMapOf()
                            result.success(pushRuntimeThemeToMain(payload))
                        }
                        "clearRuntimeThemeOnMain" -> {
                            val pageKey = call.argument<String>("pageKey").orEmpty()
                            result.success(clearRuntimeThemeOnMain(pageKey))
                        }
                        else -> result.notImplemented()
                    }
                }
            }

        sessionStateChannel =
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "fly_player/session_state",
            )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "fly_player/embedding",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "canOpenEmbeddedDetail" -> result.success(canOpenEmbeddedDetail())
                "openItemDetail" -> {
                    val itemGuid = call.argument<String>("itemGuid").orEmpty()
                    result.success(openEmbeddedDetail(itemGuid))
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
                    openFullscreenPlayer(title, source, result)
                }
                "getParallelHostContext" -> result.success(getParallelHostContext())
                "getParallelWindowSettings" -> result.success(ParallelWindowCoordinator.settingsMap())
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
                    val snapshot =
                        (call.arguments as? Map<*, *>)?.let { raw ->
                            HashMap<String, Any?>().apply {
                                raw.forEach { (key, value) ->
                                    put(key?.toString().orEmpty(), value)
                                }
                            }
                        }
                    result.success(reportBrowseSnapshot(snapshot))
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "fly_player/player_host",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "consumeInitialPlayerArgs" -> result.success(consumeInitialPlayerArgs())
                "finishPlayerActivity" -> {
                    val payload = call.argument<HashMap<String, Any?>>("result")
                    result.success(finishPlayerActivity(payload))
                }
                "switchPlayerLayoutMode" -> {
                    val title = call.argument<String>("title").orEmpty()
                    val source = call.argument<HashMap<String, Any?>>("source")
                    val targetMode = call.argument<String>("targetMode").orEmpty()
                    val resultPayload = call.argument<HashMap<String, Any?>>("result")
                    result.success(
                        switchPlayerLayoutMode(
                            title = title,
                            source = source,
                            targetMode = targetMode,
                            resultPayload = resultPayload,
                        ),
                    )
                }
                "isSystemMultiWindowActive" -> {
                    result.success(isSystemMultiWindowActive())
                }
                else -> result.notImplemented()
            }
        }

        playerHostStateChannel =
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "fly_player/player_host_state",
            )
        notifyPlayerHostSystemWindowMode()

        detailHostChannel =
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "fly_player/detail_host",
            )

        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "fly_player/mpv_view",
                MpvPlayerViewFactory(flutterEngine.dartExecutor.binaryMessenger),
            )
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
        if (requestCode == SCOPED_TREE_ACCESS_REQUEST_CODE) {
            val callback = pendingScopedTreeAccessResult
            pendingScopedTreeAccessResult = null
            if (callback == null) {
                return
            }
            if (resultCode != RESULT_OK || data?.data == null) {
                callback.success(null)
                return
            }
            val treeUri = data.data ?: run {
                callback.success(null)
                return
            }
            val grantFlags =
                data.flags and
                    (Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            callback.success(
                scopedTreeAccessController.persistGrantedTree(
                    treeUri = treeUri,
                    grantFlags = grantFlags,
                ),
            )
            return
        }
        if (requestCode != PLAYER_ACTIVITY_REQUEST_CODE) return
        val callback = pendingPlayerResult ?: return
        pendingPlayerResult = null
        callback.success(PlayerLaunchContract.readResultPayload(data))
    }

    protected open fun canOpenEmbeddedDetail(): Boolean {
        if (!ParallelWindowCoordinator.isParallelWindowEnabled()) {
            Log.d(logTag, "canOpenEmbeddedDetail=false disabledBySettings")
            return false
        }
        if (ParallelWindowCoordinator.isSplitPlayerVisible() && this !is PlayerActivity) {
            Log.d(logTag, "canOpenEmbeddedDetail=false splitPlayerVisible")
            return false
        }
        if (Build.VERSION.SDK_INT < 32) return false
        val splitSupportStatus = SplitController.getInstance(this).splitSupportStatus
        if (splitSupportStatus != SplitController.SplitSupportStatus.SPLIT_AVAILABLE) {
            Log.d(logTag, "canOpenEmbeddedDetail=false splitSupportStatus=$splitSupportStatus")
            return false
        }

        if (ParallelWindowCoordinator.hasRightPaneHost()) {
            Log.d(
                logTag,
                "canOpenEmbeddedDetail=true reusedExistingSplit rightPaneHost=${ParallelWindowCoordinator.hasRightPaneHost()}",
            )
            return true
        }

        val configuration = resources.configuration
        val canOpen =
            configuration.orientation == Configuration.ORIENTATION_LANDSCAPE &&
            configuration.screenWidthDp >= MIN_EMBEDDED_WIDTH_DP &&
            configuration.smallestScreenWidthDp >= MIN_EMBEDDED_SMALLEST_WIDTH_DP
        Log.d(
            logTag,
            "canOpenEmbeddedDetail=$canOpen splitSupportStatus=$splitSupportStatus orientation=${configuration.orientation} widthDp=${configuration.screenWidthDp} smallestWidthDp=${configuration.smallestScreenWidthDp}",
        )
        return canOpen
    }

    protected open fun openEmbeddedDetail(itemGuid: String): Boolean {
        val normalizedGuid = itemGuid.trim()
        if (normalizedGuid.isEmpty() || !canOpenEmbeddedDetail()) return false
        val route =
            Uri
                .Builder()
                .path("/detail/item")
                .appendQueryParameter("itemGuid", normalizedGuid)
                .build()
                .toString()
        if (ParallelWindowCoordinator.isSplitPlayerVisible()) {
            ParallelWindowCoordinator.updateCurrentDetailItemGuid(normalizedGuid)
            ParallelWindowCoordinator.updateCurrentDetailRoute(route)
            val playerHost = ParallelWindowCoordinator.currentPlayerHost() ?: return false
            return playerHost.replaceRightPaneRouteInPlace(route)
        }
        if (replaceCurrentDetailRouteIfSamePath(route)) {
            ParallelWindowCoordinator.updateCurrentDetailItemGuid(normalizedGuid)
            return true
        }
        ParallelWindowCoordinator.updateCurrentDetailItemGuid(normalizedGuid)
        startActivity(DetailActivity.createIntent(this, normalizedGuid))
        return true
    }

    protected open fun openEmbeddedRoute(routeName: String): Boolean {
        val normalizedRoute = routeName.trim()
        if (normalizedRoute.isEmpty() || !canOpenEmbeddedDetail()) return false
        if (ParallelWindowCoordinator.isSplitPlayerVisible()) {
            ParallelWindowCoordinator.updateCurrentDetailRoute(normalizedRoute)
            val parsedUri = Uri.parse(normalizedRoute)
            parsedUri.getQueryParameter("itemGuid")?.trim()?.takeIf { it.isNotEmpty() }?.let {
                ParallelWindowCoordinator.updateCurrentDetailItemGuid(it)
            }
            parsedUri.getQueryParameter("personGuid")?.trim()?.takeIf { it.isNotEmpty() }?.let {
                ParallelWindowCoordinator.updateCurrentDetailItemGuid(it)
            }
            val playerHost = ParallelWindowCoordinator.currentPlayerHost() ?: return false
            return playerHost.replaceRightPaneRouteInPlace(normalizedRoute)
        }
        if (replaceCurrentDetailRouteIfSamePath(normalizedRoute)) {
            ParallelWindowCoordinator.updateCurrentDetailRoute(normalizedRoute)
            return true
        }
        ParallelWindowCoordinator.clearRightPane()
        startActivity(DetailActivity.createRouteIntent(this, normalizedRoute))
        return true
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
                .appendQueryParameter(
                    "seasonItem",
                    org.json.JSONObject(normalizedSeasonItem as Map<*, *>).toString(),
                ).build()
                .toString()
        if (ParallelWindowCoordinator.isSplitPlayerVisible()) {
            ParallelWindowCoordinator.updateCurrentDetailItemGuid(seasonGuid)
            ParallelWindowCoordinator.updateCurrentDetailRoute(route)
            val playerHost = ParallelWindowCoordinator.currentPlayerHost() ?: return false
            return playerHost.replaceRightPaneRouteInPlace(route)
        }
        if (replaceCurrentDetailRouteIfSamePath(route)) {
            ParallelWindowCoordinator.updateCurrentDetailItemGuid(seasonGuid)
            return true
        }
        ParallelWindowCoordinator.updateCurrentDetailItemGuid(seasonGuid)
        startActivity(
            DetailActivity.createSeasonIntent(
                context = this,
                parentGuid = normalizedParentGuid,
                seriesTitle = seriesTitle,
                backdropPath = backdropPath,
                seasonItem = HashMap(normalizedSeasonItem),
            ),
        )
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
        ParallelWindowCoordinator.clearRightPane()
        ParallelWindowCoordinator.setSplitPlayerVisible(false)

        ParallelWindowCoordinator.currentMainHost()?.dispatchSessionState("loggedOut")
        ParallelWindowCoordinator.currentDetailHost()?.dispatchSessionState("loggedOut")
        ParallelWindowCoordinator.currentPlaceholderHost()?.dispatchSessionState("loggedOut")
        ParallelWindowCoordinator.currentPlayerHost()?.dispatchSessionState("loggedOut")

        ParallelWindowCoordinator.currentPlayerHost()?.let { playerHost ->
            if (playerHost !== this) {
                playerHost.finish()
            }
        }

        ParallelWindowCoordinator.currentDetailHost()?.let { detailHost ->
            if (detailHost !== this) {
                detailHost.finish()
            }
        }

        ParallelWindowCoordinator.currentPlaceholderHost()?.let { placeholderHost ->
            if (placeholderHost !== this) {
                placeholderHost.finish()
            }
        }

        if (this is DetailActivity || this is PlaceholderActivity || this is PlayerActivity) {
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

    protected fun applyParallelWindowImmersiveMode() {
        val immersive = shouldUseParallelWindowImmersiveMode()
        WindowCompat.setDecorFitsSystemWindows(window, !immersive)
        val controller = WindowInsetsControllerCompat(window, window.decorView)
        controller.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        if (immersive) {
            controller.hide(WindowInsetsCompat.Type.statusBars())
        } else {
            controller.show(WindowInsetsCompat.Type.statusBars())
        }
    }

    protected open fun hostSurface(): String = "standalone"

    protected open fun hostPaneSide(): ParallelPaneSide = ParallelPaneSide.FULLSCREEN

    protected open fun hostRoleOverride(): ParallelHostRole? = null

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
        playerHostStateChannel?.invokeMethod(
            "systemMultiWindowModeChanged",
            hashMapOf("active" to isSystemMultiWindowActive()),
        )
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
        targetMode: String,
        resultPayload: HashMap<String, Any?>?,
    ): Boolean = false

    open fun dispatchSystemPlaybackCommand(
        method: String,
        arguments: HashMap<String, Any?> = hashMapOf(),
    ) {
        runOnUiThread {
            val payload: Any? = if (arguments.isEmpty()) null else arguments
            systemChannel?.invokeMethod(method, payload)
        }
    }

    private fun pushRuntimeThemeToMain(payload: HashMap<String, Any?>): Boolean {
        val mainHost = ParallelWindowCoordinator.currentMainHost() ?: return false
        Log.d(logTag, "pushRuntimeThemeToMain page=${payload["pageKey"]} mainHost=${mainHost.javaClass.simpleName}")
        mainHost.dispatchRuntimeThemeSync("applyRuntimeDynamicTheme", payload)
        return true
    }

    private fun clearRuntimeThemeOnMain(pageKey: String): Boolean {
        val normalizedPageKey = pageKey.trim()
        if (normalizedPageKey.isEmpty()) {
            return false
        }
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
                playerHost.replaceSourceInPlace(normalizedTitle, HashMap(playerSource))
                result.success(null)
                return
            }
            runCatching {
                startActivity(
                    PlayerActivity.createIntent(
                        context = this,
                        title = normalizedTitle,
                        source = HashMap(playerSource),
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
        runCatching {
            startActivityForResult(
                PlayerActivity.createIntent(
                    context = this,
                    title = normalizedTitle,
                    source = HashMap(playerSource),
                    fromParallelHost = this is DetailActivity && ParallelWindowCoordinator.hasRightPaneHost(),
                    hostContext = getParallelHostContext(),
                    layoutMode =
                        if (preferFullscreen) {
                            PlayerLaunchContract.MODE_FULLSCREEN
                        } else {
                            PlayerLaunchContract.MODE_SPLIT
                        },
                    initialRightPaneRoute = resolvePlayerInitialRightPaneRoute(),
                ),
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
        runCatching {
            val intent =
                Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
                    )
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        scopedTreeAccessController.currentTreeUri()?.let { uri ->
                            putExtra(DocumentsContract.EXTRA_INITIAL_URI, uri)
                        }
                    }
                }
            startActivityForResult(intent, SCOPED_TREE_ACCESS_REQUEST_CODE)
        }.onFailure {
            pendingScopedTreeAccessResult = null
            result.success(null)
        }
    }

    private companion object {
        const val PLAYER_ACTIVITY_REQUEST_CODE = 2072
        const val STORAGE_PERMISSION_REQUEST_CODE = 2071
        const val SCOPED_TREE_ACCESS_REQUEST_CODE = 2073
        const val MIN_EMBEDDED_WIDTH_DP = 840
        const val MIN_EMBEDDED_SMALLEST_WIDTH_DP = 600
    }
}
