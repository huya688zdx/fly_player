package com.geqian.flyplayer.fly_player

import org.junit.Assert.*
import org.junit.Test

class NativeEpisodeCatalogTest {
    private fun args(scope: String, series: String = "series", season: String = "season-1") =
        mapOf<String, Any?>("playbackSessionScope" to scope, "seriesGuid" to series, "seasonGuid" to season)

    @Test fun accountAndServerSwitchRejectOldSeasonResponseEvenWithIdenticalIds() {
        for (nextScope in listOf("server/user-B", "other-server/user-A")) {
            val catalog = NativeEpisodeCatalog()
            catalog.select(args("server/user-A"))
            val generation = catalog.generation
            catalog.episodes["season-1"] = listOf(mapOf("guid" to "old-user-episode"))
            assertFalse(catalog.select(args(nextScope)))
            assertTrue(catalog.episodes.isEmpty())
            assertFalse(catalog.complete(generation, "season-1", listOf(mapOf("guid" to "late-old"))))
            assertTrue(catalog.episodes.isEmpty())
        }
    }

    @Test fun sameAccountCrossSeasonKeepsVisitedSeasonsAndInflightRequest() {
        val catalog = NativeEpisodeCatalog()
        catalog.select(args("server/user"))
        val generation = catalog.generation
        catalog.episodes["season-1"] = listOf(mapOf("guid" to "episode-1"))
        assertTrue(catalog.select(args("server/user", season = "season-2")))
        assertEquals(generation, catalog.generation)
        assertTrue(catalog.complete(generation, "season-2", listOf(mapOf("guid" to "episode-2"))))
        assertEquals(setOf("season-1", "season-2"), catalog.episodes.keys)
    }

    @Test fun knownSeasonCanRetainWhenSeriesIdIsAbsent() {
        val catalog = NativeEpisodeCatalog()
        catalog.select(args("server/user", series = ""))
        assertTrue(catalog.select(args("server/user", series = "")))
    }

    @Test fun oldReplyCannotReplaceNewAccountReplyForTheSameSeason() {
        val catalog = NativeEpisodeCatalog()
        catalog.select(args("server/old"))
        val oldGeneration = catalog.generation
        catalog.select(args("server/new"))
        assertTrue(catalog.complete(catalog.generation, "season-1", listOf(mapOf("guid" to "new"))))
        assertFalse(catalog.complete(oldGeneration, "season-1", listOf(mapOf("guid" to "old"))))
        assertEquals("new", catalog.episodes["season-1"]!!.single()["guid"])
    }

    @Test fun differentSeriesCannotReuseEvenWhenSeasonIdsCollide() {
        val catalog = NativeEpisodeCatalog()
        catalog.select(args("server/user"))
        assertFalse(catalog.select(args("server/user", series = "other-series")))
    }

    @Test fun unknownScopeOrUnknownCatalogCannotInherit() {
        for (scope in listOf("", "server/user")) {
            val catalog = NativeEpisodeCatalog()
            catalog.select(args(scope, series = "", season = ""))
            assertFalse(catalog.select(args(scope, series = "", season = "")))
        }
        val catalog = NativeEpisodeCatalog()
        catalog.select(args(""))
        assertFalse(catalog.select(args("")))
    }
}
