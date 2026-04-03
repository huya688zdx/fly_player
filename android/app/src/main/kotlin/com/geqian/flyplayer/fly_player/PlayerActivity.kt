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
import android.view.WindowManager
import java.util.HashMap

class PlayerActivity : FlutterHostActivity() {
    private fun currentLayoutMode(): String = PlayerLaunchContract.readLayoutMode(intent)

    private fun currentInitialRightPaneRoute(): String {
        return PlayerLaunchContract.readInitialRightPaneRoute(intent)
    }

    private fun applyLayoutModeState() {
        ParallelWindowCoordinator.setSplitPlayerVisible(
            currentLayoutMode() == PlayerLaunchContract.MODE_SPLIT,
        )
    }

    override fun getInitialRoute(): String = "/player?layoutMode=${currentLayoutMode()}"

    override fun hostSurface(): String = "player"

    override fun hostPaneSide(): ParallelPaneSide = ParallelPaneSide.FULLSCREEN

    override fun hostRoleOverride(): ParallelHostRole = ParallelHostRole.FULLSCREEN

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        PlaybackSessionCoordinator.allowSessionUpdates()
        ParallelWindowCoordinator.attachPlayerHost(this)
        applyLayoutModeState()
        Log.d(
            TAG,
            "onCreate layoutMode=${currentLayoutMode()} action=${intent?.action} fromParallel=${PlayerLaunchContract.isFromParallelHost(intent)} rightPaneRoute=${currentInitialRightPaneRoute()}",
        )
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        applyLayoutModeState()
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

    fun replaceSourceInPlace(
        title: String,
        source: HashMap<String, Any?>,
        initialPlayInfo: HashMap<String, Any?>? = null,
        startSource: String = "manual",
    ) {
        val normalizedTitle = title.trim()
        if (normalizedTitle.isEmpty() || source.isEmpty()) return
        val nextIntent =
            createIntent(
                context = this,
                title = normalizedTitle,
                source = HashMap(source),
                initialPlayInfo = initialPlayInfo?.let { HashMap(it) },
                startSource = startSource,
                fromParallelHost = PlayerLaunchContract.isFromParallelHost(intent),
                hostContext = getParallelHostContext(),
                layoutMode = currentLayoutMode(),
                initialRightPaneRoute = currentInitialRightPaneRoute(),
            )
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
            createIntent(
                context = this,
                title = normalizedTitle,
                source = HashMap(normalizedSource),
                initialPlayInfo = initialPlayInfo?.let { HashMap(it) },
                startSource = startSource,
                fromParallelHost = PlayerLaunchContract.isFromParallelHost(intent),
                hostContext = getParallelHostContext(),
                layoutMode = targetMode,
                initialRightPaneRoute = currentInitialRightPaneRoute(),
            )
        setIntent(nextIntent)
        applyLayoutModeState()
        Log.d(
            TAG,
            "switchPlayerLayoutMode target=$targetMode handledInFlutter=true itemGuid=${normalizedSource["itemGuid"]}",
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
            createIntent(
                context = this,
                title = normalizedTitle,
                source = HashMap(normalizedSource),
                initialPlayInfo = initialPlayInfo?.let { HashMap(it) },
                startSource = startSource,
                fromParallelHost = PlayerLaunchContract.isFromParallelHost(intent),
                hostContext = getParallelHostContext(),
                layoutMode = currentLayoutMode(),
                initialRightPaneRoute = currentInitialRightPaneRoute(),
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
        val width = decorView.width.coerceAtLeast(1)
        val height = decorView.height.coerceAtLeast(1)
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
