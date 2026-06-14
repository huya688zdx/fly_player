package com.geqian.flyplayer.fly_player

import android.content.Context
import java.lang.ref.WeakReference

/**
 * 统一维护分屏浏览、详情页和播放器之间共享的界面状态。
 * 这里既保存用户的并行窗口偏好，也缓存最近一次可恢复的详情页定位信息。
 */
object ParallelWindowCoordinator {
    private const val PREFS_NAME = "parallel_window_settings"
    private const val KEY_ENABLED = "parallel_window_enabled"
    private const val KEY_PRIMARY_SIDE = "parallel_window_primary_side"
    private const val KEY_PLAYBACK_PRIMARY_SIDE = "parallel_window_playback_primary_side"
    private const val KEY_SPLIT_RATIO_PRESET = "parallel_window_split_ratio_preset"
    private const val KEY_DEFAULT_PLAYBACK_FULLSCREEN = "parallel_window_default_playback_fullscreen"
    private const val KEY_IMMERSIVE_STATUS_BAR = "parallel_window_immersive_status_bar"
    private const val KEY_LAST_NATIVE_PLAYBACK_SPLIT = "parallel_window_last_native_playback_split"

    @Volatile
    var lastBrowseSnapshot: HashMap<String, Any?>? = null

    @Volatile
    var currentDetailItemGuid: String = ""

    @Volatile
    private var currentDetailRoute: String = ""

    // 右侧详情页关闭后，仍保留最近一次有效目标，便于恢复或重建宿主。
    @Volatile
    private var rememberedDetailItemGuid: String = ""

    @Volatile
    private var rememberedDetailRoute: String = ""

    @Volatile
    private var rightPaneHostCount: Int = 0

    private val rightPaneHostRefs = mutableListOf<WeakReference<FlutterHostActivity>>()

    @Volatile
    private var preferredPrimaryPaneSide: ParallelPaneSide = ParallelPaneSide.LEFT

    @Volatile
    private var parallelWindowEnabled: Boolean = true

    @Volatile
    private var preferredPlaybackPrimaryPaneSide: ParallelPaneSide = ParallelPaneSide.RIGHT

    @Volatile
    private var splitPlayerVisible: Boolean = false

    @Volatile
    private var splitRatioPreset: String = "balanced"

    @Volatile
    private var defaultPlaybackFullscreen: Boolean = true

    @Volatile
    private var immersiveStatusBar: Boolean = true

    // 原生壳上次以分屏还是全屏退出，供下次进入"记住上次"决策。
    @Volatile
    private var lastNativePlaybackSplit: Boolean = false

    // 原生壳「当前是否处于分屏」。独立于旧 splitPlayerVisible（后者是 PlayerActivity 分屏专用，
    // 被 canOpenEmbeddedDetail/closeRightPane 等消费），原生壳绝不复用它，避免劫持那套机器。
    @Volatile
    private var nativeSplitPlayerVisible: Boolean = false

    // 只保留 Activity 的弱引用，避免 coordinator 把界面实例意外长时间持有住。
    @Volatile
    private var detailHostRef: WeakReference<DetailActivity>? = null

    @Volatile
    private var placeholderHostRef: WeakReference<PlaceholderActivity>? = null

    @Volatile
    private var playerHostRef: WeakReference<PlayerActivity>? = null

    @Volatile
    private var mainHostRef: WeakReference<MainActivity>? = null

    @Volatile
    private var homePaneHostRef: WeakReference<HomePaneActivity>? = null

    @Volatile
    private var browseHostRef: WeakReference<FlutterHostActivity>? = null

    fun updateBrowseSnapshot(snapshot: HashMap<String, Any?>) {
        lastBrowseSnapshot = HashMap(snapshot)
    }

    fun updateCurrentDetailItemGuid(itemGuid: String) {
        val normalized = itemGuid.trim()
        currentDetailItemGuid = normalized
        if (normalized.isNotEmpty()) {
            rememberedDetailItemGuid = normalized
        }
    }

    fun updateCurrentDetailRoute(route: String) {
        val normalized = route.trim()
        currentDetailRoute = normalized
        if (normalized.isNotEmpty() && normalized != "/") {
            rememberedDetailRoute = normalized
        }
    }

    fun currentDetailRoute(): String = currentDetailRoute

    fun rememberedDetailRoute(): String = rememberedDetailRoute

    fun rememberedDetailItemGuid(): String = rememberedDetailItemGuid

    fun snapshotDetailForRestore() {
        if (currentDetailItemGuid.isNotEmpty()) {
            rememberedDetailItemGuid = currentDetailItemGuid
        }
        if (currentDetailRoute.isNotEmpty() && currentDetailRoute != "/") {
            rememberedDetailRoute = currentDetailRoute
        }
    }

    fun isParallelWindowEnabled(): Boolean = parallelWindowEnabled

    fun setParallelWindowEnabled(enabled: Boolean) {
        parallelWindowEnabled = enabled
    }

    fun isSplitPlayerVisible(): Boolean = splitPlayerVisible

    fun setSplitPlayerVisible(visible: Boolean) {
        splitPlayerVisible = visible
    }

    fun preferredPrimaryPaneSide(): ParallelPaneSide = preferredPrimaryPaneSide

    fun preferredPlaybackPrimaryPaneSide(): ParallelPaneSide = preferredPlaybackPrimaryPaneSide

    fun splitRatioPreset(): String = splitRatioPreset

    fun browsePrimaryRatio(): Float =
        when (splitRatioPreset) {
            "equal" -> 0.50f
            "focus_detail" -> 0.35f
            "focus_home" -> 0.45f
            else -> 0.42f
        }

    fun playerPrimaryRatio(): Float = 1.0f - browsePrimaryRatio()

    fun defaultPlaybackFullscreen(): Boolean = defaultPlaybackFullscreen

    fun immersiveStatusBar(): Boolean = immersiveStatusBar

    fun isNativeSplitPlayerVisible(): Boolean = nativeSplitPlayerVisible

    fun setNativeSplitPlayerVisible(visible: Boolean) {
        nativeSplitPlayerVisible = visible
    }

    fun lastNativePlaybackSplit(): Boolean = lastNativePlaybackSplit

    fun setLastNativePlaybackSplit(
        context: Context,
        split: Boolean,
    ) {
        lastNativePlaybackSplit = split
        context
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_LAST_NATIVE_PLAYBACK_SPLIT, split)
            .apply()
    }

    fun preferredSecondaryPaneSide(): ParallelPaneSide =
        if (preferredPrimaryPaneSide == ParallelPaneSide.RIGHT) {
            ParallelPaneSide.LEFT
        } else {
            ParallelPaneSide.RIGHT
        }

    fun preferredPlaybackSecondaryPaneSide(): ParallelPaneSide =
        if (preferredPlaybackPrimaryPaneSide == ParallelPaneSide.RIGHT) {
            ParallelPaneSide.LEFT
        } else {
            ParallelPaneSide.RIGHT
        }

    fun activePlayerPrimaryPaneSide(): ParallelPaneSide = preferredPlaybackPrimaryPaneSide()

    fun activePlayerSecondaryPaneSide(): ParallelPaneSide = preferredPlaybackSecondaryPaneSide()

    fun setPreferredPrimaryPaneSide(paneSide: ParallelPaneSide) {
        if (paneSide == ParallelPaneSide.LEFT || paneSide == ParallelPaneSide.RIGHT) {
            preferredPrimaryPaneSide = paneSide
        }
    }

    fun setPreferredPlaybackPrimaryPaneSide(paneSide: ParallelPaneSide) {
        if (paneSide == ParallelPaneSide.LEFT || paneSide == ParallelPaneSide.RIGHT) {
            preferredPlaybackPrimaryPaneSide = paneSide
        }
    }

    fun setSplitRatioPreset(preset: String) {
        splitRatioPreset =
            when (preset.trim()) {
                "equal", "focus_detail", "focus_home" -> preset.trim()
                else -> "balanced"
            }
    }

    fun setDefaultPlaybackFullscreen(fullscreen: Boolean) {
        defaultPlaybackFullscreen = fullscreen
    }

    fun setImmersiveStatusBar(enabled: Boolean) {
        immersiveStatusBar = enabled
    }

    fun restoreFromPreferences(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        parallelWindowEnabled = prefs.getBoolean(KEY_ENABLED, true)
        preferredPrimaryPaneSide =
            when (prefs.getString(KEY_PRIMARY_SIDE, ParallelPaneSide.LEFT.wireValue)) {
                ParallelPaneSide.RIGHT.wireValue -> ParallelPaneSide.RIGHT
                else -> ParallelPaneSide.LEFT
            }
        preferredPlaybackPrimaryPaneSide =
            when (prefs.getString(KEY_PLAYBACK_PRIMARY_SIDE, ParallelPaneSide.RIGHT.wireValue)) {
                ParallelPaneSide.LEFT.wireValue -> ParallelPaneSide.LEFT
                else -> ParallelPaneSide.RIGHT
            }
        setSplitRatioPreset(prefs.getString(KEY_SPLIT_RATIO_PRESET, "balanced").orEmpty())
        defaultPlaybackFullscreen = prefs.getBoolean(KEY_DEFAULT_PLAYBACK_FULLSCREEN, true)
        immersiveStatusBar = prefs.getBoolean(KEY_IMMERSIVE_STATUS_BAR, true)
        lastNativePlaybackSplit = prefs.getBoolean(KEY_LAST_NATIVE_PLAYBACK_SPLIT, false)
    }

    fun attachDetailHost(activity: DetailActivity) {
        detailHostRef = attachHostReference(activity)
    }

    fun detachDetailHost(activity: DetailActivity) {
        detailHostRef = detachHostReference(detailHostRef, activity)
    }

    fun currentDetailHost(): DetailActivity? = detailHostRef?.get()

    // 原生壳分屏副栏（第二引擎的 DetailActivity）独立跟踪，与浏览详情 host 互不干扰。
    @Volatile
    private var splitDetailHostRef: WeakReference<DetailActivity>? = null

    fun attachSplitDetailHost(activity: DetailActivity) {
        splitDetailHostRef = attachHostReference(activity)
    }

    fun detachSplitDetailHost(activity: DetailActivity) {
        splitDetailHostRef = detachHostReference(splitDetailHostRef, activity)
    }

    fun currentSplitDetailHost(): DetailActivity? = splitDetailHostRef?.get()

    fun attachPlaceholderHost(activity: PlaceholderActivity) {
        placeholderHostRef = attachHostReference(activity)
    }

    fun detachPlaceholderHost(activity: PlaceholderActivity) {
        placeholderHostRef = detachHostReference(placeholderHostRef, activity)
    }

    fun currentPlaceholderHost(): PlaceholderActivity? = placeholderHostRef?.get()

    fun attachPlayerHost(activity: PlayerActivity) {
        playerHostRef = attachHostReference(activity)
    }

    fun detachPlayerHost(activity: PlayerActivity) {
        playerHostRef = detachHostReference(playerHostRef, activity)
    }

    fun currentPlayerHost(): PlayerActivity? = playerHostRef?.get()

    fun attachMainHost(activity: MainActivity) {
        mainHostRef = attachHostReference(activity)
    }

    fun detachMainHost(activity: MainActivity) {
        mainHostRef = detachHostReference(mainHostRef, activity)
    }

    fun currentMainHost(): MainActivity? = mainHostRef?.get()

    fun attachHomePaneHost(activity: HomePaneActivity) {
        homePaneHostRef = attachHostReference(activity)
    }

    fun detachHomePaneHost(activity: HomePaneActivity) {
        homePaneHostRef = detachHostReference(homePaneHostRef, activity)
    }

    fun currentHomePaneHost(): HomePaneActivity? = homePaneHostRef?.get()

    fun attachBrowseHost(activity: FlutterHostActivity) {
        browseHostRef = attachHostReference(activity)
    }

    fun detachBrowseHost(activity: FlutterHostActivity) {
        browseHostRef = detachHostReference(browseHostRef, activity)
    }

    fun currentBrowseHost(): FlutterHostActivity? =
        browseHostRef?.get() ?: currentHomePaneHost() ?: currentMainHost()

    fun persistSettings(
        context: Context,
        enabled: Boolean,
        paneSide: ParallelPaneSide,
        playbackPaneSide: ParallelPaneSide,
        splitRatioPreset: String,
        defaultPlaybackFullscreen: Boolean,
        immersiveStatusBar: Boolean,
    ) {
        setParallelWindowEnabled(enabled)
        setPreferredPrimaryPaneSide(paneSide)
        setPreferredPlaybackPrimaryPaneSide(playbackPaneSide)
        setSplitRatioPreset(splitRatioPreset)
        setDefaultPlaybackFullscreen(defaultPlaybackFullscreen)
        setImmersiveStatusBar(immersiveStatusBar)
        context
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_ENABLED, parallelWindowEnabled)
            .remove("parallel_window_force_enabled")
            .putString(KEY_PRIMARY_SIDE, preferredPrimaryPaneSide.wireValue)
            .putString(KEY_PLAYBACK_PRIMARY_SIDE, preferredPlaybackPrimaryPaneSide.wireValue)
            .putString(KEY_SPLIT_RATIO_PRESET, this.splitRatioPreset)
            .putBoolean(KEY_DEFAULT_PLAYBACK_FULLSCREEN, this.defaultPlaybackFullscreen)
            .putBoolean(KEY_IMMERSIVE_STATUS_BAR, this.immersiveStatusBar)
            .apply()
    }

    fun settingsMap(): HashMap<String, Any?> {
        return hashMapOf(
            "enabled" to parallelWindowEnabled,
            "preferredPrimaryPaneSide" to preferredPrimaryPaneSide.wireValue,
            "preferredPlaybackPrimaryPaneSide" to preferredPlaybackPrimaryPaneSide.wireValue,
            "splitRatioPreset" to splitRatioPreset,
            "defaultPlaybackFullscreen" to defaultPlaybackFullscreen,
            "immersiveStatusBar" to immersiveStatusBar,
        )
    }

    fun resolveHostRole(paneSide: ParallelPaneSide): ParallelHostRole {
        return when (paneSide) {
            ParallelPaneSide.FULLSCREEN -> ParallelHostRole.FULLSCREEN
            preferredPrimaryPaneSide -> ParallelHostRole.PRIMARY
            else -> ParallelHostRole.SECONDARY
        }
    }

    fun buildHostContext(
        surface: String,
        paneSide: ParallelPaneSide,
    ): HashMap<String, Any?> {
        return hashMapOf(
            "surface" to surface,
            "paneSide" to paneSide.wireValue,
            "hostRole" to resolveHostRole(paneSide).wireValue,
            "preferredPrimaryPaneSide" to preferredPrimaryPaneSide.wireValue,
            "preferredPlaybackPrimaryPaneSide" to preferredPlaybackPrimaryPaneSide.wireValue,
        )
    }

    @Synchronized
    fun attachRightPaneHost(activity: FlutterHostActivity) {
        pruneRightPaneHostsLocked()
        val exists =
            rightPaneHostRefs.any { reference ->
                reference.get() === activity
            }
        if (!exists) {
            rightPaneHostRefs += WeakReference(activity)
        }
        rightPaneHostCount = rightPaneHostRefs.size
    }

    @Synchronized
    fun detachRightPaneHost(activity: FlutterHostActivity) {
        rightPaneHostRefs.removeAll { reference ->
            val host = reference.get()
            host == null || host === activity
        }
        rightPaneHostCount = rightPaneHostRefs.size
    }

    @Synchronized
    fun rightPaneHostsSnapshot(): List<FlutterHostActivity> {
        pruneRightPaneHostsLocked()
        rightPaneHostCount = rightPaneHostRefs.size
        return rightPaneHostRefs.mapNotNull { reference -> reference.get() }
    }

    @Synchronized
    fun hasRightPaneHost(): Boolean {
        pruneRightPaneHostsLocked()
        rightPaneHostCount = rightPaneHostRefs.size
        return rightPaneHostCount > 0
    }

    fun clearRightPane() {
        currentDetailItemGuid = ""
        currentDetailRoute = ""
    }

    fun clearSessionUiState() {
        clearRightPane()
        rememberedDetailItemGuid = ""
        rememberedDetailRoute = ""
        lastBrowseSnapshot = null
    }

    @Synchronized
    private fun pruneRightPaneHostsLocked() {
        rightPaneHostRefs.removeAll { reference -> reference.get() == null }
    }

    private fun <T : Any> attachHostReference(activity: T): WeakReference<T> = WeakReference(activity)

    private fun <T : Any> detachHostReference(
        currentRef: WeakReference<T>?,
        activity: T,
    ): WeakReference<T>? {
        val current = currentRef?.get()
        return if (current === activity) {
            null
        } else {
            currentRef
        }
    }
}
