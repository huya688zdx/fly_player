package com.geqian.flyplayer.fly_player

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class PlaybackCommandReceiver : BroadcastReceiver() {
    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        when (intent.action) {
            ACTION_PLAY -> PlaybackSessionCoordinator.dispatchCommand("systemPlay")
            ACTION_PAUSE -> PlaybackSessionCoordinator.dispatchCommand("systemPause")
            ACTION_SKIP_TO_PREVIOUS -> PlaybackSessionCoordinator.dispatchCommand("systemSkipToPrevious")
            ACTION_SKIP_TO_NEXT -> PlaybackSessionCoordinator.dispatchCommand("systemSkipToNext")
        }
    }

    companion object {
        const val ACTION_PLAY = "com.geqian.flyplayer.fly_player.action.PLAYBACK_PLAY"
        const val ACTION_PAUSE = "com.geqian.flyplayer.fly_player.action.PLAYBACK_PAUSE"
        const val ACTION_SKIP_TO_PREVIOUS =
            "com.geqian.flyplayer.fly_player.action.PLAYBACK_SKIP_TO_PREVIOUS"
        const val ACTION_SKIP_TO_NEXT =
            "com.geqian.flyplayer.fly_player.action.PLAYBACK_SKIP_TO_NEXT"
    }
}
