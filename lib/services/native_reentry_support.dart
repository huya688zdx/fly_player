import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../api/feiniu_api.dart';
import '../player/controllers/mpv_player_controller.dart';
import '../player/controllers/player_source_controller.dart';
import '../providers/nas_provider.dart';
import '../utils/app_exception.dart';
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
