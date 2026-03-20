import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../models/play_info.dart';
import '../models/stream_track_data.dart';
import '../providers/nas_provider.dart';
import '../services/download_task_service.dart';
import '../services/embedded_detail_launcher.dart';
import '../theme/app_theme.dart';
import '../utils/api_url_helper.dart';
import '../utils/detail_top_tip.dart';
import '../utils/media_locale_store.dart';
import '../widgets/detail/tv_season_download_sheet.dart';

class PlayDetailDownloadSheetController {
  static final DetailTopTip _topTip = DetailTopTip();

  const PlayDetailDownloadSheetController();

  Future<void> show(
    BuildContext context, {
    required String itemGuid,
    required PlayItem item,
    SubtitleTrackOption? selectedSubtitleTrack,
    String parentGuid = '',
    List<String> previewUrls = const <String>[],
    Map<String, dynamic> localeMap = const <String, dynamic>{},
  }) async {
    final provider = context.read<NasProvider>();
    final api = FeiniuApi(provider);
    final colors = context.appColors;
    final downloadService = DownloadTaskService.instance;

    try {
      await downloadService.initialize();
      final detail = await api.getItemDetail(itemGuid);
      if (!context.mounted) return;

      final itemMap = _detailItem(detail);
      final groupMeta = await _resolveGroupMeta(
        api,
        provider.baseUrl,
        detail,
        itemMap,
        item,
        parentGuid,
      );
      final resolutionGuid = await _resolveDownloadResolutionGuid(
        api,
        requestedItemGuid: itemGuid,
        detail: detail,
        itemMap: itemMap,
        playItem: item,
      );
      if (!context.mounted) return;
      if (resolutionGuid.isEmpty) {
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
        resolutionGuid,
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

      final sourceResolution = _sourceResolution(itemMap, item);
      final posterUrls = previewUrls.isNotEmpty
          ? previewUrls
          : _posterUrls(provider.baseUrl, item);
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
        itemTitle: _buildTitle(item),
        posterUrls: posterUrls,
        token: provider.token,
        posterBadgeLabel: _posterBadgeLabel(sourceResolution),
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
                    itemGuid,
                    quality,
                  ),
                ),
              ),
            )
            .toList(growable: false),
        initialQuality: _initialQuality(qualities, sourceResolution),
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
        primaryActionState: downloadService.actionStateForItem(itemGuid),
      );

      await TvSeasonDownloadSheet.show(
        context,
        payload: payload,
        onDownloadTap: (selectedQuality) async {
          try {
            final result = await downloadService.startDownload(
              provider: provider,
              itemGuid: itemGuid,
              resolution: selectedQuality,
              title: _recordTitle(item),
              groupId: groupMeta.id,
              groupTitle: groupMeta.title,
              durationText: _durationText(item),
              posterUrls: posterUrls,
              groupPosterUrls: groupMeta.posterUrls,
              preferredSubtitleTrack: selectedSubtitleTrack,
            );
            if (!context.mounted) return;
            if (result.state == DownloadStartState.started) {
              _showTopTip(
                context,
                '已开始下载 ${_qualityLabel(selectedQuality, localeMap)}',
                colors.success,
              );
              return;
            }
            if (result.state == DownloadStartState.importedFromCache) {
              _showTopTip(
                context,
                '宸蹭粠缂撳瓨鍔犲叆涓嬭浇 ${_qualityLabel(selectedQuality, localeMap)}',
                colors.success,
              );
              return;
            }
            if (result.state == DownloadStartState.downloading) {
              _showTopTip(context, '该影片正在下载中', colors.warning);
              return;
            }
            _showTopTip(context, '该影片已下载完成', colors.textSecondary);
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

  static Future<String> _resolveDownloadResolutionGuid(
    FeiniuApi api, {
    required String requestedItemGuid,
    required Map<String, dynamic> detail,
    required Map<String, dynamic> itemMap,
    required PlayItem playItem,
  }) async {
    final candidates = <String>{
      _extractPlayItemGuid(detail, itemMap),
      requestedItemGuid.trim(),
      playItem.guid.trim(),
      (itemMap['guid'] ?? '').toString().trim(),
    }.where((value) => value.isNotEmpty).toList(growable: false);

    for (final guid in candidates) {
      final qualities = await api.getDownloadResolutionOptions(
        guid,
        lan: 'zh-CN',
      );
      if (qualities.isNotEmpty) {
        return guid;
      }
    }
    return candidates.isNotEmpty ? candidates.first : '';
  }

  static String _sourceResolution(Map<String, dynamic> itemMap, PlayItem item) {
    final stream = itemMap['media_stream'];
    if (stream is Map<String, dynamic>) {
      final values = stream['resolutions'];
      if (values is List && values.isNotEmpty) {
        final value = values.first.toString().trim();
        if (value.isNotEmpty) return value;
      }
    }
    if (item.resolutions.isNotEmpty) {
      return item.resolutions.first.trim();
    }
    return '';
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

  static Future<_DownloadGroupMeta> _resolveGroupMeta(
    FeiniuApi api,
    String baseUrl,
    Map<String, dynamic> detail,
    Map<String, dynamic> itemMap,
    PlayItem item,
    String parentGuid,
  ) async {
    final candidates = <String>{
      parentGuid.trim(),
      (detail['parent_guid'] ?? '').toString().trim(),
      (itemMap['parent_guid'] ?? '').toString().trim(),
    }.where((value) => value.isNotEmpty).toList(growable: false);

    for (final guid in candidates) {
      try {
        final parentDetail = await api.getItemDetail(guid);
        final parentItem = _detailItem(parentDetail);
        final parentTitle = _collectionTitleFromMap(parentItem);
        final resolvedTitle = _composeGroupTitle(
          seriesTitle: item.tvTitle,
          collectionTitle: parentTitle,
          fallbackTitle: item.parentTitle,
        );
        if (resolvedTitle == item.tvTitle.trim() && candidates.length > 1) {
          continue;
        }
        final parentPosterPath =
            (parentItem['posters'] ?? parentItem['poster'] ?? '')
                .toString()
                .trim();
        final urls = ApiUrlHelper.imageCandidates(
          baseUrl,
          parentPosterPath,
          width: 720,
          preferDirectPath: true,
        );
        return _DownloadGroupMeta(
          id: guid,
          title: resolvedTitle,
          posterUrls: urls,
        );
      } catch (_) {}
    }
    if (candidates.isNotEmpty) {
      return _DownloadGroupMeta(
        id: candidates.first,
        title: _groupTitle(item),
        posterUrls: const <String>[],
      );
    }
    return _DownloadGroupMeta(
      id: item.guid.trim().isNotEmpty
          ? item.guid.trim()
          : (itemMap['guid'] ?? '').toString().trim(),
      title: _groupTitle(item),
      posterUrls: _posterUrls(baseUrl, item),
    );
  }

  static String _buildTitle(PlayItem item) {
    final parts = <String>[
      if (item.tvTitle.trim().isNotEmpty) item.tvTitle.trim(),
      if (item.parentTitle.trim().isNotEmpty) item.parentTitle.trim(),
      if (item.episodeNumber > 0) '第 ${item.episodeNumber} 集',
      if (item.title.trim().isNotEmpty &&
          item.title.trim() != item.tvTitle.trim())
        item.title.trim(),
    ];
    if (parts.isNotEmpty) return parts.join(' ');
    return item.displayTitle.trim();
  }

  static String _groupTitle(PlayItem item) {
    return _composeGroupTitle(
      seriesTitle: item.tvTitle,
      collectionTitle: _collectionTitleFromPlayItem(item),
      fallbackTitle: item.episodeNumber <= 0 ? item.title : '',
    );
  }

  static String _recordTitle(PlayItem item) {
    final title = item.title.trim();
    if (item.episodeNumber > 0) {
      if (title.isNotEmpty && title != item.tvTitle.trim()) {
        return '第 ${item.episodeNumber} 集 $title';
      }
      return '第 ${item.episodeNumber} 集';
    }
    if (title.isNotEmpty) return title;
    if (item.parentTitle.trim().isNotEmpty) return item.parentTitle.trim();
    if (item.tvTitle.trim().isNotEmpty) return item.tvTitle.trim();
    return item.displayTitle.trim();
  }

  static String _durationText(PlayItem item) {
    if (item.runtime > 0) return '${item.runtime}分钟';
    final totalSeconds = item.duration > 0 ? item.duration : 0;
    if (totalSeconds <= 0) return '';
    final hour = totalSeconds ~/ 3600;
    final minute = (totalSeconds % 3600) ~/ 60;
    final second = totalSeconds % 60;
    if (hour > 0) return '$hour小时$minute分钟';
    if (minute > 0) return second > 0 ? '$minute分钟$second秒' : '$minute分钟';
    return '$second秒';
  }

  static List<String> _posterUrls(String baseUrl, PlayItem item) {
    return ApiUrlHelper.imageCandidates(baseUrl, item.posters, width: 720);
  }

  static String _collectionTitleFromMap(Map<String, dynamic> item) {
    final title = (item['title'] ?? '').toString().trim();
    if (title.isNotEmpty) return title;
    final seasonNumber = int.tryParse('${item['season_number'] ?? ''}') ?? 0;
    if (seasonNumber > 0) return '第$seasonNumber季';
    return '';
  }

  static String _collectionTitleFromPlayItem(PlayItem item) {
    if (item.parentTitle.trim().isNotEmpty) return item.parentTitle.trim();
    if (item.seasonNumber > 0) return '第${item.seasonNumber}季';
    return '';
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
    return series;
  }

  static String _posterBadgeLabel(String resolution) {
    final trimmed = resolution.trim();
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

  static String _initialQuality(List<String> qualities, String resolution) {
    for (final quality in qualities) {
      if (_isSameQuality(quality, resolution)) {
        return quality;
      }
    }
    return qualities.isNotEmpty ? qualities.first : '';
  }

  static bool _isSameQuality(String lhs, String rhs) {
    return lhs.trim().toLowerCase() == rhs.trim().toLowerCase();
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
