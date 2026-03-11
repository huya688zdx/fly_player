import '../api/feiniu_api.dart';
import '../models/playback_stream.dart';
import '../models/stream_track_data.dart';
import '../utils/api_url_helper.dart';
import '../utils/play_detail_track_selector.dart';

class PlayerPlayableSource {
  final String? proxySessionId;
  final String url;
  final Map<String, String> headers;
  final bool reliableSeek;
  final String? seekProbeSummary;

  const PlayerPlayableSource({
    required this.proxySessionId,
    required this.url,
    required this.headers,
    this.reliableSeek = true,
    this.seekProbeSummary,
  });
}

class PlayerInitialPlaybackResult {
  final PlayerPlayableSource playableSource;
  final String mediaGuid;
  final String videoGuid;
  final String? playLink;
  final bool serverPlaybackManaged;

  const PlayerInitialPlaybackResult({
    required this.playableSource,
    required this.mediaGuid,
    required this.videoGuid,
    required this.playLink,
    required this.serverPlaybackManaged,
  });
}

class PlayerSourceSnapshot {
  final String itemGuid;
  final String mediaGuid;
  final String subtitleSourceMediaGuid;
  final String videoGuid;
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
  final bool serverPlaybackManaged;
  final Set<String> serverFallbackSubtitleGuids;

  const PlayerSourceSnapshot({
    required this.itemGuid,
    required this.mediaGuid,
    required this.subtitleSourceMediaGuid,
    required this.videoGuid,
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
    required this.serverPlaybackManaged,
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
  final bool serverPlaybackManaged;
  final String? oldSessionId;
  final String? oldSubtitleSessionId;

  const PlayerServerReloadResult({
    required this.activeProxySessionId,
    required this.activeSubtitleProxySessionId,
    required this.currentPlayLink,
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
    required this.serverPlaybackManaged,
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

  Future<PlayerInitialPlaybackResult> buildInitialPlaybackResult({
    required FeiniuApi api,
    required String directUrl,
    required String mediaGuid,
    required String videoGuid,
    required PlaybackQualityOption? quality,
    required AudioTrackOption? selectedAudio,
    required Duration startPosition,
  }) async {
    final normalizedMediaGuid = mediaGuid.trim();
    final normalizedVideoGuid = videoGuid.trim();
    final selectedQuality = quality;
    final shouldUseServerPlaySession =
        selectedQuality != null && selectedQuality.isDefault != 1;
    if (!shouldUseServerPlaySession) {
      return PlayerInitialPlaybackResult(
        playableSource: await buildPlayableSource(api, directUrl),
        mediaGuid: normalizedMediaGuid,
        videoGuid: normalizedVideoGuid,
        playLink: null,
        serverPlaybackManaged: false,
      );
    }

    final targetMediaGuid = selectedQuality.mediaGuid.trim().isNotEmpty
        ? selectedQuality.mediaGuid.trim()
        : normalizedMediaGuid;
    final targetVideoGuid = selectedQuality.videoGuid.trim().isNotEmpty
        ? selectedQuality.videoGuid.trim()
        : normalizedVideoGuid;
    final startTimestamp = startPosition.inSeconds.clamp(0, 2147483647);
    final session = await api.createServerPlaySession(
      mediaGuid: targetMediaGuid,
      videoGuid: targetVideoGuid,
      audioGuid: selectedAudio?.guid.trim() ?? '',
      subtitleGuid: '',
      videoEncoder: 'hevc',
      resolution: _normalizeServerResolution(selectedQuality.resolution),
      bitrate: selectedQuality.bitrate,
      startTimestamp: startTimestamp,
      audioEncoder: 'aac',
      channels: _serverAudioChannels(selectedAudio),
    );
    final playUrl = _resolvePlayableUrl(api, session.playLink);
    if (playUrl.isEmpty) {
      throw Exception('missing server play link');
    }
    return PlayerInitialPlaybackResult(
      playableSource: await buildPlayableSource(api, playUrl),
      mediaGuid: session.mediaGuid.trim().isNotEmpty
          ? session.mediaGuid.trim()
          : targetMediaGuid,
      videoGuid: session.videoGuid.trim().isNotEmpty
          ? session.videoGuid.trim()
          : targetVideoGuid,
      playLink: session.playLink.trim().isEmpty
          ? null
          : session.playLink.trim(),
      serverPlaybackManaged: true,
    );
  }

  Future<PlayerServerReloadResult> reloadServerPlaySession({
    required FeiniuApi api,
    required PlayerSourceSnapshot snapshot,
    required PlayerServerReloadRequest request,
  }) async {
    final targetMediaGuid = request.quality?.mediaGuid.trim().isNotEmpty == true
        ? request.quality!.mediaGuid.trim()
        : snapshot.mediaGuid;

    var targetAudioTracks = snapshot.audioTracks;
    var targetSubtitleTracks = snapshot.subtitleTracks;
    var targetQualities = snapshot.qualities;
    VideoStreamInfo? targetVideoInfo;
    final subtitleSourceMediaGuid =
        snapshot.subtitleSourceMediaGuid.trim().isNotEmpty
        ? snapshot.subtitleSourceMediaGuid.trim()
        : targetMediaGuid;

    if (request.quality != null || snapshot.serverPlaybackManaged) {
      StreamTrackData? trackData;
      try {
        trackData = await api.getStreamTrackData(snapshot.itemGuid);
      } catch (_) {}

      final playbackStream = await api.getPlaybackStream(targetMediaGuid);
      final subtitlePlaybackStream = subtitleSourceMediaGuid == targetMediaGuid
          ? playbackStream
          : await api.getPlaybackStream(subtitleSourceMediaGuid);
      targetAudioTracks = playbackStream.audioStreams;
      targetSubtitleTracks = PlayDetailTrackSelector.mergeSubtitleTracks(
        primaryTracks: subtitlePlaybackStream.subtitleStreams,
        extraTracks:
            trackData?.subtitlesForMedia(subtitleSourceMediaGuid) ?? const [],
      );
      targetQualities = playbackStream.qualities.isNotEmpty
          ? playbackStream.qualities
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
    final targetVideoGuid = request.quality?.videoGuid.trim().isNotEmpty == true
        ? request.quality!.videoGuid.trim()
        : (targetVideoInfo?.guid.trim().isNotEmpty == true
              ? targetVideoInfo!.guid.trim()
              : snapshot.videoGuid);
    final normalizedResolution = _normalizeServerResolution(
      request.quality?.resolution ??
          targetVideoInfo?.resolutionType ??
          snapshot.resolution,
    );
    final targetBitrate =
        request.quality?.bitrate ?? targetVideoInfo?.bps ?? snapshot.bitrate;
    final startTimestamp = request.startPosition.inSeconds.clamp(0, 2147483647);

    final session = await api.createServerPlaySession(
      mediaGuid: targetMediaGuid,
      videoGuid: targetVideoGuid,
      audioGuid: selectedAudioGuid,
      subtitleGuid: '',
      videoEncoder: 'hevc',
      resolution: normalizedResolution,
      bitrate: targetBitrate,
      startTimestamp: startTimestamp,
      audioEncoder: 'aac',
      channels: _serverAudioChannels(selectedAudioTrack),
    );
    final playUrl = _resolvePlayableUrl(api, session.playLink);
    if (playUrl.isEmpty) {
      throw Exception('missing play link');
    }
    final playableSource = await buildPlayableSource(api, playUrl);

    return PlayerServerReloadResult(
      activeProxySessionId: playableSource.proxySessionId,
      activeSubtitleProxySessionId: null,
      currentPlayLink: session.playLink.trim().isEmpty
          ? null
          : session.playLink.trim(),
      currentUrl: playableSource.url,
      currentHeaders: playableSource.headers,
      reliableSeek: playableSource.reliableSeek,
      seekProbeSummary: playableSource.seekProbeSummary,
      currentMediaGuid: targetMediaGuid,
      currentVideoGuid: session.videoGuid.trim().isNotEmpty
          ? session.videoGuid.trim()
          : targetVideoGuid,
      currentAudioGuid: session.audioGuid.trim(),
      currentSubtitleGuid: selectedSubtitleGuid,
      audioTracks: targetAudioTracks,
      subtitleTracks: targetSubtitleTracks,
      qualities: targetQualities,
      currentVideoWidth: targetVideoInfo?.width ?? snapshot.videoWidth,
      currentVideoHeight: targetVideoInfo?.height ?? snapshot.videoHeight,
      currentResolution: request.quality?.resolution.trim().isNotEmpty == true
          ? request.quality!.resolution.trim()
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
      serverPlaybackManaged: true,
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
    } catch (_) {}
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
    return track.isExternal == 1 || track.extraFile == 1;
  }

  static String resolvePlayableUrl(FeiniuApi api, String pathOrUrl) {
    return _resolvePlayableUrl(api, pathOrUrl);
  }

  static Future<PlayerPlayableSource> buildPlayableSource(
    FeiniuApi api,
    String pathOrUrl,
  ) async {
    final resolvedUrl = _resolvePlayableUrl(api, pathOrUrl);
    if (resolvedUrl.isEmpty) {
      return const PlayerPlayableSource(
        proxySessionId: null,
        url: '',
        headers: <String, String>{},
      );
    }
    final headers = api.buildPlaybackHeadersForUrl(resolvedUrl);
    if (_shouldUseNativeProxy(resolvedUrl)) {
      return PlayerPlayableSource(
        proxySessionId: null,
        url: resolvedUrl,
        headers: headers,
        reliableSeek: true,
        seekProbeSummary: 'native-proxy',
      );
    }
    return PlayerPlayableSource(
      proxySessionId: null,
      url: resolvedUrl,
      headers: headers,
      reliableSeek: true,
      seekProbeSummary: 'direct-local',
    );
  }

  static bool _shouldUseNativeProxy(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    return host != '127.0.0.1' && host != 'localhost';
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
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
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
