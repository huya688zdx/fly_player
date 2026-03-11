part of 'mpv_player_page.dart';

extension _MpvPlayerOptionsMixin on _MpvPlayerPageState {
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
    if (_audioTracks.isEmpty) {
      _showTransientMessage('当前没有可用音轨');
      return;
    }
    final result = await _showPlayerOptionSheet(
      title: '音频',
      sectionLabel: '音轨列表',
      items: _audioTracks
          .map(
            (track) => PlayerOptionSheetItem(
              id: track.guid,
              title: _audioTitle(track),
              subtitle: _audioSubtitle(track),
            ),
          )
          .toList(),
      selectedId: _currentAudioGuid,
    );
    if (!mounted || result == null || result == _currentAudioGuid) return;
    final selected = _findAudioTrack(result);
    if (selected == null) return;
    if (_serverPlaybackManaged) {
      _updatePlayerState(() {
        _qualitySwitchLoading = true;
        _currentAudioGuid = selected.guid;
      });
      _showSubtitleSwitchMessage('\u6b63\u5728\u5207\u6362\u97f3\u9891\uff0c\u8bf7\u7a0d\u7b49...');
      try {
        await _reloadServerPlaySession(audioGuid: selected.guid);
        _showControls();
      } finally {
        if (mounted) {
          _updatePlayerState(() => _qualitySwitchLoading = false);
        }
        _hideSubtitleSwitchMessage(delay: const Duration(milliseconds: 900));
      }
      return;
    }
    _updatePlayerState(() => _currentAudioGuid = selected.guid);
    await _controller.setAudioTrack(
      trackIndex: _mpvAudioTrackId(selected),
      trackGuid: selected.guid,
    );
    _showControls();
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
    if (_serverPlaybackManaged &&
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
    _showSubtitleSwitchMessage(_subtitleSwitchMessageForTrack(selected));
    try {
      await _applySubtitleSelection();
      _showControls();
    } finally {
      _updatePlayerState(() => _qualitySwitchLoading = false);
      _hideSubtitleSwitchMessage(delay: const Duration(milliseconds: 900));
    }
    */
  }

  Future<void> _showQualitySheet() async {
    if (_qualities.isEmpty) {
      _showTransientMessage('当前没有可切换清晰度');
      return;
    }
    final result = await _showPlayerOptionSheet(
      title: '清晰度',
      sectionLabel: '清晰度列表',
      items: _qualities
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
    final selected = _qualities.cast<PlaybackQualityOption?>().firstWhere(
      (quality) => quality != null && _qualityId(quality) == result,
      orElse: () => null,
    );
    if (selected == null) return;
    await _switchQuality(selected);
  }

  Future<void> _switchQuality(PlaybackQualityOption quality) async {
    if (quality.mediaGuid == _currentMediaGuid &&
        quality.videoGuid == _currentVideoGuid &&
        quality.resolution == _currentResolution &&
        quality.bitrate == _currentBitrate) {
      return;
    }

    final currentPosition = _displayPosition(_controller.value.value);
    _updatePlayerState(() => _qualitySwitchLoading = true);
    _showSubtitleSwitchMessage(
      PlayerSourceController.qualitySwitchMessageFor(quality),
    );
    try {
      await _reloadServerPlaySession(
        quality: quality,
        startPosition: currentPosition,
      );
      _showControls();
    } catch (error) {
      _showTransientMessage('获取字幕切换提示失败: $error');
    } finally {
      _updatePlayerState(() => _qualitySwitchLoading = false);
      _hideSubtitleSwitchMessage(delay: const Duration(milliseconds: 900));
    }
  }

  Future<void> _reloadServerPlaySession({
    String? audioGuid,
    String? subtitleGuid,
    PlaybackQualityOption? quality,
    Duration? startPosition,
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
      _currentAudioGuid = result.currentAudioGuid;
      _currentSubtitleGuid = result.currentSubtitleGuid;
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
      _pendingSubtitleSelectionRefresh = result.pendingSubtitleSelectionRefresh;
      _pendingReloadAutoplayRefresh = true;
      _serverPlaybackManaged = result.serverPlaybackManaged;
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

    final source = _buildCurrentSource(startPosition: resolvedStartPosition);
    _controller.prepareForSourceLoad(
      source,
      paused: _controller.value.value.paused,
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
    _updatePlayerState(() => _subtitleSwitchMessage = message);
  }

  void _hideSubtitleSwitchMessage({Duration? delay}) {
    _subtitleSwitchOverlayTimer?.cancel();
    if (delay == null || delay <= Duration.zero) {
      if (!mounted) return;
      _updatePlayerState(() => _subtitleSwitchMessage = null);
      return;
    }
    _subtitleSwitchOverlayTimer = Timer(delay, () {
      if (!mounted) return;
      _updatePlayerState(() => _subtitleSwitchMessage = null);
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

  Future<void> _applySubtitleSelection() async {
    var selected = _syncCurrentSubtitleTrackSelection();
    if (selected == null || (_currentSubtitleGuid ?? '').trim().isEmpty) {
      _pendingExternalSubtitlePath = null;
      _releaseSubtitleProxySession();
      await _controller.setSubtitleTrack(trackIndex: null, trackGuid: null);
      return;
    }
    if (_subtitleShouldUseExternalFile(selected)) {
      final subtitleForFile = selected;
      var path = await _ensureSubtitleFile(subtitleForFile);
      if (!mounted) return;
      if (path == null) {
        final refreshed = await _refreshSubtitleTracksFromSource(
          preferredGuid: selected.guid,
        );
        if (!mounted) return;
        if (refreshed != null &&
            refreshed.guid == selected.guid &&
            _subtitleShouldUseExternalFile(refreshed)) {
          selected = refreshed;
          path = await _ensureSubtitleFile(refreshed);
        }
      }
      if (!mounted) return;
      if (path == null) {
        _serverFallbackSubtitleGuids.add(selected.guid);
        return;
      }
      _serverFallbackSubtitleGuids.remove(subtitleForFile.guid);
      _subtitleFailureNoticeShownGuids.remove(subtitleForFile.guid);
      _pendingExternalSubtitlePath = path;
      _releaseSubtitleProxySession();
      _handlePlayerValueChanged();
      return;
    }
    _pendingExternalSubtitlePath = null;
    _releaseSubtitleProxySession();
    await _controller.setSubtitleTrack(
      trackIndex: _mpvSubtitleTrackId(selected),
      trackGuid: selected.guid,
    );
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
    } catch (error) {
      debugPrint(
        '[MPV][SUBTITLE] download failed guid=${subtitle.guid} error=$error',
      );
      final appError = AppException.from(
        error,
        action: 'subtitle download',
        fallbackKind: AppExceptionKind.noData,
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
