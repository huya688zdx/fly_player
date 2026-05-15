part of '../../mpv_player_page.dart';

const Duration _downloadedPlaybackMetadataLookupTimeout = Duration(
  milliseconds: 700,
);

extension _MpvPlayerOptionsMixin on _MpvPlayerPageState {
  bool _isDirectPlaybackQuality(PlaybackQualityOption quality) {
    return !quality.isServerSession;
  }

  void _toggleSpeedDialOverlay() {
    if (_playerUiLocked) return;
    if (_speedDialVisible) {
      _hideSpeedDialOverlay();
      return;
    }
    _showSpeedDialOverlay();
  }

  Future<void> _showSpeedDialOverlay() async {
    if (_playerUiLocked) return;
    if (_speedDialVisible || !mounted) return;
    _overlayState.cancelAutoHide();
    final restoreControls = _controlsVisible || _controlsAnimatingOut;
    if (restoreControls) {
      _hideControlsImmediately();
    }

    _updatePlayerState(() {
      _speedDialVisible = true;
    });
  }

  void _hideSpeedDialOverlay({bool restoreAutoHide = true}) {
    if (!_speedDialVisible) return;
    if (mounted) {
      _updatePlayerState(() => _speedDialVisible = false);
    } else {
      _speedDialVisible = false;
    }
    if (!restoreAutoHide) return;
    _scheduleControlsAutoHide();
  }

  void _applyPlaybackSpeed(double speed, {bool triggerHaptics = false}) {
    final normalized = PlayerSpeedDialScale.normalizeSpeed(speed);
    if ((normalized - _playbackSpeed).abs() < 0.001) return;
    if (triggerHaptics) {
      if (PlayerSpeedDialScale.isKeySpeed(normalized)) {
        unawaited(HapticFeedback.mediumImpact());
      } else {
        unawaited(HapticFeedback.selectionClick());
      }
    }
    _updatePlayerState(() => _playbackSpeed = normalized);
    unawaited(_controller.setSpeed(normalized));
    unawaited(_syncNativeDanmakuRenderer());
    if (_speedDialVisible) {
      _overlayState.cancelAutoHide();
      return;
    }
    _showControls();
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
    if (_playerUiLocked) return null;
    _hideSpeedDialOverlay(restoreAutoHide: false);
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
      if (mounted && !restoreControls) {
        _scheduleControlsAutoHide();
      }
    }
    return result;
  }

  void _handleSpeedDialSpeedChanged(double speed) {
    _applyPlaybackSpeed(speed, triggerHaptics: true);
  }

  Future<void> _showAudioSheet() async {
    await _showAudioDrawer();
  }

  Future<void> _showSubtitleSheet() async {
    await _showSubtitleDrawer();
  }

  Future<void> _showQualitySheet() async {
    if (_externalLocalSource) return;
    final visibleQualities = _displayQualityOptionsForCurrentMode();
    if (visibleQualities.isEmpty) {
      _showTransientMessage(
        AppLocalizations.of(context).playerQualityNoAvailableOptions,
      );
      return;
    }

    final result = await _showPlayerOptionSheet(
      title: AppLocalizations.of(context).playerQualitySheetTitle,
      sectionLabel: AppLocalizations.of(context).playerQualitySheetSection,
      items: visibleQualities
          .map(
            (quality) => PlayerOptionSheetItem(
              id: _qualityId(quality),
              title: _qualityDisplayLabel(quality),
              badgeText: _qualityOptionBadge(quality),
              subtitle: _qualityOptionSubtitle(quality),
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
    if (_externalLocalSource) return;
    final l10n = AppLocalizations.of(context);
    _uiController.clearWeakNetworkSuggestionSuppression();
    _uiController.clearWeakNetworkSuggestion();
    final currentQualityMatches =
        quality.mediaGuid == _currentMediaGuid &&
        quality.videoGuid == _currentVideoGuid &&
        quality.resolution == _currentResolution &&
        quality.bitrate == _currentBitrate &&
        quality.directLinkQualityIndex == _currentDirectLinkQualityIndex;
    if (currentQualityMatches) {
      return;
    }

    final currentValue = _controller.value.value;
    final currentPosition = _displayPosition(currentValue);
    final pausedAfterReload = _shouldPauseAfterQualityReload(currentValue);
    _updatePlayerState(() {
      _uiController.qualitySwitchLoading = true;
      _uiController.subtitleSwitchMessage =
          loadingMessage ?? _qualitySwitchPromptFor(quality);
    });
    _uiController.pendingLoadingTransition = true;
    _markAwaitingVisualPlaybackStart(
      currentPosition,
      targetPaused: pausedAfterReload,
    );
    var reloadStarted = false;
    try {
      final localDownloadRecord = _downloadedRecordForQuality(quality);
      if (_currentSourceIsDownloadedFile && localDownloadRecord != null) {
        await _reloadDownloadedLocalQuality(
          localDownloadRecord,
          quality: quality,
          startPosition: currentPosition,
          pausedAfterReload: pausedAfterReload,
        );
      } else if (_isDirectPlaybackQuality(quality)) {
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
      _uiController.allowPlaybackProgressTransitionCompletion = true;
      reloadStarted = true;
      _showControls();
    } catch (error) {
      _showTransientMessage(l10n.playerQualitySwitchFailed('$error'));
    } finally {
      if (!reloadStarted) {
        _cancelPendingLoadingTransition();
      }
    }
  }

  bool _shouldPauseAfterQualityReload(MpvPlayerValue value) {
    if (_uiController.pendingTransitionTargetPaused) {
      return true;
    }
    if (_uiController.pendingLoadingTransition ||
        _uiController.awaitingVisualPlaybackStart ||
        value.isTransientLoadingPhase) {
      return false;
    }
    return value.playbackPhase == MpvPlaybackPhase.paused ||
        (value.paused && value.ready && value.nativeLibLoaded);
  }

  Future<T?> _loadDownloadedPlaybackMetadata<T>(
    Future<T> Function() loader,
  ) async {
    try {
      return await loader().timeout(_downloadedPlaybackMetadataLookupTimeout);
    } catch (_) {
      return null;
    }
  }

  String _qualityOptionSubtitle(PlaybackQualityOption quality) {
    final parts = <String>[];
    if (_downloadedRecordForQuality(quality) != null) {
      parts.add(AppLocalizations.of(context).playerQualityDownloaded);
    }
    return parts.join(' \u00b7 ');
  }

  DownloadTaskRecord? _downloadedRecordForQuality(
    PlaybackQualityOption quality,
  ) {
    return DownloadTaskService.instance.downloadedRecordForItem(
      _currentItemGuid,
      resolution: _qualityLabel(quality),
    );
  }

  Future<void> _reloadDownloadedLocalQuality(
    DownloadTaskRecord record, {
    required PlaybackQualityOption quality,
    Duration? startPosition,
    bool? pausedAfterReload,
  }) async {
    if (_externalLocalSource) return;
    _invalidateNextEpisodePreload();
    final path = record.filePath.trim();
    if (path.isEmpty || !File(path).existsSync()) {
      throw Exception('local downloaded file missing');
    }
    final api = FeiniuApi(context.read<NasProvider>());
    final currentPosition =
        startPosition ?? _displayPosition(_controller.value.value);
    PlayInfoData? playInfo;
    StreamTrackData? trackData;
    final metadataResults = await Future.wait<Object?>([
      _loadDownloadedPlaybackMetadata<PlayInfoData>(
        () => api.getPlayInfo(_currentItemGuid),
      ),
      _loadDownloadedPlaybackMetadata<StreamTrackData>(
        () => api.getStreamTrackData(_currentItemGuid),
      ),
    ]);
    playInfo = metadataResults[0] as PlayInfoData?;
    trackData = metadataResults[1] as StreamTrackData?;
    final resolvedMediaGuid = record.mediaGuid.trim().isNotEmpty
        ? record.mediaGuid.trim()
        : (quality.mediaGuid.trim().isNotEmpty
              ? quality.mediaGuid.trim()
              : _currentMediaGuid);
    final videoInfo = resolvedMediaGuid.isEmpty
        ? null
        : trackData?.videoForMedia(resolvedMediaGuid);
    final fallbackAudioTracks = _audioTracks.isNotEmpty
        ? _audioTracks
        : record.audioTracks;
    final audioTracks = resolvedMediaGuid.isEmpty
        ? fallbackAudioTracks
        : (trackData?.audiosForMedia(resolvedMediaGuid).isNotEmpty == true
              ? trackData!.audiosForMedia(resolvedMediaGuid)
              : fallbackAudioTracks);
    final selectedAudio = PlayDetailTrackSelector.selectedOrFirstAudio(
      selectedAudioGuid: _normalizedAudioGuid(),
      audioTracks: audioTracks,
    );
    final runtimeSubtitleTrack = _currentSubtitleTrack();
    final runtimeSubtitleTrackIndex =
        runtimeSubtitleTrack?.guid.startsWith('mpv-subtitle:') == true &&
            (runtimeSubtitleTrack?.index ?? 0) > 0
        ? runtimeSubtitleTrack!.index
        : null;
    final fallbackSubtitleTracks = _subtitleTracks.isNotEmpty
        ? _subtitleTracks
        : record.subtitleTracks;
    final subtitleTracks = resolvedMediaGuid.isEmpty
        ? fallbackSubtitleTracks
        : (trackData?.subtitlesForMedia(resolvedMediaGuid).isNotEmpty == true
              ? trackData!.subtitlesForMedia(resolvedMediaGuid)
              : fallbackSubtitleTracks);
    final selectedSubtitle = runtimeSubtitleTrackIndex != null
        ? null
        : PlayDetailTrackSelector.selectedOrFirstSubtitle(
            selectedSubtitleGuid: _normalizedSubtitleGuid(),
            subtitleTracks: subtitleTracks,
          );
    final embeddedSubtitleTrackIndex =
        runtimeSubtitleTrackIndex ??
        PlayDetailTrackSelector.embeddedSubtitleTrackIndex(
          selectedSubtitle: selectedSubtitle,
          subtitleTracks: subtitleTracks,
        );
    final durationSeconds = playInfo?.item.duration ?? _durationSeconds;
    final localSource = MpvMediaSource.localFile(
      filePath: path,
      itemGuid: _currentItemGuid,
      seasonGuid: (playInfo?.parentGuid ?? _currentSeasonGuid).trim(),
      posterPath: _currentPosterPath.trim().isNotEmpty
          ? _currentPosterPath.trim()
          : widget.source.posterPath.trim(),
      mediaGuid: resolvedMediaGuid,
      mediaType: playInfo?.item.type ?? _currentMediaType,
      ancestorName: playInfo?.item.ancestorName ?? _currentAncestorName,
      videoGuid: videoInfo?.guid.trim().isNotEmpty == true
          ? videoInfo!.guid.trim()
          : (quality.videoGuid.trim().isNotEmpty
                ? quality.videoGuid.trim()
                : _currentVideoGuid),
      title: playInfo == null
          ? _currentTitle
          : formatPlayerTitleFromPlayItem(
              playInfo.item,
              fallbackTitle: _currentTitle,
            ),
      seriesTitle: (playInfo?.item.tvTitle ?? widget.source.seriesTitle).trim(),
      seasonNumber: playInfo?.item.seasonNumber ?? widget.source.seasonNumber,
      tmdbId: playInfo?.item.trimId ?? widget.source.tmdbId,
      episodeNumber: playInfo?.item.episodeNumber ?? _currentEpisodeNumber,
      startPosition: currentPosition,
      audioTrackGuid: selectedAudio?.guid,
      subtitleTrackIndex: embeddedSubtitleTrackIndex,
      subtitleTrackGuid: _normalizedSubtitleGuid(),
      resolution: record.resolution.trim().isNotEmpty
          ? record.resolution.trim()
          : _qualityLabel(quality),
      bitrate: quality.bitrate,
      durationSeconds: durationSeconds,
      videoWidth: videoInfo?.width ?? _currentVideoWidth,
      videoHeight: videoInfo?.height ?? _currentVideoHeight,
      videoCodecName: videoInfo?.codecName ?? _currentVideoCodecName,
      videoProfile: videoInfo?.profile ?? _currentVideoProfile,
      colorSpace: videoInfo?.colorSpace ?? _currentColorSpace,
      colorTransfer: videoInfo?.colorTransfer ?? _currentColorTransfer,
      colorPrimaries: videoInfo?.colorPrimaries ?? _currentColorPrimaries,
      bitDepth: videoInfo?.bitDepth ?? _currentBitDepth,
      audioTracks: audioTracks,
      subtitleTracks: subtitleTracks,
      qualities: mergePlaybackQualitiesWithStreamTrackData(
        _qualities,
        trackData,
      ),
      playbackSpeed: _playbackSpeed,
    );
    final oldSessionId = _activeProxySessionId;
    final oldSubtitleSessionId = _activeSubtitleProxySessionId;
    _updatePlayerState(() {
      _activeProxySessionId = null;
      _activeSubtitleProxySessionId = null;
      _currentPlayLink = null;
      _currentServerSessionHlsTimeSeconds = 0;
      _currentUrl = localSource.url;
      _currentHeaders = const <String, String>{};
      _currentReliableSeek = true;
      _currentSeekProbeSummary = 'local-download';
      _currentMediaGuid = localSource.mediaGuid;
      _subtitleSourceMediaGuid = localSource.mediaGuid;
      _currentVideoGuid = localSource.videoGuid;
      _currentDirectLinkQualityIndex = null;
      _currentAudioGuid = localSource.audioTrackGuid ?? selectedAudio?.guid;
      _currentSubtitleGuid = localSource.subtitleTrackGuid;
      _currentSeasonGuid = localSource.seasonGuid;
      _currentMediaType = localSource.mediaType;
      _currentAncestorName = localSource.ancestorName;
      _currentTitle = localSource.title;
      _currentEpisodeNumber = localSource.episodeNumber;
      _currentPosterPath = localSource.posterPath;
      _audioTracks = localSource.audioTracks;
      _subtitleTracks = localSource.subtitleTracks;
      _qualities = localSource.qualities;
      _currentVideoWidth = localSource.videoWidth;
      _currentVideoHeight = localSource.videoHeight;
      _currentResolution = localSource.resolution;
      _currentBitrate = localSource.bitrate;
      _currentVideoCodecName = localSource.videoCodecName;
      _currentVideoProfile = localSource.videoProfile;
      _currentColorSpace = localSource.colorSpace;
      _currentColorTransfer = localSource.colorTransfer;
      _currentColorPrimaries = localSource.colorPrimaries;
      _currentBitDepth = localSource.bitDepth;
      _durationSeconds = localSource.durationSeconds;
      _subtitleExplicitlyDisabled = false;
      _pendingExternalSubtitlePath = null;
      _serverFallbackSubtitleGuids.clear();
      _pendingSubtitleSelectionRefresh = true;
      _pendingReloadAutoplayRefresh = true;
      _playbackMode = PlayerPlaybackMode.originalQuality;
    });
    _gestureController.resetSeekTracking();
    unawaited(_prefetchCurrentSubtitleFileIfNeeded());
    if (oldSessionId != null && oldSessionId.isNotEmpty) {
      _scheduleProxySessionRelease(oldSessionId);
    }
    if (oldSubtitleSessionId != null && oldSubtitleSessionId.isNotEmpty) {
      _scheduleProxySessionRelease(oldSubtitleSessionId);
    }
    final source = localSource.copyWith(loadNonce: _issueNextLoadNonce());
    final effectiveSource = source.copyWith(
      startPaused: pausedAfterReload ?? _controller.value.value.paused,
    );
    _markAwaitingVisualPlaybackStart(
      effectiveSource.startPosition,
      targetPaused: pausedAfterReload ?? _controller.value.value.paused,
    );
    _controller.prepareForSourceLoad(
      effectiveSource,
      paused: pausedAfterReload ?? _controller.value.value.paused,
    );
    await _controller.reload(effectiveSource);
  }

  Future<void> _reloadDirectPlayback({
    required PlaybackQualityOption quality,
    Duration? startPosition,
    bool? pausedAfterReload,
  }) async {
    if (_externalLocalSource) return;
    _invalidateNextEpisodePreload();
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
      _currentServerSessionHlsTimeSeconds = 0;
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
    unawaited(_prefetchCurrentSubtitleFileIfNeeded());

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
    final effectiveSource = source.copyWith(
      startPaused: pausedAfterReload ?? _controller.value.value.paused,
    );
    _markAwaitingVisualPlaybackStart(
      effectiveSource.startPosition,
      targetPaused: pausedAfterReload ?? _controller.value.value.paused,
    );
    _controller.prepareForSourceLoad(
      effectiveSource,
      paused: pausedAfterReload ?? _controller.value.value.paused,
    );
    await _controller.reload(effectiveSource);
  }

  Future<void> _reloadServerPlaySession({
    String? audioGuid,
    String? subtitleGuid,
    PlaybackQualityOption? quality,
    Duration? startPosition,
    bool? pausedAfterReload,
    String? pendingExternalSubtitlePath,
  }) async {
    if (_externalLocalSource) return;
    _invalidateNextEpisodePreload();
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
    final normalizedPendingExternalSubtitlePath =
        pendingExternalSubtitlePath?.trim().isNotEmpty == true
        ? pendingExternalSubtitlePath!.trim()
        : null;
    _updatePlayerState(() {
      _activeProxySessionId = result.activeProxySessionId;
      _activeSubtitleProxySessionId = result.activeSubtitleProxySessionId;
      _currentPlayLink = result.currentPlayLink;
      _currentServerSessionHlsTimeSeconds =
          result.currentServerSessionHlsTimeSeconds;
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
      _pendingExternalSubtitlePath = normalizedPendingExternalSubtitlePath;
      _pendingSubtitleSelectionRefresh =
          result.pendingSubtitleSelectionRefresh ||
          normalizedPendingExternalSubtitlePath != null;
      _pendingReloadAutoplayRefresh = true;
      _playbackMode = result.playbackMode;
    });
    _gestureController.resetSeekTracking();
    unawaited(_prefetchCurrentSubtitleFileIfNeeded());

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
    final effectiveSource = source.copyWith(
      startPaused: pausedAfterReload ?? _controller.value.value.paused,
    );
    _markAwaitingVisualPlaybackStart(
      effectiveSource.startPosition,
      targetPaused: pausedAfterReload ?? _controller.value.value.paused,
    );
    _controller.prepareForSourceLoad(
      effectiveSource,
      paused: pausedAfterReload ?? _controller.value.value.paused,
    );
    await _controller.reload(effectiveSource);
  }

  SubtitleTrackOption? _syncCurrentSubtitleTrackSelection() {
    final normalized = _normalizedSubtitleGuid() ?? '';
    if (normalized.isEmpty) return null;
    final localRuntimeSource = _isLocalRuntimeTrackSource();
    bool isAllowedLocalRuntimeGuid(String guid) {
      return guid.startsWith('mpv-subtitle:') || guid.startsWith('local:');
    }

    final selected = _findSubtitleTrack(normalized);
    if (selected != null &&
        (!localRuntimeSource ||
            isAllowedLocalRuntimeGuid(selected.guid.trim()))) {
      return selected;
    }
    SubtitleTrackOption? fallback;
    for (final track in _subtitleTracks) {
      if (localRuntimeSource && !isAllowedLocalRuntimeGuid(track.guid.trim())) {
        continue;
      }
      if (track.isDefaultOption) {
        fallback = track;
        break;
      }
    }
    if (fallback == null) {
      for (final track in _subtitleTracks) {
        if (!localRuntimeSource ||
            isAllowedLocalRuntimeGuid(track.guid.trim())) {
          fallback = track;
          break;
        }
      }
    }
    if (fallback != null && mounted) {
      _updatePlayerState(() => _currentSubtitleGuid = fallback!.guid);
    }
    return fallback;
  }

  Future<SubtitleTrackOption?> _refreshSubtitleTracksFromSource({
    String? preferredGuid,
  }) async {
    if (_externalLocalSource) return null;
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
    unawaited(
      _prefetchCurrentSubtitleFileIfNeeded(preferredGuid: result.selectedGuid),
    );
    return result.selectedTrack;
  }

  Future<void> _prefetchCurrentSubtitleFileIfNeeded({
    String? preferredGuid,
  }) async {
    final guid = (preferredGuid ?? _normalizedSubtitleGuid() ?? '').trim();
    if (guid.isEmpty) return;
    final track = _findSubtitleTrack(guid);
    if (track == null || !_subtitleShouldUseExternalFile(track)) return;
    final path = await _ensureSubtitleFile(track, silent: true);
    if (!mounted || path == null) return;
    final value = _controller.value.value;
    if ((_normalizedSubtitleGuid() ?? '').trim() != guid ||
        _pendingExternalSubtitlePath != null ||
        !_pendingSubtitleSelectionRefresh ||
        !value.nativeLibLoaded ||
        !value.ready) {
      return;
    }
    unawaited(_refreshSubtitleSelectionIfNeeded());
  }

  void _showSubtitleSwitchMessage(String message) {
    _subtitleSwitchOverlayTimer?.cancel();
    if (!mounted) return;
    _updatePlayerState(() => _uiController.subtitleSwitchMessage = message);
  }

  String _qualitySwitchPromptFor(PlaybackQualityOption quality) {
    return AppLocalizations.of(
      context,
    ).playerQualitySwitching(_qualityDisplayLabel(quality), '');
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
    final l10n = AppLocalizations.of(context);
    if (track == null) {
      return l10n.playerSubtitleClosingPleaseWait;
    }
    final title = _subtitleTitle(track);
    final format = (track.format.isNotEmpty ? track.format : track.codecName)
        .trim()
        .toLowerCase();
    final suffix = format.isEmpty ? '' : '($format)';
    return l10n.playerSubtitleSwitchingPleaseWait(title, suffix);
  }

  // ignore: unused_element
  String _qualitySwitchMessageFor(PlaybackQualityOption quality) {
    final badge = _qualityOptionBadge(quality);
    final suffix = badge.isEmpty ? '' : ' $badge';
    return AppLocalizations.of(
      context,
    ).playerQualitySwitching(_qualityDisplayLabel(quality), suffix);
  }

  // ignore: unused_element
  String _resolvePlayableUrl(String pathOrUrl) {
    final raw = pathOrUrl.trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') ||
        raw.startsWith('https://') ||
        raw.startsWith('file://') ||
        raw.startsWith('content://')) {
      return raw;
    }
    final nasProvider = _nasProvider ?? context.read<NasProvider>();
    return ApiUrlHelper.apiUrl(nasProvider.baseUrl, raw);
  }

  Future<bool> _applySubtitleSelection() async {
    _invalidateNextEpisodePreload();
    final localRuntimeSource = _isLocalRuntimeTrackSource();
    final serverManagedRuntimeSource =
        _playbackMode.isServerManaged && !localRuntimeSource;
    var normalizedGuid = (_normalizedSubtitleGuid() ?? '').trim();
    if (normalizedGuid.isEmpty &&
        localRuntimeSource &&
        !_subtitleExplicitlyDisabled) {
      final fallback = _preferredRuntimeSubtitleTrack();
      if (fallback == null) {
        return false;
      }
      normalizedGuid = fallback.guid.trim();
      if (normalizedGuid.isNotEmpty && mounted) {
        _updatePlayerState(() => _currentSubtitleGuid = normalizedGuid);
      }
    }
    var selected = _syncCurrentSubtitleTrackSelection();
    if (normalizedGuid.isEmpty) {
      _pendingExternalSubtitlePath = null;
      _releaseSubtitleProxySession();
      if (serverManagedRuntimeSource) {
        await _reloadServerPlaySession(subtitleGuid: '');
        return true;
      }
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
      if (path == null && !localRuntimeSource) {
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
        if (serverManagedRuntimeSource) {
          _pendingExternalSubtitlePath = null;
          _releaseSubtitleProxySession();
          await _reloadServerPlaySession(subtitleGuid: selected.guid);
          return true;
        }
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
      _releaseSubtitleProxySession();
      if (serverManagedRuntimeSource) {
        await _reloadServerPlaySession(
          subtitleGuid: selected.guid,
          pendingExternalSubtitlePath: path,
        );
        return true;
      }
      _pendingExternalSubtitlePath = path;
      _handlePlayerValueChanged();
      return true;
    }
    if (serverManagedRuntimeSource) {
      _serverFallbackSubtitleGuids.remove(selected.guid);
      _pendingExternalSubtitlePath = null;
      _releaseSubtitleProxySession();
      await _reloadServerPlaySession(subtitleGuid: selected.guid);
      return true;
    }
    if (_subtitleShouldPreferEmbeddedTrack(selected)) {
      _serverFallbackSubtitleGuids.remove(selected.guid);
      _pendingExternalSubtitlePath = null;
      _releaseSubtitleProxySession();
      await _controller.setSubtitleTrack(
        trackIndex: _mpvSubtitleTrackId(selected),
        trackGuid: selected.guid,
      );
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

  SubtitleTrackOption? _preferredRuntimeSubtitleTrack() {
    SubtitleTrackOption? firstAllowedTrack;
    for (final track in _subtitleTracks) {
      final guid = track.guid.trim();
      final allowed =
          guid.startsWith('local:') || guid.startsWith('mpv-subtitle:');
      if (!allowed) {
        continue;
      }
      firstAllowedTrack ??= track;
      if (guid.startsWith('local:') && track.isDefaultOption) {
        return track;
      }
    }
    if (firstAllowedTrack != null) {
      return firstAllowedTrack;
    }
    for (final track in _subtitleTracks) {
      if (track.isDefaultOption) {
        return track;
      }
    }
    return _subtitleTracks.isEmpty ? null : _subtitleTracks.first;
  }

  Future<String?> _ensureSubtitleFile(
    SubtitleTrackOption subtitle, {
    bool silent = false,
  }) async {
    final guid = subtitle.guid.trim();
    final existing = _subtitleFileByGuid[guid];
    if (existing != null && File(existing).existsSync()) return existing;
    if (_isLocalRuntimeTrackSource()) return null;
    if (_subtitleShouldPreferEmbeddedTrack(subtitle)) return null;
    final pending = _subtitleFileRequestByGuid[guid];
    if (pending != null) {
      return pending;
    }
    if (!silent && _subtitleLoading) return existing;

    final request = _downloadSubtitleFile(subtitle, guid: guid, silent: silent);
    _subtitleFileRequestByGuid[guid] = request;
    try {
      return await request;
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
          _showTransientMessage(
            AppLocalizations.of(context).playerSubtitleFileFallbackApplied,
          );
        }
      } else {
        if (_subtitleFailureNoticeShownGuids.add(subtitle.guid)) {
          _showTransientMessage(
            AppLocalizations.of(context).playerSubtitleLoadFailed('$error'),
          );
        }
      }
      return null;
    } finally {
      if (identical(_subtitleFileRequestByGuid[guid], request)) {
        _subtitleFileRequestByGuid.remove(guid);
      }
    }
  }

  Future<String?> _downloadSubtitleFile(
    SubtitleTrackOption subtitle, {
    required String guid,
    required bool silent,
  }) async {
    if (_externalLocalSource) return null;
    if (!silent) {
      _subtitleLoading = true;
    }
    final l10n = AppLocalizations.of(context);
    try {
      final api = FeiniuApi(context.read<NasProvider>());
      final text = await api.downloadSubtitleText(guid);
      if (!mounted || text.trim().isEmpty) return null;
      final filePath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'fly_player_sub_$guid.${_subtitleExtension(subtitle)}';
      final writtenPath = await _writeSubtitleTextToTempFile(
        path: filePath,
        text: text,
      );
      _subtitleFileByGuid[guid] = writtenPath;
      _serverFallbackSubtitleGuids.remove(guid);
      _subtitleFailureNoticeShownGuids.remove(guid);
      return writtenPath;
    } catch (error, stackTrace) {
      debugPrint('[MPV][SUBTITLE] download failed guid=$guid error=$error');
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
          details: 'subtitleGuid=$guid',
        ),
      );
      if (!silent) {
        if (appError.isNoData) {
          if (_subtitleFailureNoticeShownGuids.add(guid)) {
            _showTransientMessage(l10n.playerSubtitleFileFallbackApplied);
          }
        } else {
          if (_subtitleFailureNoticeShownGuids.add(guid)) {
            _showTransientMessage(l10n.playerSubtitleLoadFailed('$error'));
          }
        }
      }
      return null;
    } finally {
      if (!silent) {
        _subtitleLoading = false;
      }
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
