package com.geqian.flyplayer.fly_player

/** Catalog ownership survives Activity reuse independently of its current Intent. */
internal class NativeEpisodeCatalog {
    private var scope = ""
    private var series = ""
    private var season = ""
    var generation = 0
        private set
    val episodes = HashMap<String, List<Map<String, Any?>>>()

    fun canReuse(args: Map<String, Any?>): Boolean {
        val nextScope = args["playbackSessionScope"]?.toString().orEmpty()
        val nextSeries = args["seriesGuid"]?.toString().orEmpty()
        val nextSeason = args["seasonGuid"]?.toString().orEmpty()
        val sameSeries = if (series.isNotEmpty() && nextSeries.isNotEmpty()) {
            series == nextSeries
        } else {
            season.isNotEmpty() && season == nextSeason
        }
        return scope.isNotEmpty() && scope == nextScope && sameSeries
    }

    fun select(args: Map<String, Any?>): Boolean {
        val reuse = canReuse(args)
        scope = args["playbackSessionScope"]?.toString().orEmpty()
        series = args["seriesGuid"]?.toString().orEmpty()
        season = args["seasonGuid"]?.toString().orEmpty()
        if (!reuse) { ++generation; episodes.clear() }
        return reuse
    }

    fun complete(requestGeneration: Int, seasonGuid: String, result: List<Map<String, Any?>>): Boolean {
        if (requestGeneration != generation) return false
        if (result.isNotEmpty()) episodes[seasonGuid] = result
        return true
    }
}
