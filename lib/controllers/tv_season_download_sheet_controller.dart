import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../media_backend/feiniu/feiniu_detail_data_gateway.dart';
import '../models/media_library_item.dart';
import '../models/tv_episode_browser_models.dart';
import '../providers/nas_provider.dart';
import '../services/download_task_service.dart';
import '../services/embedded_detail_launcher.dart';
import '../theme/app_theme.dart';
import '../utils/api_url_helper.dart';
import '../utils/async_action_guard.dart';
import '../utils/detail_top_tip.dart';
import '../widgets/detail/tv_season_download_sheet.dart';

/// 负责展示季度或剧集范围的下载面板。
class TvSeasonDownloadSheetController {
  static final DetailTopTip _topTip = DetailTopTip();
  static final Map<String, List<String>> _cachedQualities =
      <String, List<String>>{};
  static final Map<String, Map<String, dynamic>> _cachedItemDetails =
      <String, Map<String, dynamic>>{};

  /// 创建一个季度下载面板控制器。
  const TvSeasonDownloadSheetController();

  /// 释放所有静态缓存（详情页退出时调用）。
  static void clearCache() {
    _cachedQualities.clear();
    _cachedItemDetails.clear();
  }

  /// 获取已缓存的 item detail，可能为 null。
  static Map<String, dynamic>? cachedItemDetail(String itemGuid) {
    return _cachedItemDetails[itemGuid.trim()];
  }

  /// 预加载剧集下载所需数据（在季度详情页加载时调用）。
  /// 遍历候选项，直到找到一个同时缓存了 item detail 和分辨率列表的条目。
  static Future<void> prefetchSeasonDownloadData(
    FeiniuDetailDataGateway api, {
    required List<String> candidateItemGuids,
  }) async {
    for (final guid in candidateItemGuids) {
      final key = guid.trim();
      if (key.isEmpty) continue;
      try {
        // Resolve detail — prefer cache, otherwise fetch.
        final detail = _cachedItemDetails[key] ?? await api.getItemDetail(key);
        if (detail.isEmpty) continue;
        _cachedItemDetails[key] = detail;

        final item = _detailItem(detail);
        final playItemGuid = _extractPlayItemGuid(detail, item);
        if (playItemGuid.isEmpty) continue; // Need playItemGuid for qualities.

        if (_cachedQualities.containsKey(playItemGuid)) return; // Already done.

        final qualities = await api.getDownloadResolutionOptions(
          playItemGuid,
          lan: 'zh-CN',
        );
        if (qualities.isNotEmpty) {
          _cachedQualities[playItemGuid] = qualities;
          return; // Successfully cached both detail and qualities.
        }
        // Qualities came back empty — continue to next candidate.
      } catch (_) {
        // Try next candidate.
      }
    }
  }

  /// 遍历候选项缓存，尝试找到已缓存的清晰度列表。
  static List<String> _resolveCachedQualities({
    required List<String> candidateItemGuids,
  }) {
    for (final guid in candidateItemGuids) {
      final key = guid.trim();
      if (key.isEmpty) continue;
      final detail = _cachedItemDetails[key];
      if (detail == null) continue;
      final item = _detailItem(detail);
      final playItemGuid = _extractPlayItemGuid(detail, item);
      if (playItemGuid.isEmpty) continue;
      final qualities = _cachedQualities[playItemGuid];
      if (qualities != null && qualities.isNotEmpty) return qualities;
    }
    return const <String>[];
  }

  /// 遍历候选项缓存，尝试提取源清晰度。
  static String _resolveCachedSourceResolution({
    required MediaLibraryItem? episode,
    required List<String> candidateItemGuids,
  }) {
    for (final guid in candidateItemGuids) {
      final key = guid.trim();
      if (key.isEmpty) continue;
      final detail = _cachedItemDetails[key];
      if (detail == null) continue;
      final item = _detailItem(detail);
      return _extractSourceResolution(item, episode);
    }
    return '';
  }

  /// 加载下载信息并展示季度下载面板。[gateway] 由调用页注入（飞牛详情数据网关）。
  Future<void> show(
    BuildContext context, {
    required FeiniuDetailDataGateway gateway,
    MediaLibraryItem? episode,
    List<String> candidateItemGuids = const <String>[],
    List<TvEpisodeCardData> episodeEntries = const <TvEpisodeCardData>[],
    int initialRangeIndex = 0,
    int rangeSize = 30,
    required String seriesTitle,
    String preferredSubtitleGuid = '',
    Map<String, dynamic> localeMap = const <String, dynamic>{},
  }) async {
    final l10n = AppLocalizations.of(context);
    final primaryGuid = episode?.guid.trim().isNotEmpty == true
        ? episode!.guid.trim()
        : candidateItemGuids
              .map((value) => value.trim())
              .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final actionKey =
        'tv_season_download_sheet:$primaryGuid:${seriesTitle.trim()}';
    if (AsyncActionGuard.isRunning(actionKey)) {
      _showTopTip(context, l10n.downloadLoadingInfo, context.appColors.warning);
      return;
    }

    final provider = context.read<NasProvider>();
    final colors = context.appColors;
    final downloadService = DownloadTaskService.instance;

    // Shared context populated during loading, used by download callbacks.
    Map<String, dynamic>? loadedItem;
    _DownloadGroupMeta? loadedGroupMeta;

    await AsyncActionGuard.run<void>(
      actionKey,
      settleDuration: const Duration(milliseconds: 500),
      action: () async {
        try {
          await downloadService.initialize();

          // Try to pre-populate quality options from cache.
          final sourceResolution = _resolveCachedSourceResolution(
            episode: episode,
            candidateItemGuids: candidateItemGuids,
          );
          final cachedQualityStrings = _resolveCachedQualities(
            candidateItemGuids: candidateItemGuids,
          );
          final cachedQualityOptions = cachedQualityStrings.isNotEmpty
              ? cachedQualityStrings
                    .map(
                      (quality) => TvSeasonDownloadQualityOption(
                        value: quality,
                        label: _qualityLabel(quality, l10n),
                        hint: _downloadQualityHint(
                          l10n: l10n,
                          sourceResolution: sourceResolution,
                          quality: quality,
                          downloaded: downloadService.hasDownloadedResolution(
                            episode?.guid ?? '',
                            quality,
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false)
              : const <TvSeasonDownloadQualityOption>[];

          // Build initial payload with static data — shown immediately.
          final episodePoster = (episode?.poster ?? '').trim();
          final initialPosterUrl = episodePoster.isNotEmpty
              ? '${provider.baseUrl}$episodePoster'
              : '';
          final initialPayload = TvSeasonDownloadSheetPayload(
            sheetTitle: l10n.downloadSelectItem,
            qualityLabel: l10n.downloadQuality,
            qualitySheetTitle: l10n.downloadSelectQuality,
            itemTitle: episode?.title ?? seriesTitle,
            posterUrls: initialPosterUrl.isNotEmpty
                ? <String>[initialPosterUrl]
                : const <String>[],
            token: provider.token,
            posterBadgeLabel: _posterBadgeLabel(sourceResolution),
            episodeEntries: episodeEntries,
            qualityOptions: cachedQualityOptions,
            initialQuality: _resolveInitialQuality(
              cachedQualityStrings,
              sourceResolution,
            ),
            initialRangeIndex: initialRangeIndex,
            rangeSize: rangeSize,
            downloadLabel: l10n.downloadDownload,
            downloadingLabel: l10n.downloadDownloading,
            downloadedLabel: l10n.downloadDownloaded,
            pausedLabel: l10n.downloadPaused,
            openListLabel: l10n.downloadOpenList,
            primaryActionState: downloadService.actionStateForItem(
              episode?.guid ?? '',
            ),
            episodeActionStates: downloadService.actionStatesForItems(
              episodeEntries.map((entry) => entry.guid),
            ),
          );

          final payloadNotifier = ValueNotifier<TvSeasonDownloadSheetPayload>(
            initialPayload,
          );

          // Kick off API loading in background (does not block sheet display).
          unawaited(
            _loadSheetApiData(
              api: gateway,
              provider: provider,
              episode: episode,
              candidateItemGuids: candidateItemGuids,
              episodeEntries: episodeEntries,
              seriesTitle: seriesTitle,
              initialRangeIndex: initialRangeIndex,
              rangeSize: rangeSize,
              l10n: l10n,
              downloadService: downloadService,
              payloadNotifier: payloadNotifier,
              initialPayload: initialPayload,
              onItemLoaded: (item) => loadedItem = item,
              onGroupMetaLoaded: (meta) => loadedGroupMeta = meta,
            ),
          );

          // Show sheet immediately with static data; blocks until sheet closes.
          if (!context.mounted) return;
          await TvSeasonDownloadSheet.show(
            context,
            payloadNotifier: payloadNotifier,
            onDownloadTap: (selectedQuality) async {
              final targetEpisode = episode;
              if (targetEpisode == null) return;
              final item = loadedItem;
              final groupMeta = loadedGroupMeta;
              if (item == null || groupMeta == null) return;
              try {
                final result = await downloadService.startDownload(
                  provider: provider,
                  itemGuid: targetEpisode.guid,
                  resolution: selectedQuality,
                  title: _buildItemTitle(
                    item,
                    targetEpisode,
                    seriesTitle,
                    l10n,
                  ),
                  groupId: groupMeta.id,
                  groupTitle: groupMeta.title,
                  durationText: _durationText(targetEpisode.duration, l10n),
                  posterUrls: _posterUrls(
                    provider.baseUrl,
                    item,
                    targetEpisode,
                  ),
                  groupPosterUrls: groupMeta.posterUrls,
                  preferredSubtitleGuid: preferredSubtitleGuid,
                );
                if (!context.mounted) return;
                _showStartResultTip(
                  context,
                  result: result,
                  qualityText: _qualityLabel(selectedQuality, l10n),
                  colors: colors,
                  l10n: l10n,
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
            onEpisodeDownloadTap: (episodeGuid, selectedQuality) async {
              final matched = episodeEntries
                  .cast<TvEpisodeCardData?>()
                  .firstWhere(
                    (entry) => entry?.guid == episodeGuid,
                    orElse: () => null,
                  );
              if (matched == null) return;
              final groupMeta = loadedGroupMeta;
              if (groupMeta == null) return;
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
                  qualityText: _qualityLabel(selectedQuality, l10n),
                  colors: colors,
                  l10n: l10n,
                  title: matched.title,
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

  static Future<void> _loadSheetApiData({
    required FeiniuDetailDataGateway api,
    required NasProvider provider,
    MediaLibraryItem? episode,
    required List<String> candidateItemGuids,
    required List<TvEpisodeCardData> episodeEntries,
    required String seriesTitle,
    required int initialRangeIndex,
    required int rangeSize,
    required AppLocalizations l10n,
    required DownloadTaskService downloadService,
    required ValueNotifier<TvSeasonDownloadSheetPayload> payloadNotifier,
    required TvSeasonDownloadSheetPayload initialPayload,
    required void Function(Map<String, dynamic>?) onItemLoaded,
    required void Function(_DownloadGroupMeta?) onGroupMetaLoaded,
  }) async {
    try {
      final detail = await _resolveDownloadDetail(
        api,
        episode: episode,
        candidateItemGuids: candidateItemGuids,
      );
      if (detail == null) return;

      final item = _detailItem(detail);
      onItemLoaded(item);
      final groupMeta = await _resolveGroupMeta(
        api,
        provider.baseUrl,
        detail,
        item,
        episode,
        seriesTitle,
        l10n,
      );
      onGroupMetaLoaded(groupMeta);

      final playItemGuid = _extractPlayItemGuid(detail, item);
      if (playItemGuid.isEmpty) return;

      final qualities =
          _cachedQualities[playItemGuid] ??
          await api.getDownloadResolutionOptions(playItemGuid, lan: 'zh-CN');
      if (qualities.isEmpty) return;
      _cachedQualities[playItemGuid] = qualities;

      final sourceResolution = _extractSourceResolution(item, episode);
      final updatedPayload = TvSeasonDownloadSheetPayload(
        sheetTitle: initialPayload.sheetTitle,
        qualityLabel: initialPayload.qualityLabel,
        qualitySheetTitle: initialPayload.qualitySheetTitle,
        itemTitle: _buildItemTitle(item, episode, seriesTitle, l10n),
        posterUrls: _posterUrls(provider.baseUrl, item, episode),
        token: initialPayload.token,
        posterBadgeLabel: _posterBadgeLabel(sourceResolution),
        episodeEntries: initialPayload.episodeEntries,
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
                    episode?.guid ?? '',
                    quality,
                  ),
                ),
              ),
            )
            .toList(growable: false),
        initialQuality: _resolveInitialQuality(qualities, sourceResolution),
        initialRangeIndex: initialPayload.initialRangeIndex,
        rangeSize: initialPayload.rangeSize,
        downloadLabel: initialPayload.downloadLabel,
        downloadingLabel: initialPayload.downloadingLabel,
        downloadedLabel: initialPayload.downloadedLabel,
        pausedLabel: initialPayload.pausedLabel,
        openListLabel: initialPayload.openListLabel,
        primaryActionState: initialPayload.primaryActionState,
        episodeActionStates: initialPayload.episodeActionStates,
      );
      payloadNotifier.value = updatedPayload;
    } catch (error) {
      // Push an error-indicating payload so the sheet shows the failure state.
      payloadNotifier.value = initialPayload.copyWith(loadingError: true);
    }
  }

  static Future<Map<String, dynamic>?> _resolveDownloadDetail(
    FeiniuDetailDataGateway api, {
    required MediaLibraryItem? episode,
    required List<String> candidateItemGuids,
  }) async {
    final candidates = <String>{
      if (episode?.guid.trim().isNotEmpty == true) episode!.guid.trim(),
      ...candidateItemGuids
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty),
    }.toList(growable: false);

    // Check cache first.
    for (final guid in candidates) {
      final cached = _cachedItemDetails[guid];
      if (cached != null) {
        final item = _detailItem(cached);
        if (_extractPlayItemGuid(cached, item).isNotEmpty) {
          return cached;
        }
      }
    }

    for (final guid in candidates) {
      final detail = await api.getItemDetail(guid);
      if (detail.isNotEmpty) {
        _cachedItemDetails[guid] = detail;
      }
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
    FeiniuDetailDataGateway api,
    String baseUrl,
    Map<String, dynamic> detail,
    Map<String, dynamic> item,
    MediaLibraryItem? episode,
    String seriesTitle,
    AppLocalizations l10n,
  ) async {
    final currentPosterUrls = _posterUrls(baseUrl, item, episode);
    final currentTitle = _collectionTitleFromMap(item, l10n);
    final tvTitle = (item['tv_title'] ?? '').toString().trim();
    final currentSeasonNumber = _asInt(item['season_number']);
    if (currentTitle.isNotEmpty &&
        (currentTitle != tvTitle || currentSeasonNumber > 0)) {
      final currentGuid = (item['guid'] ?? detail['guid'] ?? '')
          .toString()
          .trim();
      return _DownloadGroupMeta(
        id: currentGuid.isNotEmpty ? currentGuid : seriesTitle.trim(),
        title: _groupTitle(
          seriesTitle: seriesTitle,
          seasonTitle: currentTitle,
          l10n: l10n,
        ),
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
        final parentTitle = _collectionTitleFromMap(parentItem, l10n);
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
            fallbackTitle: _fallbackGroupSuffix(item, episode, l10n),
            l10n: l10n,
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
        collectionTitle: _fallbackGroupSuffix(item, episode, l10n),
        l10n: l10n,
      ),
      posterUrls: const <String>[],
    );
  }

  static String _buildItemTitle(
    Map<String, dynamic> item,
    MediaLibraryItem? episode,
    String seriesTitle,
    AppLocalizations l10n,
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
      if (episodeNumber > 0) _episodeLabel(episodeNumber, l10n),
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

  static String _qualityLabel(String raw, AppLocalizations l10n) {
    final trimmed = raw.trim();
    if (trimmed == 'Others') {
      return l10n.commonOther;
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
    AppLocalizations l10n,
  ) {
    final seasonNumber = _asInt(item['season_number']);
    if (seasonNumber > 0) return _seasonLabel(seasonNumber, l10n);
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

  static String _collectionTitleFromMap(
    Map<String, dynamic> item,
    AppLocalizations l10n,
  ) {
    final title = (item['title'] ?? '').toString().trim();
    if (title.isNotEmpty) return title;
    final seasonNumber = _asInt(item['season_number']);
    if (seasonNumber > 0) return _seasonLabel(seasonNumber, l10n);
    return '';
  }

  static String _groupTitle({
    required String seriesTitle,
    required String seasonTitle,
    required AppLocalizations l10n,
  }) {
    final parts = <String>[
      if (seriesTitle.trim().isNotEmpty) seriesTitle.trim(),
      if (seasonTitle.trim().isNotEmpty) seasonTitle.trim(),
    ];
    if (parts.isNotEmpty) return parts.join(' ');
    return l10n.downloadListTitle;
  }

  static String _composeGroupTitle({
    required String seriesTitle,
    required String collectionTitle,
    String fallbackTitle = '',
    AppLocalizations? l10n,
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
    return series.isNotEmpty ? series : l10n?.downloadListTitle ?? '';
  }

  static String _durationText(int durationSeconds, AppLocalizations l10n) {
    if (durationSeconds <= 0) return '';
    final hour = durationSeconds ~/ 3600;
    final minute = (durationSeconds % 3600) ~/ 60;
    final second = durationSeconds % 60;
    if (hour > 0) return _hoursMinutesLabel(hour, minute, l10n);
    if (minute > 0) {
      return second > 0
          ? _minutesSecondsLabel(minute, second, l10n)
          : _minutesLabel(minute, l10n);
    }
    return _secondsLabel(second, l10n);
  }

  static void _showStartResultTip(
    BuildContext context, {
    required DownloadStartResult result,
    required String qualityText,
    required AppThemeColors colors,
    required AppLocalizations l10n,
    String title = '',
  }) {
    final prefix = title.trim().isEmpty ? '' : '${title.trim()} ';
    if (result.state == DownloadStartState.started) {
      _showTopTip(
        context,
        '$prefix${l10n.downloadStartedWithQuality(qualityText)}',
        colors.success,
      );
      return;
    }
    if (result.state == DownloadStartState.downloading) {
      _showTopTip(
        context,
        '$prefix${l10n.downloadItemDownloading}',
        colors.warning,
      );
      return;
    }
    _showTopTip(
      context,
      '$prefix${l10n.downloadItemDownloaded}',
      colors.textSecondary,
    );
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
