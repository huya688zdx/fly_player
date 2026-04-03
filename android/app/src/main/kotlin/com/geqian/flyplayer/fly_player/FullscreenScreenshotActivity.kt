package com.geqian.flyplayer.fly_player

import android.content.Context
import android.content.Intent
import android.net.Uri

object ScreenshotLightboxActivityContract {
    private const val ROUTE_PATH = "/screen/screenshot/lightbox"
    private const val PAYLOAD_TOKEN_KEY = "payloadToken"

    fun buildRouteName(token: String): String {
        return Uri.Builder()
            .path(ROUTE_PATH)
            .appendQueryParameter(PAYLOAD_TOKEN_KEY, token.trim())
            .build()
            .toString()
    }
}

class FullscreenScreenshotActivity : FlutterHostActivity() {
    override fun getInitialRoute(): String =
        intent.getStringExtra(EXTRA_INITIAL_ROUTE)?.trim().orEmpty().ifEmpty {
            "/"
        }

    override fun hostSurface(): String = "screenshot"

    override fun hostPaneSide(): ParallelPaneSide = ParallelPaneSide.FULLSCREEN

    override fun hostRoleOverride(): ParallelHostRole = ParallelHostRole.FULLSCREEN

    override fun finish() {
        super.finish()
        overridePendingTransition(
            R.anim.screenshot_activity_close_enter,
            R.anim.screenshot_activity_close_exit,
        )
    }

    companion object {
        private const val EXTRA_INITIAL_ROUTE = "initial_route"

        fun createIntent(
            context: Context,
            routeName: String,
        ): Intent {
            return Intent(context, FullscreenScreenshotActivity::class.java).apply {
                putExtra(EXTRA_INITIAL_ROUTE, routeName.trim())
            }
        }
    }
}
