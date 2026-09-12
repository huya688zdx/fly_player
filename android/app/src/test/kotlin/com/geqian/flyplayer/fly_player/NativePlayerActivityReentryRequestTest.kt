package com.geqian.flyplayer.fly_player

import org.junit.Assert.*
import org.junit.Test

/** Calls the Activity's actual shortcut and request-owner methods; no decoder. */
class NativePlayerActivityReentryRequestTest {
    private fun set(player: NativePlayerActivity, name: String, value: Any) {
        NativePlayerActivity::class.java.getDeclaredField(name).apply { isAccessible = true }.set(player, value)
    }

    private fun get(player: NativePlayerActivity, name: String): Any? =
        NativePlayerActivity::class.java.getDeclaredField(name).apply { isAccessible = true }.get(player)

    private fun call(player: NativePlayerActivity, name: String, vararg args: Any): Any? {
        val method = NativePlayerActivity::class.java.declaredMethods.single { it.name == name }
        method.isAccessible = true
        return method.invoke(player, *args)
    }

    private fun source(scope: String = "server/account", series: String = "", season: String = "") =
        mapOf<String, Any?>("itemGuid" to "item", "mediaGuid" to "media", "playbackSessionScope" to scope,
            "seriesGuid" to series, "seasonGuid" to season)

    private fun player(args: Map<String, Any?> = source()): NativePlayerActivity = NativePlayerActivity().also {
        set(it, "loadArgsMap", args)
        set(it, "playbackSessionScope", args["playbackSessionScope"]!!)
        call(it, "selectEpisodeCatalog", args)
    }

    private fun keep(player: NativePlayerActivity, args: Map<String, Any?>, parked: Boolean = false) =
        call(player, "canKeepCurrentPlayback", args, parked) as Boolean

    @Test fun sameMovieWithoutCatalogKeepsPlaybackWhileUnknownCatalogStillCannotBeInherited() {
        val source = source()
        val player = player(source)
        assertTrue(keep(player, source))
        val catalog = get(player, "episodeCatalog") as NativeEpisodeCatalog
        assertFalse(catalog.canReuse(source))
    }

    @Test fun currentMovieRejectsDifferentScopeItemMediaAndInvalidPlayingIdentity() {
        val source = source()
        val player = player(source)
        assertFalse(keep(player, source("server/other-account")))
        assertFalse(keep(player, source + ("itemGuid" to "other-item")))
        assertFalse(keep(player, source + ("mediaGuid" to "other-media")))
        assertFalse(keep(player, source + ("itemGuid" to "")))
        assertFalse(keep(player, source, parked = true))
        set(player, "mediaLoadPending", true)
        assertFalse(keep(player, source))
    }

    @Test fun explicitSeriesOrSeasonConflictRequiresReload() {
        val original = source(series = "series", season = "season-1")
        val player = player(original)
        assertTrue(keep(player, original))
        assertFalse(keep(player, source(series = "other-series", season = "season-1")))
        assertFalse(keep(player, source(series = "series", season = "season-2")))
        val noSeries = player(source(season = "season-1"))
        assertFalse(keep(noSeries, source(season = "season-2")))
    }

    @Test fun missingDirectoryMetadataDoesNotInterruptSameKnownPlayingIdentity() {
        assertTrue(keep(player(source(series = "series", season = "season")), source()))
        assertTrue(keep(player(), source(series = "series", season = "season")))
    }

    private fun begin(player: NativePlayerActivity): Any = call(player, "beginPlaybackResolveRequest")!!
    private fun current(player: NativePlayerActivity, request: Any) = call(player, "canApplyPlaybackResolveRequest", request) as Boolean

    @Test fun newestRequestWinsInBothCompletionOrders() {
        for (oldFirst in listOf(true, false)) {
            val player = player()
            val old = begin(player)
            val latest = begin(player)
            val arrived = if (oldFirst) listOf(old to "A", latest to "B") else listOf(latest to "B", old to "A")
            val applied = mutableListOf<String>()
            for ((request, label) in arrived) {
                if (current(player, request)) {
                    applied += label
                    // Successful applyEpisodeResult advances the media-load
                    // generation. Keep that boundary in both reply orders.
                    set(player, "mediaLoadGeneration", (get(player, "mediaLoadGeneration") as Int) + 1)
                }
            }
            assertEquals(listOf("B"), applied)
        }
    }

    @Test fun staleErrorsCannotReplaceLatestSuccessAndLatestFailureCannotReviveOldSuccess() {
        val player = player()
        val old = begin(player)
        val latest = begin(player)
        assertFalse("old error must be ignored", current(player, old))
        assertTrue("latest success or failure remains current", current(player, latest))
        assertFalse("latest failure does not authorize old success", current(player, old))
    }

    @Test fun requestIntentDoesNotInvalidateCurrentMediaPreloadsOrCatalog() {
        val player = player(source(series = "series", season = "season"))
        val mediaGeneration = get(player, "mediaLoadGeneration")
        val catalog = get(player, "episodeCatalog") as NativeEpisodeCatalog
        val catalogGeneration = catalog.generation
        begin(player)
        begin(player)
        assertEquals(mediaGeneration, get(player, "mediaLoadGeneration"))
        assertEquals(catalogGeneration, catalog.generation)
        assertFalse(get(player, "mediaLoadPending") as Boolean)
    }

    @Test fun newIntentOrScopeLoadStillInvalidatesPreviousResolveOwner() {
        val player = player()
        val request = begin(player)
        val mediaGeneration = get(player, "mediaLoadGeneration")
        call(player, "invalidatePlaybackResolveRequests")
        assertFalse(current(player, request))
        assertEquals(mediaGeneration, get(player, "mediaLoadGeneration"))
        val nextRequest = begin(player)
        set(player, "mediaLoadGeneration", (get(player, "mediaLoadGeneration") as Int) + 1)
        assertFalse(current(player, nextRequest))
        assertTrue(current(player, begin(player)))
    }
}
