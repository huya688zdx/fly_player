import 'dart:convert';

import '../l10n/generated/app_localizations.dart';
import '../media_backend/media_backend.dart';
import '../media_backend/playback/media_playback.dart';
import '../media_backend/playback/media_session_reload.dart';
import '../playback/playback_source.dart';
import 'native_reentry_support.dart';

/// 服务器族（Emby 等）「反向重载桥接器」：原生壳切画质 / 转码态切音轨字幕的反向链路。
///
/// 对位飞牛 [NativeReentrySupport.reloadServerSession]，但不走飞牛私有 reload 内核——
/// 服务器族的 `getPlayback` 一次取数即自足，重载 = 带上「保留项」重新解析 + 桥接器重装配，
/// 再用 `copyWith` 把新播放事实（url / 画质 / 轨道 / 模式）叠回当前 loadArgs，装载态
/// （倍速 / 听视频 / 弹幕开关 / 本地字幕等）与 `episodes` 原样保留，原生原地换源。
///
/// [MediaSessionReloadIntent] 的 `null` 一律表示「保留当前选择」：当前音轨 / 字幕从
/// loadArgs 的 guid 取，当前画质档按 `qualities` 列表对位（列表由后端确定性重建，下标
/// 跨重载稳定）。UI / channel 协议与飞牛完全共用，无 `if (isEmby)`。
class ServerReentrySupport {
  const ServerReentrySupport._();

  static Future<Map<String, dynamic>?> reloadServerSession(
    MediaBackend backend, {
    required String currentLoadArgs,
    required MediaSessionReloadIntent intent,
    required AppLocalizations l10n,
  }) async {
    if (currentLoadArgs.trim().isEmpty) return null;
    final MpvMediaSource source;
    final Map<String, dynamic> raw;
    try {
      raw = (jsonDecode(currentLoadArgs) as Map).map(
        (key, value) => MapEntry(key.toString(), value),
      );
      source = MpvMediaSource.fromMap(raw);
    } catch (_) {
      return null;
    }
    // 切画质任意模式都走这里；「非服务端托管的纯切音轨/字幕」由 mpv 本地切轨，不该来。
    if (intent.qualityIndex == null && !source.playbackMode.isServerManaged) {
      return null;
    }

    // 目标画质档：显式下标（越界忽略）→ 否则定位当前档保持画质不变。
    var qualityIndex = intent.qualityIndex;
    if (qualityIndex != null &&
        (qualityIndex < 0 || qualityIndex >= source.qualities.length)) {
      qualityIndex = null;
    }
    qualityIndex ??= currentQualityIndex(source);

    final startPos = intent.startPosition ?? source.startPosition;

    // 字幕三态：intent 显式关闭 / 显式切轨 → 从其意；否则沿用当前（guid 空串 = 保持关闭，
    // null = 沿用服务端默认）。不能把「保持关闭」折叠成默认，否则切音轨会把字幕切回来。
    final currentSubtitle = source.subtitleTrackGuid;
    final String? subtitleTrackId;
    final bool subtitleDisabled;
    if (intent.subtitleDisabled) {
      subtitleTrackId = null;
      subtitleDisabled = true;
    } else if (intent.subtitleTrackId != null) {
      subtitleTrackId = intent.subtitleTrackId;
      subtitleDisabled = false;
    } else if (currentSubtitle == null) {
      subtitleTrackId = null;
      subtitleDisabled = false;
    } else if (currentSubtitle.trim().isEmpty) {
      subtitleTrackId = null;
      subtitleDisabled = true;
    } else {
      subtitleTrackId = currentSubtitle;
      subtitleDisabled = false;
    }
    final currentAudio = source.audioTrackGuid?.trim() ?? '';
    final intentAudio = intent.audioTrackId?.trim() ?? '';
    final audioTrackId = intentAudio.isNotEmpty
        ? intentAudio
        : (currentAudio.isNotEmpty ? currentAudio : null);

    final request = MediaPlaybackRequest(
      itemId: source.itemGuid,
      fallbackTitle: source.title,
      resumePosition: startPos,
      qualityIndex: qualityIndex,
      // 版本锚：裸 MediaSource 版本 id，只锁定当前版本、不参与画质选档（后端约定）。
      qualityId: source.mediaGuid,
      audioTrackId: audioTrackId,
      subtitleTrackId: subtitleTrackId,
      subtitleTrackExplicitlyDisabled: subtitleDisabled,
      seriesId: source.seriesGuid,
      // 下标定位失败的兜底：按当前分辨率字符串继承，避免静默跳回默认档。
      preferredQualityResolution: qualityIndex == null ? source.resolution : '',
    );

    final MpvMediaSource assembled;
    try {
      final resolution = await backend.getPlayback(request);
      final result = await backend.playbackSourceBridge.assemblePlaybackSource(
        request: request,
        bundle: resolution.bundle,
        context: resolution.backendContext,
        l10n: l10n,
      );
      assembled = result.source;
    } catch (_) {
      return null;
    }

    // 起播位取意图/当前位（不是 bundle 续播对账结果——重载须精确停留在当前进度）。
    final resolvedStart = (!assembled.reliableSeek && startPos > Duration.zero)
        ? Duration.zero
        : startPos;
    final newSource = source.copyWith(
      loadNonce: assembled.loadNonce,
      url: assembled.url,
      headers: assembled.headers,
      mediaGuid: assembled.mediaGuid,
      videoGuid: assembled.videoGuid,
      videoWidth: assembled.videoWidth,
      videoHeight: assembled.videoHeight,
      resolution: assembled.resolution,
      bitrate: assembled.bitrate,
      videoCodecName: assembled.videoCodecName,
      videoProfile: assembled.videoProfile,
      colorSpace: assembled.colorSpace,
      colorTransfer: assembled.colorTransfer,
      colorPrimaries: assembled.colorPrimaries,
      bitDepth: assembled.bitDepth,
      playbackMode: assembled.playbackMode,
      qualities: assembled.qualities,
      audioTracks: assembled.audioTracks,
      subtitleTracks: assembled.subtitleTracks,
      // 轨道三态逐位对齐装配结果（转码档 aid/sid 恒空：音轨烧录、字幕走外挂 sub-add）。
      audioTrackIndex: assembled.audioTrackIndex,
      clearAudioTrackIndex: assembled.audioTrackIndex == null,
      subtitleTrackIndex: assembled.subtitleTrackIndex,
      clearSubtitleTrackIndex: assembled.subtitleTrackIndex == null,
      audioTrackGuid: assembled.audioTrackGuid,
      clearAudioTrackGuid: assembled.audioTrackGuid == null,
      // 空串（显式关闭）原样保留，null 才清——折叠会丢「保持关闭」语义。
      subtitleTrackGuid: assembled.subtitleTrackGuid,
      clearSubtitleTrackGuid: assembled.subtitleTrackGuid == null,
      preferExternalSubtitle: assembled.preferExternalSubtitle,
      reliableSeek: assembled.reliableSeek,
      startPosition: resolvedStart,
    );
    final newArgs = NativeReentrySupport.preserveEpisodesForServerReload(
      raw,
      newSource.toMap(),
    );
    return <String, dynamic>{'loadArgs': jsonEncode(newArgs)};
  }

  /// 纯切音轨/字幕（转码态）时定位「当前画质档」在候选列表中的下标，保持画质不变。
  ///
  /// 原画态取原画档下标；转码态按 分辨率+码率 精确对位，码率缺失退分辨率首档。
  /// 找不到返回 null（由 preferredQualityResolution 兜底）。纯函数，便于单测。
  static int? currentQualityIndex(MpvMediaSource source) {
    final qualities = source.qualities;
    if (qualities.isEmpty) return null;
    if (!source.playbackMode.isServerManaged) {
      final index = qualities.indexWhere((q) => q.isOriginalProxy);
      return index < 0 ? null : index;
    }
    final res = source.resolution.trim();
    var fallback = -1;
    for (var i = 0; i < qualities.length; i++) {
      final quality = qualities[i];
      if (!quality.isServerSession) continue;
      if (quality.resolution.trim() != res) continue;
      if (source.bitrate > 0 && quality.bitrate == source.bitrate) return i;
      if (fallback < 0) fallback = i;
    }
    return fallback < 0 ? null : fallback;
  }
}
