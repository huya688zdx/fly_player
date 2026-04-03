import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/embedded_detail_launcher.dart';
import '../../services/play_stats/play_stats.dart';
import '../../ui/app_transitions.dart';
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
    final anime = node.anime;
    return Scaffold(
      appBar: buildPlayStatsDebugAppBar(
        context,
        title: Text(anime.title.isEmpty ? '番剧详情' : anime.title),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          PlayStatsDebugSectionCard(
            title: '番剧字段',
            child: buildDebugRows(_animeRows(anime, formatters)),
          ),
          const SizedBox(height: 12),
          PlayStatsDebugSectionCard(
            title: '番剧元数据',
            child: buildDebugRows(_animeMetadataRows(node, formatters)),
          ),
          const SizedBox(height: 12),
          PlayStatsDebugSectionCard(
            title: '季度列表',
            child: node.seasons.isEmpty
                ? const Text('没有季度数据。')
                : Column(
                    children: node.seasons
                        .map(
                          (seasonNode) => PlayStatsDebugEntryTile(
                            title: seasonNode.season?.title.isNotEmpty == true
                                ? seasonNode.season!.title
                                : '未命名季度',
                            subtitle:
                                '剧集 ${seasonNode.videos.length} / 已完播 ${seasonNode.season?.completedEpisodeCount ?? 0}',
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
              title: '未归属到季度的视频',
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
    final season = node.season;
    final credits = seasonCredits(node);
    return Scaffold(
      appBar: buildPlayStatsDebugAppBar(
        context,
        title: Text(season?.title.isNotEmpty == true ? season!.title : '季度详情'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          PlayStatsDebugSectionCard(
            title: '季度字段',
            child: buildDebugRows(_seasonRows(node, formatters)),
          ),
          if (credits.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            PlayStatsDebugSectionCard(
              title: '演职人员',
              child: PlayStatsDebugCreditCarousel(credits: credits),
            ),
          ],
          const SizedBox(height: 12),
          PlayStatsDebugSectionCard(
            title: '剧集列表',
            child: node.videos.isEmpty
                ? const Text('没有剧集数据。')
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
    final video = node.video;
    final isMovie = video.videoKind.trim().toLowerCase() == 'movie';
    return Scaffold(
      appBar: buildPlayStatsDebugAppBar(
        context,
        title: Text(video.title.isEmpty ? '视频详情' : video.title),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          PlayStatsDebugSectionCard(
            title: isMovie ? '电影字段' : '剧集字段',
            child: buildDebugRows(_videoRows(video, formatters)),
          ),
          if (isMovie) ...<Widget>[
            const SizedBox(height: 12),
            PlayStatsDebugSectionCard(
              title: '演职人员',
              child: PlayStatsDebugCreditCarousel(credits: video.credits),
            ),
          ],
          const SizedBox(height: 12),
          PlayStatsDebugSectionCard(
            title: '播放历史',
            child: node.history.isEmpty
                ? const Text('没有播放历史。')
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
    return Scaffold(
      appBar: buildPlayStatsDebugAppBar(
        context,
        title: Text(item.title.isEmpty ? '播放历史详情' : item.title),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          PlayStatsDebugSectionCard(
            title: '历史字段',
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
  return PlayStatsDebugEntryTile(
    title: node.video.title.isEmpty ? '未命名视频' : node.video.title,
    subtitle:
        subtitleOverride ??
        '历史 ${node.history.length} 条 / 观看数 ${node.video.viewCount}',
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
  return PlayStatsDebugEntryTile(
    title: item.title.isEmpty
        ? formatters.dateTime(item.startedAtMs)
        : item.title,
    subtitle:
        '${formatters.dateTime(item.startedAtMs)} / 观看 ${formatters.duration(item.watchedMs)} / 完播 ${formatters.yesNo(item.countedAsCompleted)}',
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
  return <PlayStatsDebugRowData>[
    PlayStatsDebugRowData('番剧 ID', anime.animeId),
    PlayStatsDebugRowData('标题', anime.title),
    PlayStatsDebugRowData('点击数', '${anime.clickCount}'),
    PlayStatsDebugRowData('观看数', '${anime.viewCount}'),
    PlayStatsDebugRowData('累计播放时长', f.duration(anime.totalPlayedMs)),
    PlayStatsDebugRowData('快进次数', '${anime.forwardSeekCount}'),
    PlayStatsDebugRowData('回退次数', '${anime.backwardSeekCount}'),
    PlayStatsDebugRowData('已观看正片集数', '${anime.watchedEpisodeCount}'),
    PlayStatsDebugRowData('已完播正片集数', '${anime.completedEpisodeCount}'),
    PlayStatsDebugRowData('已完播季数', '${anime.completedSeasonCount}'),
    PlayStatsDebugRowData('上次播放时间', f.dateTime(anime.lastPlayedAtMs)),
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
  return <PlayStatsDebugRowData>[
    PlayStatsDebugRowData('年份', f.zeroAsDash(metadataVideo?.year ?? 0)),
    PlayStatsDebugRowData('国家首值', f.empty(metadataVideo?.country ?? '')),
    PlayStatsDebugRowData(
      '国家地区代码',
      f.joinStrings(metadataVideo?.countryCodes ?? const <String>[]),
    ),
    PlayStatsDebugRowData(
      '国家地区中文',
      f.countryNames(metadataVideo?.countryCodes ?? const <String>[]),
    ),
    PlayStatsDebugRowData(
      '类型 ID',
      f.joinInts(metadataVideo?.genreIds ?? const <int>[]),
    ),
    PlayStatsDebugRowData(
      '类型中文',
      f.genreNames(metadataVideo?.genreIds ?? const <int>[]),
    ),
  ];
}

List<PlayStatsDebugRowData> _seasonRows(
  PlayStatsDebugSeasonNode node,
  PlayStatsDebugFormatters f,
) {
  final season = node.season;
  return <PlayStatsDebugRowData>[
    PlayStatsDebugRowData('季度 ID', season?.seasonId ?? ''),
    PlayStatsDebugRowData('番剧 ID', season?.animeId ?? ''),
    PlayStatsDebugRowData('标题', season?.title ?? ''),
    PlayStatsDebugRowData('总正片集数', '${season?.totalEpisodeCount ?? 0}'),
    PlayStatsDebugRowData('已观看集数', '${season?.watchedEpisodeCount ?? 0}'),
    PlayStatsDebugRowData('已完播集数', '${season?.completedEpisodeCount ?? 0}'),
    PlayStatsDebugRowData('是否季完播', f.yesNo(season?.isCompleted == true)),
    PlayStatsDebugRowData('上次播放时间', f.dateTime(season?.lastPlayedAtMs ?? 0)),
  ];
}

List<PlayStatsDebugRowData> _videoRows(
  VideoStatsRecord video,
  PlayStatsDebugFormatters f,
) {
  return <PlayStatsDebugRowData>[
    PlayStatsDebugRowData('视频 ID', video.videoId),
    PlayStatsDebugRowData('番剧 ID', video.animeId),
    PlayStatsDebugRowData('季度 ID', video.seasonId),
    PlayStatsDebugRowData('标题', video.title),
    PlayStatsDebugRowData('番剧标题', video.animeTitle),
    PlayStatsDebugRowData('季度标题', video.seasonTitle),
    PlayStatsDebugRowData('视频种类', video.videoKind),
    PlayStatsDebugRowData('是否计入季完播', f.yesNo(video.countsTowardCompletion)),
    PlayStatsDebugRowData('媒体总时长', f.duration(video.mediaDurationMs)),
    PlayStatsDebugRowData('点击数', '${video.clickCount}'),
    PlayStatsDebugRowData('自动连播次数', '${video.autoPlayCount}'),
    PlayStatsDebugRowData('观看数', '${video.viewCount}'),
    PlayStatsDebugRowData('累计播放时长', f.duration(video.totalPlayedMs)),
    PlayStatsDebugRowData('最大播放进度', f.percent(video.maxProgress)),
    PlayStatsDebugRowData('最后播放进度', f.percent(video.lastProgress)),
    PlayStatsDebugRowData('最后播放位置', f.duration(video.lastPositionMs)),
    PlayStatsDebugRowData('是否完播', f.yesNo(video.completed)),
    PlayStatsDebugRowData('元数据已补全', f.yesNo(video.metadataEnriched)),
    PlayStatsDebugRowData('上次播放时间', f.dateTime(video.lastPlayedAtMs)),
  ];
}

List<PlayStatsDebugRowData> _historyRows(
  PlayHistoryRecord item,
  PlayStatsDebugFormatters f,
) {
  return <PlayStatsDebugRowData>[
    PlayStatsDebugRowData('历史 ID', item.historyId),
    PlayStatsDebugRowData('视频 ID', item.videoId),
    PlayStatsDebugRowData('番剧 ID', item.animeId),
    PlayStatsDebugRowData('季度 ID', item.seasonId),
    PlayStatsDebugRowData('标题', item.title),
    PlayStatsDebugRowData('番剧标题', item.animeTitle),
    PlayStatsDebugRowData('季度标题', item.seasonTitle),
    PlayStatsDebugRowData('视频种类', item.videoKind),
    PlayStatsDebugRowData('是否计入季完播', f.yesNo(item.countsTowardCompletion)),
    PlayStatsDebugRowData('开始来源', f.startSource(item.startSource)),
    PlayStatsDebugRowData('开始时间', f.dateTime(item.startedAtMs)),
    PlayStatsDebugRowData('结束时间', f.dateTime(item.endedAtMs)),
    PlayStatsDebugRowData('媒体总时长', f.duration(item.mediaDurationMs)),
    PlayStatsDebugRowData('观看时长', f.duration(item.watchedMs)),
    PlayStatsDebugRowData('最大播放进度', f.percent(item.maxProgress)),
    PlayStatsDebugRowData('最大播放位置', f.duration(item.maxPositionMs)),
    PlayStatsDebugRowData('是否计入观看', f.yesNo(item.countedAsView)),
    PlayStatsDebugRowData('是否计入完播', f.yesNo(item.countedAsCompleted)),
    PlayStatsDebugRowData('国家地区代码', f.joinStrings(item.countryCodes)),
    PlayStatsDebugRowData('国家地区中文', f.countryNames(item.countryCodes)),
    PlayStatsDebugRowData('类型 ID', f.joinInts(item.genreIds)),
    PlayStatsDebugRowData('类型中文', f.genreNames(item.genreIds)),
    PlayStatsDebugRowData('已识别 OP', f.yesNo(item.opDetected)),
    PlayStatsDebugRowData('已识别 ED', f.yesNo(item.edDetected)),
    PlayStatsDebugRowData('已跳过 OP', f.yesNo(item.opSkipped)),
    PlayStatsDebugRowData('已跳过 ED', f.yesNo(item.edSkipped)),
    PlayStatsDebugRowData('未跳过 OP', f.yesNo(item.opNotSkipped)),
    PlayStatsDebugRowData('未跳过 ED', f.yesNo(item.edNotSkipped)),
    PlayStatsDebugRowData('OP 播放时长', f.duration(item.opPlayedMs)),
    PlayStatsDebugRowData('ED 播放时长', f.duration(item.edPlayedMs)),
    PlayStatsDebugRowData('快进次数', '${item.forwardSeekCount}'),
    PlayStatsDebugRowData('回退次数', '${item.backwardSeekCount}'),
  ];
}
