part of 'mpv_player_page.dart';

extension _MpvPlayerSourceMixin on _MpvPlayerPageState {
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
    final normalized = (_currentSubtitleGuid ?? '').trim();
    if (normalized.isEmpty) return null;
    final selected = _findSubtitleTrack(normalized);
    if (selected != null) return selected;
    for (final track in _subtitleTracks) {
      if (track.isDefaultOption) return track;
    }
    return null;
  }

  bool _subtitleShouldUseExternalFile(SubtitleTrackOption? track) {
    if (track == null) return false;
    if (_serverFallbackSubtitleGuids.contains(track.guid)) return false;
    return _subtitleHasDirectFile(track);
  }

  bool _subtitleHasDirectFile(SubtitleTrackOption? track) {
    if (track == null) return false;
    return track.isExternal == 1 || track.extraFile == 1;
  }

  // ignore: unused_element
  String _subtitleSwitchMessageForTrack(SubtitleTrackOption? track) {
    if (track == null) {
      return '正在为您关闭字幕，请稍等...';
    }
    final title = _subtitleTitle(track);
    final format = (track.format.isNotEmpty ? track.format : track.codecName)
        .trim()
        .toLowerCase();
    final suffix = format.isEmpty ? '' : ' ($format)';
    return '正在为您切换至$title$suffix 字幕，请稍等...';
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

  String? _pickSubtitleGuid({
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

  int? _mpvAudioTrackId(AudioTrackOption? track) {
    if (track == null) return null;
    final ordinal = _audioTracks.indexWhere((item) => item.guid == track.guid);
    if (ordinal < 0) return null;
    return ordinal + 1;
  }

  int? _mpvSubtitleTrackId(SubtitleTrackOption? track) {
    if (track == null) return null;
    final ordinal = _subtitleTracks.indexWhere(
      (item) => item.guid == track.guid,
    );
    if (ordinal < 0) return null;
    return ordinal + 1;
  }

  String? _normalizedAudioGuid() {
    return (_currentAudioGuid ?? '').trim().isEmpty ? null : _currentAudioGuid;
  }

  String? _normalizedSubtitleGuid() {
    return (_currentSubtitleGuid ?? '').trim().isEmpty
        ? null
        : _currentSubtitleGuid;
  }

  String _speedLabel(double speed) {
    if ((speed - speed.roundToDouble()).abs() < 0.001) {
      return '${speed.toStringAsFixed(0)}x';
    }
    return '${speed.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}x';
  }

  String _speedDescription(double speed) {
    if ((speed - 1.0).abs() < 0.001) return '标准速度';
    if (speed < 1.0) return '慢速播放';
    return '快速播放';
  }

  String _audioTitle(AudioTrackOption track) {
    return track.displayLabel.trim().isEmpty
        ? '未知音轨'
        : track.displayLabel.trim();
  }

  String _audioSubtitle(AudioTrackOption track) {
    return track.detailLabel.trim();
  }

  String _subtitleTitle(SubtitleTrackOption track) {
    final language = MediaLanguageMapper.subtitleLabel(track.language).trim();
    final normalized =
        (language.isEmpty || language == '字幕' || language == '未知')
        ? '未知字幕'
        : language;
    final suffix = track.isDefaultOption
        ? '默认'
        : (track.isExternal == 1 ? '外挂' : '');
    return suffix.isEmpty ? normalized : '$normalized-$suffix';
  }

  String _subtitleSubtitle(SubtitleTrackOption track) {
    final format = (track.format.isNotEmpty ? track.format : track.codecName)
        .trim()
        .toUpperCase();
    return format;
  }

  String _qualityId(PlaybackQualityOption quality) {
    return '${quality.mediaGuid}|${quality.videoGuid}|${quality.resolution}|${quality.bitrate}';
  }

  double _videoAspectRatio() {
    if (_currentVideoWidth > 0 && _currentVideoHeight > 0) {
      return _currentVideoWidth / _currentVideoHeight;
    }
    return 16 / 9;
  }

  String _selectedQualityId() {
    for (final quality in _qualities) {
      if (quality.mediaGuid == _currentMediaGuid &&
          quality.videoGuid == _currentVideoGuid) {
        return _qualityId(quality);
      }
    }
    final currentResolution = _normalizeQualityResolution(_currentResolution);
    for (final quality in _qualities) {
      if (_normalizeQualityResolution(quality.resolution) ==
              currentResolution &&
          _qualityBitrateMatches(quality.bitrate, _currentBitrate)) {
        return _qualityId(quality);
      }
    }
    if (_isCurrentOriginalQuality()) {
      for (final quality in _qualities) {
        if (quality.isDefault == 1) return _qualityId(quality);
      }
    }
    for (final quality in _qualities) {
      if (quality.mediaGuid == _currentMediaGuid) return _qualityId(quality);
    }
    final original = _originalQualityOption();
    if (original != null && _isCurrentOriginalQuality()) {
      return _qualityId(original);
    }
    return _qualities.isNotEmpty ? _qualityId(_qualities.first) : '';
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
    return quality.isDefault == 1 ? '原画' : '清晰度';
  }

  String _qualityOptionBadge(PlaybackQualityOption quality) {
    final label = _qualityLabel(quality);
    final original = _originalQualityOption();
    if (original == null || _qualityId(original) != _qualityId(quality)) {
      return '';
    }
    if (label == '原画') return '';
    return '原画';
  }

  String _currentQualityButtonLabel() {
    if (_isCurrentOriginalQuality()) {
      return '原画';
    }
    return _currentResolution.isNotEmpty ? _currentResolution : '原画';
  }

  PlaybackQualityOption? _originalQualityOption() {
    if (_qualities.isEmpty) return null;
    for (final quality in _qualities) {
      if (quality.isDefault == 1) return quality;
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

  MpvMediaSource _buildCurrentSource({Duration? startPosition}) {
    final audio = _currentAudioTrack();
    final subtitle = _currentSubtitleTrack();
    final preferExternalSubtitle =
        _subtitleShouldUseExternalFile(subtitle) ||
        (_activeSubtitleProxySessionId?.isNotEmpty ?? false);
    return widget.source.copyWith(
      itemGuid: _currentItemGuid,
      seasonGuid: _currentSeasonGuid,
      mediaGuid: _currentMediaGuid,
      videoGuid: _currentVideoGuid,
      videoWidth: _currentVideoWidth,
      videoHeight: _currentVideoHeight,
      videoCodecName: _currentVideoCodecName,
      videoProfile: _currentVideoProfile,
      colorSpace: _currentColorSpace,
      colorTransfer: _currentColorTransfer,
      colorPrimaries: _currentColorPrimaries,
      bitDepth: _currentBitDepth,
      proxySessionId: _activeProxySessionId,
      playLink: _currentPlayLink,
      url: _currentUrl,
      headers: Map<String, String>.from(_currentHeaders),
      title: _currentTitle,
      episodeNumber: _currentEpisodeNumber,
      startPosition: startPosition ?? _controller.value.value.position,
      audioTrackIndex: _mpvAudioTrackId(audio),
      clearAudioTrackIndex: audio == null,
      subtitleTrackIndex: preferExternalSubtitle
          ? null
          : _mpvSubtitleTrackId(subtitle),
      clearSubtitleTrackIndex: preferExternalSubtitle || subtitle == null,
      audioTrackGuid: audio?.guid,
      clearAudioTrackGuid: audio == null,
      subtitleTrackGuid: (_currentSubtitleGuid ?? '').trim().isEmpty
          ? null
          : _currentSubtitleGuid,
      clearSubtitleTrackGuid: (_currentSubtitleGuid ?? '').trim().isEmpty,
      resolution: _currentResolution,
      bitrate: _currentBitrate,
      durationSeconds: _durationSeconds,
      preferExternalSubtitle: preferExternalSubtitle,
      reliableSeek: _currentReliableSeek,
      seekProbeSummary: _currentSeekProbeSummary,
      serverPlaybackManaged: _serverPlaybackManaged,
      playbackSpeed: _playbackSpeed,
      audioTracks: _audioTracks,
      subtitleTracks: _subtitleTracks,
      qualities: _qualities,
    );
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
