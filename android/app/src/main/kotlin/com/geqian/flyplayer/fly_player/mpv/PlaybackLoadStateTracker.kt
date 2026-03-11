package com.geqian.flyplayer.fly_player.mpv

class PlaybackLoadStateTracker {
    var loadedSourceUrl: String? = null
        private set
    var loadingSourceUrl: String? = null
        private set
    var activePlaybackUrl: String? = null
        private set
    var pendingLoadRequested: Boolean = false
        private set
    var sourceFileLoaded: Boolean = false
        private set

    fun reset() {
        loadedSourceUrl = null
        loadingSourceUrl = null
        activePlaybackUrl = null
        pendingLoadRequested = false
        sourceFileLoaded = false
    }

    fun resetForSource(sourceUrl: String) {
        loadedSourceUrl = null
        loadingSourceUrl = null
        activePlaybackUrl = null
        sourceFileLoaded = false
        pendingLoadRequested = sourceUrl.isNotBlank()
    }

    fun requestLoad(sourceUrl: String) {
        pendingLoadRequested = sourceUrl.isNotBlank()
    }

    fun clearPendingLoad() {
        pendingLoadRequested = false
    }

    fun onLoadCommandStarted(sourceUrl: String, playbackUrl: String) {
        loadingSourceUrl = sourceUrl
        activePlaybackUrl = playbackUrl
        sourceFileLoaded = false
    }

    fun onLoadCommandFailed() {
        loadingSourceUrl = null
    }

    fun takeLoadingSourceUrl(): String? {
        val completed = loadingSourceUrl
        loadingSourceUrl = null
        return completed
    }

    fun markCurrentSourceLoaded(sourceUrl: String) {
        pendingLoadRequested = false
        loadedSourceUrl = sourceUrl
        sourceFileLoaded = true
    }

    fun markSourceFileLoaded() {
        sourceFileLoaded = true
    }

    fun clearSourceFileLoaded() {
        sourceFileLoaded = false
    }

    fun clearLoadedSource() {
        loadedSourceUrl = null
        loadingSourceUrl = null
        sourceFileLoaded = false
    }

    fun clearForRecovery(sourceUrl: String) {
        pendingLoadRequested = sourceUrl.isNotBlank()
        loadedSourceUrl = null
        loadingSourceUrl = null
        sourceFileLoaded = false
    }

    fun clearForProxyFailure() {
        sourceFileLoaded = false
        loadedSourceUrl = null
        loadingSourceUrl = null
        pendingLoadRequested = false
    }

    fun hasLoadedSource(sourceUrl: String): Boolean {
        return loadedSourceUrl == sourceUrl && loadedSourceUrl != null
    }

    fun shouldStartLoad(sourceUrl: String): Boolean {
        return sourceUrl.isNotBlank() &&
            loadedSourceUrl != sourceUrl &&
            loadingSourceUrl != sourceUrl
    }

    fun shouldRunDeferredLoad(sourceUrl: String): Boolean {
        return pendingLoadRequested && loadingSourceUrl != sourceUrl
    }

    fun isCurrentSourceStable(sourceUrl: String): Boolean {
        return sourceFileLoaded &&
            loadingSourceUrl == null &&
            loadedSourceUrl == sourceUrl
    }
}
