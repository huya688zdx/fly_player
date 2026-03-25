import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/feiniu_api.dart';
import '../../providers/nas_provider.dart';
import '../../services/embedded_detail_launcher.dart';
import '../../services/play_stats/play_stats.dart';
import '../../ui/app_transitions.dart';
import 'play_stats_debug_detail_pages.dart';
import 'play_stats_debug_formatters.dart';
import 'play_stats_debug_widgets.dart';

class PlayStatsDebugPage extends StatefulWidget {
  const PlayStatsDebugPage({super.key});

  @override
  State<PlayStatsDebugPage> createState() => _PlayStatsDebugPageState();
}

class _PlayStatsDebugPageState extends State<PlayStatsDebugPage> {
  late Future<PlayStatsDebugSnapshot> _snapshotFuture;
  Map<int, String> _genreMap = const <int, String>{};
  Map<String, String> _countryMap = const <String, String>{};
  bool _metadataBackfillRunning = false;

  PlayStatsSummaryRepository get _summaryRepository =>
      PlayStatsService.instance.summaryRepository;

  PlayStatsRepository get _repository => PlayStatsService.instance.repository;

  PlayStatsMetadataBackfillService get _backfillService =>
      PlayStatsService.instance.metadataBackfillService;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = _summaryRepository.loadDebugSnapshot();
    _snapshotFuture.then((snapshot) {
      if (!mounted) {
        return;
      }
      unawaited(
        _triggerMetadataBackfill(preferredVideoIds: _collectVideoIds(snapshot)),
      );
    });
    _loadMetadataMaps();
  }

  List<String> _collectVideoIds(PlayStatsDebugSnapshot snapshot) {
    final ids = <String>{};
    for (final anime in snapshot.animes) {
      for (final season in anime.seasons) {
        for (final video in season.videos) {
          final id = video.video.videoId.trim();
          if (id.isNotEmpty) {
            ids.add(id);
          }
        }
      }
      for (final video in anime.ungroupedVideos) {
        final id = video.video.videoId.trim();
        if (id.isNotEmpty) {
          ids.add(id);
        }
      }
    }
    for (final movie in snapshot.movies) {
      final id = movie.video.videoId.trim();
      if (id.isNotEmpty) {
        ids.add(id);
      }
    }
    for (final video in snapshot.orphanVideos) {
      final id = video.video.videoId.trim();
      if (id.isNotEmpty) {
        ids.add(id);
      }
    }
    return ids.toList(growable: false);
  }

  Future<void> _loadMetadataMaps() async {
    final provider = context.read<NasProvider>();
    if (!provider.isConfigured) {
      return;
    }
    try {
      final api = FeiniuApi(provider);
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        api.getTagGenresMap(lan: 'zh-CN'),
        api.getTagIso3166Map(lan: 'zh-CN'),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _genreMap = results[0] as Map<int, String>;
        _countryMap = results[1] as Map<String, String>;
      });
    } catch (_) {}
  }

  Future<void> _refresh() async {
    final next = _summaryRepository.loadDebugSnapshot();
    setState(() {
      _snapshotFuture = next;
    });
    await next;
    await _loadMetadataMaps();
  }

  Future<void> _refreshWithBackfill() async {
    final snapshot = await _summaryRepository.loadDebugSnapshot();
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshotFuture = Future<PlayStatsDebugSnapshot>.value(snapshot);
    });
    await _triggerMetadataBackfill(
      preferredVideoIds: _collectVideoIds(snapshot),
    );
  }

  Future<void> _triggerMetadataBackfill({
    Iterable<String> preferredVideoIds = const <String>[],
  }) async {
    final provider = context.read<NasProvider>();
    if (!provider.isConfigured || _metadataBackfillRunning) {
      return;
    }
    setState(() => _metadataBackfillRunning = true);
    try {
      await _backfillService.backfillNow(
        provider: provider,
        preferredVideoIds: preferredVideoIds,
        limit: 12,
      );
      if (!mounted) {
        return;
      }
      await _refresh();
    } finally {
      if (mounted) {
        setState(() => _metadataBackfillRunning = false);
      }
    }
  }

  Future<void> _clearStats() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('清空播放统计'),
          content: const Text('这会删除本地播放历史和所有聚合统计数据。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('清空'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    await _repository.clearAll();
    if (!mounted) {
      return;
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final formatters = PlayStatsDebugFormatters(
      genreMap: _genreMap,
      countryMap: _countryMap,
    );
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () {
            unawaited(EmbeddedDetailLauncher.closeHostOrPop(context));
          },
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        title: const Text('播放统计'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: _refreshWithBackfill,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: '清空统计',
            onPressed: _clearStats,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: FutureBuilder<PlayStatsDebugSnapshot>(
        future: _snapshotFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('加载播放统计失败：${snapshot.error}'));
          }
          final data =
              snapshot.data ??
              const PlayStatsDebugSnapshot(
                totals: PlayStatsTotals(
                  totalPlayedMs: 0,
                  totalClickCount: 0,
                  totalViewCount: 0,
                  totalCompletedVideoCount: 0,
                  totalCompletedSeasonCount: 0,
                ),
                animes: <PlayStatsDebugAnimeNode>[],
              );
          return RefreshIndicator(
            onRefresh: _refreshWithBackfill,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: <Widget>[
                PlayStatsDebugSectionCard(
                  title: '总览',
                  child: buildDebugRows(<PlayStatsDebugRowData>[
                    PlayStatsDebugRowData(
                      '总播放时长',
                      formatters.duration(data.totals.totalPlayedMs),
                    ),
                    PlayStatsDebugRowData(
                      '总点击数',
                      '${data.totals.totalClickCount}',
                    ),
                    PlayStatsDebugRowData(
                      '总观看数',
                      '${data.totals.totalViewCount}',
                    ),
                    PlayStatsDebugRowData(
                      '总完播视频数',
                      '${data.totals.totalCompletedVideoCount}',
                    ),
                    PlayStatsDebugRowData(
                      '总完播季数',
                      '${data.totals.totalCompletedSeasonCount}',
                    ),
                  ]),
                ),
                if (_metadataBackfillRunning) ...<Widget>[
                  const SizedBox(height: 12),
                  const PlayStatsDebugSectionCard(
                    title: '后台补全',
                    child: Text('正在后台补全年份、国家、类型和演职人员。'),
                  ),
                ],
                const SizedBox(height: 12),
                PlayStatsDebugSectionCard(
                  title: '番剧列表',
                  child: data.animes.isEmpty
                      ? const Text('还没有番剧播放统计。')
                      : Column(
                          children: data.animes
                              .map(
                                (node) => PlayStatsDebugEntryTile(
                                  title: node.anime.title.isEmpty
                                      ? '未命名番剧'
                                      : node.anime.title,
                                  subtitle:
                                      '季度 ${node.seasons.length} / 未分组视频 ${node.ungroupedVideos.length}',
                                  onTap: () {
                                    Navigator.of(context).push(
                                      AppTransitions.paneCardRoute<void>(
                                        PlayStatsDebugAnimePage(
                                          node: node,
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
                if (data.movies.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  PlayStatsDebugSectionCard(
                    title: '电影列表',
                    child: Column(
                      children: data.movies
                          .map(
                            (node) => buildVideoEntry(
                              context,
                              node,
                              formatters,
                              subtitleOverride:
                                  '电影 / 历史 ${node.history.length} 条 / 观看数 ${node.video.viewCount}',
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                ],
                if (data.orphanVideos.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  PlayStatsDebugSectionCard(
                    title: '异常未归类视频',
                    child: Column(
                      children: data.orphanVideos
                          .map(
                            (node) => buildVideoEntry(
                              context,
                              node,
                              formatters,
                              subtitleOverride:
                                  '未匹配番剧或季度 / 历史 ${node.history.length} 条',
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                ],
                if (data.unlinkedHistory.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  PlayStatsDebugSectionCard(
                    title: '未关联历史',
                    child: PlayStatsDebugEntryTile(
                      title: '未关联历史',
                      subtitle: '共 ${data.unlinkedHistory.length} 条',
                      onTap: () {
                        Navigator.of(context).push(
                          AppTransitions.paneCardRoute<void>(
                            PlayStatsDebugHistoryListPage(
                              title: '未关联历史',
                              items: data.unlinkedHistory,
                              formatters: formatters,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
