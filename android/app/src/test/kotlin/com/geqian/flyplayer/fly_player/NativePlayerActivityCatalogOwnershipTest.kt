package com.geqian.flyplayer.fly_player

import org.junit.Assert.*
import org.junit.Test

/** Runs the Activity's actual catalog transition method with mockable Android APIs. */
class NativePlayerActivityCatalogOwnershipTest {
    private fun field(player: NativePlayerActivity, name: String): Any? =
        NativePlayerActivity::class.java.getDeclaredField(name).apply { isAccessible = true }.get(player)

    private fun select(player: NativePlayerActivity, scope: String, season: String = "season-1") {
        val method = NativePlayerActivity::class.java.getDeclaredMethod("selectEpisodeCatalog", Map::class.java)
        method.isAccessible = true
        method.invoke(player, mapOf("playbackSessionScope" to scope, "seriesGuid" to "series", "seasonGuid" to season))
    }

    @Test fun activityInvalidatesOldCatalogAndRequestWaitersBeforeNewLoadApplies() {
        val player = NativePlayerActivity()
        select(player, "server/account-A")
        val catalog = field(player, "episodeCatalog") as NativeEpisodeCatalog
        val generation = catalog.generation
        catalog.episodes["season-1"] = listOf(mapOf("guid" to "account-A-episode"))
        @Suppress("UNCHECKED_CAST")
        val requests = field(player, "seasonEpisodeRequests") as MutableMap<String, MutableList<(List<Map<String, Any?>>) -> Unit>>
        var delivered = false
        requests["season-1"] = mutableListOf({ delivered = true })
        val oldPanelToken = field(player, "episodePanelLoadToken") as Int
        select(player, "server/account-B")
        assertTrue(requests.isEmpty())
        assertTrue(catalog.episodes.isEmpty())
        assertTrue((field(player, "episodePanelLoadToken") as Int) > oldPanelToken)
        assertFalse(catalog.complete(generation, "season-1", listOf(mapOf("guid" to "late-account-A"))))
        assertFalse(delivered)
    }

    @Test fun activityKeepsSameAccountCrossSeasonCatalogAndRequestWaiters() {
        val player = NativePlayerActivity()
        select(player, "server/account")
        val catalog = field(player, "episodeCatalog") as NativeEpisodeCatalog
        val generation = catalog.generation
        catalog.episodes["season-1"] = listOf(mapOf("guid" to "episode"))
        @Suppress("UNCHECKED_CAST")
        val requests = field(player, "seasonEpisodeRequests") as MutableMap<String, MutableList<(List<Map<String, Any?>>) -> Unit>>
        requests["season-2"] = mutableListOf({})
        select(player, "server/account", "season-2")
        assertEquals(generation, catalog.generation)
        assertTrue(catalog.episodes.containsKey("season-1"))
        assertTrue(requests.containsKey("season-2"))
    }
}
