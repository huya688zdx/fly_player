part of '../../mpv_player_page.dart';

extension _MpvPlayerSourceMixin on _MpvPlayerPageState {
  String _preferredVideoOutputBackend(String requestedBackend) {
    if (Platform.isAndroid &&
        _useNativeDanmakuRenderer &&
        _danmakuController.settings.enabled &&
        _danmakuController.settings.avoidCenterArea) {
      // Prefer the async capture path only while native danmaku center
      // occlusion is actively in use. Otherwise keep the default texture
      // backend so player drawers and popups don't pay the SurfaceView
      // composition cost for sessions without danmaku.
      return MpvVideoOutputBackend.surface;
    }
    return MpvVideoOutputBackend.normalize(requestedBackend);
  }

  String _resolvedVideoOutputBackend(String requestedBackend) {
    final lockedBackend = _lockedPlatformViewBackend;
    if (lockedBackend != null && lockedBackend.trim().isNotEmpty) {
      return MpvVideoOutputBackend.normalize(lockedBackend);
    }
    return _preferredVideoOutputBackend(requestedBackend);
  }

  MpvMediaSource _resolvedPlatformViewSource(MpvMediaSource source) {
    final resolvedBackend = _resolvedVideoOutputBackend(source.videoOutputBackend);
    if (resolvedBackend == source.videoOutputBackend) {
      return source;
    }
    return source.copyWith(videoOutputBackend: resolvedBackend);
  }

  AudioTrackOption? _findAudioTrack(String? guid) {
    final normalized = guid?.trim() ?? '';
    if (normalized.isEmpty) return null;
    for (final track in _audioTracks) {
      if (track.guid == normalized) return track;
    }
    return null;
  }

  SubtitleTrackOption? _findSubtitleTrack(String? guid) {
    final normalized = guid?.trim() ?? '';
    if (normalized.isEmpty) return null;
    for (final track in _subtitleTracks) {
      if (track.guid == normalized) return track;
    }
    return null;
  }

  AudioTrackOption? _currentAudioTrack() {
    final selected = _findAudioTrack(_currentAudioGuid);
    if (selected != null) return selected;
    for (final track in _audioTracks) {
      if (track.isDefaultOption) return track;
    }
    return _audioTracks.isNotEmpty ? _audioTracks.first : null;
  }

  SubtitleTrackOption? _currentSubtitleTrack() {
    final normalized = _normalizedSubtitleGuid();
    if (normalized == null || normalized.isEmpty) return null;
    final selected = _findSubtitleTrack(normalized);
    if (selected != null) return selected;
    for (final track in _subtitleTracks) {
      if (track.isDefaultOption) return track;
    }
    return null;
  }

  bool _subtitleShouldPreferEmbeddedTrack(SubtitleTrackOption? track) {
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

  bool _subtitleShouldUseExternalFile(SubtitleTrackOption? track) {
    if (track == null) return false;
    if (_serverFallbackSubtitleGuids.contains(track.guid)) return false;
    if (_subtitleShouldPreferEmbeddedTrack(track)) return false;
    if (track.isExternal == 1 || track.extraFile == 1) return true;
    return track.guid.startsWith('local:');
  }

  bool _subtitleHasDirectFile(SubtitleTrackOption? track) {
    if (track == null) return false;
    return track.isExternal == 1 || track.extraFile == 1;
  }

  // ignore: unused_element
  String _subtitleSwitchMessageForTrack(SubtitleTrackOption? track) {
    final l10n = AppLocalizations.of(context);
    if (track == null) {
      return l10n.playerSubtitleClosingPleaseWait;
    }
    final title = _subtitleTitle(track);
    final format = (track.format.isNotEmpty ? track.format : track.codecName)
        .trim()
        .toLowerCase();
    final suffix = format.isEmpty ? '' : ' ($format)';
    return l10n.playerSubtitleSwitchingPleaseWait(title, suffix);
  }

  void _releaseSubtitleProxySession([String? keepSessionId]) {
    final current = _activeSubtitleProxySessionId;
    if (current == null || current.isEmpty || current == keepSessionId) {
      return;
    }
    _scheduleProxySessionRelease(current);
    _activeSubtitleProxySessionId = null;
  }

  void _cancelScheduledProxyRelease(String? sessionId) {
    if (sessionId == null || sessionId.isEmpty) return;
    _proxyReleaseTimers.remove(sessionId)?.cancel();
  }

  void _scheduleProxySessionRelease(
    String? sessionId, {
    Duration delay = const Duration(seconds: 12),
  }) {
    if (sessionId == null || sessionId.isEmpty) return;
    _proxyReleaseTimers.remove(sessionId)?.cancel();
    _proxyReleaseTimers[sessionId] = Timer(delay, () {
      _proxyReleaseTimers.remove(sessionId)?.cancel();
      MpvProxyServer.instance.unregister(sessionId);
    });
  }

  String? _pickAudioGuid({
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

  AudioTrackOption? _audioTrackByGuid(
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

  int? _mpvAudioTrackId(AudioTrackOption? track) {
    if (track == null) return null;
    if (track.guid.startsWith('mpv-audio:') && track.index > 0) {
      return track.index;
    }
    final ordinal = _audioTracks.indexWhere((item) => item.guid == track.guid);
    if (ordinal < 0) return null;
    return ordinal + 1;
  }

  int? _mpvSubtitleTrackId(SubtitleTrackOption? track) {
    if (track == null) return null;
    if (track.guid.startsWith('mpv-subtitle:') && track.index > 0) {
      return track.index;
    }
    final embeddedTracks = _subtitleTracks
        .where((item) {
          if (item.guid.trim().isEmpty) return false;
          return !_subtitleShouldUseExternalFile(item);
        })
        .toList(growable: false);
    final ordinal = embeddedTracks.indexWhere(
      (item) => item.guid == track.guid,
    );
    if (ordinal < 0) return null;
    return ordinal + 1;
  }

  String? _normalizedAudioGuid() {
    return (_currentAudioGuid ?? '').trim().isEmpty ? null : _currentAudioGuid;
  }

  String? _normalizedSubtitleGuid() {
    final normalized = (_currentSubtitleGuid ?? '').trim();
    if (normalized.isEmpty) return null;
    if (_isLocalRuntimeTrackSource() ||
        !normalized.startsWith('mpv-subtitle:')) {
      return normalized;
    }
    final runtimeId = int.tryParse(normalized.substring(13));
    if (runtimeId != null && runtimeId > 0) {
      final embeddedTracks = _subtitleTracks
          .where((track) {
            if (track.guid.trim().isEmpty) return false;
            if (track.guid.startsWith('mpv-subtitle:')) return false;
            return !_subtitleShouldUseExternalFile(track);
          })
          .toList(growable: false);
      if (runtimeId <= embeddedTracks.length) {
        return embeddedTracks[runtimeId - 1].guid;
      }
      for (final track in embeddedTracks) {
        if (track.index == runtimeId) {
          return track.guid;
        }
      }
    }
    final sourceGuid = widget.source.subtitleTrackGuid?.trim() ?? '';
    if (sourceGuid.isNotEmpty && !sourceGuid.startsWith('mpv-subtitle:')) {
      return sourceGuid;
    }
    return null;
  }

  String _speedLabel(double speed) {
    if ((speed - speed.roundToDouble()).abs() < 0.001) {
      return '${speed.toStringAsFixed(0)}x';
    }
    return '${speed.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}x';
  }

  String _audioTitle(AudioTrackOption track) {
    return track.displayLabel.trim().isEmpty
        ? AppLocalizations.of(context).playerAudioUnknownTrack
        : track.displayLabel.trim();
  }

  String _audioSubtitle(AudioTrackOption track) {
    return track.detailLabel.trim();
  }

  String _subtitleTitle(SubtitleTrackOption track) {
    final l10n = AppLocalizations.of(context);
    final language = MediaLanguageMapper.subtitleLabel(track.language).trim();
    final normalized =
        (language.isEmpty || language == '字幕' || language == '未知')
        ? l10n.playerSubtitleUnknownTrack
        : language;
    final suffix = track.isDefaultOption
        ? l10n.mpvDefault
        : (track.isExternal == 1 ? l10n.playerSubtitleExternal : '');
    return suffix.isEmpty ? normalized : '$normalized-$suffix';
  }

  String _subtitleSubtitle(SubtitleTrackOption track) {
    final format = (track.format.isNotEmpty ? track.format : track.codecName)
        .trim()
        .toUpperCase();
    return format;
  }

  String _qualityId(PlaybackQualityOption quality) {
    return '${quality.source.name}|${quality.mediaGuid}|${quality.videoGuid}|${quality.resolution}|${quality.bitrate}|${quality.directLinkQualityIndex ?? ''}';
  }

  double _videoAspectRatio() {
    if (_currentVideoWidth > 0 && _currentVideoHeight > 0) {
      return _currentVideoWidth / _currentVideoHeight;
    }
    return 16 / 9;
  }

  bool _currentSourceHasVideoTrack() {
    if (_currentVideoWidth > 0 && _currentVideoHeight > 0) {
      return true;
    }
    if (_currentVideoGuid.trim().isNotEmpty) {
      return true;
    }
    if (widget.source.videoWidth > 0 && widget.source.videoHeight > 0) {
      return true;
    }
    return widget.source.videoGuid.trim().isNotEmpty;
  }

  String _selectedQualityId() {
    final visibleQualities = _displayQualityOptionsForCurrentMode();
    for (final quality in visibleQualities) {
      if (_currentDirectLinkQualityIndex != null &&
          quality.directLinkQualityIndex == _currentDirectLinkQualityIndex) {
        return _qualityId(quality);
      }
      if (quality.mediaGuid == _currentMediaGuid &&
          quality.videoGuid == _currentVideoGuid &&
          quality.source == _currentPlaybackQualitySource()) {
        return _qualityId(quality);
      }
    }
    final currentResolution = _normalizeQualityResolution(_currentResolution);
    for (final quality in visibleQualities) {
      if (_normalizeQualityResolution(quality.resolution) ==
              currentResolution &&
          _qualityBitrateMatches(quality.bitrate, _currentBitrate)) {
        return _qualityId(quality);
      }
    }
    if (_isCurrentOriginalQuality()) {
      for (final quality in visibleQualities) {
        if (quality.isDefault == 1) return _qualityId(quality);
      }
    }
    for (final quality in visibleQualities) {
      if (quality.mediaGuid == _currentMediaGuid) return _qualityId(quality);
    }
    final original = _originalQualityOption();
    if (original != null && _isCurrentOriginalQuality()) {
      return _qualityId(original);
    }
    return visibleQualities.isNotEmpty
        ? _qualityId(visibleQualities.first)
        : '';
  }

  String _normalizeQualityResolution(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return '';
    final match = RegExp(r'(\d{3,4})').firstMatch(normalized);
    if (match != null) return match.group(1) ?? normalized;
    return normalized;
  }

  bool _qualityBitrateMatches(int qualityBitrate, int currentBitrate) {
    if (qualityBitrate <= 0 || currentBitrate <= 0) return false;
    return qualityBitrate == currentBitrate;
  }

  bool _isCurrentOriginalQuality() {
    final original = _originalQualityOption();
    if (original == null) return false;
    if (_currentPlaybackQualitySource() !=
        PlaybackQualitySource.originalProxy) {
      return false;
    }
    if (original.mediaGuid == _currentMediaGuid &&
        (original.videoGuid.isEmpty ||
            original.videoGuid == _currentVideoGuid)) {
      return true;
    }
    final currentResolution = _normalizeQualityResolution(_currentResolution);
    return _normalizeQualityResolution(original.resolution) ==
            currentResolution &&
        _qualityBitrateMatches(original.bitrate, _currentBitrate);
  }

  String _qualityLabel(PlaybackQualityOption quality) {
    final resolution = quality.resolution.trim();
    if (resolution.isNotEmpty) return resolution;
    final l10n = AppLocalizations.of(context);
    return quality.isDefault == 1
        ? l10n.playerQualityOriginal
        : l10n.playerQualityGeneric;
  }

  String _qualityDisplayLabel(PlaybackQualityOption quality) {
    final resolution = _qualityDisplayResolution(_qualityLabel(quality));
    final bitrate = _qualityBitrateLabel(quality.bitrate);
    if (bitrate.isEmpty) return resolution;
    return '$resolution $bitrate';
  }

  String _qualityDisplayResolution(String resolution) {
    final trimmed = resolution.trim();
    if (trimmed.isEmpty) return trimmed;
    if (RegExp(r'^\d+$').hasMatch(trimmed)) {
      return '${trimmed}p';
    }
    return trimmed;
  }

  String _qualityBitrateLabel(int bitrate) {
    if (bitrate <= 0) return '';
    final mbps = bitrate / 1000000;
    final rounded = mbps.roundToDouble();
    final value = (mbps - rounded).abs() < 0.05
        ? rounded.toInt().toString()
        : mbps.toStringAsFixed(1);
    return '${value}Mbps';
  }

  String _qualityOptionBadge(PlaybackQualityOption quality) {
    final label = _qualityLabel(quality);
    final original = _originalQualityOption();
    if (original == null || _qualityId(original) != _qualityId(quality)) {
      return '';
    }
    final originalLabel = AppLocalizations.of(context).playerQualityOriginal;
    if (label == originalLabel) return '';
    return originalLabel;
  }

  String _currentQualityButtonLabel() {
    final originalLabel = AppLocalizations.of(context).playerQualityOriginal;
    if (_isCurrentOriginalQuality()) {
      return originalLabel;
    }
    return _currentResolution.isNotEmpty ? _currentResolution : originalLabel;
  }

  List<PlaybackQualityOption> _visibleQualityOptionsForCurrentMode() {
    if (_qualities.isEmpty) return const <PlaybackQualityOption>[];
    final visible = <PlaybackQualityOption>[];
    for (final quality in _qualities) {
      if (_playbackMode.isDirectLink) {
        if (quality.isServerSession) continue;
      } else {
        if (quality.isDirectLink) continue;
      }
      visible.add(quality);
    }
    return visible.isNotEmpty ? visible : _qualities;
  }

  List<PlaybackQualityOption> _displayQualityOptionsForCurrentMode() {
    final visible = _visibleQualityOptionsForCurrentMode();
    if (visible.length <= 1) return visible;
    final deduped = <String, PlaybackQualityOption>{};
    for (final quality in visible) {
      final key = _qualityDisplayDedupKey(quality);
      final existing = deduped[key];
      if (existing == null ||
          _shouldPreferDisplayedQuality(quality, existing)) {
        deduped[key] = quality;
      }
    }
    return deduped.values.toList(growable: false);
  }

  String _qualityDisplayDedupKey(PlaybackQualityOption quality) {
    final normalizedResolution = _normalizeQualityResolution(
      quality.resolution,
    );
    final fallbackLabel = _qualityLabel(quality).trim().toLowerCase();
    return '${normalizedResolution.isNotEmpty ? normalizedResolution : fallbackLabel}|${quality.bitrate}';
  }

  bool _shouldPreferDisplayedQuality(
    PlaybackQualityOption candidate,
    PlaybackQualityOption current,
  ) {
    if (candidate.isOriginalProxy != current.isOriginalProxy) {
      return candidate.isOriginalProxy;
    }
    if ((candidate.isDefault == 1) != (current.isDefault == 1)) {
      return candidate.isDefault == 1;
    }
    final candidateResolution = int.tryParse(
      _normalizeQualityResolution(candidate.resolution),
    );
    final currentResolution = int.tryParse(
      _normalizeQualityResolution(current.resolution),
    );
    if (candidateResolution != currentResolution) {
      return (candidateResolution ?? -1) > (currentResolution ?? -1);
    }
    if (candidate.bitrate != current.bitrate) {
      return candidate.bitrate > current.bitrate;
    }
    return _qualityLabel(candidate).trim().length <
        _qualityLabel(current).trim().length;
  }

  PlaybackQualityOption? _originalQualityOption() {
    if (_qualities.isEmpty) return null;
    for (final quality in _qualities) {
      if (quality.isOriginalProxy) return quality;
    }
    PlaybackQualityOption best = _qualities.first;
    for (final quality in _qualities.skip(1)) {
      final qualityResolution = int.tryParse(
        _normalizeQualityResolution(quality.resolution),
      );
      final bestResolution = int.tryParse(
        _normalizeQualityResolution(best.resolution),
      );
      final qualityScore =
          (qualityResolution ?? -1) * 100000000 + quality.bitrate;
      final bestScore = (bestResolution ?? -1) * 100000000 + best.bitrate;
      if (qualityScore > bestScore) {
        best = quality;
      }
    }
    return best;
  }

  PlaybackQualitySource _currentPlaybackQualitySource() {
    if (_playbackMode.isServerManaged) {
      return PlaybackQualitySource.serverSession;
    }
    if (_playbackMode.isDirectLink) {
      return PlaybackQualitySource.directLink;
    }
    return PlaybackQualitySource.originalProxy;
  }

  int _issueNextLoadNonce() {
    _loadNonceSeed += 1;
    return _loadNonceSeed;
  }

  MpvMediaSource _buildCurrentSource({
    Duration? startPosition,
    int? loadNonce,
  }) {
    final audio = _currentAudioTrack();
    final subtitle = _currentSubtitleTrack();
    final serverManagedPlayback = _playbackMode.isServerManaged;
    final preferExternalSubtitle =
        _subtitleShouldUseExternalFile(subtitle) ||
        (_activeSubtitleProxySessionId?.isNotEmpty ?? false);
    final subtitleExplicitOff =
        _subtitleExplicitlyDisabled &&
        (_currentSubtitleGuid ?? '').trim().isEmpty;
    final audioTrackIndex = serverManagedPlayback
        ? null
        : _mpvAudioTrackId(audio);
    final clearAudioTrackIndex = serverManagedPlayback || audio == null;
    final subtitleTrackIndex = serverManagedPlayback
        ? null
        : (subtitleExplicitOff
              ? -1
              : (preferExternalSubtitle
                    ? null
                    : _mpvSubtitleTrackId(subtitle)));
    final clearSubtitleTrackIndex =
        serverManagedPlayback || preferExternalSubtitle || subtitle == null;
    final normalizedStartPosition = _normalizedSourceStartPosition(
      startPosition ?? _controller.value.value.position,
    );
    return widget.source.copyWith(
      loadNonce: loadNonce ?? widget.source.loadNonce,
      itemGuid: _currentItemGuid,
      seasonGuid: _currentSeasonGuid,
      posterPath: _currentPosterPath.trim().isNotEmpty
          ? _currentPosterPath.trim()
          : widget.source.posterPath.trim(),
      mediaGuid: _currentMediaGuid,
      mediaType: _currentMediaType,
      ancestorName: _currentAncestorName,
      videoGuid: _currentVideoGuid,
      directLinkQualityIndex: _currentDirectLinkQualityIndex,
      videoWidth: _currentVideoWidth,
      videoHeight: _currentVideoHeight,
      videoCodecName: _currentVideoCodecName,
      videoProfile: _currentVideoProfile,
      colorSpace: _currentColorSpace,
      colorTransfer: _currentColorTransfer,
      colorPrimaries: _currentColorPrimaries,
      bitDepth: _currentBitDepth,
      isDownloadedFile: _currentSourceIsDownloadedFile,
      proxySessionId: _activeProxySessionId,
      playLink: _currentPlayLink,
      serverSessionHlsTimeSeconds: _currentServerSessionHlsTimeSeconds,
      url: _currentUrl,
      headers: Map<String, String>.from(_currentHeaders),
      title: _currentTitle,
      episodeNumber: _currentEpisodeNumber,
      startPosition: normalizedStartPosition,
      audioTrackIndex: audioTrackIndex,
      clearAudioTrackIndex: clearAudioTrackIndex,
      subtitleTrackIndex: subtitleTrackIndex,
      clearSubtitleTrackIndex: clearSubtitleTrackIndex,
      audioTrackGuid: audio?.guid,
      clearAudioTrackGuid: audio == null,
      subtitleTrackGuid: _normalizedSubtitleGuid(),
      clearSubtitleTrackGuid: _normalizedSubtitleGuid() == null,
      resolution: _currentResolution,
      bitrate: _currentBitrate,
      durationSeconds: _durationSeconds,
      preferExternalSubtitle: preferExternalSubtitle,
      forceNativeProxy: widget.source.forceNativeProxy,
      extremePlaybackEnabled:
          _extremePlaybackEnabled &&
          _isExtremePlaybackApplicableForCurrentSource(),
      reliableSeek: _currentReliableSeek,
      seekProbeSummary: _currentSeekProbeSummary,
      playbackMode: _playbackMode,
      playbackSpeed: _playbackSpeed,
      listenVideoModeEnabled: _listenVideoModeEnabled,
      videoOutputBackend: _resolvedVideoOutputBackend(
        widget.source.videoOutputBackend,
      ),
      audioTracks: _audioTracks,
      subtitleTracks: _subtitleTracks,
      qualities: _qualities,
    );
  }

  Duration _normalizedSourceStartPosition(Duration requestedPosition) {
    if (requestedPosition <= Duration.zero) {
      return Duration.zero;
    }
    if (_durationSeconds <= 0) {
      return requestedPosition;
    }
    final duration = Duration(seconds: _durationSeconds);
    if (requestedPosition >= duration) {
      return Duration.zero;
    }
    final normalized = _completionController.normalizedStartPosition(
      startPosition: requestedPosition,
      durationSeconds: _durationSeconds,
    );
    if (normalized >= duration) {
      return Duration.zero;
    }
    return normalized;
  }

  bool _isExtremePlaybackApplicableForCurrentSource() {
    final uri = Uri.tryParse(_currentUrl.trim());
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;
    final host = uri.host.trim().toLowerCase();
    return host.isNotEmpty && host != '127.0.0.1' && host != 'localhost';
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds.clamp(0, 359999);
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
