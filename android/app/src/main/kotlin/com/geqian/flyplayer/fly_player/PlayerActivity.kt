package com.geqian.flyplayer.fly_player

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.util.Rational
import android.view.Display
import android.view.WindowManager
import java.util.HashMap
import kotlin.math.abs

/**
 * 播放器宿主 Activity。
 * 这里主要负责播放器窗口形态、启动参数同步，以及与 Flutter 播放页之间的状态桥接。
 */
class PlayerActivity : FlutterHostActivity() {
    private var wasInPictureInPictureMode = false

    private val decorFrameRateProbe =
        ViewFrameRateProbe(
            logTag = TAG,
            label = "player_decor",
            viewProvider = { window?.decorView },
        )

    private fun currentLayoutMode(): String = PlayerLaunchContract.readLayoutMode(intent)

    private fun currentInitialRightPaneRoute(): String {
        return PlayerLaunchContract.readInitialRightPaneRoute(intent)
    }

    private fun applyLayoutModeState() {
        ParallelWindowCoordinator.setSplitPlayerVisible(
            currentLayoutMode() == PlayerLaunchContract.MODE_SPLIT,
        )
    }

    private fun notifyPlayerHostLayoutModeChanged() {
        playerHostStateChannel?.invokeMethod(
            "layoutModeChanged",
            hashMapOf(
                "layoutMode" to currentLayoutMode(),
                "initialRightPaneRoute" to currentInitialRightPaneRoute(),
            ),
        )
    }

    private fun buildCurrentPlayerIntent(
        title: String,
        source: HashMap<String, Any?>,
        initialPlayInfo: HashMap<String, Any?>? = null,
        startSource: String = "manual",
        layoutMode: String = currentLayoutMode(),
    ): Intent =
        createIntent(
            context = this,
            title = title.trim(),
            source = HashMap(source),
            initialPlayInfo = initialPlayInfo?.let { HashMap(it) },
            startSource = startSource,
            fromParallelHost = PlayerLaunchContract.isFromParallelHost(intent),
            hostContext = getParallelHostContext(),
            layoutMode = layoutMode,
            initialRightPaneRoute = currentInitialRightPaneRoute(),
        )

    override fun getInitialRoute(): String = "/player?layoutMode=${currentLayoutMode()}"

    override fun hostSurface(): String = "player"

    override fun hostPaneSide(): ParallelPaneSide = ParallelPaneSide.FULLSCREEN

    override fun hostRoleOverride(): ParallelHostRole = ParallelHostRole.FULLSCREEN

    override fun shouldApplyHostPreferredDisplayMode(): Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyPreferredDisplayMode(reason = "create")
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        PlaybackSessionCoordinator.allowSessionUpdates()
        ParallelWindowCoordinator.attachPlayerHost(this)
        applyLayoutModeState()
        Log.d(
            TAG,
            "onCreate layoutMode=${currentLayoutMode()} action=${intent?.action} fromParallel=${PlayerLaunchContract.isFromParallelHost(intent)} rightPaneRoute=${currentInitialRightPaneRoute()}",
        )
    }

    override fun onResume() {
        super.onResume()
        wasInPictureInPictureMode = false
        applyPreferredDisplayMode(reason = "resume")
        decorFrameRateProbe.start()
    }

    override fun onPause() {
        decorFrameRateProbe.stop(reason = "pause")
        super.onPause()
    }

    override fun onStop() {
        super.onStop()
        if (wasInPictureInPictureMode) {
            wasInPictureInPictureMode = false
            Log.d(TAG, "onStop pipDismissed finishing layoutMode=${currentLayoutMode()}")
            finish()
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            applyPreferredDisplayMode(reason = "focus")
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        applyLayoutModeState()
        applyPreferredDisplayMode(reason = "newIntent")
        notifyPlayerHostLayoutModeChanged()
        Log.d(
            TAG,
            "onNewIntent layoutMode=${currentLayoutMode()} action=${intent.action} fromParallel=${PlayerLaunchContract.isFromParallelHost(intent)} rightPaneRoute=${currentInitialRightPaneRoute()}",
        )
        if (intent.action == PlayerLaunchContract.ACTION_RESUME_PLAYER) {
            return
        }
        PlayerLaunchContract.buildInitialArgs(intent)?.let { args ->
            playerHostStateChannel?.invokeMethod("replaceSource", args)
        }
    }

    override fun onDestroy() {
        decorFrameRateProbe.stop(reason = "destroy")
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (isFinishing && !isChangingConfigurations) {
            PlaybackSessionCoordinator.blockSessionUpdates()
            PlaybackSessionCoordinator.detachHost(this)
            PlayerNotificationService.stop(applicationContext)
        }
        ParallelWindowCoordinator.detachPlayerHost(this)
        ParallelWindowCoordinator.setSplitPlayerVisible(false)
        super.onDestroy()
    }

    private fun applyPreferredDisplayMode(reason: String) {
        val currentDisplay = resolveActivityDisplay() ?: return
        val preferredRefreshRateHz =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                currentDisplay.supportedModes.maxByOrNull { it.refreshRate }?.refreshRate
                    ?: currentDisplay.refreshRate
            } else {
                @Suppress("DEPRECATION")
                currentDisplay.refreshRate
            }.coerceAtLeast(60f)
        val params = window.attributes
        var changed = false
        if (abs(params.preferredRefreshRate - preferredRefreshRateHz) > 0.1f) {
            params.preferredRefreshRate = preferredRefreshRateHz
            changed = true
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val bestMode = currentDisplay.supportedModes.maxByOrNull { it.refreshRate }
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
                @Suppress("DEPRECATION")
                currentDisplay.refreshRate
            }
        Log.d(
            TAG,
            "applyPreferredDisplayMode reason=$reason " +
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

    fun replaceSourceInPlace(
        title: String,
        source: HashMap<String, Any?>,
        initialPlayInfo: HashMap<String, Any?>? = null,
        startSource: String = "manual",
    ) {
        val normalizedTitle = title.trim()
        if (normalizedTitle.isEmpty() || source.isEmpty()) return
        val nextIntent = buildCurrentPlayerIntent(normalizedTitle, source, initialPlayInfo, startSource)
        setIntent(nextIntent)
        PlayerLaunchContract.buildInitialArgs(nextIntent)?.let { args ->
            Log.d(
                TAG,
                "replaceSourceInPlace layoutMode=${currentLayoutMode()} itemGuid=${source["itemGuid"]}",
            )
            playerHostStateChannel?.invokeMethod("replaceSource", args)
        }
    }

    fun replaceRightPaneRouteInPlace(routeName: String): Boolean {
        val normalizedRoute = routeName.trim()
        if (normalizedRoute.isEmpty()) return false
        Log.d(
            TAG,
            "replaceRightPaneRouteInPlace layoutMode=${currentLayoutMode()} route=$normalizedRoute",
        )
        playerHostStateChannel?.invokeMethod(
            "replaceRightPaneRoute",
            hashMapOf("routeName" to normalizedRoute),
        )
        return true
    }

    override fun consumeInitialPlayerArgs(): HashMap<String, Any?>? {
        return PlayerLaunchContract.buildInitialArgs(intent)
    }

    override fun finishPlayerActivity(result: HashMap<String, Any?>?): Boolean {
        PlaybackSessionCoordinator.blockSessionUpdates()
        PlaybackSessionCoordinator.detachHost(this)
        PlayerNotificationService.stop(applicationContext)
        Log.d(
            TAG,
            "finishPlayerActivity layoutMode=${currentLayoutMode()} rightPaneRoute=${currentInitialRightPaneRoute()}",
        )
        setResult(
            Activity.RESULT_OK,
            Intent().apply {
                PlayerLaunchContract.putResultPayload(this, result)
            },
        )
        runAfterMethodReply {
            finish()
        }
        return true
    }

    override fun switchPlayerLayoutMode(
        title: String,
        source: HashMap<String, Any?>?,
        initialPlayInfo: HashMap<String, Any?>?,
        startSource: String,
        targetMode: String,
        resultPayload: HashMap<String, Any?>?,
    ): Boolean {
        val normalizedTitle = title.trim()
        val normalizedSource = source ?: hashMapOf()
        if (normalizedTitle.isEmpty() || normalizedSource.isEmpty()) {
            return false
        }
        if (targetMode != PlayerLaunchContract.MODE_SPLIT &&
            targetMode != PlayerLaunchContract.MODE_FULLSCREEN
        ) {
            return false
        }
        val nextIntent =
            buildCurrentPlayerIntent(
                title = normalizedTitle,
                source = normalizedSource,
                initialPlayInfo = initialPlayInfo,
                startSource = startSource,
                layoutMode = targetMode,
            )
        setIntent(nextIntent)
        applyLayoutModeState()
        notifyPlayerHostLayoutModeChanged()
        Log.d(
            TAG,
            "switchPlayerLayoutMode target=$targetMode handledInPlace=true itemGuid=${normalizedSource["itemGuid"]}",
        )
        return true
    }

    override fun syncPlayerLaunchState(
        title: String,
        source: HashMap<String, Any?>?,
        initialPlayInfo: HashMap<String, Any?>?,
        startSource: String,
    ): Boolean {
        val normalizedTitle = title.trim()
        val normalizedSource = source ?: hashMapOf()
        if (normalizedTitle.isEmpty() || normalizedSource.isEmpty()) {
            return false
        }
        val nextIntent =
            buildCurrentPlayerIntent(
                title = normalizedTitle,
                source = normalizedSource,
                initialPlayInfo = initialPlayInfo,
                startSource = startSource,
            )
        setIntent(nextIntent)
        Log.d(
            TAG,
            "syncPlayerLaunchState layoutMode=${currentLayoutMode()} itemGuid=${normalizedSource["itemGuid"]}",
        )
        return true
    }

    override fun isPictureInPictureSupported(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return false
        }
        if (!packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE)) {
            return false
        }
        if (currentLayoutMode() != PlayerLaunchContract.MODE_FULLSCREEN) {
            return false
        }
        if (PlayerLaunchContract.isFromParallelHost(intent)) {
            return false
        }
        return !isInPictureInPictureMode
    }

    override fun enterPictureInPicture(): Boolean {
        if (!isPictureInPictureSupported()) {
            return false
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return false
        }
        val decorView = window.decorView
        val rawWidth = decorView.width.coerceAtLeast(1)
        val rawHeight = decorView.height.coerceAtLeast(1)
        val width = maxOf(rawWidth, rawHeight)
        val height = minOf(rawWidth, rawHeight)
        val params =
            PictureInPictureParams
                .Builder()
                .setAspectRatio(Rational(width, height))
                .build()
        return runCatching { enterPictureInPictureMode(params) }.getOrDefault(false)
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (isInPictureInPictureMode) {
            wasInPictureInPictureMode = true
        }
        playerHostStateChannel?.invokeMethod(
            "pictureInPictureModeChanged",
            hashMapOf("active" to isInPictureInPictureMode),
        )
        notifyPlayerHostSystemWindowMode()
        Log.d(
            TAG,
            "onPictureInPictureModeChanged active=$isInPictureInPictureMode layoutMode=${currentLayoutMode()}",
        )
    }

    companion object {
        private const val TAG = "PlayerActivity"

        fun createIntent(
            context: Context,
            title: String,
            source: HashMap<String, Any?>,
            initialPlayInfo: HashMap<String, Any?>? = null,
            startSource: String = "manual",
            fromParallelHost: Boolean = false,
            hostContext: HashMap<String, Any?> = hashMapOf(),
            layoutMode: String = PlayerLaunchContract.MODE_FULLSCREEN,
            initialRightPaneRoute: String = "",
        ): Intent {
            return PlayerLaunchContract.applyLaunchExtras(
                intent = Intent(context, PlayerActivity::class.java),
                title = title,
                source = source,
                initialPlayInfo = initialPlayInfo?.let { HashMap(it) },
                startSource = startSource,
                fromParallelHost = fromParallelHost,
                hostContext = hostContext,
                layoutMode = layoutMode,
                initialRightPaneRoute = initialRightPaneRoute,
            )
        }

        fun createResumeIntent(
            context: Context,
            title: String,
            source: HashMap<String, Any?>,
            initialPlayInfo: HashMap<String, Any?>? = null,
            startSource: String = "manual",
            fromParallelHost: Boolean = false,
            layoutMode: String = PlayerLaunchContract.MODE_FULLSCREEN,
            initialRightPaneRoute: String = "",
        ): Intent {
            return createIntent(
                context = context,
                title = title,
                source = source,
                initialPlayInfo = initialPlayInfo?.let { HashMap(it) },
                startSource = startSource,
                fromParallelHost = fromParallelHost,
                hostContext = hashMapOf(),
                layoutMode = layoutMode,
                initialRightPaneRoute = initialRightPaneRoute,
            ).apply {
                action = PlayerLaunchContract.ACTION_RESUME_PLAYER
            }
        }
    }
}
