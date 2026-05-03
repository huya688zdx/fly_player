import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/feiniu_api.dart';
import '../../providers/nas_provider.dart';
import '../../services/embedded_detail_launcher.dart';
import '../../services/play_stats/play_stats.dart';
import '../../ui/app_transitions.dart';
import '../../l10n/generated/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.playStatsClearTitle),
          content: Text(l10n.playStatsClearContent),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.commonClear),
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
    final l10n = AppLocalizations.of(context);
    final formatters = PlayStatsDebugFormatters(
      l10n: l10n,
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
        title: Text(l10n.playStatsTitle),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.commonRefresh,
            onPressed: _refreshWithBackfill,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: l10n.playStatsClearTooltip,
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
            return Center(
              child: Text(l10n.playStatsLoadFailed('${snapshot.error}')),
            );
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
                  title: l10n.playStatsOverview,
                  child: buildDebugRows(<PlayStatsDebugRowData>[
                    PlayStatsDebugRowData(
                      l10n.playStatsTotalPlayedDuration,
                      formatters.duration(data.totals.totalPlayedMs),
                    ),
                    PlayStatsDebugRowData(
                      l10n.playStatsTotalClicks,
                      '${data.totals.totalClickCount}',
                    ),
                    PlayStatsDebugRowData(
                      l10n.playStatsTotalViews,
                      '${data.totals.totalViewCount}',
                    ),
                    PlayStatsDebugRowData(
                      l10n.playStatsTotalCompletedVideos,
                      '${data.totals.totalCompletedVideoCount}',
                    ),
                    PlayStatsDebugRowData(
                      l10n.playStatsTotalCompletedSeasons,
                      '${data.totals.totalCompletedSeasonCount}',
                    ),
                  ]),
                ),
                if (_metadataBackfillRunning) ...<Widget>[
                  const SizedBox(height: 12),
                  PlayStatsDebugSectionCard(
                    title: l10n.playStatsBackfillTitle,
                    child: Text(l10n.playStatsBackfillRunning),
                  ),
                ],
                const SizedBox(height: 12),
                PlayStatsDebugSectionCard(
                  title: l10n.playStatsAnimeList,
                  child: data.animes.isEmpty
                      ? Text(l10n.playStatsNoAnimeStats)
                      : Column(
                          children: data.animes
                              .map(
                                (node) => PlayStatsDebugEntryTile(
                                  title: node.anime.title.isEmpty
                                      ? l10n.playStatsUnnamedAnime
                                      : node.anime.title,
                                  subtitle: l10n.playStatsAnimeSubtitle(
                                    node.seasons.length,
                                    node.ungroupedVideos.length,
                                  ),
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
                    title: l10n.playStatsMovieList,
                    child: Column(
                      children: data.movies
                          .map(
                            (node) => buildVideoEntry(
                              context,
                              node,
                              formatters,
                              subtitleOverride: l10n.playStatsMovieSubtitle(
                                node.history.length,
                                node.video.viewCount,
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                ],
                if (data.orphanVideos.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  PlayStatsDebugSectionCard(
                    title: l10n.playStatsOrphanVideos,
                    child: Column(
                      children: data.orphanVideos
                          .map(
                            (node) => buildVideoEntry(
                              context,
                              node,
                              formatters,
                              subtitleOverride: l10n.playStatsOrphanSubtitle(
                                node.history.length,
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                ],
                if (data.unlinkedHistory.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  PlayStatsDebugSectionCard(
                    title: l10n.playStatsUnlinkedHistory,
                    child: PlayStatsDebugEntryTile(
                      title: l10n.playStatsUnlinkedHistory,
                      subtitle: l10n.playStatsCountItems(
                        data.unlinkedHistory.length,
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          AppTransitions.paneCardRoute<void>(
                            PlayStatsDebugHistoryListPage(
                              title: l10n.playStatsUnlinkedHistory,
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
