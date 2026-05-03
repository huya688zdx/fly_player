part of '../../mpv_player_page.dart';

extension _MpvPlayerSystemSessionMixin on _MpvPlayerPageState {
  Future<void> _handleSystemPlaybackMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'systemPlay':
        await _controller.play();
        return;
      case 'systemPause':
        await _controller.pause();
        return;
      case 'systemSeekTo':
        final rawArgs = call.arguments;
        if (rawArgs is Map) {
          final rawPosition = rawArgs['positionMs'];
          final positionMs = switch (rawPosition) {
            int value => value,
            num value => value.toInt(),
            _ => int.tryParse('$rawPosition') ?? 0,
          };
          await _seekWithStats(
            Duration(milliseconds: positionMs.clamp(0, 1 << 31)),
            userInitiated: true,
          );
        }
        return;
      case 'systemSkipToPrevious':
        await _showPreviousEpisode();
        return;
      case 'systemSkipToNext':
        await _showNextEpisode();
        return;
      default:
        return;
    }
  }

  Future<void> _startOrUpdateSystemPlaybackSession({
    bool forceStart = false,
    bool force = false,
  }) async {
    if (!Platform.isAndroid || _exitInProgress) {
      return;
    }
    final payload = _buildSystemPlaybackSessionPayload();
    if (payload['title'] case final String title when title.trim().isEmpty) {
      return;
    }
    if (!force && !_shouldPublishSystemPlaybackSessionPayload(payload)) {
      return;
    }
    _lastSystemPlaybackSessionPayload = payload;
    if (!_systemPlaybackSessionStarted || forceStart) {
      _systemPlaybackSessionStarted = true;
      await PlayerSystemSessionBridge.start(payload);
      return;
    }
    await PlayerSystemSessionBridge.update(payload);
  }

  Future<void> _stopSystemPlaybackSession() async {
    if (!Platform.isAndroid || !_systemPlaybackSessionStarted) {
      return;
    }
    _systemPlaybackSessionStarted = false;
    _lastSystemPlaybackSessionPayload = null;
    await PlayerSystemSessionBridge.stop();
  }

  Map<String, Object?> _buildSystemPlaybackSessionPayload({
    bool? isPlayingOverride,
    double? speedOverride,
    bool? readyOverride,
  }) {
    final value = _controller.value.value;
    final position = _displayPosition(value);
    final duration = _effectiveDuration();
    final fallbackTitle = widget.title.trim();
    final title = _currentTitle.trim().isNotEmpty
        ? _currentTitle.trim()
        : fallbackTitle;
    final subtitle = _currentSeriesTitle.trim().isNotEmpty
        ? _currentSeriesTitle.trim()
        : (_currentAncestorName.trim().isNotEmpty
              ? _currentAncestorName.trim()
              : _currentMediaType.trim());
    final hasError = (value.error ?? '').trim().isNotEmpty;
    final safePositionMs = position.inMilliseconds.clamp(0, 1 << 31);
    final safeDurationMs = duration.inMilliseconds.clamp(0, 1 << 31);
    final artworkUrls = _resolveSystemPlaybackArtworkUrls();
    final artworkUrl = artworkUrls.isNotEmpty ? artworkUrls.first : '';
    final artworkHeaders = _resolveSystemPlaybackArtworkHeaders();
    final albumTitle = _resolveSystemPlaybackAlbumTitle();
    final artist = _resolveSystemPlaybackArtist(subtitle);
    final description = _resolveSystemPlaybackDescription();
    final trackCount = _episodeItems.length;
    final launchSource = _buildSystemPlaybackLaunchSource(position);
    final isReady = readyOverride ?? (value.ready && value.nativeLibLoaded);
    final isPlaying =
        isPlayingOverride ??
        (isReady &&
            !hasError &&
            value.playbackPhase == MpvPlaybackPhase.playing);
    final speed = speedOverride ?? (isPlaying ? _playbackSpeed : 0.0);
    return <String, Object?>{
      'itemGuid': _currentItemGuid,
      'title': title,
      'subtitle': subtitle,
      'albumTitle': albumTitle,
      'artist': artist,
      'description': description,
      'mediaType': _currentMediaType.trim(),
      'seasonNumber': _currentSeasonNumber,
      'episodeNumber': _currentEpisodeNumber,
      'trackCount': trackCount,
      'artworkUrl': artworkUrl,
      'artworkUrls': artworkUrls,
      'artworkHeaders': artworkHeaders,
      'isPlaying': isPlaying,
      'positionMs': safePositionMs,
      'durationMs': safeDurationMs,
      'speed': speed,
      'canSeek': safeDurationMs > 0,
      'canPause': true,
      'canPlay': true,
      'canSkipToPrevious': _canSkipToPreviousEpisodeForSystemSession(),
      'canSkipToNext': _canSkipToNextEpisodeForSystemSession(),
      'ready': isReady,
      'error': hasError ? value.error!.trim() : null,
      'launchTitle': title,
      'launchSource': launchSource,
      'launchFromParallelHost': widget.parallelLayoutToggleEnabled,
      'launchLayoutMode': widget.parallelLayoutMode.trim().isNotEmpty
          ? widget.parallelLayoutMode.trim()
          : 'fullscreen',
      'launchInitialRightPaneRoute': '',
    };
  }

  Map<String, Object?> _buildSystemPlaybackLaunchSource(Duration position) {
    final safePosition = position >= Duration.zero ? position : Duration.zero;
    final currentSource = widget.source.copyWith(
      loadNonce: createMpvLoadNonce(),
      itemGuid: _currentItemGuid.trim().isNotEmpty
          ? _currentItemGuid.trim()
          : widget.source.itemGuid,
      seasonGuid: _currentSeasonGuid.trim().isNotEmpty
          ? _currentSeasonGuid.trim()
          : widget.source.seasonGuid,
      posterPath: _currentPosterPath.trim().isNotEmpty
          ? _currentPosterPath.trim()
          : widget.source.posterPath,
      mediaGuid: _currentMediaGuid.trim().isNotEmpty
          ? _currentMediaGuid.trim()
          : widget.source.mediaGuid,
      mediaType: _currentMediaType.trim().isNotEmpty
          ? _currentMediaType.trim()
          : widget.source.mediaType,
      ancestorName: _currentAncestorName.trim().isNotEmpty
          ? _currentAncestorName.trim()
          : widget.source.ancestorName,
      videoGuid: _currentVideoGuid.trim().isNotEmpty
          ? _currentVideoGuid.trim()
          : widget.source.videoGuid,
      directLinkQualityIndex: _currentDirectLinkQualityIndex,
      clearDirectLinkQualityIndex: _currentDirectLinkQualityIndex == null,
      videoWidth: _currentVideoWidth > 0
          ? _currentVideoWidth
          : widget.source.videoWidth,
      videoHeight: _currentVideoHeight > 0
          ? _currentVideoHeight
          : widget.source.videoHeight,
      proxySessionId: _activeProxySessionId,
      playLink: _currentPlayLink,
      url: _currentUrl.trim().isNotEmpty
          ? _currentUrl.trim()
          : widget.source.url,
      headers: _currentHeaders.isNotEmpty
          ? _currentHeaders
          : widget.source.headers,
      title: _currentTitle.trim().isNotEmpty
          ? _currentTitle.trim()
          : widget.source.title,
      seriesTitle: _currentSeriesTitle.trim().isNotEmpty
          ? _currentSeriesTitle.trim()
          : widget.source.seriesTitle,
      seasonNumber: _currentSeasonNumber > 0
          ? _currentSeasonNumber
          : widget.source.seasonNumber,
      tmdbId: _currentTmdbId.trim().isNotEmpty
          ? _currentTmdbId.trim()
          : widget.source.tmdbId,
      episodeNumber: _currentEpisodeNumber > 0
          ? _currentEpisodeNumber
          : widget.source.episodeNumber,
      startPosition: safePosition,
      audioTrackGuid: _currentAudioGuid,
      clearAudioTrackGuid: _currentAudioGuid == null,
      subtitleTrackGuid: _normalizedSubtitleGuid(),
      clearSubtitleTrackGuid: _normalizedSubtitleGuid() == null,
      resolution: _currentResolution.trim().isNotEmpty
          ? _currentResolution.trim()
          : widget.source.resolution,
      bitrate: _currentBitrate > 0 ? _currentBitrate : widget.source.bitrate,
      durationSeconds: _durationSeconds > 0
          ? _durationSeconds
          : widget.source.durationSeconds,
      videoCodecName: _currentVideoCodecName.trim().isNotEmpty
          ? _currentVideoCodecName.trim()
          : widget.source.videoCodecName,
      videoProfile: _currentVideoProfile.trim().isNotEmpty
          ? _currentVideoProfile.trim()
          : widget.source.videoProfile,
      colorSpace: _currentColorSpace.trim().isNotEmpty
          ? _currentColorSpace.trim()
          : widget.source.colorSpace,
      colorTransfer: _currentColorTransfer.trim().isNotEmpty
          ? _currentColorTransfer.trim()
          : widget.source.colorTransfer,
      colorPrimaries: _currentColorPrimaries.trim().isNotEmpty
          ? _currentColorPrimaries.trim()
          : widget.source.colorPrimaries,
      bitDepth: _currentBitDepth > 0
          ? _currentBitDepth
          : widget.source.bitDepth,
      reliableSeek: _currentReliableSeek,
      seekProbeSummary: _currentSeekProbeSummary,
      clearSeekProbeSummary: _currentSeekProbeSummary == null,
      playbackSpeed: _playbackSpeed,
      audioTracks: _audioTracks,
      subtitleTracks: _subtitleTracks,
      qualities: _qualities,
    );
    return currentSource.toMap();
  }

  bool _shouldPublishSystemPlaybackSessionPayload(Map<String, Object?> next) {
    final previous = _lastSystemPlaybackSessionPayload;
    if (previous == null) {
      return true;
    }
    for (final key in const <String>[
      'itemGuid',
      'title',
      'subtitle',
      'albumTitle',
      'artist',
      'description',
      'mediaType',
      'seasonNumber',
      'episodeNumber',
      'trackCount',
      'artworkUrl',
      'artworkUrls',
      'artworkHeaders',
      'isPlaying',
      'durationMs',
      'speed',
      'canSeek',
      'canPause',
      'canPlay',
      'canSkipToPrevious',
      'canSkipToNext',
      'ready',
      'error',
    ]) {
      if (!_systemPlaybackFieldEquals(previous[key], next[key])) {
        return true;
      }
    }
    final previousPosition = previous['positionMs'];
    final nextPosition = next['positionMs'];
    final previousMs = previousPosition is int ? previousPosition : 0;
    final nextMs = nextPosition is int ? nextPosition : 0;
    return (previousMs - nextMs).abs() >=
        _MpvPlayerPageState
            ._systemPlaybackSessionPositionThreshold
            .inMilliseconds;
  }

  List<String> _resolveSystemPlaybackArtworkUrls() {
    final localArtworkUrls = _resolveLocalDownloadedArtworkUrls();
    if (localArtworkUrls.isNotEmpty) {
      return localArtworkUrls;
    }
    final rawPath = _currentPosterPath.trim().isNotEmpty
        ? _currentPosterPath.trim()
        : widget.source.posterPath.trim();
    if (rawPath.isEmpty) {
      return const <String>[];
    }
    final baseUrl = context.read<NasProvider>().baseUrl;
    return ApiUrlHelper.imageCandidates(baseUrl, rawPath, width: 480);
  }

  List<String> _resolveLocalDownloadedArtworkUrls() {
    if (!_currentSourceIsDownloadedFile) {
      return const <String>[];
    }
    final service = DownloadTaskService.instance;
    final currentItemGuid = _currentItemGuid.trim().isNotEmpty
        ? _currentItemGuid.trim()
        : widget.source.itemGuid.trim();
    final currentMediaGuid = _currentMediaGuid.trim().isNotEmpty
        ? _currentMediaGuid.trim()
        : widget.source.mediaGuid.trim();
    final currentFilePath = _resolveCurrentLocalPlaybackFilePath();

    DownloadTaskRecord? fallbackRecord;
    for (final record in service.downloadedRecords) {
      if (currentFilePath.isNotEmpty &&
          _sameLocalPlaybackPath(record.filePath, currentFilePath)) {
        final urls = _preferredLocalArtworkUrlsForRecord(record);
        if (urls.isNotEmpty) {
          return urls;
        }
      }
      if (currentItemGuid.isEmpty || record.itemGuid != currentItemGuid) {
        continue;
      }
      if (currentMediaGuid.isNotEmpty && record.mediaGuid == currentMediaGuid) {
        fallbackRecord = record;
        break;
      }
      fallbackRecord ??= record;
    }
    return fallbackRecord == null
        ? const <String>[]
        : _preferredLocalArtworkUrlsForRecord(fallbackRecord);
  }

  String _resolveCurrentLocalPlaybackFilePath() {
    final rawUrl = _currentUrl.trim().isNotEmpty
        ? _currentUrl.trim()
        : widget.source.url.trim();
    if (rawUrl.isEmpty) {
      return '';
    }
    final parsed = Uri.tryParse(rawUrl);
    if (parsed != null && parsed.scheme.toLowerCase() == 'file') {
      return parsed.toFilePath();
    }
    return rawUrl.startsWith('/') ? rawUrl : '';
  }

  bool _sameLocalPlaybackPath(String a, String b) {
    final normalizedA = a.trim().replaceAll('\\', '/');
    final normalizedB = b.trim().replaceAll('\\', '/');
    if (normalizedA.isEmpty || normalizedB.isEmpty) {
      return false;
    }
    return normalizedA == normalizedB;
  }

  List<String> _preferredLocalArtworkUrlsForRecord(DownloadTaskRecord record) {
    final combined = <String>[...record.posterUrls, ...record.groupPosterUrls];
    final local = combined.where(_isLocalArtworkUrl).toList(growable: false);
    if (local.isNotEmpty) {
      return local;
    }
    return combined
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  bool _isLocalArtworkUrl(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.startsWith('file://') || normalized.startsWith('/');
  }

  Map<String, String> _resolveSystemPlaybackArtworkHeaders() {
    final headers = <String, String>{};
    final token = context.read<NasProvider>().token.trim();
    if (token.isNotEmpty) {
      headers['Authorization'] = token;
      headers['Trim-MC-token'] = token;
    }
    for (final entry in _currentHeaders.entries) {
      final key = entry.key.trim();
      final value = entry.value.trim();
      if (key.isEmpty || value.isEmpty) {
        continue;
      }
      final normalizedKey = key.toLowerCase();
      if (normalizedKey == 'authorization' ||
          normalizedKey == 'trim-mc-token' ||
          normalizedKey == 'cookie' ||
          normalizedKey == 'user-agent' ||
          normalizedKey == 'referer') {
        headers.putIfAbsent(key, () => value);
      }
    }
    return headers;
  }

  String _resolveSystemPlaybackAlbumTitle() {
    if (_currentSeriesTitle.trim().isNotEmpty) {
      return _currentSeriesTitle.trim();
    }
    if (_currentAncestorName.trim().isNotEmpty) {
      return _currentAncestorName.trim();
    }
    return _currentTitle.trim();
  }

  String _resolveSystemPlaybackArtist(String subtitle) {
    if (_currentSeriesTitle.trim().isNotEmpty &&
        _currentSeriesTitle.trim() != subtitle) {
      return _currentSeriesTitle.trim();
    }
    if (_currentAncestorName.trim().isNotEmpty &&
        _currentAncestorName.trim() != subtitle) {
      return _currentAncestorName.trim();
    }
    return subtitle;
  }

  String _resolveSystemPlaybackDescription() {
    final parts = <String>[];
    if (_currentSeasonNumber > 0) {
      parts.add('S$_currentSeasonNumber');
    }
    if (_currentEpisodeNumber > 0) {
      parts.add('E$_currentEpisodeNumber');
    }
    final mediaType = _currentMediaType.trim();
    if (mediaType.isNotEmpty) {
      parts.add(mediaType);
    }
    return parts.join(' · ');
  }

  bool _systemPlaybackFieldEquals(Object? previous, Object? next) {
    if (previous is List && next is List) {
      if (previous.length != next.length) {
        return false;
      }
      for (var index = 0; index < previous.length; index += 1) {
        if (!_systemPlaybackFieldEquals(previous[index], next[index])) {
          return false;
        }
      }
      return true;
    }
    if (previous is Map && next is Map) {
      if (previous.length != next.length) {
        return false;
      }
      for (final entry in previous.entries) {
        if (!next.containsKey(entry.key)) {
          return false;
        }
        if (!_systemPlaybackFieldEquals(entry.value, next[entry.key])) {
          return false;
        }
      }
      return true;
    }
    return previous == next;
  }

  bool _canSkipToPreviousEpisodeForSystemSession() {
    if (_externalLocalSource) return false;
    if (_episodeItems.isNotEmpty) {
      return _hasPreviousEpisodeInLoadedItems();
    }
    return _currentEpisodeNumber > 1 || widget.source.episodeNumber > 1;
  }

  bool _canSkipToNextEpisodeForSystemSession() {
    if (_externalLocalSource) return false;
    if (_episodeItems.isNotEmpty) {
      return _hasNextEpisodeInLoadedItems();
    }
    if (_currentSeasonGuid.trim().isNotEmpty) {
      return true;
    }
    if (widget.source.seasonGuid.trim().isNotEmpty) {
      return true;
    }
    return _currentEpisodeNumber > 0 || widget.source.episodeNumber > 0;
  }
}
