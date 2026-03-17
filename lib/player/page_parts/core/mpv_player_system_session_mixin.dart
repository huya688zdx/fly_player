part of mpv_player_page;

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
          await _controller.seek(
            Duration(milliseconds: positionMs.clamp(0, 1 << 31)),
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

  Map<String, Object?> _buildSystemPlaybackSessionPayload() {
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
    final isReady = value.ready && value.nativeLibLoaded;
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
      'isPlaying': isReady && !hasError && !value.paused,
      'positionMs': safePositionMs,
      'durationMs': safeDurationMs,
      'speed': !value.paused ? _playbackSpeed : 0.0,
      'canSeek': safeDurationMs > 0,
      'canPause': true,
      'canPlay': true,
      'canSkipToPrevious': _canSkipToPreviousEpisodeForSystemSession(),
      'canSkipToNext': _canSkipToNextEpisodeForSystemSession(),
      'ready': isReady,
      'error': hasError ? value.error!.trim() : null,
    };
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
    final rawPath = _currentPosterPath.trim().isNotEmpty
        ? _currentPosterPath.trim()
        : widget.source.posterPath.trim();
    if (rawPath.isEmpty) {
      return const <String>[];
    }
    final baseUrl = context.read<NasProvider>().baseUrl;
    return ApiUrlHelper.imageCandidates(baseUrl, rawPath, width: 480);
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
    return parts.join(' 路 ');
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
    if (_episodeItems.isNotEmpty) {
      return _hasPreviousEpisodeInLoadedItems();
    }
    return _currentEpisodeNumber > 1 || widget.source.episodeNumber > 1;
  }

  bool _canSkipToNextEpisodeForSystemSession() {
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
