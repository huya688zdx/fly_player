import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/embedded_detail_launcher.dart';
import '../../services/play_stats/play_stats.dart';
import '../../ui/app_transitions.dart';
import '../../l10n/generated/app_localizations.dart';
import 'play_stats_debug_formatters.dart';
import 'play_stats_debug_widgets.dart';

PreferredSizeWidget buildPlayStatsDebugAppBar(
  BuildContext context, {
  required Widget title,
}) {
  return AppBar(
    leading: IconButton(
      onPressed: () {
        unawaited(EmbeddedDetailLauncher.closeHostOrPop(context));
      },
      icon: const Icon(Icons.arrow_back_ios_new_rounded),
    ),
    title: title,
  );
}

class PlayStatsDebugAnimePage extends StatelessWidget {
  final PlayStatsDebugAnimeNode node;
  final PlayStatsDebugFormatters formatters;

  const PlayStatsDebugAnimePage({
    super.key,
    required this.node,
    required this.formatters,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final anime = node.anime;
    return Scaffold(
      appBar: buildPlayStatsDebugAppBar(
        context,
        title: Text(
          anime.title.isEmpty ? l10n.playStatsAnimeDetail : anime.title,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          PlayStatsDebugSectionCard(
            title: l10n.playStatsAnimeFields,
            child: buildDebugRows(_animeRows(anime, formatters)),
          ),
          const SizedBox(height: 12),
          PlayStatsDebugSectionCard(
            title: l10n.playStatsAnimeMetadata,
            child: buildDebugRows(_animeMetadataRows(node, formatters)),
          ),
          const SizedBox(height: 12),
          PlayStatsDebugSectionCard(
            title: l10n.playStatsSeasonList,
            child: node.seasons.isEmpty
                ? Text(l10n.playStatsNoSeasonData)
                : Column(
                    children: node.seasons
                        .map(
                          (seasonNode) => PlayStatsDebugEntryTile(
                            title: seasonNode.season?.title.isNotEmpty == true
                                ? seasonNode.season!.title
                                : l10n.playStatsUnnamedSeason,
                            subtitle: l10n.playStatsSeasonSubtitle(
                              seasonNode.videos.length,
                              seasonNode.season?.completedEpisodeCount ?? 0,
                            ),
                            onTap: () {
                              Navigator.of(context).push(
                                AppTransitions.paneCardRoute<void>(
                                  PlayStatsDebugSeasonPage(
                                    node: seasonNode,
                                    formatters: formatters,
                                  ),
                                ),
                              );
                            },
                          ),
                        )
                        .toList(growable: false),
                  ),
          ),
          if (node.ungroupedVideos.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            PlayStatsDebugSectionCard(
              title: l10n.playStatsUngroupedVideos,
              child: Column(
                children: node.ungroupedVideos
                    .map(
                      (videoNode) =>
                          buildVideoEntry(context, videoNode, formatters),
                    )
                    .toList(growable: false),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PlayStatsDebugSeasonPage extends StatelessWidget {
  final PlayStatsDebugSeasonNode node;
  final PlayStatsDebugFormatters formatters;

  const PlayStatsDebugSeasonPage({
    super.key,
    required this.node,
    required this.formatters,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final season = node.season;
    final credits = seasonCredits(node);
    return Scaffold(
      appBar: buildPlayStatsDebugAppBar(
        context,
        title: Text(
          season?.title.isNotEmpty == true
              ? season!.title
              : l10n.playStatsSeasonDetail,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          PlayStatsDebugSectionCard(
            title: l10n.playStatsSeasonFields,
            child: buildDebugRows(_seasonRows(node, formatters)),
          ),
          if (credits.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            PlayStatsDebugSectionCard(
              title: l10n.playStatsCredits,
              child: PlayStatsDebugCreditCarousel(credits: credits),
            ),
          ],
          const SizedBox(height: 12),
          PlayStatsDebugSectionCard(
            title: l10n.playStatsEpisodeList,
            child: node.videos.isEmpty
                ? Text(l10n.playStatsNoEpisodeData)
                : Column(
                    children: node.videos
                        .map(
                          (videoNode) =>
                              buildVideoEntry(context, videoNode, formatters),
                        )
                        .toList(growable: false),
                  ),
          ),
        ],
      ),
    );
  }
}

class PlayStatsDebugVideoPage extends StatelessWidget {
  final PlayStatsDebugVideoNode node;
  final PlayStatsDebugFormatters formatters;

  const PlayStatsDebugVideoPage({
    super.key,
    required this.node,
    required this.formatters,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final video = node.video;
    final isMovie = video.videoKind.trim().toLowerCase() == 'movie';
    return Scaffold(
      appBar: buildPlayStatsDebugAppBar(
        context,
        title: Text(
          video.title.isEmpty ? l10n.playStatsVideoDetail : video.title,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          PlayStatsDebugSectionCard(
            title: isMovie
                ? l10n.playStatsMovieFields
                : l10n.playStatsEpisodeFields,
            child: buildDebugRows(_videoRows(video, formatters)),
          ),
          if (isMovie) ...<Widget>[
            const SizedBox(height: 12),
            PlayStatsDebugSectionCard(
              title: l10n.playStatsCredits,
              child: PlayStatsDebugCreditCarousel(credits: video.credits),
            ),
          ],
          const SizedBox(height: 12),
          PlayStatsDebugSectionCard(
            title: l10n.playStatsPlaybackHistory,
            child: node.history.isEmpty
                ? Text(l10n.playStatsNoPlaybackHistory)
                : PlayStatsDebugHistoryPager(
                    items: node.history,
                    formatters: formatters,
                    itemBuilder: (context, item) =>
                        buildHistoryEntry(context, item, formatters),
                  ),
          ),
        ],
      ),
    );
  }
}

class PlayStatsDebugHistoryListPage extends StatelessWidget {
  final String title;
  final List<PlayHistoryRecord> items;
  final PlayStatsDebugFormatters formatters;

  const PlayStatsDebugHistoryListPage({
    super.key,
    required this.title,
    required this.items,
    required this.formatters,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildPlayStatsDebugAppBar(context, title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          PlayStatsDebugHistoryPager(
            items: items,
            formatters: formatters,
            itemBuilder: (context, item) =>
                buildHistoryEntry(context, item, formatters),
          ),
        ],
      ),
    );
  }
}

class PlayStatsDebugHistoryDetailPage extends StatelessWidget {
  final PlayHistoryRecord item;
  final PlayStatsDebugFormatters formatters;

  const PlayStatsDebugHistoryDetailPage({
    super.key,
    required this.item,
    required this.formatters,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: buildPlayStatsDebugAppBar(
        context,
        title: Text(
          item.title.isEmpty ? l10n.playStatsHistoryDetail : item.title,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          PlayStatsDebugSectionCard(
            title: l10n.playStatsHistoryFields,
            child: buildDebugRows(_historyRows(item, formatters)),
          ),
        ],
      ),
    );
  }
}

PlayStatsDebugEntryTile buildVideoEntry(
  BuildContext context,
  PlayStatsDebugVideoNode node,
  PlayStatsDebugFormatters formatters, {
  String? subtitleOverride,
}) {
  final l10n = formatters.l10n;
  return PlayStatsDebugEntryTile(
    title: node.video.title.isEmpty
        ? l10n.playStatsUnnamedVideo
        : node.video.title,
    subtitle:
        subtitleOverride ??
        l10n.playStatsVideoSubtitle(node.history.length, node.video.viewCount),
    onTap: () {
      Navigator.of(context).push(
        AppTransitions.paneCardRoute<void>(
          PlayStatsDebugVideoPage(node: node, formatters: formatters),
        ),
      );
    },
  );
}

PlayStatsDebugEntryTile buildHistoryEntry(
  BuildContext context,
  PlayHistoryRecord item,
  PlayStatsDebugFormatters formatters,
) {
  final l10n = formatters.l10n;
  return PlayStatsDebugEntryTile(
    title: item.title.isEmpty
        ? formatters.dateTime(item.startedAtMs)
        : item.title,
    subtitle: l10n.playStatsHistoryEntrySubtitle(
      formatters.dateTime(item.startedAtMs),
      formatters.duration(item.watchedMs),
      formatters.yesNo(item.countedAsCompleted),
    ),
    onTap: () {
      Navigator.of(context).push(
        AppTransitions.paneCardRoute<void>(
          PlayStatsDebugHistoryDetailPage(item: item, formatters: formatters),
        ),
      );
    },
  );
}

List<PlayStatsCredit> seasonCredits(PlayStatsDebugSeasonNode node) {
  for (final videoNode in node.videos) {
    if (videoNode.video.credits.isNotEmpty) {
      return videoNode.video.credits;
    }
  }
  return const <PlayStatsCredit>[];
}

List<PlayStatsDebugRowData> _animeRows(
  AnimeStatsRecord anime,
  PlayStatsDebugFormatters f,
) {
  final l10n = f.l10n;
  return <PlayStatsDebugRowData>[
    PlayStatsDebugRowData(l10n.playStatsFieldAnimeId, anime.animeId),
    PlayStatsDebugRowData(l10n.playStatsFieldTitle, anime.title),
    PlayStatsDebugRowData(l10n.playStatsFieldClickCount, '${anime.clickCount}'),
    PlayStatsDebugRowData(l10n.playStatsFieldViewCount, '${anime.viewCount}'),
    PlayStatsDebugRowData(
      l10n.playStatsFieldTotalPlayedDuration,
      f.duration(anime.totalPlayedMs),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldForwardSeekCount,
      '${anime.forwardSeekCount}',
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldBackwardSeekCount,
      '${anime.backwardSeekCount}',
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldWatchedEpisodeCount,
      '${anime.watchedEpisodeCount}',
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldCompletedEpisodeCount,
      '${anime.completedEpisodeCount}',
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldCompletedSeasonCount,
      '${anime.completedSeasonCount}',
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldLastPlayedAt,
      f.dateTime(anime.lastPlayedAtMs),
    ),
  ];
}

List<PlayStatsDebugRowData> _animeMetadataRows(
  PlayStatsDebugAnimeNode node,
  PlayStatsDebugFormatters f,
) {
  VideoStatsRecord? metadataVideo;
  for (final season in node.seasons) {
    if (season.videos.isNotEmpty) {
      metadataVideo = season.videos.first.video;
      break;
    }
  }
  metadataVideo ??= node.ungroupedVideos.isNotEmpty
      ? node.ungroupedVideos.first.video
      : null;
  final l10n = f.l10n;
  return <PlayStatsDebugRowData>[
    PlayStatsDebugRowData(
      l10n.playStatsFieldYear,
      f.zeroAsDash(metadataVideo?.year ?? 0),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldCountryFirstValue,
      f.empty(metadataVideo?.country ?? ''),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldCountryCodes,
      f.joinStrings(metadataVideo?.countryCodes ?? const <String>[]),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldCountryNames,
      f.countryNames(metadataVideo?.countryCodes ?? const <String>[]),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldGenreIds,
      f.joinInts(metadataVideo?.genreIds ?? const <int>[]),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldGenreNames,
      f.genreNames(metadataVideo?.genreIds ?? const <int>[]),
    ),
  ];
}

List<PlayStatsDebugRowData> _seasonRows(
  PlayStatsDebugSeasonNode node,
  PlayStatsDebugFormatters f,
) {
  final season = node.season;
  final l10n = f.l10n;
  return <PlayStatsDebugRowData>[
    PlayStatsDebugRowData(l10n.playStatsFieldSeasonId, season?.seasonId ?? ''),
    PlayStatsDebugRowData(l10n.playStatsFieldAnimeId, season?.animeId ?? ''),
    PlayStatsDebugRowData(l10n.playStatsFieldTitle, season?.title ?? ''),
    PlayStatsDebugRowData(
      l10n.playStatsFieldTotalEpisodeCount,
      '${season?.totalEpisodeCount ?? 0}',
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldWatchedEpisodeCountShort,
      '${season?.watchedEpisodeCount ?? 0}',
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldCompletedEpisodeCountShort,
      '${season?.completedEpisodeCount ?? 0}',
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldIsSeasonCompleted,
      f.yesNo(season?.isCompleted == true),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldLastPlayedAt,
      f.dateTime(season?.lastPlayedAtMs ?? 0),
    ),
  ];
}

List<PlayStatsDebugRowData> _videoRows(
  VideoStatsRecord video,
  PlayStatsDebugFormatters f,
) {
  final l10n = f.l10n;
  return <PlayStatsDebugRowData>[
    PlayStatsDebugRowData(l10n.playStatsFieldVideoId, video.videoId),
    PlayStatsDebugRowData(l10n.playStatsFieldAnimeId, video.animeId),
    PlayStatsDebugRowData(l10n.playStatsFieldSeasonId, video.seasonId),
    PlayStatsDebugRowData(l10n.playStatsFieldTitle, video.title),
    PlayStatsDebugRowData(l10n.playStatsFieldAnimeTitle, video.animeTitle),
    PlayStatsDebugRowData(l10n.playStatsFieldSeasonTitle, video.seasonTitle),
    PlayStatsDebugRowData(l10n.playStatsFieldVideoKind, video.videoKind),
    PlayStatsDebugRowData(
      l10n.playStatsFieldCountsTowardCompletion,
      f.yesNo(video.countsTowardCompletion),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldMediaDuration,
      f.duration(video.mediaDurationMs),
    ),
    PlayStatsDebugRowData(l10n.playStatsFieldClickCount, '${video.clickCount}'),
    PlayStatsDebugRowData(
      l10n.playStatsFieldAutoPlayCount,
      '${video.autoPlayCount}',
    ),
    PlayStatsDebugRowData(l10n.playStatsFieldViewCount, '${video.viewCount}'),
    PlayStatsDebugRowData(
      l10n.playStatsFieldTotalPlayedDuration,
      f.duration(video.totalPlayedMs),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldMaxProgress,
      f.percent(video.maxProgress),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldLastProgress,
      f.percent(video.lastProgress),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldLastPosition,
      f.duration(video.lastPositionMs),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldCompleted,
      f.yesNo(video.completed),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldMetadataEnriched,
      f.yesNo(video.metadataEnriched),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldLastPlayedAt,
      f.dateTime(video.lastPlayedAtMs),
    ),
  ];
}

List<PlayStatsDebugRowData> _historyRows(
  PlayHistoryRecord item,
  PlayStatsDebugFormatters f,
) {
  final l10n = f.l10n;
  return <PlayStatsDebugRowData>[
    PlayStatsDebugRowData(l10n.playStatsFieldHistoryId, item.historyId),
    PlayStatsDebugRowData(l10n.playStatsFieldVideoId, item.videoId),
    PlayStatsDebugRowData(l10n.playStatsFieldAnimeId, item.animeId),
    PlayStatsDebugRowData(l10n.playStatsFieldSeasonId, item.seasonId),
    PlayStatsDebugRowData(l10n.playStatsFieldTitle, item.title),
    PlayStatsDebugRowData(l10n.playStatsFieldAnimeTitle, item.animeTitle),
    PlayStatsDebugRowData(l10n.playStatsFieldSeasonTitle, item.seasonTitle),
    PlayStatsDebugRowData(l10n.playStatsFieldVideoKind, item.videoKind),
    PlayStatsDebugRowData(
      l10n.playStatsFieldCountsTowardCompletion,
      f.yesNo(item.countsTowardCompletion),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldStartSource,
      f.startSource(item.startSource),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldStartedAt,
      f.dateTime(item.startedAtMs),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldEndedAt,
      f.dateTime(item.endedAtMs),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldMediaDuration,
      f.duration(item.mediaDurationMs),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldWatchedDuration,
      f.duration(item.watchedMs),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldMaxProgress,
      f.percent(item.maxProgress),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldMaxPosition,
      f.duration(item.maxPositionMs),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldCountedAsView,
      f.yesNo(item.countedAsView),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldCountedAsCompleted,
      f.yesNo(item.countedAsCompleted),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldCountryCodes,
      f.joinStrings(item.countryCodes),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldCountryNames,
      f.countryNames(item.countryCodes),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldGenreIds,
      f.joinInts(item.genreIds),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldGenreNames,
      f.genreNames(item.genreIds),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldOpDetected,
      f.yesNo(item.opDetected),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldEdDetected,
      f.yesNo(item.edDetected),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldOpSkipped,
      f.yesNo(item.opSkipped),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldEdSkipped,
      f.yesNo(item.edSkipped),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldOpNotSkipped,
      f.yesNo(item.opNotSkipped),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldEdNotSkipped,
      f.yesNo(item.edNotSkipped),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldOpPlayedDuration,
      f.duration(item.opPlayedMs),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldEdPlayedDuration,
      f.duration(item.edPlayedMs),
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldForwardSeekCount,
      '${item.forwardSeekCount}',
    ),
    PlayStatsDebugRowData(
      l10n.playStatsFieldBackwardSeekCount,
      '${item.backwardSeekCount}',
    ),
  ];
}
