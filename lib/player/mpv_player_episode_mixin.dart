part of 'mpv_player_page.dart';

extension _MpvPlayerEpisodeMixin on _MpvPlayerPageState {
  Future<void> _showEpisodeSheet() async {
    final episodes = await _ensureEpisodeItems();
    if (!mounted || episodes.isEmpty) return;

    final provider = context.read<NasProvider>();
    final playbackState = _episodePickerPlaybackState();
    final result = await EpisodePickerSheet.show(
      context,
      title: '选集',
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
  }

  Future<void> _showNextEpisode() async {
    final nextEpisode = await _nextEpisodeOrNull();
    if (nextEpisode == null) {
      _showTransientMessage('当前已经是最后一集');
      return;
    }
    await _switchToEpisode(nextEpisode);
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

  bool _hasNextEpisodeInLoadedItems() {
    if (_episodeItems.isEmpty) return true;
    final currentIndex = _episodeItems.indexWhere(
      (episode) => episode.guid == _currentItemGuid,
    );
    if (currentIndex < 0) return true;
    return currentIndex + 1 < _episodeItems.length;
  }

  Future<List<MediaLibraryItem>> _ensureEpisodeItems() async {
    if (_episodeItems.isNotEmpty) return _episodeItems;
    if (_episodeListLoading) return _episodeItems;

    final seasonGuid = await _resolveSeasonGuid();
    if (!mounted || seasonGuid.isEmpty) {
      _showTransientMessage('当前内容没有可用的选集信息');
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
        _showTransientMessage('获取选集失败: $error');
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
    } catch (_) {
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
    final seriesTitle = item.displayTitle.trim();
    final episodeTitle = item.title.trim();
    if (seriesTitle.isNotEmpty &&
        episodeTitle.isNotEmpty &&
        seriesTitle != episodeTitle) {
      return '$seriesTitle $episodeTitle';
    }
    if (episodeTitle.isNotEmpty) return episodeTitle;
    if (seriesTitle.isNotEmpty) return seriesTitle;
    return _currentTitle;
  }

  PlaybackQualityOption? _matchPreferredQuality(
    List<PlaybackQualityOption> qualities,
  ) {
    if (qualities.isEmpty) return null;
    for (final quality in qualities) {
      if (_currentResolution.isNotEmpty &&
          quality.resolution.trim() == _currentResolution) {
        return quality;
      }
    }
    for (final quality in qualities) {
      if (quality.isDefault == 1) return quality;
    }
    return qualities.first;
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

  Future<void> _switchToEpisode(
    MediaLibraryItem episode, {
    bool fromAutoPlay = false,
  }) async {
    if (episode.guid.trim().isEmpty || episode.guid == _currentItemGuid) return;

    final api = FeiniuApi(context.read<NasProvider>());
    final shouldResumePlayback =
        fromAutoPlay || !_controller.value.value.paused;
    try {
      await _submitPlaybackRecord(force: true);

      final info = await api.getPlayInfo(episode.guid);
      final trackData = await api.getStreamTrackData(episode.guid);
      final baseMediaGuid = _pickEpisodeBaseMediaGuid(
        info: info,
        trackData: trackData,
      );
      if (baseMediaGuid.isEmpty) {
        throw Exception('missing media guid');
      }

      final initialStream = await api.getPlaybackStream(baseMediaGuid);
      final preferredQuality = _matchPreferredQuality(initialStream.qualities);
      final targetMediaGuid =
          preferredQuality?.mediaGuid.trim().isNotEmpty == true
          ? preferredQuality!.mediaGuid.trim()
          : baseMediaGuid;
      final playbackStream = targetMediaGuid == baseMediaGuid
          ? initialStream
          : await api.getPlaybackStream(targetMediaGuid);
      final mergedSubtitleTracks = PlayDetailTrackSelector.mergeSubtitleTracks(
        primaryTracks: playbackStream.subtitleStreams,
        extraTracks: trackData.subtitlesForMedia(targetMediaGuid),
      );
      final streamUrl = api.getStreamUrl(targetMediaGuid);
      if (streamUrl.trim().isEmpty) {
        throw Exception('missing stream url');
      }

      final selectedAudioGuid = _pickAudioGuid(
        preferredGuid: _normalizedAudioGuid() ?? info.audioGuid,
        tracks: playbackStream.audioStreams,
      );
      final selectedSubtitleGuid = _pickSubtitleGuid(
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
            quality: preferredQuality,
            selectedAudio: selectedAudio,
            startPosition: resumeStartPosition,
          );
      final playableSource = initialPlayback.playableSource;
      final resolvedResumeStartPosition =
          !playableSource.reliableSeek && resumeStartPosition > Duration.zero
          ? Duration.zero
          : resumeStartPosition;

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
        _currentMediaGuid = initialPlayback.mediaGuid;
        _subtitleSourceMediaGuid = baseMediaGuid;
        _currentVideoGuid = initialPlayback.videoGuid;
        _currentVideoWidth = playbackStream.videoStream?.width ?? 0;
        _currentVideoHeight = playbackStream.videoStream?.height ?? 0;
        _currentVideoCodecName = playbackStream.videoStream?.codecName ?? '';
        _currentVideoProfile = playbackStream.videoStream?.profile ?? '';
        _currentColorSpace = playbackStream.videoStream?.colorSpace ?? '';
        _currentColorTransfer = playbackStream.videoStream?.colorTransfer ?? '';
        _currentColorPrimaries =
            playbackStream.videoStream?.colorPrimaries ?? '';
        _currentBitDepth = playbackStream.videoStream?.bitDepth ?? 0;
        _currentResolution =
            playbackStream.videoStream?.resolutionType.trim().isNotEmpty == true
            ? playbackStream.videoStream!.resolutionType.trim()
            : preferredQuality?.resolution ?? '';
        _currentBitrate =
            playbackStream.videoStream?.bps ?? preferredQuality?.bitrate ?? 0;
        _durationSeconds = durationSeconds;
        _audioTracks = playbackStream.audioStreams;
        _subtitleTracks = mergedSubtitleTracks;
        _qualities = playbackStream.qualities;
        _currentAudioGuid = selectedAudio?.guid;
        _currentSubtitleGuid = selectedSubtitleGuid;
        _pendingExternalSubtitlePath = null;
        _serverPlaybackManaged = initialPlayback.serverPlaybackManaged;
        _pendingSubtitleSelectionRefresh = true;
        _pendingReloadAutoplayRefresh =
            shouldResumePlayback && !shouldPromptForAutoPlay;
        _watchedMarkedForCurrentItem = false;
        _resumeStartPosition = resolvedResumeStartPosition;
        _lastRecordedSecond = -1;
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
      );
      _controller.prepareForSourceLoad(
        source,
        paused: shouldPromptForAutoPlay ? true : !shouldResumePlayback,
      );
      await _controller.reload(source);
      _showControls();
    } catch (error) {
      _showTransientMessage('切换剧集失败: $error');
    }
  }
}
