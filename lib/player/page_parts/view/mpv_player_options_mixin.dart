part of mpv_player_page;

extension _MpvPlayerOptionsMixin on _MpvPlayerPageState {
  bool _isDirectPlaybackQuality(PlaybackQualityOption quality) {
    return !quality.isServerSession;
  }

  Future<String?> _showPlayerOptionSheet({
    required String title,
    required List<PlayerOptionSheetItem> items,
    String? selectedId,
    String? sectionLabel,
    List<PlayerOptionSheetAction> headerActions =
        const <PlayerOptionSheetAction>[],
    bool centeredTitle = false,
    bool useCardStyle = false,
  }) async {
    _overlayState.cancelAutoHide();
    final restoreControls = _controlsVisible;
    if (restoreControls) {
      _hideControlsImmediately();
    }
    String? result;
    try {
      result = await PlayerOptionSheet.show(
        context,
        title: title,
        items: items,
        selectedId: selectedId,
        sectionLabel: sectionLabel,
        headerActions: headerActions,
        centeredTitle: centeredTitle,
        useCardStyle: useCardStyle,
      );
    } finally {
      if (mounted) {
        if (restoreControls) {
          _showControls();
        }
      }
    }
    return result;
  }

  Future<void> _showSpeedSheet() async {
    const speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final result = await _showPlayerOptionSheet(
      title: '倍速',
      sectionLabel: '播放速度',
      items: speeds
          .map(
            (speed) => PlayerOptionSheetItem(
              id: speed.toStringAsFixed(2),
              title: _speedLabel(speed),
              subtitle: _speedDescription(speed),
            ),
          )
          .toList(),
      selectedId: _playbackSpeed.toStringAsFixed(2),
    );
    if (!mounted || result == null) return;
    final speed = double.tryParse(result);
    if (speed == null || (speed - _playbackSpeed).abs() < 0.001) return;
    _updatePlayerState(() => _playbackSpeed = speed);
    await _controller.setSpeed(speed);
    _showControls();
  }

  Future<void> _showAudioSheet() async {
    await _showAudioDrawer();
  }

  Future<void> _showSubtitleSheet() async {
    await _showSubtitleDrawer();
    return;
    /*
    // ignore: dead_code, use_build_context_synchronously
    _deferredSubtitleSelectionTimer?.cancel();
    if (_subtitleTracks.isEmpty) {
      _showTransientMessage('当前没有可切换字幕');
      return;
    }
    try {
      // ignore: use_build_context_synchronously
      final languageMap = await FeiniuApi(
        context.read<NasProvider>(),
      ).getTagIso6392Map(lan: 'zh-CN');
      if (languageMap.isNotEmpty) {
        MediaLanguageMapper.mergeLanguageMap(languageMap);
      }
    } catch (_) {}
    final result = await _showPlayerOptionSheet(
      title: '选择字幕',
      items: <PlayerOptionSheetItem>[
        const PlayerOptionSheetItem(id: '__subtitle_off__', title: '关闭字幕'),
        ..._subtitleTracks.map(
          (track) => PlayerOptionSheetItem(
            id: track.guid,
            title: _subtitleTitle(track),
            subtitle: _subtitleSubtitle(track),
          ),
        ),
      ],
      selectedId: (_currentSubtitleGuid ?? '').trim().isEmpty
          ? '__subtitle_off__'
          : _currentSubtitleGuid,
      centeredTitle: true,
      useCardStyle: true,
    );
    if (!mounted || result == null) return;
    final normalized = result == '__subtitle_off__' ? '' : result.trim();
    if (normalized == (_currentSubtitleGuid ?? '').trim()) return;
    final selected = _findSubtitleTrack(normalized);
    if (_playbackMode.isServerManaged &&
        normalized.isNotEmpty &&
        !_subtitleHasDirectFile(selected)) {
      _showTransientMessage('当前字幕未提取，暂不支持切换');
      return;
    }
    _updatePlayerState(() {
      _currentSubtitleGuid = normalized;
      if (normalized.isEmpty) return;
      _subtitleFailureNoticeShownGuids.remove(normalized);
      _serverFallbackSubtitleGuids.remove(normalized);
    });
    _showSubtitleSwitchMessage(_subtitleSwitchPromptForTrack(selected));
    try {
      await _applySubtitleSelection();
      _showControls();
    } finally {
      if (!reloadStarted) {
        _cancelPendingLoadingTransition();
      }
    }
    */
  }

  Future<void> _showQualitySheet() async {
    final visibleQualities = _visibleQualityOptionsForCurrentMode();
    if (visibleQualities.isEmpty) {
      _showTransientMessage('当前没有可切换清晰度');
      return;
    }
    final result = await _showPlayerOptionSheet(
      title: '清晰度',
      sectionLabel: '清晰度列表',
      items: visibleQualities
          .map(
            (quality) => PlayerOptionSheetItem(
              id: _qualityId(quality),
              title: _qualityLabel(quality),
              badgeText: _qualityOptionBadge(quality),
              subtitle: quality.bitrate > 0
                  ? '${(quality.bitrate / 1000000).toStringAsFixed(1)} Mbps'
                  : '',
            ),
          )
          .toList(),
      selectedId: _selectedQualityId(),
    );
    if (!mounted || result == null) return;
    final selected = visibleQualities.cast<PlaybackQualityOption?>().firstWhere(
      (quality) => quality != null && _qualityId(quality) == result,
      orElse: () => null,
    );
    if (selected == null) return;
    await _switchQuality(selected);
  }

  Future<void> _switchQuality(
    PlaybackQualityOption quality, {
    String? loadingMessage,
  }) async {
    final currentQualityMatches =
        quality.mediaGuid == _currentMediaGuid &&
        quality.videoGuid == _currentVideoGuid &&
        quality.resolution == _currentResolution &&
        quality.bitrate == _currentBitrate &&
        quality.directLinkQualityIndex == _currentDirectLinkQualityIndex;
    if (currentQualityMatches) {
      return;
    }

    final currentPosition = _displayPosition(_controller.value.value);
    final pausedAfterReload = _controller.value.value.paused;
    _updatePlayerState(() => _uiController.qualitySwitchLoading = true);
    _uiController.pendingLoadingTransition = true;
    _markAwaitingVisualPlaybackStart(
      currentPosition,
      targetPaused: pausedAfterReload,
    );
    _showSubtitleSwitchMessage(
      loadingMessage ?? _qualitySwitchPromptFor(quality),
    );
    var reloadStarted = false;
    try {
      if (_isDirectPlaybackQuality(quality)) {
        await _reloadDirectPlayback(
          quality: quality,
          startPosition: currentPosition,
          pausedAfterReload: pausedAfterReload,
        );
      } else {
        await _reloadServerPlaySession(
          quality: quality,
          startPosition: currentPosition,
          pausedAfterReload: pausedAfterReload,
        );
      }
      reloadStarted = true;
      _showControls();
    } catch (error) {
      _showTransientMessage('切换清晰度失败: $error');
    } finally {
      if (!reloadStarted) {
        _cancelPendingLoadingTransition();
      }
    }
  }

  Future<void> _reloadDirectPlayback({
    required PlaybackQualityOption quality,
    Duration? startPosition,
    bool? pausedAfterReload,
  }) async {
    final api = FeiniuApi(context.read<NasProvider>());
    final currentPosition =
        startPosition ?? _displayPosition(_controller.value.value);
    final directMediaGuid = _subtitleSourceMediaGuid.trim().isNotEmpty
        ? _subtitleSourceMediaGuid.trim()
        : (quality.mediaGuid.trim().isNotEmpty
              ? quality.mediaGuid.trim()
              : _currentMediaGuid.trim());
    if (directMediaGuid.isEmpty) {
      throw Exception('missing direct media guid');
    }

    final playbackStream = await api.getPlaybackStream(directMediaGuid);
    final trackData = await api.getStreamTrackData(_currentItemGuid);
    final mergedQualities = mergePlaybackQualitiesWithStreamTrackData(
      playbackStream.qualities,
      trackData,
    );
    final mergedSubtitleTracks = PlayDetailTrackSelector.mergeSubtitleTracks(
      primaryTracks: playbackStream.subtitleStreams,
      extraTracks: trackData.subtitlesForMedia(directMediaGuid),
    );
    final selectedAudioTrack =
        _audioTrackByGuid(
          _normalizedAudioGuid(),
          playbackStream.audioStreams,
        ) ??
        playbackStream.audioStreams.cast<AudioTrackOption?>().firstWhere(
          (track) => track?.isDefaultOption ?? false,
          orElse: () => playbackStream.audioStreams.isNotEmpty
              ? playbackStream.audioStreams.first
              : null,
        );
    final selectedSubtitleGuid =
        _pickEpisodeSubtitleGuid(
          preferredGuid: _normalizedSubtitleGuid(),
          tracks: mergedSubtitleTracks,
        ) ??
        '';
    final selectedSubtitleTrack = mergedSubtitleTracks
        .cast<SubtitleTrackOption?>()
        .firstWhere(
          (track) => track?.guid == selectedSubtitleGuid,
          orElse: () => null,
        );
    final directLinkQualityIndex = quality.isDirectLink
        ? quality.directLinkQualityIndex
        : null;
    final directUrl = api.getStreamUrl(
      directMediaGuid,
      directLinkQualityIndex: directLinkQualityIndex,
    );
    if (directUrl.trim().isEmpty) {
      throw Exception('missing direct playback url');
    }
    final directLinkTarget = quality.isDirectLink
        ? playbackStream.buildDirectLinkTarget(directLinkQualityIndex)
        : null;
    final playableSource = await PlayerSourceController.buildPlayableSource(
      api,
      directLinkTarget?.url ?? directUrl,
      headersOverride: directLinkTarget?.headers,
      forceNativeProxy: directLinkTarget?.forceNativeProxy ?? false,
      seekProbeSummary:
          directLinkTarget?.debugSummary ??
          (quality.isDirectLink ? 'direct-link-quality' : 'direct'),
    );
    final resolvedStartPosition =
        !playableSource.reliableSeek && currentPosition > Duration.zero
        ? Duration.zero
        : currentPosition;
    final oldSessionId = _activeProxySessionId;
    final oldSubtitleSessionId = _activeSubtitleProxySessionId;
    _cancelScheduledProxyRelease(playableSource.proxySessionId);
    _updatePlayerState(() {
      _activeProxySessionId = playableSource.proxySessionId;
      _activeSubtitleProxySessionId = null;
      _currentPlayLink = null;
      _currentUrl = playableSource.url;
      _currentHeaders = playableSource.headers;
      _currentReliableSeek = playableSource.reliableSeek;
      _currentSeekProbeSummary = playableSource.seekProbeSummary;
      _currentMediaGuid = directMediaGuid;
      _subtitleSourceMediaGuid = directMediaGuid;
      _currentVideoGuid = quality.isDirectLink
          ? quality.videoGuid.trim()
          : (playbackStream.videoStream?.guid.trim().isNotEmpty == true
                ? playbackStream.videoStream!.guid.trim()
                : quality.videoGuid.trim());
      _currentDirectLinkQualityIndex = directLinkQualityIndex;
      _currentAudioGuid = selectedAudioTrack?.guid;
      _currentSubtitleGuid = selectedSubtitleGuid;
      if (selectedSubtitleGuid.isNotEmpty) {
        _subtitleExplicitlyDisabled = false;
      }
      _audioTracks = playbackStream.audioStreams;
      _subtitleTracks = mergedSubtitleTracks;
      _qualities = mergedQualities;
      _currentVideoWidth = playbackStream.videoStream?.width ?? 0;
      _currentVideoHeight = playbackStream.videoStream?.height ?? 0;
      _currentResolution =
          quality.isDirectLink && quality.resolution.trim().isNotEmpty
          ? quality.resolution.trim()
          : (playbackStream.videoStream?.resolutionType.trim().isNotEmpty ==
                    true
                ? playbackStream.videoStream!.resolutionType.trim()
                : quality.resolution.trim());
      _currentBitrate = quality.isDirectLink && quality.bitrate > 0
          ? quality.bitrate
          : (playbackStream.videoStream?.bps ?? quality.bitrate);
      _currentVideoCodecName = playbackStream.videoStream?.codecName ?? '';
      _currentVideoProfile = playbackStream.videoStream?.profile ?? '';
      _currentColorSpace = playbackStream.videoStream?.colorSpace ?? '';
      _currentColorTransfer = playbackStream.videoStream?.colorTransfer ?? '';
      _currentColorPrimaries = playbackStream.videoStream?.colorPrimaries ?? '';
      _currentBitDepth = playbackStream.videoStream?.bitDepth ?? 0;
      _serverFallbackSubtitleGuids.clear();
      _pendingExternalSubtitlePath = null;
      _pendingSubtitleSelectionRefresh =
          selectedSubtitleGuid.isNotEmpty ||
          PlayerSourceController.subtitleShouldUseExternalFile(
            selectedSubtitleTrack,
            _serverFallbackSubtitleGuids,
          );
      _pendingReloadAutoplayRefresh = true;
      _playbackMode = quality.isDirectLink
          ? PlayerPlaybackMode.directLinkQuality
          : PlayerPlaybackMode.originalQuality;
    });
    _gestureController.resetSeekTracking();

    if (oldSessionId != null &&
        oldSessionId.isNotEmpty &&
        oldSessionId != playableSource.proxySessionId) {
      _scheduleProxySessionRelease(oldSessionId);
    }
    if (oldSubtitleSessionId != null &&
        oldSubtitleSessionId.isNotEmpty &&
        oldSubtitleSessionId != _activeSubtitleProxySessionId) {
      _scheduleProxySessionRelease(oldSubtitleSessionId);
    }

    final source = _buildCurrentSource(
      startPosition: resolvedStartPosition,
      loadNonce: _issueNextLoadNonce(),
    );
    _markAwaitingVisualPlaybackStart(
      source.startPosition,
      targetPaused: pausedAfterReload ?? _controller.value.value.paused,
    );
    _controller.prepareForSourceLoad(
      source,
      paused: pausedAfterReload ?? _controller.value.value.paused,
    );
    await _controller.reload(source);
  }

  Future<void> _reloadServerPlaySession({
    String? audioGuid,
    String? subtitleGuid,
    PlaybackQualityOption? quality,
    Duration? startPosition,
    bool? pausedAfterReload,
  }) async {
    final api = FeiniuApi(context.read<NasProvider>());
    final currentPosition =
        startPosition ?? _displayPosition(_controller.value.value);
    final result = await _sourceController.reloadServerPlaySession(
      api: api,
      snapshot: _currentSourceSnapshot(),
      request: PlayerServerReloadRequest(
        audioGuid: audioGuid,
        subtitleGuid: subtitleGuid,
        quality: quality,
        startPosition: currentPosition,
      ),
    );
    _cancelScheduledProxyRelease(result.activeProxySessionId);
    _updatePlayerState(() {
      _activeProxySessionId = result.activeProxySessionId;
      _activeSubtitleProxySessionId = result.activeSubtitleProxySessionId;
      _currentPlayLink = result.currentPlayLink;
      _currentUrl = result.currentUrl;
      _currentHeaders = result.currentHeaders;
      _currentReliableSeek = result.reliableSeek;
      _currentSeekProbeSummary = result.seekProbeSummary;
      _currentMediaGuid = result.currentMediaGuid;
      _currentVideoGuid = result.currentVideoGuid;
      _currentDirectLinkQualityIndex = result.playbackMode.isDirectLink
          ? quality?.directLinkQualityIndex
          : null;
      _currentAudioGuid = result.currentAudioGuid;
      _currentSubtitleGuid = result.currentSubtitleGuid;
      if (result.currentSubtitleGuid?.trim().isNotEmpty == true) {
        _subtitleExplicitlyDisabled = false;
      }
      _audioTracks = result.audioTracks;
      _subtitleTracks = result.subtitleTracks;
      _qualities = result.qualities;
      _currentVideoWidth = result.currentVideoWidth;
      _currentVideoHeight = result.currentVideoHeight;
      _currentResolution = result.currentResolution;
      _currentBitrate = result.currentBitrate;
      _currentVideoCodecName = result.currentVideoCodecName;
      _currentVideoProfile = result.currentVideoProfile;
      _currentColorSpace = result.currentColorSpace;
      _currentColorTransfer = result.currentColorTransfer;
      _currentColorPrimaries = result.currentColorPrimaries;
      _currentBitDepth = result.currentBitDepth;
      _pendingExternalSubtitlePath = null;
      _pendingSubtitleSelectionRefresh =
          result.pendingSubtitleSelectionRefresh ||
          (result.currentSubtitleGuid?.trim().isNotEmpty == true);
      _pendingReloadAutoplayRefresh = true;
      _playbackMode = result.playbackMode;
    });
    _gestureController.resetSeekTracking();

    final resolvedStartPosition =
        !result.reliableSeek && currentPosition > Duration.zero
        ? Duration.zero
        : currentPosition;

    if (result.oldSessionId != null &&
        result.oldSessionId!.isNotEmpty &&
        result.oldSessionId != result.activeProxySessionId) {
      _scheduleProxySessionRelease(result.oldSessionId);
    }
    if (result.oldSubtitleSessionId != null &&
        result.oldSubtitleSessionId!.isNotEmpty &&
        result.oldSubtitleSessionId != _activeSubtitleProxySessionId) {
      _scheduleProxySessionRelease(result.oldSubtitleSessionId);
    }

    final source = _buildCurrentSource(
      startPosition: resolvedStartPosition,
      loadNonce: _issueNextLoadNonce(),
    );
    _markAwaitingVisualPlaybackStart(
      source.startPosition,
      targetPaused: pausedAfterReload ?? _controller.value.value.paused,
    );
    _controller.prepareForSourceLoad(
      source,
      paused: pausedAfterReload ?? _controller.value.value.paused,
    );
    await _controller.reload(source);
  }

  SubtitleTrackOption? _syncCurrentSubtitleTrackSelection() {
    final normalized = (_currentSubtitleGuid ?? '').trim();
    if (normalized.isEmpty) return null;
    final selected = _findSubtitleTrack(normalized);
    if (selected != null) return selected;
    SubtitleTrackOption? fallback;
    for (final track in _subtitleTracks) {
      if (track.isDefaultOption) {
        fallback = track;
        break;
      }
    }
    fallback ??= _subtitleTracks.isNotEmpty ? _subtitleTracks.first : null;
    if (fallback != null && mounted) {
      _updatePlayerState(() => _currentSubtitleGuid = fallback!.guid);
    }
    return fallback;
  }

  Future<SubtitleTrackOption?> _refreshSubtitleTracksFromSource({
    String? preferredGuid,
  }) async {
    final api = FeiniuApi(context.read<NasProvider>());
    final result = await _sourceController.refreshSubtitleTracksFromSource(
      api: api,
      snapshot: _currentSourceSnapshot(),
      preferredGuid: preferredGuid,
    );
    if (!mounted) return result.selectedTrack;
    _updatePlayerState(() {
      _subtitleTracks = result.subtitleTracks;
      _currentSubtitleGuid = result.selectedGuid;
    });
    return result.selectedTrack;
  }

  void _showSubtitleSwitchMessage(String message) {
    _subtitleSwitchOverlayTimer?.cancel();
    if (!mounted) return;
    _updatePlayerState(() => _uiController.subtitleSwitchMessage = message);
  }

  String _subtitleSwitchPromptForTrack(SubtitleTrackOption? track) {
    if (track == null) {
      return '正在为您关闭字幕，请稍等...';
    }
    final title = _subtitleTitle(track);
    final format = (track.format.isNotEmpty ? track.format : track.codecName)
        .trim()
        .toLowerCase();
    final suffix = format.isEmpty ? '' : '($format)';
    return '正在为您切换至 $title$suffix 字幕，请稍等...';
  }

  String _qualitySwitchPromptFor(PlaybackQualityOption quality) {
    final title = quality.resolution.trim().isNotEmpty
        ? quality.resolution.trim()
        : (quality.isDefault == 1 ? '原画' : '清晰度');
    final bitrate = quality.bitrate > 0
        ? ' ${(quality.bitrate / 1000000).toStringAsFixed(0)} Mbps'
        : '';
    return '正在为您切换至 $title$bitrate 画质，请稍等...';
  }

  void _hideSubtitleSwitchMessage({Duration? delay}) {
    _subtitleSwitchOverlayTimer?.cancel();
    if (delay == null || delay <= Duration.zero) {
      if (!mounted) return;
      _updatePlayerState(() => _uiController.subtitleSwitchMessage = null);
      return;
    }
    _subtitleSwitchOverlayTimer = Timer(delay, () {
      if (!mounted) return;
      _updatePlayerState(() => _uiController.subtitleSwitchMessage = null);
    });
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
    final suffix = format.isEmpty ? '' : '($format)';
    return '正在为您切换至$title$suffix 字幕，请稍等...';
  }

  // ignore: unused_element
  String _qualitySwitchMessageFor(PlaybackQualityOption quality) {
    final title = _qualityLabel(quality);
    final badge = _qualityOptionBadge(quality);
    final bitrate = quality.bitrate > 0
        ? ' ${(quality.bitrate / 1000000).toStringAsFixed(0)} Mbps'
        : '';
    final suffix = badge.isEmpty ? '' : ' $badge';
    return '正在为您切换至 $title$bitrate$suffix 画质，请稍等...';
  }

  // ignore: unused_element
  String _resolvePlayableUrl(String pathOrUrl) {
    final raw = pathOrUrl.trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }
    final nasProvider = _nasProvider ?? context.read<NasProvider>();
    return ApiUrlHelper.apiUrl(nasProvider.baseUrl, raw);
  }

  Future<bool> _applySubtitleSelection() async {
    final normalizedGuid = (_currentSubtitleGuid ?? '').trim();
    var selected = _syncCurrentSubtitleTrackSelection();
    if (normalizedGuid.isEmpty) {
      _pendingExternalSubtitlePath = null;
      _releaseSubtitleProxySession();
      await _controller.setSubtitleTrack(trackIndex: null, trackGuid: null);
      return true;
    }
    if (selected == null) {
      // Track list not ready yet, keep pending refresh.
      return false;
    }
    if (_subtitleShouldUseExternalFile(selected)) {
      final subtitleForFile = selected;
      var path = await _ensureSubtitleFile(subtitleForFile);
      if (!mounted) return false;
      if (path == null) {
        final refreshed = await _refreshSubtitleTracksFromSource(
          preferredGuid: selected.guid,
        );
        if (!mounted) return false;
        if (refreshed != null &&
            refreshed.guid == selected.guid &&
            _subtitleShouldUseExternalFile(refreshed)) {
          selected = refreshed;
          path = await _ensureSubtitleFile(refreshed);
        }
      }
      if (!mounted) return false;
      if (path == null) {
        _serverFallbackSubtitleGuids.add(selected.guid);
        final fallbackTrackId = _mpvSubtitleTrackId(selected);
        if (fallbackTrackId != null) {
          await _controller.setSubtitleTrack(
            trackIndex: fallbackTrackId,
            trackGuid: selected.guid,
          );
        }
        return true;
      }
      _serverFallbackSubtitleGuids.remove(subtitleForFile.guid);
      _subtitleFailureNoticeShownGuids.remove(subtitleForFile.guid);
      _pendingExternalSubtitlePath = path;
      _releaseSubtitleProxySession();
      _handlePlayerValueChanged();
      return true;
    }
    _pendingExternalSubtitlePath = null;
    _releaseSubtitleProxySession();
    await _controller.setSubtitleTrack(
      trackIndex: _mpvSubtitleTrackId(selected),
      trackGuid: selected.guid,
    );
    return true;
  }

  Future<String?> _ensureSubtitleFile(SubtitleTrackOption subtitle) async {
    final existing = _subtitleFileByGuid[subtitle.guid];
    if (existing != null && File(existing).existsSync()) return existing;
    if (_subtitleLoading) return existing;

    _subtitleLoading = true;
    try {
      final api = FeiniuApi(context.read<NasProvider>());
      final text = await api.downloadSubtitleText(subtitle.guid);
      if (!mounted || text.trim().isEmpty) return null;
      final filePath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'fly_player_sub_${subtitle.guid}.${_subtitleExtension(subtitle)}';
      final writtenPath = await _writeSubtitleTextToTempFile(
        path: filePath,
        text: text,
      );
      _subtitleFileByGuid[subtitle.guid] = writtenPath;
      _serverFallbackSubtitleGuids.remove(subtitle.guid);
      _subtitleFailureNoticeShownGuids.remove(subtitle.guid);
      return writtenPath;
    } catch (error, stackTrace) {
      debugPrint(
        '[MPV][SUBTITLE] download failed guid=${subtitle.guid} error=$error',
      );
      final appError = AppException.from(
        error,
        action: 'subtitle download',
        fallbackKind: AppExceptionKind.noData,
        stackTrace: stackTrace,
      );
      unawaited(
        AppErrorReporter.report(
          appError,
          action: 'subtitle download',
          source: 'mpv_player_options',
          stackTrace: stackTrace,
          fallbackKind: AppExceptionKind.noData,
          details: 'subtitleGuid=${subtitle.guid}',
        ),
      );
      if (appError.isNoData) {
        if (_subtitleFailureNoticeShownGuids.add(subtitle.guid)) {
          _showTransientMessage('当前字幕文件不可直接获取，已切换兼容方案');
        }
      } else {
        if (_subtitleFailureNoticeShownGuids.add(subtitle.guid)) {
          _showTransientMessage('字幕加载失败: $error');
        }
      }
      return null;
    } finally {
      _subtitleLoading = false;
    }
  }

  String _subtitleExtension(SubtitleTrackOption subtitle) {
    final format = subtitle.format.trim().toLowerCase();
    if (format.isNotEmpty) {
      return format.replaceAll(RegExp(r'[^a-z0-9]+'), '');
    }
    final codec = subtitle.codecName.trim().toLowerCase();
    if (codec.contains('ass')) return 'ass';
    if (codec.contains('srt')) return 'srt';
    return 'ass';
  }
}
