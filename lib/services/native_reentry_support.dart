import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../api/feiniu_api.dart';
import '../models/media_library_item.dart';
import '../player/controllers/mpv_player_controller.dart';
import '../player/controllers/player_source_controller.dart';
import '../providers/nas_provider.dart';
import '../utils/api_url_helper.dart';
import '../utils/app_exception.dart';
import 'download_task_service.dart';
import 'playback_progress_offline_queue.dart';

/// 原生壳反向通道的共享支持。
///
/// 渐进原生化：原生壳（独立 task、无 FlutterEngine）切画质/选集/退出时，通过反向通道
/// 把意图/进度回传 Flutter 编排层。各播放入口（item/tv_season/电影/下载）的「进度回写」
/// 逻辑完全一致——都是用回传 payload（源自 loadArgs）直接调 `recordPlayback`，与具体
/// launcher 无关，故抽到这里共用。
///
/// `bindReentry` 的 handler 捕获 [NasProvider]（App 级长存活单例）而非 widget context：
/// 原生壳在独立 task 前台时，发起页面可能已退到后台甚至被回收，widget context 不可靠，
/// 但 NasProvider 始终有效。
class NativeReentrySupport {
  const NativeReentrySupport._();

  static const String playlistViewTypeCard = 'card';
  static const String playlistViewTypeButton = 'button';

  /// 原生壳选集面板的数据源：视图偏好、季列表、指定季剧集都仍由 Flutter/NAS 层负责。
  static Future<Map<String, dynamic>?> loadEpisodePickerData(
    NasProvider nas, {
    required String currentLoadArgs,
    String seasonGuid = '',
    List<Map<String, dynamic>> fallbackEpisodes =
        const <Map<String, dynamic>>[],
  }) async {
    if (!nas.isConfigured || currentLoadArgs.trim().isEmpty) return null;
    final Map<String, dynamic> loadArgs;
    try {
      loadArgs = (jsonDecode(currentLoadArgs) as Map).map(
        (key, value) => MapEntry(key.toString(), value),
      );
    } catch (_) {
      return null;
    }

    final embeddedEpisodes = _episodesFromLoadArgs(loadArgs);
    final fallback = fallbackEpisodes.isNotEmpty
        ? fallbackEpisodes
        : embeddedEpisodes;
    final api = FeiniuApi(nas);
    final viewType = await _loadPlaylistViewType(api);
    final requestedSeasonGuid = seasonGuid.trim().isNotEmpty
        ? seasonGuid.trim()
        : (loadArgs['seasonGuid'] ?? '').toString().trim();
    final seriesGuid = await _resolveSeriesGuid(
      api,
      loadArgs,
      requestedSeasonGuid,
    );
    final seasons = await _loadNativeSeasonOptions(api, seriesGuid);
    final targetSeasonGuid = _resolveTargetSeasonGuid(
      requestedSeasonGuid: requestedSeasonGuid,
      seasons: seasons,
      fallbackEpisodes: fallback,
    );
    final episodes = await _loadNativeSeasonEpisodes(
      nas,
      api,
      targetSeasonGuid,
      fallbackEpisodes: fallback,
    );
    return <String, dynamic>{
      'viewType': viewType,
      'selectedSeasonGuid': targetSeasonGuid,
      'seriesTitle': (loadArgs['seriesTitle'] ?? '').toString(),
      'seasons': seasons
          .map(
            (season) => <String, dynamic>{
              ...season,
              'selected': season['seasonGuid'] == targetSeasonGuid,
            },
          )
          .toList(growable: false),
      'episodes': episodes,
    };
  }

  /// 只拉取指定季的剧集（单次 `getEpisodeList`），供原生壳「后台并行预取其它季 / 按需切季」。
  /// 比 [loadEpisodePickerData] 轻得多——后者每次还要拉 viewType + 解析 seriesGuid + 季列表，
  /// 切季只需要该季剧集，用这个避免那 3 个冗余请求，切季近乎即时。
  static Future<Map<String, dynamic>?> loadSeasonEpisodes(
    NasProvider nas, {
    required String seasonGuid,
  }) async {
    final guid = seasonGuid.trim();
    if (!nas.isConfigured || guid.isEmpty) return null;
    final api = FeiniuApi(nas);
    final episodes = await _loadNativeSeasonEpisodes(
      nas,
      api,
      guid,
      fallbackEpisodes: const <Map<String, dynamic>>[],
    );
    if (episodes.isEmpty) return null;
    return <String, dynamic>{'seasonGuid': guid, 'episodes': episodes};
  }

  static Future<bool> setEpisodePickerViewType(
    NasProvider nas,
    String viewType,
  ) async {
    final normalized = viewType.trim();
    if (!nas.isConfigured ||
        (normalized != playlistViewTypeCard &&
            normalized != playlistViewTypeButton)) {
      return false;
    }
    return FeiniuApi(nas).setPlaylistViewType(normalized);
  }

  /// 原生壳回传进度 → `recordPlayback`。本地源（缺 mediaGuid/videoGuid）自动跳过，
  /// 对齐播放器 `_submitPlaybackRecord` 的 `_externalLocalSource` 早退语义。
  static Future<void> recordProgress(
    NasProvider nas,
    Map<String, dynamic> progress,
  ) async {
    final itemGuid = (progress['itemGuid'] ?? '').toString().trim();
    final mediaGuid = (progress['mediaGuid'] ?? '').toString().trim();
    final videoGuid = (progress['videoGuid'] ?? '').toString().trim();
    if (itemGuid.isEmpty || mediaGuid.isEmpty || videoGuid.isEmpty) return;
    final ts = (progress['ts'] as num?)?.toInt() ?? 0;
    final duration = (progress['duration'] as num?)?.toInt() ?? 0;
    if (duration <= 0) return;
    try {
      await FeiniuApi(nas).recordPlayback(
        itemGuid: itemGuid,
        mediaGuid: mediaGuid,
        videoGuid: videoGuid,
        audioGuid: (progress['audioGuid'] ?? '').toString(),
        subtitleGuid: (progress['subtitleGuid'] ?? '').toString(),
        resolution: (progress['resolution'] ?? '').toString(),
        bitrate: (progress['bitrate'] as num?)?.toInt() ?? 0,
        ts: ts.clamp(0, duration),
        duration: duration,
        playLink: (progress['playLink'] ?? '').toString(),
      );
      // 回写成功 = 网络可用，顺带重放离线队列里断网期间积压的进度。
      unawaited(PlaybackProgressOfflineQueue.flush(nas));
    } catch (e) {
      // 断网/超时（可恢复）→ 落盘排队，网络恢复或下次启动重放；
      // 鉴权/数据/致命等不可恢复错误不入队（与在线播放器一致，静默丢弃）。
      final ex = AppException.from(e, action: 'playback record');
      if (ex.isTransient) {
        await PlaybackProgressOfflineQueue.enqueue(progress);
      }
    }
  }

  /// 原生壳「转码流切音轨/字幕/画质」反向链路：复用播放器 [PlayerSourceController.
  /// reloadServerPlaySession]——服务端按所选音轨+字幕+画质重新出流，**保留**未指定的项
  /// （切音轨不动画质、切画质保留音轨/字幕），而不是 `_resolve` 那条会重挑画质（默认回
  /// 1080p）的从头解析路径。
  ///
  /// 入参 [currentLoadArgs] 为原生壳当前完整 loadArgs（即上次回传的 source.toMap），据此
  /// 重建当前态快照；[audioGuid]/[subtitleGuid] 为 null 时保留当前（subtitleGuid 空串=关闭）；
  /// [qualityIndex] 为 null 时保留当前画质。回传新 source 的 loadArgs，原生原地换源。
  static List<Map<String, dynamic>> _episodesFromLoadArgs(
    Map<String, dynamic> loadArgs,
  ) {
    final raw = loadArgs['episodes'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((episode) => episode.map((key, value) => MapEntry('$key', value)))
        .toList(growable: false);
  }

  static Future<String> _loadPlaylistViewType(FeiniuApi api) async {
    try {
      return await api.getPlaylistViewType() ?? playlistViewTypeCard;
    } catch (_) {
      return playlistViewTypeCard;
    }
  }

  static Future<String> _resolveSeriesGuid(
    FeiniuApi api,
    Map<String, dynamic> loadArgs,
    String selectedSeasonGuid,
  ) async {
    final direct = (loadArgs['seriesGuid'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;

    final itemGuid = (loadArgs['itemGuid'] ?? '').toString().trim();
    if (itemGuid.isNotEmpty) {
      try {
        final playInfo = await api.getPlayInfo(itemGuid);
        final fromPlayInfo = playInfo.grandGuid.trim();
        if (fromPlayInfo.isNotEmpty) return fromPlayInfo;
      } catch (_) {}
    }

    if (selectedSeasonGuid.isNotEmpty) {
      try {
        final detail = await api.getItemDetail(selectedSeasonGuid);
        final item = detail['item'];
        final itemMap = item is Map<String, dynamic> ? item : detail;
        final parentGuid = (itemMap['parent_guid'] ?? '').toString().trim();
        if (parentGuid.isNotEmpty) return parentGuid;
      } catch (_) {}
    }
    return '';
  }

  static Future<List<Map<String, dynamic>>> _loadNativeSeasonOptions(
    FeiniuApi api,
    String seriesGuid,
  ) async {
    if (seriesGuid.trim().isEmpty) return const <Map<String, dynamic>>[];
    try {
      final seasons = await api.getSeasonList(seriesGuid.trim());
      return seasons
          .map(
            (season) => <String, dynamic>{
              'seasonGuid': season.guid,
              'seasonLabel': _nativeSeasonLabel(season),
              'seasonNumber': season.seasonNumber,
            },
          )
          .where((season) => (season['seasonGuid'] ?? '').toString().isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  static String _resolveTargetSeasonGuid({
    required String requestedSeasonGuid,
    required List<Map<String, dynamic>> seasons,
    required List<Map<String, dynamic>> fallbackEpisodes,
  }) {
    final requested = requestedSeasonGuid.trim();
    if (requested.isNotEmpty) return requested;
    final firstEpisode = fallbackEpisodes.isNotEmpty
        ? fallbackEpisodes.first
        : null;
    final fallbackSeason = firstEpisode == null
        ? ''
        : (firstEpisode['seasonGuid'] ?? firstEpisode['parentGuid'])
                  ?.toString()
                  .trim() ??
              '';
    if (fallbackSeason.isNotEmpty) return fallbackSeason;
    return seasons.isNotEmpty
        ? (seasons.first['seasonGuid'] ?? '').toString().trim()
        : '';
  }

  static Future<List<Map<String, dynamic>>> _loadNativeSeasonEpisodes(
    NasProvider nas,
    FeiniuApi api,
    String seasonGuid, {
    required List<Map<String, dynamic>> fallbackEpisodes,
  }) async {
    if (seasonGuid.trim().isEmpty) return fallbackEpisodes;
    try {
      final episodes = await api.getEpisodeList(seasonGuid.trim());
      episodes.sort((a, b) {
        final left = a.episodeNumber > 0 ? a.episodeNumber : a.numberOfItem;
        final right = b.episodeNumber > 0 ? b.episodeNumber : b.numberOfItem;
        return left.compareTo(right);
      });
      final mapped = <Map<String, dynamic>>[
        for (final episode in episodes) _nativeEpisodeMap(nas, episode),
      ];
      return mapped.isNotEmpty ? mapped : fallbackEpisodes;
    } catch (_) {
      return fallbackEpisodes;
    }
  }

  static Map<String, dynamic> _nativeEpisodeMap(
    NasProvider nas,
    MediaLibraryItem episode,
  ) {
    final record = DownloadTaskService.instance.downloadedRecordForItem(
      episode.guid,
    );
    final localCover = record == null
        ? ''
        : DownloadTaskService.instance.resolveExistingLocalCover(record);
    final usingLocal = localCover.isNotEmpty;
    return <String, dynamic>{
      'itemGuid': episode.guid,
      'seasonGuid': episode.parentGuid,
      'episodeNumber': episode.episodeNumber,
      'shortLabel': episode.episodeNumber > 0
          ? '${episode.episodeNumber}'
          : (episode.numberOfItem > 0 ? '${episode.numberOfItem}' : ''),
      'title': _nativeEpisodeTitle(episode),
      'poster': usingLocal ? localCover : _nativePosterUrl(nas, episode.poster),
      'imageAuth': usingLocal ? '' : nas.token,
      'duration': episode.duration,
      'watched': episode.watched,
      'watchedTs': episode.watchedTs,
      'ts': episode.ts,
      'downloaded': record != null,
    };
  }

  static String _nativeSeasonLabel(MediaLibraryItem season) {
    if (season.seasonNumber == 0) return '特别篇';
    if (season.seasonNumber > 0) return '第${season.seasonNumber}季';
    final title = season.title.trim();
    if (title.isNotEmpty) return title;
    return '季';
  }

  static String _nativeEpisodeTitle(MediaLibraryItem episode) {
    return episode.title.trim().replaceAll(
      RegExp(r'\.(mkv|mp4|m4v|avi|ts|flv|mov)$', caseSensitive: false),
      '',
    );
  }

  static String _nativePosterUrl(NasProvider nas, String raw) {
    if (raw.trim().isEmpty) return '';
    final candidates = ApiUrlHelper.imageCandidates(
      nas.baseUrl,
      raw,
      width: 320,
    );
    return candidates.isNotEmpty ? candidates.first : '';
  }

  static Future<Map<String, dynamic>?> reloadServerSession(
    NasProvider nas, {
    required String currentLoadArgs,
    String? audioGuid,
    String? subtitleGuid,
    int? qualityIndex,
    int? startPositionMs,
  }) async {
    if (currentLoadArgs.trim().isEmpty) return null;
    final MpvMediaSource source;
    try {
      final raw = (jsonDecode(currentLoadArgs) as Map).map(
        (key, value) => MapEntry(key.toString(), value),
      );
      source = MpvMediaSource.fromMap(raw);
    } catch (_) {
      return null;
    }
    // 切画质（qualityIndex != null）任意模式都走这里——reloadServerPlaySession 会按所选档
    // 重建会话/直链并正确产出分辨率与音轨；只有「非 serverManaged 的纯切音轨/字幕」不该来
    // （那种本地 mpv 切轨即可，原生侧也不会调到这条）。
    if (qualityIndex == null && !source.playbackMode.isServerManaged) {
      return null;
    }

    final api = FeiniuApi(nas);
    final snapshot = PlayerSourceSnapshot(
      itemGuid: source.itemGuid,
      mediaGuid: source.mediaGuid,
      subtitleSourceMediaGuid: source.mediaGuid,
      videoGuid: source.videoGuid,
      directLinkQualityIndex: source.directLinkQualityIndex,
      audioGuid: source.audioTrackGuid,
      subtitleGuid: source.subtitleTrackGuid,
      resolution: source.resolution,
      bitrate: source.bitrate,
      videoWidth: source.videoWidth,
      videoHeight: source.videoHeight,
      currentHeaders: source.headers,
      activeProxySessionId: source.proxySessionId,
      activeSubtitleProxySessionId: null,
      audioTracks: source.audioTracks,
      subtitleTracks: source.subtitleTracks,
      qualities: source.qualities,
      playbackMode: source.playbackMode,
      serverFallbackSubtitleGuids: const <String>{},
    );
    final selectedQuality =
        (qualityIndex != null &&
            qualityIndex >= 0 &&
            qualityIndex < source.qualities.length)
        ? source.qualities[qualityIndex]
        : null;
    final startPos = startPositionMs != null
        ? Duration(milliseconds: startPositionMs)
        : source.startPosition;

    final PlayerServerReloadResult result;
    try {
      result = await const PlayerSourceController().reloadServerPlaySession(
        api: api,
        snapshot: snapshot,
        request: PlayerServerReloadRequest(
          audioGuid: audioGuid,
          subtitleGuid: subtitleGuid,
          quality: selectedQuality,
          startPosition: startPos,
        ),
      );
    } catch (_) {
      return null;
    }

    final resolvedStart = (!result.reliableSeek && startPos > Duration.zero)
        ? Duration.zero
        : startPos;
    final newSource = source.copyWith(
      loadNonce: createMpvLoadNonce(),
      url: result.currentUrl,
      headers: result.currentHeaders,
      proxySessionId: result.activeProxySessionId,
      playLink: result.currentPlayLink,
      serverSessionHlsTimeSeconds: result.currentServerSessionHlsTimeSeconds,
      reliableSeek: result.reliableSeek,
      seekProbeSummary: result.seekProbeSummary,
      mediaGuid: result.currentMediaGuid,
      videoGuid: result.currentVideoGuid,
      audioTrackGuid: result.currentAudioGuid,
      subtitleTrackGuid: result.currentSubtitleGuid,
      clearSubtitleTrackGuid: (result.currentSubtitleGuid ?? '').trim().isEmpty,
      audioTracks: result.audioTracks,
      subtitleTracks: result.subtitleTracks,
      qualities: result.qualities,
      resolution: result.currentResolution,
      bitrate: result.currentBitrate,
      videoWidth: result.currentVideoWidth,
      videoHeight: result.currentVideoHeight,
      videoCodecName: result.currentVideoCodecName,
      videoProfile: result.currentVideoProfile,
      colorSpace: result.currentColorSpace,
      colorTransfer: result.currentColorTransfer,
      colorPrimaries: result.currentColorPrimaries,
      bitDepth: result.currentBitDepth,
      playbackMode: result.playbackMode,
      startPosition: resolvedStart,
      // 服务端会话把所选音轨/字幕烧录进流，mpv 端不再按 sid 选轨。
      clearAudioTrackIndex: true,
      clearSubtitleTrackIndex: true,
      preferExternalSubtitle: false,
    );
    return <String, dynamic>{'loadArgs': jsonEncode(newSource.toMap())};
  }

  /// 原生壳选中 NAS 外挂字幕 → 下载文本落临时文件 → 返回路径，供原生壳 `sub-add`。
  ///
  /// 对齐播放器 `_downloadSubtitleFile`：`downloadSubtitleText(guid)` 取文本，写
  /// `fly_player_sub_<guid>.<ext>`。本地同名字幕（guid 以 `local:` 开头、已在
  /// loadArgs.localSubtitleFiles）由原生壳直接取路径，不走此处。失败返回 null。
  static Future<String?> resolveSubtitleFile(
    NasProvider nas,
    String guid, {
    String? format,
  }) async {
    final normalizedGuid = guid.trim();
    if (normalizedGuid.isEmpty || normalizedGuid.startsWith('local:')) {
      return null;
    }
    try {
      final text = await FeiniuApi(nas).downloadSubtitleText(normalizedGuid);
      if (text.trim().isEmpty) return null;
      final ext = _subtitleExtension(format);
      final safeName = normalizedGuid.replaceAll(
        RegExp(r'[^A-Za-z0-9_-]'),
        '_',
      );
      final filePath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'fly_player_sub_$safeName.$ext';
      final file = File(filePath);
      await file.writeAsString(text, flush: true);
      return file.path;
    } catch (_) {
      // 外挂字幕是旁路能力，下载失败静默（原生壳回退到「无外挂字幕」）。
      return null;
    }
  }

  static String _subtitleExtension(String? format) {
    final normalized = (format ?? '').trim().toLowerCase();
    const supported = <String>{'ass', 'ssa', 'srt', 'vtt', 'sub', 'lrc'};
    if (supported.contains(normalized)) return normalized;
    return 'srt';
  }
}
