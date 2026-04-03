import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../models/media_library_item.dart';
import '../models/tv_episode_browser_models.dart';
import '../providers/nas_provider.dart';
import '../services/download_task_service.dart';
import '../services/embedded_detail_launcher.dart';
import '../theme/app_theme.dart';
import '../utils/api_url_helper.dart';
import '../utils/detail_top_tip.dart';
import '../utils/media_locale_store.dart';
import '../widgets/detail/tv_season_download_sheet.dart';

class TvSeasonDownloadSheetController {
  static final DetailTopTip _topTip = DetailTopTip();

  const TvSeasonDownloadSheetController();

  Future<void> show(
    BuildContext context, {
    MediaLibraryItem? episode,
    List<String> candidateItemGuids = const <String>[],
    List<TvEpisodeCardData> episodeEntries = const <TvEpisodeCardData>[],
    int initialRangeIndex = 0,
    int rangeSize = 30,
    required String seriesTitle,
    String preferredSubtitleGuid = '',
    Map<String, dynamic> localeMap = const <String, dynamic>{},
  }) async {
    final provider = context.read<NasProvider>();
    final api = FeiniuApi(provider);
    final colors = context.appColors;
    final downloadService = DownloadTaskService.instance;

    try {
      await downloadService.initialize();
      final detail = await _resolveDownloadDetail(
        api,
        episode: episode,
        candidateItemGuids: candidateItemGuids,
      );
      if (!context.mounted || detail == null) return;

      final item = _detailItem(detail);
      final groupMeta = await _resolveGroupMeta(
        api,
        provider.baseUrl,
        detail,
        item,
        episode,
        seriesTitle,
      );
      final playItemGuid = _extractPlayItemGuid(detail, item);
      if (playItemGuid.isEmpty) {
        _showTopTip(
          context,
          MediaLocaleStore.text(
            localeMap,
            'common.actions.download.unavailable',
            fallback: '暂无可下载资源',
          ),
          colors.warning,
        );
        return;
      }

      final qualities = await api.getDownloadResolutionOptions(
        playItemGuid,
        lan: 'zh-CN',
      );
      if (!context.mounted) return;
      if (qualities.isEmpty) {
        _showTopTip(
          context,
          MediaLocaleStore.text(
            localeMap,
            'common.actions.download.noQuality',
            fallback: '暂无可下载画质',
          ),
          colors.warning,
        );
        return;
      }

      final sourceResolution = _extractSourceResolution(item, episode);
      final payload = TvSeasonDownloadSheetPayload(
        sheetTitle: MediaLocaleStore.text(
          localeMap,
          'common.actions.download.selectItem',
          fallback: '选择下载影片',
        ),
        qualityLabel: MediaLocaleStore.text(
          localeMap,
          'common.actions.download.quality',
          fallback: '下载画质',
        ),
        qualitySheetTitle: MediaLocaleStore.text(
          localeMap,
          'common.actions.download.selectQuality',
          fallback: '选择下载影片画质',
        ),
        itemTitle: _buildItemTitle(item, episode, seriesTitle),
        posterUrls: _posterUrls(provider.baseUrl, item, episode),
        token: provider.token,
        posterBadgeLabel: _posterBadgeLabel(sourceResolution),
        episodeEntries: episodeEntries,
        qualityOptions: qualities
            .map(
              (quality) => TvSeasonDownloadQualityOption(
                value: quality,
                label: _qualityLabel(quality, localeMap),
                hint: _downloadQualityHint(
                  localeMap: localeMap,
                  sourceResolution: sourceResolution,
                  quality: quality,
                  downloaded: downloadService.hasDownloadedResolution(
                    episode?.guid ?? '',
                    quality,
                  ),
                ),
              ),
            )
            .toList(growable: false),
        initialQuality: _resolveInitialQuality(qualities, sourceResolution),
        initialRangeIndex: initialRangeIndex,
        rangeSize: rangeSize,
        downloadLabel: MediaLocaleStore.text(
          localeMap,
          'common.actions.download.download',
          fallback: '下载',
        ),
        openListLabel: MediaLocaleStore.text(
          localeMap,
          'common.actions.download.openList',
          fallback: '查看下载列表',
        ),
        primaryActionState: downloadService.actionStateForItem(
          episode?.guid ?? '',
        ),
        episodeActionStates: downloadService.actionStatesForItems(
          episodeEntries.map((entry) => entry.guid),
        ),
      );

      await TvSeasonDownloadSheet.show(
        context,
        payload: payload,
        onDownloadTap: (selectedQuality) async {
          final targetEpisode = episode;
          if (targetEpisode == null) return;
          try {
            final result = await downloadService.startDownload(
              provider: provider,
              itemGuid: targetEpisode.guid,
              resolution: selectedQuality,
              title: _buildItemTitle(item, targetEpisode, seriesTitle),
              groupId: groupMeta.id,
              groupTitle: groupMeta.title,
              durationText: _durationText(targetEpisode.duration),
              posterUrls: _posterUrls(provider.baseUrl, item, targetEpisode),
              groupPosterUrls: groupMeta.posterUrls,
              preferredSubtitleGuid: preferredSubtitleGuid,
            );
            if (!context.mounted) return;
            _showStartResultTip(
              context,
              result: result,
              qualityText: _qualityLabel(selectedQuality, localeMap),
              colors: colors,
            );
          } catch (error) {
            if (!context.mounted) return;
            _showTopTip(context, '下载失败: $error', colors.danger);
          }
        },
        onEpisodeDownloadTap: (episodeGuid, selectedQuality) async {
          final matched = episodeEntries.cast<TvEpisodeCardData?>().firstWhere(
            (entry) => entry?.guid == episodeGuid,
            orElse: () => null,
          );
          if (matched == null) return;
          try {
            final result = await downloadService.startDownload(
              provider: provider,
              itemGuid: episodeGuid,
              resolution: selectedQuality,
              title: matched.title,
              groupId: groupMeta.id,
              groupTitle: groupMeta.title,
              durationText: matched.durationText,
              posterUrls: matched.imageUrls,
              groupPosterUrls: groupMeta.posterUrls,
              preferredSubtitleGuid: preferredSubtitleGuid,
            );
            if (!context.mounted) return;
            _showStartResultTip(
              context,
              result: result,
              qualityText: _qualityLabel(selectedQuality, localeMap),
              colors: colors,
              title: matched.title,
            );
          } catch (error) {
            if (!context.mounted) return;
            _showTopTip(context, '下载失败: $error', colors.danger);
          }
        },
        onOpenDownloadListTap: () {
          unawaited(
            EmbeddedDetailLauncher.openDownloads(
              context: context,
              tab: 'downloading',
            ),
          );
        },
      );
    } catch (_) {
      if (!context.mounted) return;
      _showTopTip(
        context,
        MediaLocaleStore.text(
          localeMap,
          'common.actions.download.loadFailed',
          fallback: '获取下载信息失败，请稍后重试',
        ),
        colors.danger,
      );
    }
  }

  static Future<Map<String, dynamic>?> _resolveDownloadDetail(
    FeiniuApi api, {
    required MediaLibraryItem? episode,
    required List<String> candidateItemGuids,
  }) async {
    final candidates = <String>{
      if (episode?.guid.trim().isNotEmpty == true) episode!.guid.trim(),
      ...candidateItemGuids
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty),
    }.toList(growable: false);

    for (final guid in candidates) {
      final detail = await api.getItemDetail(guid);
      final item = _detailItem(detail);
      final playItemGuid = _extractPlayItemGuid(detail, item);
      if (playItemGuid.isNotEmpty) {
        return detail;
      }
    }

    if (candidates.isEmpty) return null;
    return api.getItemDetail(candidates.first);
  }

  static String _downloadQualityHint({
    required Map<String, dynamic> localeMap,
    required String sourceResolution,
    required String quality,
    required bool downloaded,
  }) {
    final hints = <String>[
      if (_isSameQuality(quality, sourceResolution))
        MediaLocaleStore.text(
          localeMap,
          'common.actions.download.source',
          fallback: '原画',
        ),
      if (downloaded) '已下载',
    ];
    return hints.join(' · ');
  }

  static Map<String, dynamic> _detailItem(Map<String, dynamic> detail) {
    final nested = detail['item'];
    if (nested is Map<String, dynamic>) return nested;
    return detail;
  }

  static String _extractPlayItemGuid(
    Map<String, dynamic> detail,
    Map<String, dynamic> item,
  ) {
    final direct = (detail['play_item_guid'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;
    return (item['play_item_guid'] ?? '').toString().trim();
  }

  static String _extractSourceResolution(
    Map<String, dynamic> item,
    MediaLibraryItem? episode,
  ) {
    final stream = item['media_stream'];
    if (stream is Map<String, dynamic>) {
      final resolutions = stream['resolutions'];
      if (resolutions is List && resolutions.isNotEmpty) {
        final value = resolutions.first.toString().trim();
        if (value.isNotEmpty) return value;
      }
    }
    if (episode?.resolutions.isNotEmpty == true) {
      return episode!.resolutions.first.trim();
    }
    return '';
  }

  static List<String> _posterUrls(
    String baseUrl,
    Map<String, dynamic> item,
    MediaLibraryItem? episode,
  ) {
    final posterPath = (item['posters'] ?? item['poster'] ?? '')
        .toString()
        .trim();
    final resolvedPath = posterPath.isNotEmpty
        ? posterPath
        : (episode?.poster ?? '');
    return ApiUrlHelper.imageCandidates(baseUrl, resolvedPath, width: 720);
  }

  static Future<_DownloadGroupMeta> _resolveGroupMeta(
    FeiniuApi api,
    String baseUrl,
    Map<String, dynamic> detail,
    Map<String, dynamic> item,
    MediaLibraryItem? episode,
    String seriesTitle,
  ) async {
    final currentPosterUrls = _posterUrls(baseUrl, item, episode);
    final currentTitle = _collectionTitleFromMap(item);
    final tvTitle = (item['tv_title'] ?? '').toString().trim();
    final currentSeasonNumber = _asInt(item['season_number']);
    if (currentTitle.isNotEmpty &&
        (currentTitle != tvTitle || currentSeasonNumber > 0)) {
      final currentGuid = (item['guid'] ?? detail['guid'] ?? '')
          .toString()
          .trim();
      return _DownloadGroupMeta(
        id: currentGuid.isNotEmpty ? currentGuid : seriesTitle.trim(),
        title: _groupTitle(seriesTitle: seriesTitle, seasonTitle: currentTitle),
        posterUrls: currentPosterUrls,
      );
    }

    final candidates = <String>{
      (detail['parent_guid'] ?? '').toString().trim(),
      (item['parent_guid'] ?? '').toString().trim(),
      episode?.parentGuid.trim() ?? '',
    }.where((value) => value.isNotEmpty).toList(growable: false);

    for (final guid in candidates) {
      try {
        final parentDetail = await api.getItemDetail(guid);
        final parentItem = _detailItem(parentDetail);
        final parentTitle = _collectionTitleFromMap(parentItem);
        final posterPath = (parentItem['posters'] ?? parentItem['poster'] ?? '')
            .toString()
            .trim();
        final urls = ApiUrlHelper.imageCandidates(
          baseUrl,
          posterPath,
          width: 720,
          preferDirectPath: true,
        );
        return _DownloadGroupMeta(
          id: guid,
          title: _composeGroupTitle(
            seriesTitle: seriesTitle,
            collectionTitle: parentTitle,
            fallbackTitle: _fallbackGroupSuffix(item, episode),
          ),
          posterUrls: urls,
        );
      } catch (_) {}
    }

    final detailGuid = (item['guid'] ?? detail['guid'] ?? '').toString().trim();
    return _DownloadGroupMeta(
      id: detailGuid.isNotEmpty ? detailGuid : seriesTitle.trim(),
      title: _composeGroupTitle(
        seriesTitle: seriesTitle,
        collectionTitle: _fallbackGroupSuffix(item, episode),
      ),
      posterUrls: const <String>[],
    );
  }

  static String _buildItemTitle(
    Map<String, dynamic> item,
    MediaLibraryItem? episode,
    String seriesTitle,
  ) {
    final tvTitle = (item['tv_title'] ?? '').toString().trim();
    final episodeTitle = (item['title'] ?? episode?.title ?? '')
        .toString()
        .trim();
    final seasonTitle = (item['parent_title'] ?? '').toString().trim();
    final episodeNumber = _asInt(item['episode_number']);

    final parts = <String>[
      if (tvTitle.isNotEmpty) tvTitle,
      if (seasonTitle.isNotEmpty) seasonTitle,
      if (episodeNumber > 0) '第 $episodeNumber 集',
      if (episodeTitle.isNotEmpty && episodeTitle != tvTitle) episodeTitle,
    ];
    if (parts.isNotEmpty) return parts.join(' ');
    if (seriesTitle.trim().isNotEmpty) {
      return '${seriesTitle.trim()} ${(episode?.title ?? '').trim()}'.trim();
    }
    return (episode?.displayTitle ?? '').trim();
  }

  static String _posterBadgeLabel(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.toLowerCase().endsWith('p')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  static String _qualityLabel(String raw, Map<String, dynamic> localeMap) {
    final trimmed = raw.trim();
    if (trimmed == 'Others') {
      return MediaLocaleStore.text(
        localeMap,
        'stream.video.videoResolution.others',
        fallback: '其他',
      );
    }
    return trimmed;
  }

  static String _resolveInitialQuality(
    List<String> qualities,
    String sourceResolution,
  ) {
    for (final quality in qualities) {
      if (_isSameQuality(quality, sourceResolution)) {
        return quality;
      }
    }
    return qualities.isNotEmpty ? qualities.first : '';
  }

  static bool _isSameQuality(String lhs, String rhs) {
    return lhs.trim().toLowerCase() == rhs.trim().toLowerCase();
  }

  static int _asInt(dynamic value) => int.tryParse('$value') ?? 0;

  static String _fallbackGroupSuffix(
    Map<String, dynamic> item,
    MediaLibraryItem? episode,
  ) {
    final seasonNumber = _asInt(item['season_number']);
    if (seasonNumber > 0) return '第$seasonNumber季';
    final parentTitle = (item['parent_title'] ?? '').toString().trim();
    if (parentTitle.isNotEmpty) return parentTitle;
    final episodeParentTitle = episode?.parentTitle.trim() ?? '';
    if (episodeParentTitle.isNotEmpty) return episodeParentTitle;
    final title = (item['title'] ?? '').toString().trim();
    final tvTitle = (item['tv_title'] ?? '').toString().trim();
    final episodeNumber = _asInt(item['episode_number']);
    if (episodeNumber <= 0 && title.isNotEmpty && title != tvTitle) {
      return title;
    }
    return '';
  }

  static String _collectionTitleFromMap(Map<String, dynamic> item) {
    final title = (item['title'] ?? '').toString().trim();
    if (title.isNotEmpty) return title;
    final seasonNumber = _asInt(item['season_number']);
    if (seasonNumber > 0) return '第$seasonNumber季';
    return '';
  }

  static String _groupTitle({
    required String seriesTitle,
    required String seasonTitle,
  }) {
    final parts = <String>[
      if (seriesTitle.trim().isNotEmpty) seriesTitle.trim(),
      if (seasonTitle.trim().isNotEmpty) seasonTitle.trim(),
    ];
    if (parts.isNotEmpty) return parts.join(' ');
    return '下载列表';
  }

  static String _composeGroupTitle({
    required String seriesTitle,
    required String collectionTitle,
    String fallbackTitle = '',
  }) {
    final series = seriesTitle.trim();
    final suffix = collectionTitle.trim().isNotEmpty
        ? collectionTitle.trim()
        : fallbackTitle.trim();
    final parts = <String>[
      if (series.isNotEmpty) series,
      if (suffix.isNotEmpty && suffix != series) suffix,
    ];
    if (parts.isNotEmpty) return parts.join(' ');
    if (suffix.isNotEmpty) return suffix;
    return series.isNotEmpty ? series : '涓嬭浇鍒楄〃';
  }

  static String _durationText(int durationSeconds) {
    if (durationSeconds <= 0) return '';
    final hour = durationSeconds ~/ 3600;
    final minute = (durationSeconds % 3600) ~/ 60;
    final second = durationSeconds % 60;
    if (hour > 0) return '$hour小时$minute分钟';
    if (minute > 0) return second > 0 ? '$minute分钟$second秒' : '$minute分钟';
    return '$second秒';
  }

  static void _showStartResultTip(
    BuildContext context, {
    required DownloadStartResult result,
    required String qualityText,
    required AppThemeColors colors,
    String title = '',
  }) {
    final prefix = title.trim().isEmpty ? '' : '${title.trim()} ';
    if (result.state == DownloadStartState.started) {
      _showTopTip(context, '$prefix已开始下载 $qualityText', colors.success);
      return;
    }
    if (result.state == DownloadStartState.downloading) {
      _showTopTip(context, '$prefix正在下载中', colors.warning);
      return;
    }
    _showTopTip(context, '$prefix已下载完成', colors.textSecondary);
  }

  static void _showTopTip(BuildContext context, String message, Color color) {
    _topTip.show(context, message: message, color: color);
  }
}

class _DownloadGroupMeta {
  final String id;
  final String title;
  final List<String> posterUrls;

  const _DownloadGroupMeta({
    required this.id,
    required this.title,
    required this.posterUrls,
  });
}
