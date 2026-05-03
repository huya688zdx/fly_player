import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/feiniu_api.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/play_info.dart';
import '../models/stream_track_data.dart';
import '../providers/nas_provider.dart';
import '../services/download_task_service.dart';
import '../services/embedded_detail_launcher.dart';
import '../theme/app_theme.dart';
import '../utils/api_url_helper.dart';
import '../utils/async_action_guard.dart';
import '../utils/detail_top_tip.dart';
import '../widgets/detail/tv_season_download_sheet.dart';

/// 负责展示详情页的单条目下载面板。
class PlayDetailDownloadSheetController {
  static final DetailTopTip _topTip = DetailTopTip();

  /// 创建一个详情页下载面板控制器。
  const PlayDetailDownloadSheetController();

  /// 加载下载所需数据并展示下载选择面板。
  Future<void> show(
    BuildContext context, {
    required String itemGuid,
    required PlayItem item,
    SubtitleTrackOption? selectedSubtitleTrack,
    String parentGuid = '',
    List<String> previewUrls = const <String>[],
    Map<String, dynamic> localeMap = const <String, dynamic>{},
  }) async {
    final l10n = AppLocalizations.of(context);
    final actionKey = 'play_detail_download_sheet:${itemGuid.trim()}';
    if (AsyncActionGuard.isRunning(actionKey)) {
      _showTopTip(context, l10n.downloadLoadingInfo, context.appColors.warning);
      return;
    }

    final provider = context.read<NasProvider>();
    final api = FeiniuApi(provider);
    final colors = context.appColors;
    final downloadService = DownloadTaskService.instance;

    await AsyncActionGuard.run<void>(
      actionKey,
      settleDuration: const Duration(milliseconds: 500),
      action: () async {
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
            l10n,
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
            _showTopTip(context, l10n.downloadNoResources, colors.warning);
            return;
          }

          final qualities = await api.getDownloadResolutionOptions(
            resolutionGuid,
            lan: 'zh-CN',
          );
          if (!context.mounted) return;
          if (qualities.isEmpty) {
            _showTopTip(context, l10n.downloadNoQuality, colors.warning);
            return;
          }

          final sourceResolution = _sourceResolution(itemMap, item);
          final posterUrls = previewUrls.isNotEmpty
              ? previewUrls
              : _posterUrls(provider.baseUrl, item);
          final payload = TvSeasonDownloadSheetPayload(
            sheetTitle: l10n.downloadSelectItem,
            qualityLabel: l10n.downloadQuality,
            qualitySheetTitle: l10n.downloadSelectQuality,
            itemTitle: _buildTitle(item, l10n),
            posterUrls: posterUrls,
            token: provider.token,
            posterBadgeLabel: _posterBadgeLabel(sourceResolution),
            qualityOptions: qualities
                .map(
                  (quality) => TvSeasonDownloadQualityOption(
                    value: quality,
                    label: _qualityLabel(quality, l10n),
                    hint: _downloadQualityHint(
                      l10n: l10n,
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
            downloadLabel: l10n.downloadDownload,
            openListLabel: l10n.downloadOpenList,
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
                  title: _recordTitle(item, l10n),
                  groupId: groupMeta.id,
                  groupTitle: groupMeta.title,
                  durationText: _durationText(item, l10n),
                  posterUrls: posterUrls,
                  groupPosterUrls: groupMeta.posterUrls,
                  preferredSubtitleTrack: selectedSubtitleTrack,
                );
                if (!context.mounted) return;
                if (result.state == DownloadStartState.started) {
                  _showTopTip(
                    context,
                    l10n.downloadStartedWithQuality(
                      _qualityLabel(selectedQuality, l10n),
                    ),
                    colors.success,
                  );
                  return;
                }
                if (result.state == DownloadStartState.importedFromCache) {
                  _showTopTip(
                    context,
                    l10n.downloadImportedFromCacheWithQuality(
                      _qualityLabel(selectedQuality, l10n),
                    ),
                    colors.success,
                  );
                  return;
                }
                if (result.state == DownloadStartState.downloading) {
                  _showTopTip(
                    context,
                    l10n.downloadItemDownloading,
                    colors.warning,
                  );
                  return;
                }
                _showTopTip(
                  context,
                  l10n.downloadItemDownloaded,
                  colors.textSecondary,
                );
              } catch (error) {
                if (!context.mounted) return;
                _showTopTip(
                  context,
                  l10n.downloadFailedWithError(error),
                  colors.danger,
                );
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
          _showTopTip(context, l10n.downloadLoadFailed, colors.danger);
        }
      },
    );
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
    required AppLocalizations l10n,
    required String sourceResolution,
    required String quality,
    required bool downloaded,
  }) {
    final hints = <String>[
      if (_isSameQuality(quality, sourceResolution)) l10n.downloadSourceQuality,
      if (downloaded) l10n.downloadDownloaded,
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
    AppLocalizations l10n,
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
        final parentTitle = _collectionTitleFromMap(parentItem, l10n);
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
        title: _groupTitle(item, l10n),
        posterUrls: const <String>[],
      );
    }
    return _DownloadGroupMeta(
      id: item.guid.trim().isNotEmpty
          ? item.guid.trim()
          : (itemMap['guid'] ?? '').toString().trim(),
      title: _groupTitle(item, l10n),
      posterUrls: _posterUrls(baseUrl, item),
    );
  }

  static String _buildTitle(PlayItem item, AppLocalizations l10n) {
    final parts = <String>[
      if (item.tvTitle.trim().isNotEmpty) item.tvTitle.trim(),
      if (item.parentTitle.trim().isNotEmpty) item.parentTitle.trim(),
      if (item.episodeNumber > 0) _episodeLabel(item.episodeNumber, l10n),
      if (item.title.trim().isNotEmpty &&
          item.title.trim() != item.tvTitle.trim())
        item.title.trim(),
    ];
    if (parts.isNotEmpty) return parts.join(' ');
    return item.displayTitle.trim();
  }

  static String _groupTitle(PlayItem item, AppLocalizations l10n) {
    return _composeGroupTitle(
      seriesTitle: item.tvTitle,
      collectionTitle: _collectionTitleFromPlayItem(item, l10n),
      fallbackTitle: item.episodeNumber <= 0 ? item.title : '',
    );
  }

  static String _recordTitle(PlayItem item, AppLocalizations l10n) {
    final title = item.title.trim();
    if (item.episodeNumber > 0) {
      if (title.isNotEmpty && title != item.tvTitle.trim()) {
        return '${_episodeLabel(item.episodeNumber, l10n)} $title';
      }
      return _episodeLabel(item.episodeNumber, l10n);
    }
    if (title.isNotEmpty) return title;
    if (item.parentTitle.trim().isNotEmpty) return item.parentTitle.trim();
    if (item.tvTitle.trim().isNotEmpty) return item.tvTitle.trim();
    return item.displayTitle.trim();
  }

  static String _durationText(PlayItem item, AppLocalizations l10n) {
    if (item.runtime > 0) return _minutesLabel(item.runtime, l10n);
    final totalSeconds = item.duration > 0 ? item.duration : 0;
    if (totalSeconds <= 0) return '';
    final hour = totalSeconds ~/ 3600;
    final minute = (totalSeconds % 3600) ~/ 60;
    final second = totalSeconds % 60;
    if (hour > 0) return _hoursMinutesLabel(hour, minute, l10n);
    if (minute > 0) {
      return second > 0
          ? _minutesSecondsLabel(minute, second, l10n)
          : _minutesLabel(minute, l10n);
    }
    return _secondsLabel(second, l10n);
  }

  static List<String> _posterUrls(String baseUrl, PlayItem item) {
    return ApiUrlHelper.imageCandidates(baseUrl, item.posters, width: 720);
  }

  static String _collectionTitleFromMap(
    Map<String, dynamic> item,
    AppLocalizations l10n,
  ) {
    final title = (item['title'] ?? '').toString().trim();
    if (title.isNotEmpty) return title;
    final seasonNumber = int.tryParse('${item['season_number'] ?? ''}') ?? 0;
    if (seasonNumber > 0) return _seasonLabel(seasonNumber, l10n);
    return '';
  }

  static String _collectionTitleFromPlayItem(
    PlayItem item,
    AppLocalizations l10n,
  ) {
    if (item.parentTitle.trim().isNotEmpty) return item.parentTitle.trim();
    if (item.seasonNumber > 0) return _seasonLabel(item.seasonNumber, l10n);
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

  static String _qualityLabel(String raw, AppLocalizations l10n) {
    final trimmed = raw.trim();
    if (trimmed == 'Others') {
      return l10n.commonOther;
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

  static String _seasonLabel(int season, AppLocalizations l10n) {
    return l10n.detailSeasonNumber(season);
  }

  static String _episodeLabel(int episode, AppLocalizations l10n) {
    return l10n.detailEpisodeNumber(episode);
  }

  static String _hoursMinutesLabel(
    int hours,
    int minutes,
    AppLocalizations l10n,
  ) {
    return l10n.commonDurationHoursMinutes(hours, minutes);
  }

  static String _minutesSecondsLabel(
    int minutes,
    int seconds,
    AppLocalizations l10n,
  ) {
    return l10n.commonDurationMinutesSeconds(minutes, seconds);
  }

  static String _minutesLabel(int minutes, AppLocalizations l10n) {
    return l10n.commonDurationMinutes(minutes);
  }

  static String _secondsLabel(int seconds, AppLocalizations l10n) {
    return l10n.commonDurationSeconds(seconds);
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
