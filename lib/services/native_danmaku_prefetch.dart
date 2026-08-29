import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import '../danmaku/api/dandanplay_api.dart';
import '../danmaku/api/dandanplay_config.dart';
import '../danmaku/api/dandanplay_resolver.dart';
import '../danmaku/cache/dandanplay_comment_cache_store.dart';
import '../danmaku/parser/danmaku_import_parser.dart';
import '../danmaku/models/dandanplay_episode_search_item.dart';
import '../danmaku/models/danmaku_comment.dart';
import '../danmaku/models/danmaku_saved_source.dart';
import '../danmaku/models/danmaku_settings.dart';
import '../danmaku/settings/danmaku_saved_source_store.dart';
import '../danmaku/settings/danmaku_settings_store.dart';

/// 为原生播放壳预取/检索弹幕。
///
/// 渐进原生化阶段 1：原生壳是独立 Activity，拿不到播放器内的弹幕拉取链。这里在
/// Flutter 编排层（详情页 engine 仍存活时）用媒体上下文做一次 DanDanPlay 自动匹配+
/// 拉取，把结果序列化成原生 `NativeDanmakuOverlayView.setPayload` 的格式写入临时
/// 文件，路径随 Intent 传给原生壳读取（弹幕量大，走文件避开 Binder TransactionTooLarge）。
///
/// 阶段 2 在此基础上新增「在线搜索 + 选集导入」：原生壳弹幕源子页通过反向通道调
/// [searchCandidates] 拿候选、调 [importEpisodeToFile] 按所选 episodeId 落文件再读回。
///
/// 加载策略：**本地优先 + 时效回源**——本地（激活源/本地导入/随片下载）有就用本地，
/// 本地太久没更新先联网刷新，刷新失败仍落回本地（离线可播）；无本地才走在线自动匹配。
class NativeDanmakuPrefetch {
  const NativeDanmakuPrefetch._();

  static const Duration _commentCacheTtl = DanDanPlayCommentCacheStore.cacheTtl;
  static const Duration _payloadFileTtl = Duration(hours: 24);

  /// 评论缓存的磁盘保留期。缓存「过期」只代表不再新鲜（读取处按时效标记并触发回源），
  /// 回源失败时过期数据是离线兜底的唯一来源，故清理扫描用比 TTL 更长的保留期。
  static const Duration _commentCacheRetention = Duration(days: 7);

  /// 随片下载源的新鲜期：下载后 48h 内起播直接用本地弹幕、不联网；超过后视为可能积压了
  /// 新弹幕，起播先尝试在线刷新，刷新失败仍回落本地（离线可播）。
  static const Duration _downloadedSourceFreshnessTtl = Duration(hours: 48);

  /// 测试注入：评论缓存与 payload 临时文件的根目录（生产为系统临时目录）。
  @visibleForTesting
  static String? cacheRootOverrideForTest;

  static String get _cacheRoot =>
      cacheRootOverrideForTest ?? Directory.systemTemp.path;

  static DateTime? _lastTempCleanupAt;
  static Future<void>? _tempCleanupFuture;

  /// 原生壳启动时解析弹幕（**本地优先 + 时效回源**）：
  /// 1) 「激活的保存源」（用户手动选定，跨启动持久）与本地导入源（用户主动从文件导入）
  ///    最高优先；其评论缓存新鲜直接本地起播、不联网，过期则先回源刷新（太久没更新要用
  ///    网络获取），刷新失败仍落回旧缓存保证离线可播。
  /// 2) 随片下载缓存：下载后 [_downloadedSourceFreshnessTtl] 内直接本地起播不联网；过期
  ///    先在线刷新，失败落回本地。
  /// 3) 无本地可用时在线 DanDanPlay 自动匹配，无结果写 blocked 标记（6h 后才重试）。
  /// 传入 [itemGuid]/[mediaGuid]/[seasonGuid] 用于复刻 `_currentDanmakuMediaKey` 的 key，
  /// 不传则退化为纯自动匹配（旧行为）。[store] 仅供测试注入独立存储目录。
  static Future<String?> resolveToFile({
    required String seriesTitle,
    String itemTitle = '',
    required int seasonNumber,
    required int episodeNumber,
    required String tmdbId,
    required DanmakuSettings settings,
    String itemGuid = '',
    String mediaGuid = '',
    String seasonGuid = '',
    DanmakuSavedSourceStore? store,
  }) async {
    final resolvedStore = store ?? const DanmakuSavedSourceStore();
    try {
      if (!settings.enabled) return null;
      // 诊断：对比「全新启动」与「壳内切集」两条路喂进来的参数是否一致。切集没弹幕但退出重进有，
      // 多半是这里某个字段（seriesTitle/episodeNumber/tmdbId）在切集时是空的，导致下方在线匹配被跳过。
      debugPrint(
        '[DANMAKU][NATIVE_PREFETCH] in series="$seriesTitle" title="$itemTitle" s=$seasonNumber '
        'e=$episodeNumber tmdb="$tmdbId" item="$itemGuid" media="$mediaGuid" season="$seasonGuid"',
      );
      final mediaKey = _buildMediaKey(
        itemGuid: itemGuid,
        mediaGuid: mediaGuid,
        seasonGuid: seasonGuid,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        seriesTitle: seriesTitle,
      );

      if (mediaKey.isNotEmpty) {
        // 1) 激活的保存源优先（你的离线选择）。
        final activeKey = await resolvedStore.loadActiveSourceKey(mediaKey);
        final savedAll = await resolvedStore.loadForMedia(mediaKey);
        debugPrint(
          '[DANMAKU][NATIVE_PREFETCH] mediaKey=$mediaKey '
          'activeKey=$activeKey savedCount=${savedAll.length}',
        );
        if (activeKey != null && activeKey.trim().isNotEmpty) {
          for (final source in savedAll) {
            if (source.sourceKey == activeKey) {
              // 随片下载缓存不算「手动选择」，即便历史数据把它误设成 active 也不当最高优先，
              // 让它落到网络之后的兜底（修复旧版强制激活下载源的遗留数据）。
              if (source.isDownloadedFile) break;
              final path = await _loadSavedSourceToFile(source);
              debugPrint(
                '[DANMAKU][NATIVE_PREFETCH] active source loaded=${path != null} '
                'type=${source.type.name} sourceKey=${source.sourceKey}',
              );
              if (path != null) return path;
              break;
            }
          }
        }
        // 2) 本地导入源（用户**手动**「从文件导入」）优先于在线自动匹配（对齐
        //    _tryLoadPreferredDanmakuSource：本地导入 > 网络 > 本地下载）。放在 blocked
        //    判断前——即便自动匹配被屏蔽，本地导入源仍可离线使用。
        final localImport = savedAll
            .where((s) => s.isLocalFile)
            .cast<DanmakuSavedSource?>()
            .firstWhere((s) => s != null, orElse: () => null);
        if (localImport != null) {
          final path = await _loadSavedSourceToFile(localImport);
          if (path != null) return path;
        }
        // 3) 随片下载缓存（**一键下载**，非手动导入）：本地优先——下载后新鲜期内直接本地
        //    起播、不联网；过期视为可能积压了新弹幕，先在线刷新（太久没更新要用网络获取），
        //    刷新失败仍落回本地旧弹幕（断网/未配置都可离线播放）。
        final downloadedBundle = savedAll
            .where((s) => s.isDownloadedFile)
            .cast<DanmakuSavedSource?>()
            .firstWhere((s) => s != null, orElse: () => null);
        // 自动匹配被屏蔽 → 本轮不再在线请求（含过期随片源的回源刷新），但本地源照常可用。
        final autoBlocked = await resolvedStore.isAutoMatchBlocked(mediaKey);
        final canMatchOnline = !autoBlocked && seriesTitle.trim().isNotEmpty;

        Future<String?> matchOnline() => _resolveOnlineToFile(
          seriesTitle: seriesTitle,
          itemTitle: itemTitle,
          seasonNumber: seasonNumber,
          episodeNumber: episodeNumber,
          tmdbId: tmdbId,
          settings: settings,
          mediaKey: mediaKey,
          store: resolvedStore,
          itemGuid: itemGuid,
          mediaGuid: mediaGuid,
          seasonGuid: seasonGuid,
        );

        var onlineAttempted = false;
        if (downloadedBundle != null) {
          final downloadedFresh =
              DateTime.now().millisecondsSinceEpoch -
                  downloadedBundle.updatedAtMs <=
              _downloadedSourceFreshnessTtl.inMilliseconds;
          debugPrint(
            '[DANMAKU][NATIVE_PREFETCH] downloaded bundle: fresh=$downloadedFresh '
            'updatedAtMs=${downloadedBundle.updatedAtMs} '
            'commentCount=${downloadedBundle.commentCount}',
          );
          if (!downloadedFresh && canMatchOnline) {
            onlineAttempted = true;
            final refreshed = await matchOnline();
            debugPrint(
              '[DANMAKU][NATIVE_PREFETCH] downloaded refresh '
              'result=${refreshed != null}',
            );
            if (refreshed != null) return refreshed;
          }
          final localPath = await _loadSavedSourceToFile(downloadedBundle);
          if (localPath != null) return localPath;
          // 本地文件读不出来（被清/损坏）且还没试过在线 → 落到下方在线匹配。
        }

        // 4) 在线自动匹配（无随片本地源、或本地读失败时）。
        debugPrint(
          '[DANMAKU][NATIVE_PREFETCH] online gate: autoBlocked=$autoBlocked '
          'seriesTitleEmpty=${seriesTitle.trim().isEmpty} '
          'onlineAttempted=$onlineAttempted',
        );
        if (!onlineAttempted && canMatchOnline) {
          final online = await matchOnline();
          debugPrint(
            '[DANMAKU][NATIVE_PREFETCH] online result=${online != null}',
          );
          if (online != null) return online;
        }
        return null;
      }

      // 无 mediaKey（纯自动匹配旧路径）：直接在线匹配。
      return await _resolveOnlineToFile(
        seriesTitle: seriesTitle,
        itemTitle: itemTitle,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        tmdbId: tmdbId,
        settings: settings,
        mediaKey: mediaKey,
        store: resolvedStore,
      );
    } catch (_) {
      // 旁路能力：匹配失败/未配置/网络错误都静默跳过，照常播放无弹幕。
      return null;
    }
  }

  /// 在线 DanDanPlay 自动匹配并落 payload 文件；无结果时写入 blocked 标记。
  /// 网络异常就地吞掉返回 null：不能穿透到调用方的 catch 把「回源失败 → 落回本地」
  /// 的兜底链一起跳掉（否则断网时随片下载/过期缓存全部失效）。
  static Future<String?> _resolveOnlineToFile({
    required String seriesTitle,
    String itemTitle = '',
    required int seasonNumber,
    required int episodeNumber,
    required String tmdbId,
    required DanmakuSettings settings,
    required String mediaKey,
    required DanmakuSavedSourceStore store,
    String itemGuid = '',
    String mediaGuid = '',
    String seasonGuid = '',
  }) async {
    try {
      if (seriesTitle.trim().isEmpty) return null;
      if (!await DanDanPlayConfig.ensureConfigured()) return null;
      final resolver = _buildResolver();
      final resolved = await resolver.resolveForPlayback(
        seriesTitle: seriesTitle,
        itemTitle: itemTitle,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        tmdbId: tmdbId,
      );
      final comments = resolved?.result.comments ?? const <DanmakuComment>[];
      if (resolved == null || comments.isEmpty) {
        if (mediaKey.isNotEmpty) {
          await store.saveAutoMatchBlockedReason(
            mediaKey: mediaKey,
            reason: DanmakuSavedSourceStore.autoNoResultReason(),
          );
        }
        return null;
      }
      // 自动匹配命中即登记进弹幕源库，使「弹幕源」面板（原生壳 + Flutter）能看到当前正在用的
      // 弹幕、并可重选/切换。此前这条路径只写 payload 注入播放器、从不 saveSource，导致用户在
      // 源面板里看不到自动匹配到的弹幕。统一使用 dandan:<episodeId>，并明确激活当前命中源。
      final matchedItem = resolved.item;
      final sourceKey = 'dandan:${matchedItem.episodeId}';
      if (mediaKey.isNotEmpty && matchedItem.episodeId > 0) {
        await store.saveSource(
          DanmakuSavedSource(
            type: DanmakuSavedSourceType.danDanPlay,
            mediaKey: mediaKey,
            sourceKey: sourceKey,
            label: matchedItem.displayTitle,
            detail: matchedItem.displaySubtitle,
            seriesTitle: seriesTitle.trim(),
            itemTitle: itemTitle.trim(),
            itemGuid: itemGuid.trim(),
            seasonGuid: seasonGuid.trim(),
            mediaGuid: mediaGuid.trim(),
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            commentCount: comments.length,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
          activate: true,
        );
      }
      if (matchedItem.episodeId > 0) {
        await _cacheComments('dandan:${matchedItem.episodeId}', comments);
      }
      return await _writePayloadFile(
        buildPayload(settings, comments, sourceKey: sourceKey),
      );
    } catch (_) {
      return null;
    }
  }

  /// 复刻 `_currentDanmakuMediaKey`（mpv_player_danmaku_mixin）的 key 规则，保证与旧
  /// Flutter 播放器存保存源时用的 key 完全一致，才能查到。
  static String _buildMediaKey({
    required String itemGuid,
    required String mediaGuid,
    required String seasonGuid,
    required int seasonNumber,
    required int episodeNumber,
    String seriesTitle = '',
    String itemTitle = '',
  }) {
    final item = itemGuid.trim();
    final media = mediaGuid.trim();
    final season = seasonGuid.trim();
    if (item.isNotEmpty ||
        media.isNotEmpty ||
        season.isNotEmpty ||
        episodeNumber > 0) {
      return <String>[
        'v2',
        'item=$item',
        'media=$media',
        'season=$season',
        's=$seasonNumber',
        'e=$episodeNumber',
      ].join('|');
    }
    final title = (seriesTitle.trim().isNotEmpty ? seriesTitle : itemTitle)
        .trim();
    if (title.isEmpty) return '';
    return 'fallback:v2:$title:$seasonNumber:$episodeNumber';
  }

  /// 把一个保存源加载成 payload 文件：danDanPlay 按 episodeId 重拉、localFile 解析文件。
  ///
  /// 本地优先 + 时效回源：评论缓存新鲜（≤[_commentCacheTtl]）直接用、不联网；过期视为
  /// 可能积压了新弹幕，先回源拉新，回源失败（断网/未配置/原文件被清）落回过期缓存，
  /// 保证离线可播。
  static Future<String?> _loadSavedSourceToFile(
    DanmakuSavedSource source,
  ) async {
    if (source.isDanDanPlay) {
      final raw = source.sourceKey;
      final episodeId =
          int.tryParse(raw.startsWith('dandan:') ? raw.substring(7) : raw) ?? 0;
      if (episodeId <= 0) return null;
      final sourceKey = 'dandan:$episodeId';
      final cached = await _payloadFromCachedComments(sourceKey);
      if (cached != null && !cached.isStale) return cached.path;
      // 缓存缺失/过期 → 按 episodeId 回源拉新（内部自带 try/catch，失败返回 null）。
      final result = await importEpisodeToFile(
        episodeId: episodeId,
        animeTitle: source.seriesTitle,
        episodeTitle: source.itemTitle,
        episodeNumber: source.episodeNumber,
      );
      final freshPath = result?['danmakuFile'] as String?;
      if (freshPath != null) return freshPath;
      return cached?.path;
    }
    final raw = source.sourceKey;
    final path = raw.startsWith('local:') ? raw.substring(6) : raw;
    // 用户导入/随片的本地文件是唯一事实源：过期只重读原文件（不用网络弹幕顶掉用户选择），
    // 原文件被清则落回过期评论缓存，离线可播。
    final cached = await _payloadFromCachedComments('local:$path');
    if (cached != null && !cached.isStale) return cached.path;
    final result = await importLocalFileToFile(path);
    final freshPath = result?['danmakuFile'] as String?;
    if (freshPath != null) return freshPath;
    return cached?.path;
  }

  /// 在线搜索弹幕候选（供原生壳弹幕源子页）。返回每项的精简 Map，便于跨 channel 传回。
  static Future<List<Map<String, dynamic>>> searchCandidates({
    required String keyword,
    int episodeNumber = 0,
    int seasonNumber = 0,
    String tmdbId = '',
  }) async {
    try {
      if (keyword.trim().isEmpty) return const <Map<String, dynamic>>[];
      if (!await DanDanPlayConfig.ensureConfigured()) {
        return const <Map<String, dynamic>>[];
      }
      final resolver = _buildResolver();
      final items = await resolver.searchEpisodeCandidates(
        keyword: keyword,
        episodeNumber: episodeNumber,
        tmdbId: tmdbId,
        allowLooseTitleFallback: true,
      );
      final sortedItems = DanDanPlayResolver.sortCandidatesForSeason(
        items,
        seasonNumber: seasonNumber,
      );
      return <Map<String, dynamic>>[
        for (final item in sortedItems)
          <String, dynamic>{
            'episodeId': item.episodeId,
            'animeTitle': item.animeTitle,
            'episodeTitle': item.episodeTitle,
            'episodeNumber': item.episodeNumber,
            'matchesCurrentSeason': DanDanPlayResolver.candidateMatchesSeason(
              item,
              seasonNumber: seasonNumber,
            ),
            'title': item.displaySubtitle,
            'subtitle': item.displayTitle,
          },
      ];
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  /// 按所选 episodeId 拉弹幕并落临时文件，返回 `{danmakuFile, sourceKey}`；失败返回 null。
  static Future<Map<String, dynamic>?> importEpisodeToFile({
    required int episodeId,
    String animeTitle = '',
    String episodeTitle = '',
    int episodeNumber = 0,
    String itemGuid = '',
    String mediaGuid = '',
    String seasonGuid = '',
    int seasonNumber = 0,
    int currentEpisodeNumber = 0,
    String seriesTitle = '',
    String mediaItemTitle = '',
  }) async {
    try {
      if (episodeId <= 0) return null;
      if (!await DanDanPlayConfig.ensureConfigured()) return null;
      final resolver = _buildResolver();
      final item = DanDanPlayEpisodeSearchItem(
        episodeId: episodeId,
        animeTitle: animeTitle,
        episodeTitle: episodeTitle,
        episodeNumber: episodeNumber,
      );
      final result = await resolver.importEpisodeById(item);
      final comments = result?.comments ?? const <DanmakuComment>[];
      if (comments.isEmpty) return null;
      final settings = await const DanmakuSettingsStore().load();
      final sourceKey = 'dandan:$episodeId';
      // 取到评论即落持久缓存：下次断网重放/选集可直接命中，无需再联网。
      await _cacheComments(sourceKey, comments);
      final mediaKey = _buildMediaKey(
        itemGuid: itemGuid,
        mediaGuid: mediaGuid,
        seasonGuid: seasonGuid,
        seasonNumber: seasonNumber,
        episodeNumber: currentEpisodeNumber,
        seriesTitle: seriesTitle,
        itemTitle: mediaItemTitle,
      );
      if (mediaKey.isNotEmpty) {
        final savedSeriesTitle = seriesTitle.trim().isNotEmpty
            ? seriesTitle.trim()
            : animeTitle.trim();
        final savedItemTitle = mediaItemTitle.trim().isNotEmpty
            ? mediaItemTitle.trim()
            : episodeTitle.trim();
        await const DanmakuSavedSourceStore().saveSource(
          DanmakuSavedSource(
            type: DanmakuSavedSourceType.danDanPlay,
            mediaKey: mediaKey,
            sourceKey: sourceKey,
            label: item.displayTitle,
            detail: item.displaySubtitle,
            seriesTitle: savedSeriesTitle,
            itemTitle: savedItemTitle,
            itemGuid: itemGuid.trim(),
            seasonGuid: seasonGuid.trim(),
            mediaGuid: mediaGuid.trim(),
            seasonNumber: seasonNumber,
            episodeNumber: currentEpisodeNumber,
            commentCount: comments.length,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
          activate: true,
        );
      }
      final path = await _writePayloadFile(
        buildPayload(settings, comments, sourceKey: sourceKey),
      );
      if (path == null) return null;
      return <String, dynamic>{'danmakuFile': path, 'sourceKey': sourceKey};
    } catch (_) {
      return null;
    }
  }

  /// 解析本地弹幕文件（原生壳已把所选文件拷到可读路径），落临时 payload 文件后返回
  /// `{danmakuFile, sourceKey}`；失败返回 null。供原生壳「从文件导入」反向调用。
  static Future<Map<String, dynamic>?> importLocalFileToFile(
    String path,
  ) async {
    try {
      if (path.trim().isEmpty) return null;
      final result = await DanmakuImportParser.parseFile(path);
      final comments = result.comments;
      if (comments.isEmpty) return null;
      final settings = await const DanmakuSettingsStore().load();
      final sourceKey = 'local:$path';
      // 解析结果落持久缓存：原文件被清后仍可离线重放。
      await _cacheComments(sourceKey, comments);
      final out = await _writePayloadFile(
        buildPayload(settings, comments, sourceKey: sourceKey),
      );
      if (out == null) return null;
      return <String, dynamic>{'danmakuFile': out, 'sourceKey': sourceKey};
    } catch (_) {
      return null;
    }
  }

  /// 列出某媒体在 Flutter 弹幕源库（`DanmakuSavedSourceStore`）里的已保存源，供原生壳
  /// 弹幕源面板合并显示。原生侧自有一套 prefs（`danmaku_sources_v1`），与此库**互不相通**：
  /// 随片下载/在线自动匹配注册的源只落在这里，原生面板原本看不到，故走反向通道拉过来。
  /// mediaKey 由本类 [_buildMediaKey] 统一计算（原生侧无法复刻该格式），原生只需透传媒体身份。
  static Future<List<Map<String, dynamic>>> listSavedSources({
    String itemGuid = '',
    String mediaGuid = '',
    String seasonGuid = '',
    int seasonNumber = 0,
    int episodeNumber = 0,
    String seriesTitle = '',
  }) async {
    try {
      const store = DanmakuSavedSourceStore();
      final mediaKey = _buildMediaKey(
        itemGuid: itemGuid,
        mediaGuid: mediaGuid,
        seasonGuid: seasonGuid,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        seriesTitle: seriesTitle,
      );
      if (mediaKey.isEmpty) return const <Map<String, dynamic>>[];
      final sources = await store.loadForMedia(mediaKey);
      final activeKey =
          (await store.loadActiveSourceKey(mediaKey))?.trim() ?? '';
      return <Map<String, dynamic>>[
        for (final s in sources)
          <String, dynamic>{
            'sourceKey': s.sourceKey,
            'type': s.type.name, // localFile | danDanPlay | downloadedFile
            'label': s.label,
            'detail': s.detail,
            'commentCount': s.commentCount,
            'updatedAtMs': s.updatedAtMs,
            'active': activeKey.isNotEmpty && s.sourceKey == activeKey,
          },
      ];
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  /// 按 sourceKey 把 Flutter 弹幕源库里的某条源加载成 payload 文件（供原生壳点选应用）。
  /// 用户在面板里手动点选即视为「选定」，顺手设为 active 让下次播放优先复用（随片下载源
  /// 例外：[resolveToFile] 故意不把 downloadedFile 当 active 最高优先，这里设了也无副作用）。
  static Future<Map<String, dynamic>?> loadSavedSourceToFile({
    required String sourceKey,
    String itemGuid = '',
    String mediaGuid = '',
    String seasonGuid = '',
    int seasonNumber = 0,
    int episodeNumber = 0,
    String seriesTitle = '',
  }) async {
    try {
      if (sourceKey.trim().isEmpty) return null;
      const store = DanmakuSavedSourceStore();
      final mediaKey = _buildMediaKey(
        itemGuid: itemGuid,
        mediaGuid: mediaGuid,
        seasonGuid: seasonGuid,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        seriesTitle: seriesTitle,
      );
      if (mediaKey.isEmpty) return null;
      final sources = await store.loadForMedia(mediaKey);
      DanmakuSavedSource? match;
      for (final s in sources) {
        if (s.sourceKey == sourceKey) {
          match = s;
          break;
        }
      }
      if (match == null) return null;
      final path = await _loadSavedSourceToFile(match);
      if (path == null) return null;
      await store.setActiveSourceKey(mediaKey: mediaKey, sourceKey: sourceKey);
      return <String, dynamic>{'danmakuFile': path, 'sourceKey': sourceKey};
    } catch (_) {
      return null;
    }
  }

  static DanDanPlayResolver _buildResolver() => DanDanPlayResolver(
    DanDanPlayApi(
      appId: DanDanPlayConfig.appId,
      appSecrets: DanDanPlayConfig.appSecrets,
    ),
  );

  /// 已存弹幕源的持久评论缓存：首次取到评论后按 sourceKey 把**评论**(compact)落盘，
  /// 重放/选集时优先读缓存（断网可用），未命中才联网/读原文件。落 systemTemp(=app cache
  /// 目录)：系统极少清理，命名按 sourceKey 稳定，跨会话复用。重放时再用**当前** settings
  /// 重建 payload，故设置改动仍生效（缓存只存评论，不存设置）。
  static File _commentCacheFile(String sourceKey) {
    final safeKey = sourceKey.hashCode.toUnsigned(32).toRadixString(16);
    return File('$_cacheRoot/native_danmaku_cache_$safeKey.json');
  }

  static Future<void> _cleanupExpiredTempFiles() async {
    final now = DateTime.now();
    final last = _lastTempCleanupAt;
    if (last != null && now.difference(last) < const Duration(hours: 1)) {
      return;
    }
    final pending = _tempCleanupFuture;
    if (pending != null) {
      await pending;
      return;
    }
    final future = _cleanupExpiredTempFilesImpl(now);
    _tempCleanupFuture = future;
    try {
      await future;
      _lastTempCleanupAt = now;
    } finally {
      if (identical(_tempCleanupFuture, future)) {
        _tempCleanupFuture = null;
      }
    }
  }

  static Future<void> _cleanupExpiredTempFilesImpl(DateTime now) async {
    try {
      await for (final entry in Directory(_cacheRoot).list()) {
        if (entry is! File) continue;
        final name = entry.path.split(Platform.pathSeparator).last;
        if (!name.startsWith('native_danmaku_')) continue;
        final modifiedAt = (await entry.stat()).modified;
        // 缓存文件按保留期清理（过期 ≠ 可删，回源失败还要靠它离线兜底）；
        // payload 临时文件无复用价值，仍按短 TTL 清。
        final ttl = name.startsWith('native_danmaku_cache_')
            ? _commentCacheRetention
            : _payloadFileTtl;
        if (now.difference(modifiedAt) > ttl) {
          await entry.delete();
        }
      }
    } catch (_) {
      // 临时缓存清理失败不影响当前弹幕播放。
    }
  }

  static Future<void> _cacheComments(
    String sourceKey,
    List<DanmakuComment> comments,
  ) async {
    if (sourceKey.isEmpty || comments.isEmpty) return;
    try {
      final data = <List<Object?>>[
        for (final c in comments)
          <Object?>[
            c.id,
            c.timeMs,
            c.text,
            _typeIndex(c.type),
            c.color.toARGB32(),
          ],
      ];
      await _commentCacheFile(sourceKey).writeAsString(jsonEncode(data));
    } catch (_) {
      // 缓存失败不影响本次播放。
    }
  }

  /// 命中持久缓存 → 用当前设置重建 payload 并落临时文件返回路径；未命中返回 null。
  /// 过期缓存**不删除**、以 [isStale] 标记返回：回源失败时它仍是离线兜底的唯一来源，
  /// 磁盘回收交给清理扫描按 [_commentCacheRetention] 处理。
  static Future<_CachedDanmakuPayload?> _payloadFromCachedComments(
    String sourceKey,
  ) async {
    if (sourceKey.isEmpty) return null;
    try {
      final file = _commentCacheFile(sourceKey);
      if (!await file.exists()) return null;
      final modifiedAt = (await file.stat()).modified;
      final isStale = DateTime.now().difference(modifiedAt) > _commentCacheTtl;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty) return null;
      final comments = <DanmakuComment>[];
      for (final entry in decoded) {
        if (entry is! List || entry.length < 5) continue;
        comments.add(
          DanmakuComment(
            id: (entry[0] ?? '').toString(),
            timeMs: (entry[1] as num?)?.toInt() ?? 0,
            text: (entry[2] ?? '').toString(),
            type: _typeFromIndex((entry[3] as num?)?.toInt() ?? 0),
            color: Color((entry[4] as num?)?.toInt() ?? 0xFFFFFFFF),
          ),
        );
      }
      if (comments.isEmpty) return null;
      final settings = await const DanmakuSettingsStore().load();
      debugPrint(
        '[DANMAKU][NATIVE_PREFETCH] offline cache hit sourceKey=$sourceKey '
        'count=${comments.length} stale=$isStale',
      );
      final path = await _writePayloadFile(
        buildPayload(settings, comments, sourceKey: sourceKey),
      );
      if (path == null) return null;
      return _CachedDanmakuPayload(path: path, isStale: isStale);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _writePayloadFile(Map<String, Object?> payload) async {
    await _cleanupExpiredTempFiles();
    final file = File(
      '$_cacheRoot/native_danmaku_'
      '${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await file.writeAsString(jsonEncode(payload));
    return file.path;
  }

  /// 序列化模板对齐 `_syncNativeDanmakuRenderer`：settings 扁平 + commentsCompact
  /// `[id, timeMs, text, typeIndex, color]`。原生壳一次性 setPayload（非每帧），
  /// `NativeDanmakuOverlayView` 内部会排序/建索引。
  static Map<String, Object?> buildPayload(
    DanmakuSettings settings,
    List<DanmakuComment> comments, {
    String sourceKey = '',
  }) {
    return <String, Object?>{
      'enabled': settings.enabled,
      'opacity': settings.opacity,
      'density': settings.density,
      'fontScale': settings.fontScale,
      'fontThickness': settings.fontThickness,
      'speed': settings.speed,
      'displayAreaRatio': settings.displayAreaRatio,
      'targetFrameRateHz': settings.targetFrameRateHz,
      'scrollEnabled': settings.scrollEnabled,
      'topEnabled': settings.topEnabled,
      'bottomEnabled': settings.bottomEnabled,
      'colorEnabled': settings.colorEnabled,
      'hideDuplicate': settings.hideDuplicate,
      'avoidSubtitleArea': settings.avoidSubtitleArea,
      if (sourceKey.isNotEmpty) 'sourceKey': sourceKey,
      'commentsCompact': <List<Object?>>[
        for (final comment in comments)
          <Object?>[
            comment.id,
            comment.timeMs,
            comment.text,
            _typeIndex(comment.type),
            comment.color.toARGB32(),
          ],
      ],
      'commentsMode': 'replace',
      'finalChunk': true,
    };
  }

  static int _typeIndex(DanmakuCommentType type) => switch (type) {
    DanmakuCommentType.top => 1,
    DanmakuCommentType.bottom => 2,
    DanmakuCommentType.scroll => 0,
  };

  static DanmakuCommentType _typeFromIndex(int index) => switch (index) {
    1 => DanmakuCommentType.top,
    2 => DanmakuCommentType.bottom,
    _ => DanmakuCommentType.scroll,
  };
}

/// 评论缓存的一次命中结果。[isStale] 表示缓存已超过时效 TTL——仍可用（回源失败时
/// 离线兜底），但调用方应先尝试回源拉新。
class _CachedDanmakuPayload {
  final String path;
  final bool isStale;

  const _CachedDanmakuPayload({required this.path, required this.isStale});
}
