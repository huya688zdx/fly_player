part of mpv_player_page;

extension _MpvPlayerEpisodeMixin on _MpvPlayerPageState {
  Future<void> _showEpisodeSheet() async {
    final episodes = await _ensureEpisodeItems();
    if (!mounted || episodes.length <= 1) return;

    _overlayState.cancelAutoHide();
    final restoreControls = _controlsVisible;
    if (restoreControls) {
      _hideControlsImmediately();
    }
    final provider = context.read<NasProvider>();
    final playbackState = _episodePickerPlaybackState();
    try {
      final result = await EpisodePickerSheet.show(
        context,
        title: 'Episode Picker',
        sectionLabel: buildEpisodePickerSectionLabel(episodes),
        autoPlayEnabled: _autoPlayEnabled,
        onAutoPlayChanged: (value) => unawaited(_setAutoPlayEnabled(value)),
        baseUrl: provider.baseUrl,
        token: provider.token,
        items: episodes
            .map(
              (episode) => buildEpisodePickerSheetItem(
                episode,
                playbackState: playbackState,
              ),
            )
            .toList(),
        selectedId: _currentItemGuid,
      );
      if (!mounted || result == null || result == _currentItemGuid) return;

      final selected = episodes.cast<MediaLibraryItem?>().firstWhere(
        (episode) => episode?.guid == result,
        orElse: () => null,
      );
      if (selected == null) return;
      await _switchToEpisode(selected);
    } finally {
      if (mounted && restoreControls) {
        _showControls();
      }
    }
  }

  Future<void> _showNextEpisode() async {
    final nextEpisode = await _nextEpisodeOrNull();
    if (nextEpisode == null) {
      _showTransientMessage('Already at the last episode');
      return;
    }
    await _switchToEpisode(nextEpisode);
  }

  Future<void> _showPreviousEpisode() async {
    final previousEpisode = await _previousEpisodeOrNull();
    if (previousEpisode == null) {
      _showTransientMessage('Already at the first episode');
      return;
    }
    await _switchToEpisode(previousEpisode);
  }

  Future<MediaLibraryItem?> _nextEpisodeOrNull() async {
    final episodes = await _ensureEpisodeItems();
    if (!mounted || episodes.isEmpty) return null;

    final currentIndex = episodes.indexWhere(
      (episode) => episode.guid == _currentItemGuid,
    );
    if (currentIndex < 0 || currentIndex + 1 >= episodes.length) {
      return null;
    }
    return episodes[currentIndex + 1];
  }

  Future<MediaLibraryItem?> _previousEpisodeOrNull() async {
    final episodes = await _ensureEpisodeItems();
    if (!mounted || episodes.isEmpty) return null;

    final currentIndex = episodes.indexWhere(
      (episode) => episode.guid == _currentItemGuid,
    );
    if (currentIndex <= 0) {
      return null;
    }
    return episodes[currentIndex - 1];
  }

  bool _hasNextEpisodeInLoadedItems() {
    if (_episodeItems.isEmpty) return true;
    final currentIndex = _episodeItems.indexWhere(
      (episode) => episode.guid == _currentItemGuid,
    );
    if (currentIndex < 0) return true;
    return currentIndex + 1 < _episodeItems.length;
  }

  bool _hasPreviousEpisodeInLoadedItems() {
    if (_episodeItems.isEmpty) return _currentEpisodeNumber > 1;
    final currentIndex = _episodeItems.indexWhere(
      (episode) => episode.guid == _currentItemGuid,
    );
    if (currentIndex < 0) return _currentEpisodeNumber > 1;
    return currentIndex > 0;
  }

  bool _shouldShowEpisodeEntry() {
    if (_episodeItems.length > 1) return true;
    if (_episodeItems.length == 1) return false;
    if (_episodeListLoading) return true;
    if (_currentSeasonGuid.trim().isNotEmpty) return true;
    if (widget.source.seasonGuid.trim().isNotEmpty) return true;
    if (_currentEpisodeNumber > 0) return true;
    if (widget.source.episodeNumber > 0) return true;
    return false;
  }

  Future<List<MediaLibraryItem>> _ensureEpisodeItems() async {
    if (_episodeItems.isNotEmpty) return _episodeItems;
    if (_episodeListLoading) return _episodeItems;

    final seasonGuid = await _resolveSeasonGuid();
    if (!mounted || seasonGuid.isEmpty) {
      _showTransientMessage(
        'No episode list is available for the current item',
      );
      return const <MediaLibraryItem>[];
    }

    _episodeListLoading = true;
    try {
      final api = FeiniuApi(context.read<NasProvider>());
      final items = await api.getEpisodeList(seasonGuid);
      items.sort((a, b) {
        final byEpisode = _episodeSortOrder(a).compareTo(_episodeSortOrder(b));
        if (byEpisode != 0) return byEpisode;
        return a.guid.compareTo(b.guid);
      });
      if (!mounted) return items;

      String? currentPoster;
      for (final item in items) {
        if (item.guid == _currentItemGuid) {
          currentPoster = item.poster.trim();
          break;
        }
      }

      _updatePlayerState(() {
        _currentSeasonGuid = seasonGuid;
        _episodeItems = items;
        if ((currentPoster ?? '').isNotEmpty) {
          _currentPosterPath = currentPoster!;
        }
      });
      return items;
    } catch (error) {
      if (mounted) {
        _showTransientMessage('Failed to load episode list: $error');
      }
      return const <MediaLibraryItem>[];
    } finally {
      _episodeListLoading = false;
    }
  }

  int _episodeSortOrder(MediaLibraryItem item) {
    if (item.episodeNumber > 0) return item.episodeNumber;
    if (item.numberOfItem > 0) return item.numberOfItem;
    return 1 << 20;
  }

  Future<String> _resolveSeasonGuid() async {
    final existing = _currentSeasonGuid.trim();
    if (existing.isNotEmpty) return existing;
    try {
      final api = FeiniuApi(context.read<NasProvider>());
      final detail = await api.getItemDetail(_currentItemGuid);
      final seasonGuid = (detail['parent_guid'] ?? '').toString().trim();
      if (mounted && seasonGuid.isNotEmpty) {
        _updatePlayerState(() => _currentSeasonGuid = seasonGuid);
      }
      return seasonGuid;
    } catch (error, stackTrace) {
      unawaited(
        AppErrorReporter.report(
          error,
          action: 'resolve season guid',
          source: 'mpv_player_episode',
          stackTrace: stackTrace,
          fallbackKind: AppExceptionKind.noData,
          level: AppLogLevel.warning,
          details: 'itemGuid=$_currentItemGuid',
        ),
      );
      return '';
    }
  }

  EpisodePickerPlaybackState _episodePickerPlaybackState() {
    final value = _controller.value.value;
    final position = _displayPosition(value);
    final durationSeconds = _durationSeconds > 0
        ? _durationSeconds
        : value.duration.inSeconds;
    return EpisodePickerPlaybackState(
      currentItemGuid: _currentItemGuid,
      isPlaying: !value.paused,
      currentPositionSeconds: position.inSeconds,
      currentDurationSeconds: durationSeconds,
    );
  }

  String _playerTitleForItem(PlayItem item) {
    return formatPlayerTitleFromPlayItem(item, fallbackTitle: _currentTitle);
  }

  PlaybackQualityOption? _matchPreferredQuality(
    List<PlaybackQualityOption> qualities,
  ) {
    if (qualities.isEmpty) return null;
    PlaybackQualityOption? exactDirectLinkQuality;
    PlaybackQualityOption? exactMediaAndVideo;
    PlaybackQualityOption? exactResolutionAndBitrate;
    PlaybackQualityOption? exactResolution;
    for (final quality in qualities) {
      if (_currentDirectLinkQualityIndex != null &&
          quality.directLinkQualityIndex == _currentDirectLinkQualityIndex) {
        exactDirectLinkQuality = quality;
      }
      final matchesMedia =
          _currentMediaGuid.trim().isNotEmpty &&
          quality.mediaGuid.trim() == _currentMediaGuid.trim();
      final matchesVideo =
          _currentVideoGuid.trim().isNotEmpty &&
          quality.videoGuid.trim() == _currentVideoGuid.trim();
      final matchesResolution =
          _currentResolution.isNotEmpty &&
          _normalizeQualityResolution(quality.resolution) ==
              _normalizeQualityResolution(_currentResolution);
      final matchesBitrate =
          _currentBitrate > 0 && quality.bitrate == _currentBitrate;
      if (matchesMedia && matchesVideo) {
        exactMediaAndVideo = quality;
      }
      if (matchesResolution && matchesBitrate) {
        exactResolutionAndBitrate = quality;
      }
      if (matchesResolution) {
        exactResolution = quality;
      }
    }
    if (exactDirectLinkQuality != null) return exactDirectLinkQuality;
    if (exactMediaAndVideo != null) return exactMediaAndVideo;
    if (exactResolutionAndBitrate != null) return exactResolutionAndBitrate;
    if (exactResolution != null) return exactResolution;
    for (final quality in qualities) {
      if (quality.isDefault == 1) return quality;
    }
    return qualities.first;
  }

  PlaybackQualityOption? _preferredQualityForEpisodeSwitch(
    List<PlaybackQualityOption> qualities,
  ) {
    if (qualities.isEmpty) return null;
    if (_playbackMode.isServerManaged || _playbackMode.isDirectLink) {
      return _matchPreferredQuality(qualities);
    }
    return PlayerSourceController.preferredInitialQuality(qualities);
  }

  String _pickEpisodeBaseMediaGuid({
    required PlayInfoData info,
    required StreamTrackData? trackData,
  }) {
    final infoMediaGuid = info.mediaGuid.trim();
    if (infoMediaGuid.isNotEmpty) return infoMediaGuid;

    final options = trackData?.options ?? const [];
    if (options.isEmpty) return '';

    for (final option in options) {
      if (_currentResolution.isNotEmpty &&
          option.resolutionType.trim() == _currentResolution) {
        return option.mediaGuid.trim();
      }
    }
    return options.first.mediaGuid.trim();
  }

  String _normalizeEpisodeTrackText(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _normalizeEpisodeSubtitleFormat(SubtitleTrackOption track) {
    return _normalizeEpisodeTrackText(
      track.format.isNotEmpty ? track.format : track.codecName,
    );
  }

  int _episodeSubtitleMatchScore(
    SubtitleTrackOption candidate,
    SubtitleTrackOption current,
  ) {
    var score = 0;
    if (candidate.index == current.index) score += 32;
    if (candidate.isExternal == current.isExternal) score += 24;
    if (candidate.extraFile == current.extraFile) score += 18;
    if (_normalizeEpisodeTrackText(candidate.language) ==
        _normalizeEpisodeTrackText(current.language)) {
      score += 20;
    }
    if (_normalizeEpisodeSubtitleFormat(candidate) ==
        _normalizeEpisodeSubtitleFormat(current)) {
      score += 10;
    }
    if (_normalizeEpisodeTrackText(candidate.title) ==
        _normalizeEpisodeTrackText(current.title)) {
      score += 8;
    }
    if (candidate.forced == current.forced) score += 4;
    if (candidate.isBitmap == current.isBitmap) score += 2;
    if (candidate.isDefaultOption && current.isDefaultOption) score += 1;
    return score;
  }

  String? _pickEpisodeSubtitleGuid({
    required String? preferredGuid,
    required List<SubtitleTrackOption> tracks,
  }) {
    final normalizedPreferred = preferredGuid?.trim() ?? '';
    if (normalizedPreferred.isEmpty) return '';
    for (final track in tracks) {
      if (track.guid == normalizedPreferred) {
        return normalizedPreferred;
      }
    }

    final currentTrack = _currentSubtitleTrack();
    if (currentTrack != null) {
      SubtitleTrackOption? best;
      var bestScore = -1;
      for (final candidate in tracks) {
        final score = _episodeSubtitleMatchScore(candidate, currentTrack);
        if (score <= bestScore) continue;
        best = candidate;
        bestScore = score;
      }
      if (best != null && bestScore > 0) {
        return best.guid;
      }
    }

    for (final track in tracks) {
      if (track.isDefaultOption) return track.guid;
    }
    return tracks.isNotEmpty ? tracks.first.guid : '';
  }

  String _episodeSwitchLoadingMessage(MediaLibraryItem episode) {
    final episodeLabel = episode.episodeNumber > 0
        ? 'Episode ${episode.episodeNumber}'
        : episode.title.trim();
    if (episodeLabel.isEmpty) {
      return 'Preparing playback...';
    }
    return 'Switching to $episodeLabel...';
  }

  Future<void> _switchToEpisode(
    MediaLibraryItem episode, {
    bool fromAutoPlay = false,
  }) async {
    if (episode.guid.trim().isEmpty || episode.guid == _currentItemGuid) return;
    _invalidateReturnDetailPrefetch();

    final api = FeiniuApi(context.read<NasProvider>());
    final shouldResumePlayback =
        fromAutoPlay || !_controller.value.value.paused;
    final currentPosition = _displayPosition(_controller.value.value);
    _updatePlayerState(() => _uiController.qualitySwitchLoading = true);
    _uiController.pendingLoadingTransition = true;
    _markAwaitingVisualPlaybackStart(
      currentPosition,
      targetPaused: !shouldResumePlayback,
    );
    _showSubtitleSwitchMessage(_episodeSwitchLoadingMessage(episode));
    var reloadStarted = false;
    try {
      await _submitPlaybackRecord(force: true);

      final info = await api.getPlayInfo(episode.guid);
      final trackData = await api.getStreamTrackData(episode.guid);
      final baseMediaGuid = _pickEpisodeBaseMediaGuid(
        info: info,
        trackData: trackData,
      );
      if (baseMediaGuid.isEmpty) {
        throw const AppException(
          kind: AppExceptionKind.fatal,
          action: 'switch episode',
          message: 'missing media guid',
        );
      }

      final initialStream = await api.getPlaybackStream(baseMediaGuid);
      final initialQualities = mergePlaybackQualitiesWithStreamTrackData(
        initialStream.qualities,
        trackData,
      );
      final preferredQuality = _preferredQualityForEpisodeSwitch(
        initialQualities,
      );
      final targetMediaGuid =
          preferredQuality?.mediaGuid.trim().isNotEmpty == true
          ? preferredQuality!.mediaGuid.trim()
          : baseMediaGuid;
      final playbackStream = targetMediaGuid == baseMediaGuid
          ? initialStream
          : await api.getPlaybackStream(targetMediaGuid);
      final mergedQualities = mergePlaybackQualitiesWithStreamTrackData(
        playbackStream.qualities,
        trackData,
      );
      final subtitlePlaybackStream = baseMediaGuid == targetMediaGuid
          ? playbackStream
          : await api.getPlaybackStream(baseMediaGuid);
      final mergedSubtitleTracks = PlayDetailTrackSelector.mergeSubtitleTracks(
        primaryTracks: subtitlePlaybackStream.subtitleStreams,
        extraTracks: trackData.subtitlesForMedia(baseMediaGuid),
      );
      final streamUrl = api.getStreamUrl(targetMediaGuid);
      if (streamUrl.trim().isEmpty) {
        throw const AppException(
          kind: AppExceptionKind.fatal,
          action: 'switch episode',
          message: 'missing stream url',
        );
      }

      final selectedAudioGuid = _pickAudioGuid(
        preferredGuid: _normalizedAudioGuid() ?? info.audioGuid,
        tracks: playbackStream.audioStreams,
      );
      final selectedSubtitleGuid = _pickEpisodeSubtitleGuid(
        preferredGuid: _normalizedSubtitleGuid() ?? info.subtitleGuid,
        tracks: mergedSubtitleTracks,
      );
      final selectedAudio = _audioTrackByGuid(
        selectedAudioGuid,
        playbackStream.audioStreams,
      );

      final oldSessionId = _activeProxySessionId;
      final oldSubtitleSessionId = _activeSubtitleProxySessionId;
      final seasonGuid = _currentSeasonGuid;
      final sourceTs = info.ts > 0 ? info.ts : info.item.watchedTs;
      final durationSeconds = info.item.duration > 0
          ? info.item.duration
          : episode.duration;
      final rawResumeStartPosition = Duration(
        seconds: durationSeconds > 0
            ? sourceTs.clamp(0, durationSeconds)
            : sourceTs,
      );
      final shouldPromptForAutoPlay =
          fromAutoPlay &&
          _completionController.isProgressFullyWatched(
            startPosition: rawResumeStartPosition,
            durationSeconds: durationSeconds,
          );
      final resumeStartPosition = shouldPromptForAutoPlay
          ? Duration.zero
          : _completionController.normalizedStartPosition(
              startPosition: rawResumeStartPosition,
              durationSeconds: durationSeconds,
            );
      final initialPlayback = await const PlayerSourceController()
          .buildInitialPlaybackResult(
            api: api,
            directUrl: streamUrl,
            mediaGuid: targetMediaGuid,
            videoGuid:
                playbackStream.videoStream?.guid.trim().isNotEmpty == true
                ? playbackStream.videoStream!.guid.trim()
                : preferredQuality?.videoGuid ?? info.videoGuid.trim(),
            playbackStream: playbackStream,
            quality: preferredQuality,
            selectedAudio: selectedAudio,
            startPosition: resumeStartPosition,
          );
      final playableSource = initialPlayback.playableSource;
      final resolvedResumeStartPosition =
          !playableSource.reliableSeek && resumeStartPosition > Duration.zero
          ? Duration.zero
          : resumeStartPosition;
      final resolvedMediaGuid = initialPlayback.playbackMode.isServerManaged
          ? targetMediaGuid
          : initialPlayback.mediaGuid;
      final resolvedVideoGuid =
          initialPlayback.playbackMode.isServerManaged ||
              initialPlayback.playbackMode.isDirectLink
          ? (preferredQuality?.videoGuid.trim().isNotEmpty == true
                ? preferredQuality!.videoGuid.trim()
                : initialPlayback.videoGuid)
          : initialPlayback.videoGuid;
      final resolvedResolution =
          initialPlayback.playbackMode.isServerManaged ||
              initialPlayback.playbackMode.isDirectLink
          ? (preferredQuality?.resolution.trim().isNotEmpty == true
                ? preferredQuality!.resolution.trim()
                : (playbackStream.videoStream?.resolutionType
                              .trim()
                              .isNotEmpty ==
                          true
                      ? playbackStream.videoStream!.resolutionType.trim()
                      : ''))
          : (playbackStream.videoStream?.resolutionType.trim().isNotEmpty ==
                    true
                ? playbackStream.videoStream!.resolutionType.trim()
                : preferredQuality?.resolution ?? '');
      final resolvedBitrate =
          initialPlayback.playbackMode.isServerManaged ||
              initialPlayback.playbackMode.isDirectLink
          ? (preferredQuality?.bitrate ?? playbackStream.videoStream?.bps ?? 0)
          : (playbackStream.videoStream?.bps ?? preferredQuality?.bitrate ?? 0);

      if (fromAutoPlay) {
        _completionController.cancelAutoPlayPrompt(notify: false);
      } else {
        _completionController.clear();
      }
      _updatePlayerState(() {
        _serverFallbackSubtitleGuids.clear();
        _subtitleFailureNoticeShownGuids.clear();
        _currentItemGuid = episode.guid;
        _currentTitle = _playerTitleForItem(info.item);
        _currentSeasonGuid = seasonGuid;
        _currentEpisodeNumber = info.item.episodeNumber > 0
            ? info.item.episodeNumber
            : episode.episodeNumber;
        _currentPosterPath = episode.poster.trim();
        _activeProxySessionId = playableSource.proxySessionId;
        _activeSubtitleProxySessionId = null;
        _currentPlayLink = initialPlayback.playLink;
        _currentUrl = playableSource.url;
        _currentHeaders = playableSource.headers;
        _currentReliableSeek = playableSource.reliableSeek;
        _currentSeekProbeSummary = playableSource.seekProbeSummary;
        _currentMediaGuid = resolvedMediaGuid;
        _subtitleSourceMediaGuid = baseMediaGuid;
        _currentVideoGuid = resolvedVideoGuid;
        _currentDirectLinkQualityIndex =
            initialPlayback.playbackMode.isDirectLink
            ? preferredQuality?.directLinkQualityIndex
            : null;
        _currentVideoWidth = playbackStream.videoStream?.width ?? 0;
        _currentVideoHeight = playbackStream.videoStream?.height ?? 0;
        _currentVideoCodecName = playbackStream.videoStream?.codecName ?? '';
        _currentVideoProfile = playbackStream.videoStream?.profile ?? '';
        _currentColorSpace = playbackStream.videoStream?.colorSpace ?? '';
        _currentColorTransfer = playbackStream.videoStream?.colorTransfer ?? '';
        _currentColorPrimaries =
            playbackStream.videoStream?.colorPrimaries ?? '';
        _currentBitDepth = playbackStream.videoStream?.bitDepth ?? 0;
        _currentResolution = resolvedResolution;
        _currentBitrate = resolvedBitrate;
        _durationSeconds = durationSeconds;
        _audioTracks = playbackStream.audioStreams;
        _subtitleTracks = mergedSubtitleTracks;
        _qualities = mergedQualities;
        _currentAudioGuid = selectedAudio?.guid;
        _currentSubtitleGuid = selectedSubtitleGuid;
        _subtitleExplicitlyDisabled = false;
        _pendingExternalSubtitlePath = null;
        _playbackMode = initialPlayback.playbackMode;
        _pendingSubtitleSelectionRefresh = true;
        _pendingReloadAutoplayRefresh =
            shouldResumePlayback && !shouldPromptForAutoPlay;
        _watchedMarkedForCurrentItem = false;
        _resumeStartPosition = resolvedResumeStartPosition;
        _uiController.lastRecordedSecond = -1;
      });
      unawaited(_loadIntroOutroConfigForItem(episode.guid));
      if (shouldPromptForAutoPlay) {
        _completionController.requestPauseAfterReadyForAutoPlayPrompt();
      }
      _gestureController.resetSeekTracking();
      _overlayState.setResumePromptVisible(
        _shouldShowResumePrompt(
          startPosition: resolvedResumeStartPosition,
          durationSeconds: durationSeconds,
        ),
      );
      unawaited(_prefetchReturnDetailDataIfNeeded());

      if (oldSessionId != null &&
          oldSessionId.isNotEmpty &&
          oldSessionId != playableSource.proxySessionId) {
        _scheduleProxySessionRelease(oldSessionId);
      }
      if (oldSubtitleSessionId != null && oldSubtitleSessionId.isNotEmpty) {
        _scheduleProxySessionRelease(oldSubtitleSessionId);
      }

      final source = _buildCurrentSource(
        startPosition: resolvedResumeStartPosition,
        loadNonce: _issueNextLoadNonce(),
      );
      _markAwaitingVisualPlaybackStart(
        source.startPosition,
        targetPaused: shouldPromptForAutoPlay ? true : !shouldResumePlayback,
      );
      _controller.prepareForSourceLoad(
        source,
        paused: shouldPromptForAutoPlay ? true : !shouldResumePlayback,
      );
      await _controller.reload(source);
      reloadStarted = true;
      _showControls();
    } catch (error) {
      _showTransientMessage('鍒囨崲鍓ч泦澶辫触: $error');
    } finally {
      if (!reloadStarted) {
        _cancelPendingLoadingTransition();
      }
    }
  }
}
