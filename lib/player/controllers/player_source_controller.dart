import 'dart:async';
import 'dart:io';

import '../../api/feiniu_api.dart';
import '../../models/playback_stream.dart';
import '../../models/stream_track_data.dart';
import '../../services/app_log_service.dart';
import '../../utils/api_url_helper.dart';
import '../../utils/app_error_reporter.dart';
import '../../utils/app_exception.dart';
import '../../utils/play_detail_track_selector.dart';

enum PlayerPlaybackMode {
  originalQuality,
  directLinkQuality,
  serverSession;

  bool get isDirect => this != PlayerPlaybackMode.serverSession;

  bool get isOriginalQuality => this == PlayerPlaybackMode.originalQuality;

  bool get isDirectLink => this == PlayerPlaybackMode.directLinkQuality;

  bool get isServerManaged => this == PlayerPlaybackMode.serverSession;
}

class PlayerPlayableSource {
  final String? proxySessionId;
  final String url;
  final Map<String, String> headers;
  final bool forceNativeProxy;
  final bool reliableSeek;
  final String? seekProbeSummary;

  const PlayerPlayableSource({
    required this.proxySessionId,
    required this.url,
    required this.headers,
    this.forceNativeProxy = false,
    this.reliableSeek = true,
    this.seekProbeSummary,
  });
}

class PlayerInitialPlaybackResult {
  final PlayerPlayableSource playableSource;
  final String mediaGuid;
  final String videoGuid;
  final String? playLink;
  final int serverSessionHlsTimeSeconds;
  final PlayerPlaybackMode playbackMode;

  const PlayerInitialPlaybackResult({
    required this.playableSource,
    required this.mediaGuid,
    required this.videoGuid,
    required this.playLink,
    required this.serverSessionHlsTimeSeconds,
    required this.playbackMode,
  });
}

class PlayerSourceSnapshot {
  final String itemGuid;
  final String mediaGuid;
  final String subtitleSourceMediaGuid;
  final String videoGuid;
  final int? directLinkQualityIndex;
  final String? audioGuid;
  final String? subtitleGuid;
  final String resolution;
  final int bitrate;
  final int videoWidth;
  final int videoHeight;
  final Map<String, String> currentHeaders;
  final String? activeProxySessionId;
  final String? activeSubtitleProxySessionId;
  final List<AudioTrackOption> audioTracks;
  final List<SubtitleTrackOption> subtitleTracks;
  final List<PlaybackQualityOption> qualities;
  final PlayerPlaybackMode playbackMode;
  final Set<String> serverFallbackSubtitleGuids;

  const PlayerSourceSnapshot({
    required this.itemGuid,
    required this.mediaGuid,
    required this.subtitleSourceMediaGuid,
    required this.videoGuid,
    required this.directLinkQualityIndex,
    required this.audioGuid,
    required this.subtitleGuid,
    required this.resolution,
    required this.bitrate,
    required this.videoWidth,
    required this.videoHeight,
    required this.currentHeaders,
    required this.activeProxySessionId,
    required this.activeSubtitleProxySessionId,
    required this.audioTracks,
    required this.subtitleTracks,
    required this.qualities,
    required this.playbackMode,
    required this.serverFallbackSubtitleGuids,
  });
}

class PlayerServerReloadRequest {
  final String? audioGuid;
  final String? subtitleGuid;
  final PlaybackQualityOption? quality;
  final Duration startPosition;

  const PlayerServerReloadRequest({
    this.audioGuid,
    this.subtitleGuid,
    this.quality,
    required this.startPosition,
  });
}

class PlayerServerReloadResult {
  final String? activeProxySessionId;
  final String? activeSubtitleProxySessionId;
  final String? currentPlayLink;
  final int currentServerSessionHlsTimeSeconds;
  final String currentUrl;
  final Map<String, String> currentHeaders;
  final bool reliableSeek;
  final String? seekProbeSummary;
  final String currentMediaGuid;
  final String currentVideoGuid;
  final String? currentAudioGuid;
  final String? currentSubtitleGuid;
  final List<AudioTrackOption> audioTracks;
  final List<SubtitleTrackOption> subtitleTracks;
  final List<PlaybackQualityOption> qualities;
  final int currentVideoWidth;
  final int currentVideoHeight;
  final String currentResolution;
  final int currentBitrate;
  final String currentVideoCodecName;
  final String currentVideoProfile;
  final String currentColorSpace;
  final String currentColorTransfer;
  final String currentColorPrimaries;
  final int currentBitDepth;
  final bool pendingSubtitleSelectionRefresh;
  final PlayerPlaybackMode playbackMode;
  final String? oldSessionId;
  final String? oldSubtitleSessionId;

  const PlayerServerReloadResult({
    required this.activeProxySessionId,
    required this.activeSubtitleProxySessionId,
    required this.currentPlayLink,
    required this.currentServerSessionHlsTimeSeconds,
    required this.currentUrl,
    required this.currentHeaders,
    required this.reliableSeek,
    required this.seekProbeSummary,
    required this.currentMediaGuid,
    required this.currentVideoGuid,
    required this.currentAudioGuid,
    required this.currentSubtitleGuid,
    required this.audioTracks,
    required this.subtitleTracks,
    required this.qualities,
    required this.currentVideoWidth,
    required this.currentVideoHeight,
    required this.currentResolution,
    required this.currentBitrate,
    required this.currentVideoCodecName,
    required this.currentVideoProfile,
    required this.currentColorSpace,
    required this.currentColorTransfer,
    required this.currentColorPrimaries,
    required this.currentBitDepth,
    required this.pendingSubtitleSelectionRefresh,
    required this.playbackMode,
    required this.oldSessionId,
    required this.oldSubtitleSessionId,
  });
}

class PlayerSubtitleRefreshResult {
  final List<SubtitleTrackOption> subtitleTracks;
  final String? selectedGuid;
  final SubtitleTrackOption? selectedTrack;

  const PlayerSubtitleRefreshResult({
    required this.subtitleTracks,
    required this.selectedGuid,
    required this.selectedTrack,
  });
}

class PlayerSourceController {
  const PlayerSourceController();

  static bool _subtitleShouldPreferEmbeddedTrack(SubtitleTrackOption? track) {
    if (track == null) return false;
    final normalizedGuid = track.guid.trim().toLowerCase();
    if (normalizedGuid.startsWith('local:')) return false;
    if (track.isExternal == 1 || track.extraFile == 1) return false;
    if (track.isBitmap == 1) return true;
    final format = track.format.trim().toLowerCase();
    final codec = track.codecName.trim().toLowerCase();
    return format.contains('pgs') ||
        format.contains('sup') ||
        codec.contains('pgs') ||
        codec.contains('sup') ||
        codec.contains('hdmv_pgs') ||
        codec.contains('dvd_subtitle') ||
        codec.contains('vobsub');
  }

  static PlayerPlaybackMode playbackModeForQuality(
    PlaybackQualityOption? quality,
  ) {
    if (quality == null || quality.isOriginalProxy) {
      return PlayerPlaybackMode.originalQuality;
    }
    if (quality.isDirectLink) {
      return PlayerPlaybackMode.directLinkQuality;
    }
    return PlayerPlaybackMode.serverSession;
  }

  Future<PlayerInitialPlaybackResult> buildInitialPlaybackResult({
    required FeiniuApi api,
    required String directUrl,
    required String mediaGuid,
    required String videoGuid,
    required PlaybackStreamData playbackStream,
    required PlaybackQualityOption? quality,
    required AudioTrackOption? selectedAudio,
    required SubtitleTrackOption? selectedSubtitle,
    required Duration startPosition,
  }) async {
    final normalizedMediaGuid = mediaGuid.trim();
    final normalizedVideoGuid = videoGuid.trim();
    final selectedQuality = quality;
    final targetMediaGuid = selectedQuality?.mediaGuid.trim().isNotEmpty == true
        ? selectedQuality!.mediaGuid.trim()
        : normalizedMediaGuid;
    final targetVideoGuid = selectedQuality?.videoGuid.trim().isNotEmpty == true
        ? selectedQuality!.videoGuid.trim()
        : normalizedVideoGuid;
    if (selectedQuality == null || selectedQuality.isOriginalProxy) {
      return PlayerInitialPlaybackResult(
        playableSource: await buildPlayableSource(api, directUrl),
        mediaGuid: normalizedMediaGuid,
        videoGuid: normalizedVideoGuid,
        playLink: null,
        serverSessionHlsTimeSeconds: 0,
        playbackMode: PlayerPlaybackMode.originalQuality,
      );
    }

    if (selectedQuality.isDirectLink) {
      final directLinkQualityIndex = selectedQuality.directLinkQualityIndex;
      final directLinkTarget = playbackStream.buildDirectLinkTarget(
        directLinkQualityIndex,
      );
      final playUrl =
          directLinkTarget?.url ??
          api.getStreamUrl(
            targetMediaGuid,
            directLinkQualityIndex: directLinkQualityIndex,
          );
      return PlayerInitialPlaybackResult(
        playableSource: await buildPlayableSource(
          api,
          playUrl,
          headersOverride: directLinkTarget?.headers,
          forceNativeProxy: directLinkTarget?.forceNativeProxy ?? false,
          seekProbeSummary:
              directLinkTarget?.debugSummary ??
              (directLinkQualityIndex == null
                  ? 'direct'
                  : 'direct-link-quality'),
        ),
        mediaGuid: targetMediaGuid,
        videoGuid: targetVideoGuid,
        playLink: null,
        serverSessionHlsTimeSeconds: 0,
        playbackMode: PlayerPlaybackMode.directLinkQuality,
      );
    }

    final startTimestamp = startPosition.inSeconds.clamp(0, 2147483647);
    final selectedServerSubtitleGuid =
        subtitleShouldUseExternalFile(selectedSubtitle, const <String>{})
        ? ''
        : (selectedSubtitle?.guid.trim() ?? '');
    final session = await api.createServerPlaySession(
      mediaGuid: targetMediaGuid,
      videoGuid: targetVideoGuid,
      audioGuid: selectedAudio?.guid.trim() ?? '',
      subtitleGuid: selectedServerSubtitleGuid,
      videoEncoder: 'hevc',
      resolution: _normalizeServerResolution(selectedQuality.resolution),
      bitrate: selectedQuality.bitrate,
      startTimestamp: startTimestamp,
      audioEncoder: 'aac',
      channels: _serverAudioChannels(selectedAudio),
    );
    final playUrl = _resolvePlayableUrl(api, session.playLink);
    if (playUrl.isEmpty) {
      throw const AppException(
        kind: AppExceptionKind.fatal,
        action: 'create server play session',
        message: 'missing server play link',
      );
    }
    return PlayerInitialPlaybackResult(
      playableSource: await buildPlayableSource(api, playUrl),
      mediaGuid: targetMediaGuid,
      videoGuid: targetVideoGuid,
      playLink: session.playLink.trim().isEmpty
          ? null
          : session.playLink.trim(),
      serverSessionHlsTimeSeconds: session.hlsTime,
      playbackMode: PlayerPlaybackMode.serverSession,
    );
  }

  Future<PlayerServerReloadResult> reloadServerPlaySession({
    required FeiniuApi api,
    required PlayerSourceSnapshot snapshot,
    required PlayerServerReloadRequest request,
  }) async {
    final selectedQuality = request.quality;
    final preserveCurrentServerManagedVideoState =
        selectedQuality == null && snapshot.playbackMode.isServerManaged;
    final targetMediaGuid = selectedQuality?.mediaGuid.trim().isNotEmpty == true
        ? request.quality!.mediaGuid.trim()
        : snapshot.mediaGuid;

    var targetAudioTracks = snapshot.audioTracks;
    var targetSubtitleTracks = snapshot.subtitleTracks;
    var targetQualities = snapshot.qualities;
    PlaybackStreamData? targetPlaybackStream;
    VideoStreamInfo? targetVideoInfo;
    final subtitleSourceMediaGuid =
        snapshot.subtitleSourceMediaGuid.trim().isNotEmpty
        ? snapshot.subtitleSourceMediaGuid.trim()
        : targetMediaGuid;

    if (selectedQuality != null || snapshot.playbackMode.isServerManaged) {
      StreamTrackData? trackData;
      try {
        trackData = await api.getStreamTrackData(snapshot.itemGuid);
      } catch (error, stackTrace) {
        unawaited(
          AppErrorReporter.report(
            error,
            action: 'load stream track data',
            source: 'player_source_controller',
            stackTrace: stackTrace,
            fallbackKind: AppExceptionKind.noData,
            level: AppLogLevel.warning,
            details: 'itemGuid=${snapshot.itemGuid}',
          ),
        );
      }

      final playbackStream = await api.getPlaybackStream(targetMediaGuid);
      targetPlaybackStream = playbackStream;
      final subtitlePlaybackStream = subtitleSourceMediaGuid == targetMediaGuid
          ? playbackStream
          : await api.getPlaybackStream(subtitleSourceMediaGuid);
      targetAudioTracks = playbackStream.audioStreams;
      targetSubtitleTracks = PlayDetailTrackSelector.mergeSubtitleTracks(
        primaryTracks: subtitlePlaybackStream.subtitleStreams,
        extraTracks:
            trackData?.subtitlesForMedia(subtitleSourceMediaGuid) ?? const [],
      );
      final mergedQualities = mergePlaybackQualitiesWithStreamTrackData(
        playbackStream.qualities,
        trackData,
      );
      targetQualities = mergedQualities.isNotEmpty
          ? mergedQualities
          : snapshot.qualities;
      targetVideoInfo = playbackStream.videoStream;
    }

    final selectedAudioGuid =
        _pickAudioGuid(
          preferredGuid: request.audioGuid ?? snapshot.audioGuid,
          tracks: targetAudioTracks,
        ) ??
        '';
    final selectedAudioTrack = _audioTrackByGuid(
      selectedAudioGuid,
      targetAudioTracks,
    );
    final preferredSubtitleGuid =
        (request.subtitleGuid ?? snapshot.subtitleGuid ?? '').trim();
    final selectedSubtitleGuid = preferredSubtitleGuid.isEmpty
        ? ''
        : (_pickSubtitleGuid(
                preferredGuid: preferredSubtitleGuid,
                tracks: targetSubtitleTracks,
              ) ??
              '');
    final selectedSubtitleTrack = _subtitleTrackByGuid(
      selectedSubtitleGuid,
      targetSubtitleTracks,
    );
    final targetVideoGuid = selectedQuality?.videoGuid.trim().isNotEmpty == true
        ? request.quality!.videoGuid.trim()
        : preserveCurrentServerManagedVideoState &&
              snapshot.videoGuid.trim().isNotEmpty
        ? snapshot.videoGuid.trim()
        : (targetVideoInfo?.guid.trim().isNotEmpty == true
              ? targetVideoInfo!.guid.trim()
              : snapshot.videoGuid);
    if (selectedQuality != null && selectedQuality.isDirectLink) {
      final directLinkQualityIndex = selectedQuality.directLinkQualityIndex;
      final directLinkTarget = targetPlaybackStream?.buildDirectLinkTarget(
        directLinkQualityIndex,
      );
      final playUrl =
          directLinkTarget?.url ??
          api.getStreamUrl(
            targetMediaGuid,
            directLinkQualityIndex: directLinkQualityIndex,
          );
      final playableSource = await buildPlayableSource(
        api,
        playUrl,
        headersOverride: directLinkTarget?.headers,
        forceNativeProxy: directLinkTarget?.forceNativeProxy ?? false,
        seekProbeSummary:
            directLinkTarget?.debugSummary ??
            (directLinkQualityIndex == null ? 'direct' : 'direct-link-quality'),
      );
      return PlayerServerReloadResult(
        activeProxySessionId: playableSource.proxySessionId,
        activeSubtitleProxySessionId: null,
        currentPlayLink: null,
        currentServerSessionHlsTimeSeconds: 0,
        currentUrl: playableSource.url,
        currentHeaders: playableSource.headers,
        reliableSeek: playableSource.reliableSeek,
        seekProbeSummary: playableSource.seekProbeSummary,
        currentMediaGuid: targetMediaGuid,
        currentVideoGuid: targetVideoGuid,
        currentAudioGuid: selectedAudioGuid,
        currentSubtitleGuid: selectedSubtitleGuid,
        audioTracks: targetAudioTracks,
        subtitleTracks: targetSubtitleTracks,
        qualities: targetQualities,
        currentVideoWidth: targetVideoInfo?.width ?? snapshot.videoWidth,
        currentVideoHeight: targetVideoInfo?.height ?? snapshot.videoHeight,
        currentResolution: selectedQuality.resolution.trim().isNotEmpty
            ? selectedQuality.resolution.trim()
            : (targetVideoInfo?.resolutionType.trim().isNotEmpty == true
                  ? targetVideoInfo!.resolutionType.trim()
                  : snapshot.resolution),
        currentBitrate: selectedQuality.bitrate > 0
            ? selectedQuality.bitrate
            : (targetVideoInfo?.bps ?? snapshot.bitrate),
        currentVideoCodecName: targetVideoInfo?.codecName ?? '',
        currentVideoProfile: targetVideoInfo?.profile ?? '',
        currentColorSpace: targetVideoInfo?.colorSpace ?? '',
        currentColorTransfer: targetVideoInfo?.colorTransfer ?? '',
        currentColorPrimaries: targetVideoInfo?.colorPrimaries ?? '',
        currentBitDepth: targetVideoInfo?.bitDepth ?? 0,
        pendingSubtitleSelectionRefresh: subtitleShouldUseExternalFile(
          selectedSubtitleTrack,
          snapshot.serverFallbackSubtitleGuids,
        ),
        playbackMode: PlayerPlaybackMode.directLinkQuality,
        oldSessionId: snapshot.activeProxySessionId,
        oldSubtitleSessionId: snapshot.activeSubtitleProxySessionId,
      );
    }
    final normalizedResolution = _normalizeServerResolution(
      request.quality?.resolution ??
          (preserveCurrentServerManagedVideoState ? snapshot.resolution : null) ??
          targetVideoInfo?.resolutionType ??
          snapshot.resolution,
    );
    final targetBitrate = request.quality?.bitrate ??
        (preserveCurrentServerManagedVideoState ? snapshot.bitrate : null) ??
        targetVideoInfo?.bps ??
        snapshot.bitrate;
    final startTimestamp = request.startPosition.inSeconds.clamp(0, 2147483647);
    final selectedServerSubtitleGuid =
        subtitleShouldUseExternalFile(
          selectedSubtitleTrack,
          snapshot.serverFallbackSubtitleGuids,
        )
        ? ''
        : selectedSubtitleGuid;

    final session = await api.createServerPlaySession(
      mediaGuid: targetMediaGuid,
      videoGuid: targetVideoGuid,
      audioGuid: selectedAudioGuid,
      subtitleGuid: selectedServerSubtitleGuid,
      videoEncoder: 'hevc',
      resolution: normalizedResolution,
      bitrate: targetBitrate,
      startTimestamp: startTimestamp,
      audioEncoder: 'aac',
      channels: _serverAudioChannels(selectedAudioTrack),
    );
    final playUrl = _resolvePlayableUrl(api, session.playLink);
    if (playUrl.isEmpty) {
      throw const AppException(
        kind: AppExceptionKind.fatal,
        action: 'reload server play session',
        message: 'missing play link',
      );
    }
    final playableSource = await buildPlayableSource(api, playUrl);

    return PlayerServerReloadResult(
      activeProxySessionId: playableSource.proxySessionId,
      activeSubtitleProxySessionId: null,
      currentPlayLink: session.playLink.trim().isEmpty
          ? null
          : session.playLink.trim(),
      currentServerSessionHlsTimeSeconds: session.hlsTime,
      currentUrl: playableSource.url,
      currentHeaders: playableSource.headers,
      reliableSeek: playableSource.reliableSeek,
      seekProbeSummary: playableSource.seekProbeSummary,
      currentMediaGuid: targetMediaGuid,
      currentVideoGuid: targetVideoGuid,
      currentAudioGuid: session.audioGuid.trim(),
      currentSubtitleGuid: selectedSubtitleGuid,
      audioTracks: targetAudioTracks,
      subtitleTracks: targetSubtitleTracks,
      qualities: targetQualities,
      currentVideoWidth: preserveCurrentServerManagedVideoState
          ? snapshot.videoWidth
          : (targetVideoInfo?.width ?? snapshot.videoWidth),
      currentVideoHeight: preserveCurrentServerManagedVideoState
          ? snapshot.videoHeight
          : (targetVideoInfo?.height ?? snapshot.videoHeight),
      currentResolution: request.quality?.resolution.trim().isNotEmpty == true
          ? request.quality!.resolution.trim()
          : preserveCurrentServerManagedVideoState
          ? snapshot.resolution
          : (targetVideoInfo?.resolutionType.trim().isNotEmpty == true
                ? targetVideoInfo!.resolutionType.trim()
                : snapshot.resolution),
      currentBitrate: targetBitrate,
      currentVideoCodecName: targetVideoInfo?.codecName ?? '',
      currentVideoProfile: targetVideoInfo?.profile ?? '',
      currentColorSpace: targetVideoInfo?.colorSpace ?? '',
      currentColorTransfer: targetVideoInfo?.colorTransfer ?? '',
      currentColorPrimaries: targetVideoInfo?.colorPrimaries ?? '',
      currentBitDepth: targetVideoInfo?.bitDepth ?? 0,
      pendingSubtitleSelectionRefresh: subtitleShouldUseExternalFile(
        selectedSubtitleTrack,
        snapshot.serverFallbackSubtitleGuids,
      ),
      playbackMode: PlayerPlaybackMode.serverSession,
      oldSessionId: snapshot.activeProxySessionId,
      oldSubtitleSessionId: snapshot.activeSubtitleProxySessionId,
    );
  }

  Future<PlayerSubtitleRefreshResult> refreshSubtitleTracksFromSource({
    required FeiniuApi api,
    required PlayerSourceSnapshot snapshot,
    String? preferredGuid,
  }) async {
    final sourceMediaGuid = snapshot.subtitleSourceMediaGuid.trim().isNotEmpty
        ? snapshot.subtitleSourceMediaGuid.trim()
        : snapshot.mediaGuid;
    StreamTrackData? trackData;
    try {
      trackData = await api.getStreamTrackData(snapshot.itemGuid);
    } catch (error, stackTrace) {
      unawaited(
        AppErrorReporter.report(
          error,
          action: 'refresh subtitle tracks',
          source: 'player_source_controller',
          stackTrace: stackTrace,
          fallbackKind: AppExceptionKind.noData,
          level: AppLogLevel.warning,
          details: 'itemGuid=${snapshot.itemGuid}',
        ),
      );
    }
    final playbackStream = await api.getPlaybackStream(sourceMediaGuid);
    final mergedSubtitleTracks = PlayDetailTrackSelector.mergeSubtitleTracks(
      primaryTracks: playbackStream.subtitleStreams,
      extraTracks: trackData?.subtitlesForMedia(sourceMediaGuid) ?? const [],
    );
    final selectedGuid = _pickSubtitleGuid(
      preferredGuid: preferredGuid ?? snapshot.subtitleGuid,
      tracks: mergedSubtitleTracks,
    );
    return PlayerSubtitleRefreshResult(
      subtitleTracks: mergedSubtitleTracks,
      selectedGuid: selectedGuid,
      selectedTrack: _subtitleTrackByGuid(selectedGuid, mergedSubtitleTracks),
    );
  }

  static bool subtitleShouldUseExternalFile(
    SubtitleTrackOption? track,
    Set<String> serverFallbackSubtitleGuids,
  ) {
    if (track == null) return false;
    if (serverFallbackSubtitleGuids.contains(track.guid)) return false;
    if (_subtitleShouldPreferEmbeddedTrack(track)) return false;
    return track.isExternal == 1 || track.extraFile == 1;
  }

  static String resolvePlayableUrl(FeiniuApi api, String pathOrUrl) {
    return _resolvePlayableUrl(api, pathOrUrl);
  }

  static PlaybackQualityOption? preferredInitialQuality(
    List<PlaybackQualityOption> qualities, {
    bool preferConservativeDirectLink = false,
  }) {
    if (preferConservativeDirectLink) {
      final conservative = _lowestDirectLinkQuality(qualities);
      if (conservative != null) return conservative;
    }
    for (final quality in qualities) {
      if (quality.isDirectLink && quality.isDefault == 1) {
        return quality;
      }
    }
    for (final quality in qualities) {
      if (quality.isDirectLink) return quality;
    }
    for (final quality in qualities) {
      if (quality.isOriginalProxy) return quality;
    }
    for (final quality in qualities) {
      if (quality.isDefault == 1) return quality;
    }
    return qualities.isNotEmpty ? qualities.first : null;
  }

  static bool shouldPreferConservativeDirectLink(String baseUrl) {
    final normalized = ApiUrlHelper.normalizeBaseUrl(baseUrl);
    final uri = Uri.tryParse(normalized);
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;
    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty || host == '127.0.0.1' || host == 'localhost') {
      return false;
    }
    final address = InternetAddress.tryParse(host);
    if (address == null) {
      return true;
    }
    if (address.type == InternetAddressType.IPv6) {
      if (address.isLoopback || address.isLinkLocal) return false;
      final raw = address.rawAddress;
      final firstByte = raw.isNotEmpty ? raw.first : 0;
      return (firstByte & 0xfe) != 0xfc;
    }
    return !(_isPrivateIpv4Address(address) ||
        address.isLoopback ||
        address.isLinkLocal);
  }

  static Future<PlayerPlayableSource> buildPlayableSource(
    FeiniuApi api,
    String pathOrUrl, {
    Map<String, String>? headersOverride,
    bool forceNativeProxy = false,
    String? seekProbeSummary,
  }) async {
    final resolvedUrl = _resolvePlayableUrl(api, pathOrUrl);
    if (resolvedUrl.isEmpty) {
      return const PlayerPlayableSource(
        proxySessionId: null,
        url: '',
        headers: <String, String>{},
      );
    }
    final headers =
        headersOverride ??
        api.buildPlaybackHeadersForUrl(
          resolvedUrl,
          includeInitialRangeHeader: false,
        );
    if (forceNativeProxy) {
      return PlayerPlayableSource(
        proxySessionId: null,
        url: resolvedUrl,
        headers: headers,
        forceNativeProxy: true,
        reliableSeek: true,
        seekProbeSummary: seekProbeSummary ?? 'direct-remote-proxy',
      );
    }
    return PlayerPlayableSource(
      proxySessionId: null,
      url: resolvedUrl,
      headers: headers,
      forceNativeProxy: false,
      reliableSeek: true,
      seekProbeSummary: seekProbeSummary ?? 'direct-local',
    );
  }

  static PlaybackQualityOption? _lowestDirectLinkQuality(
    List<PlaybackQualityOption> qualities,
  ) {
    final directLinkQualities = qualities.where(
      (quality) => quality.isDirectLink,
    );
    PlaybackQualityOption? best;
    for (final quality in directLinkQualities) {
      if (best == null) {
        best = quality;
        continue;
      }
      final qualityScore = _qualitySortScore(quality);
      final bestScore = _qualitySortScore(best);
      if (qualityScore < bestScore) {
        best = quality;
      }
    }
    return best;
  }

  static int _qualitySortScore(PlaybackQualityOption quality) {
    final bitrateScore = quality.bitrate > 0 ? quality.bitrate : 1 << 30;
    final resolutionText = quality.resolution.toLowerCase().trim();
    final resolutionMatch = RegExp(r'(\d{3,4})').firstMatch(resolutionText);
    final resolutionScore =
        int.tryParse(resolutionMatch?.group(1) ?? '') ?? 1 << 20;
    return resolutionScore * 100000000 + bitrateScore;
  }

  static bool _isPrivateIpv4Address(InternetAddress address) {
    if (address.type != InternetAddressType.IPv4) return false;
    final raw = address.rawAddress;
    if (raw.length < 2) return false;
    final first = raw[0];
    final second = raw[1];
    return first == 10 ||
        first == 127 ||
        (first == 192 && second == 168) ||
        (first == 172 && second >= 16 && second <= 31);
  }

  static SubtitleTrackOption? subtitleTrackByGuid(
    String? guid,
    List<SubtitleTrackOption> tracks,
  ) {
    return _subtitleTrackByGuid(guid, tracks);
  }

  static String qualitySwitchMessageFor(PlaybackQualityOption quality) {
    final title = quality.resolution.trim().isNotEmpty
        ? quality.resolution.trim()
        : (quality.isDefault == 1 ? '原画' : '清晰度');
    final bitrate = quality.bitrate > 0
        ? ' ${(quality.bitrate / 1000000).toStringAsFixed(0)} Mbps'
        : '';
    return '正在为您切换至$title$bitrate 画质，请稍等...';
  }

  static String _resolvePlayableUrl(FeiniuApi api, String pathOrUrl) {
    final raw = pathOrUrl.trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') ||
        raw.startsWith('https://') ||
        raw.startsWith('file://')) {
      return raw;
    }
    if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(raw)) {
      return Uri.file(raw, windows: Platform.isWindows).toString();
    }
    if (raw.startsWith('/')) {
      final looksLikeLocalFilePath =
          raw.startsWith('/storage/') ||
          raw.startsWith('/sdcard/') ||
          raw.startsWith('/mnt/') ||
          raw.startsWith('/data/') ||
          raw.startsWith('/system/');
      if (looksLikeLocalFilePath) {
        return Uri.file(raw, windows: Platform.isWindows).toString();
      }
      return ApiUrlHelper.apiUrl(api.nasProvider.baseUrl, raw);
    }
    return ApiUrlHelper.apiUrl(api.nasProvider.baseUrl, raw);
  }

  static String? _pickAudioGuid({
    required String? preferredGuid,
    required List<AudioTrackOption> tracks,
  }) {
    final normalized = preferredGuid?.trim() ?? '';
    if (normalized.isNotEmpty) {
      for (final track in tracks) {
        if (track.guid == normalized) return normalized;
      }
    }
    for (final track in tracks) {
      if (track.isDefaultOption) return track.guid;
    }
    return tracks.isNotEmpty ? tracks.first.guid : null;
  }

  static String? _pickSubtitleGuid({
    required String? preferredGuid,
    required List<SubtitleTrackOption> tracks,
  }) {
    final normalized = preferredGuid?.trim() ?? '';
    if (normalized.isEmpty) return '';
    for (final track in tracks) {
      if (track.guid == normalized) return normalized;
    }
    for (final track in tracks) {
      if (track.isDefaultOption) return track.guid;
    }
    return tracks.isNotEmpty ? tracks.first.guid : '';
  }

  static AudioTrackOption? _audioTrackByGuid(
    String? guid,
    List<AudioTrackOption> tracks,
  ) {
    final normalized = guid?.trim() ?? '';
    if (normalized.isEmpty) return null;
    for (final track in tracks) {
      if (track.guid == normalized) return track;
    }
    return null;
  }

  static SubtitleTrackOption? _subtitleTrackByGuid(
    String? guid,
    List<SubtitleTrackOption> tracks,
  ) {
    final normalized = guid?.trim() ?? '';
    if (normalized.isEmpty) return null;
    for (final track in tracks) {
      if (track.guid == normalized) return track;
    }
    return null;
  }

  static int _serverAudioChannels(AudioTrackOption? track) {
    final channels = track?.channels ?? 0;
    if (channels <= 0) return 2;
    if (channels == 1) return 1;
    return 2;
  }

  static String _normalizeServerResolution(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return '';
    final match = RegExp(r'(\d{3,4})').firstMatch(normalized);
    if (match != null) {
      return match.group(1) ?? normalized;
    }
    return normalized;
  }
}
