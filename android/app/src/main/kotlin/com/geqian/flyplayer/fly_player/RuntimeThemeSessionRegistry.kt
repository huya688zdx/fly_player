package com.geqian.flyplayer.fly_player

import android.os.Process
import java.util.UUID

object RuntimeThemeSessionRegistry {
    val sessionId: String = "${Process.myPid()}-${UUID.randomUUID()}"
}
