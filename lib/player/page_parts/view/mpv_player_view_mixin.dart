part of mpv_player_page;

const String _playerCloudDriveModePageId = 'player_cloud_drive_mode';
const String _playerCloudDriveActionDirect = 'player_cloud_drive_action_direct';
const String _playerCloudDriveActionProxy = 'player_cloud_drive_action_proxy';

extension _MpvPlayerViewMixin on _MpvPlayerPageState {
  static const ScreenshotSettingsStore _captureSettingsStore =
      ScreenshotSettingsStore();

  Widget _buildAndroidPlayerScaffold(BuildContext context) {
    final colors = context.appColors;
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final isLandscape = media.orientation == Orientation.landscape;
    final compactUi = screenWidth < 900;
    final titleFontSize = compactUi ? 14.0 : 15.5;
    final timeFontSize = compactUi ? 11.5 : 13.0;
    final scaffold = Scaffold(
      backgroundColor: colors.backgroundBase,
      resizeToAvoidBottomInset: false,
      body: _buildAndroidPlayerBody(
        context,
        colors: colors,
        media: media,
        compactUi: compactUi,
        isLandscape: isLandscape,
        titleFontSize: titleFontSize,
        timeFontSize: timeFontSize,
      ),
    );
    if (!widget.interceptSystemBack) {
      return scaffold;
    }
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        unawaited(_handleBackAction());
      },
      child: scaffold,
    );
  }

  Widget _buildAndroidPlayerBody(
    BuildContext context, {
    required AppThemeColors colors,
    required MediaQueryData media,
    required bool compactUi,
    required bool isLandscape,
    required double titleFontSize,
    required double timeFontSize,
  }) {
    final listenVideoActive = _listenVideoModeEnabled;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
          RepaintBoundary(child: _buildVideoViewportLayer(_buildPlayerSurface())),
          if (!widget.pictureInPictureActive && !listenVideoActive)
            RepaintBoundary(child: _buildVideoViewportLayer(_buildDanmakuLayer())),
          if (!widget.pictureInPictureActive && listenVideoActive)
            Positioned.fill(
              child: _buildListenVideoPresentationLayer(
                context,
                compactUi: compactUi,
              ),
            ),
          if (!widget.pictureInPictureActive) ...[
            _buildVideoLoadingOverlayLayer(colors),
            IgnorePointer(
              ignoring: !_uiController.orientationTransitionMaskVisible,
              child: AnimatedOpacity(
                opacity: _uiController.orientationTransitionMaskVisible ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: ColoredBox(color: colors.backgroundBase),
              ),
            ),
            _buildInteractiveChromeLayer(
              context,
              compactUi: compactUi,
              isLandscape: isLandscape,
              titleFontSize: titleFontSize,
              timeFontSize: timeFontSize,
            ),
            _buildFloatingLockButton(
              media: media,
              compactUi: compactUi,
              isLandscape: isLandscape,
            ),
            _buildPlaybackCompletedOverlay(compactUi: compactUi),
            if (_shouldShowPerformanceOverlay())
              _buildPerformanceOverlay(
                compactUi: compactUi,
                viewportSize: media.size,
              ),
            Positioned.fill(
              child: PlayerSkipPromptOverlay(
                visible:
                    _supportsIntroOutroUi &&
                    _uiController.activeChapterSkipPrompt != null,
                label: _uiController.activeChapterSkipPrompt == null
                    ? ''
                    : (_uiController.activeChapterSkipPrompt!.isIntro
                          ? 'Intro'
                          : 'Outro'),
                countdownSeconds: _skipPromptCountdownSeconds,
                onClose: _dismissCurrentChapterSkipPrompt,
              ),
            ),
            Positioned.fill(
              child: PlayerSpeedDialOverlay(
                visible:
                    _speedDialVisible &&
                    !_playbackSettingsDrawerVisible &&
                    !_playbackCompleted,
                speed: _playbackSpeed,
                onSpeedChanged: _handleSpeedDialSpeedChanged,
                onDismiss: _hideSpeedDialOverlay,
                labelBuilder: _speedLabel,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVideoViewportLayer(Widget child) {
    return Center(
      child: AspectRatio(
        aspectRatio: _videoAspectRatio(),
        child: ClipRect(child: child),
      ),
    );
  }

  Widget _buildListenVideoPresentationLayer(
    BuildContext context, {
    required bool compactUi,
  }) {
    final nasProvider = _nasProvider ?? context.read<NasProvider>();
    return PlayerListenVideoPresentation(
      artworkUrls: _resolveSystemPlaybackArtworkUrls(),
      token: nasProvider.token.trim(),
      title: _currentTitle.trim().isEmpty ? widget.title : _currentTitle.trim(),
      subtitle: _listenVideoPresentationSubtitle(),
      compactUi: compactUi,
    );
  }

  String _listenVideoPresentationSubtitle() {
    final parts = <String>[];
    final seriesTitle = _currentSeriesTitle.trim();
    final ancestorName = _currentAncestorName.trim();
    if (seriesTitle.isNotEmpty) {
      parts.add(seriesTitle);
    } else if (ancestorName.isNotEmpty) {
      parts.add(ancestorName);
    }

    if (_currentSeasonNumber > 0) {
      parts.add('第$_currentSeasonNumber季');
    }
    if (_currentEpisodeNumber > 0) {
      parts.add('第$_currentEpisodeNumber集');
    }

    if (parts.isEmpty) {
      final mediaType = _currentMediaType.trim();
      if (mediaType.isNotEmpty) {
        parts.add(mediaType);
      }
    } else {
      final mediaType = _currentMediaType.trim();
      if (mediaType.isNotEmpty && !parts.contains(mediaType)) {
        parts.add(mediaType);
      }
    }

    return parts.join(' · ');
  }

  Widget _buildDanmakuLayer() {
    if (_useNativeDanmakuRenderer) {
      return const SizedBox.shrink();
    }
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        _controller.value,
        _controller.danmakuOcclusionState,
        _gestureController.speedBoostListenable,
      ]),
      builder: (context, _) {
        final value = _controller.value.value;
        final duration = _effectiveDuration();
        final rawPlaybackPosition =
            duration > Duration.zero && value.position > duration
            ? duration
            : value.position;
        return DanmakuOverlay(
          controller: _danmakuController,
          position: rawPlaybackPosition,
          paused: value.paused,
          playbackSpeedFactor: _speedBoostActive ? 2.0 : 1.0,
          occlusionState: _controller.danmakuOcclusionState.value,
        );
      },
    );
  }

  Widget _buildVideoLoadingOverlayLayer(AppThemeColors colors) {
    return ValueListenableBuilder<MpvPlayerValue>(
      valueListenable: _controller.value,
      builder: (context, value, _) {
        if (!_shouldShowVideoLoadingOverlay(value)) {
          return const SizedBox.shrink();
        }
        return Positioned.fill(
          child: ColoredBox(
            color: colors.overlayScrim.withValues(alpha: 0.40),
            child: PlayerLoadingOverlay(
              visible: true,
              message: _videoLoadingOverlayMessage(value),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFloatingLockButton({
    required MediaQueryData media,
    required bool compactUi,
    required bool isLandscape,
  }) {
    final topInset = media.padding.top + (compactUi ? 12.0 : 16.0);
    final bottomInset = media.padding.bottom + (compactUi ? 20.0 : 26.0);
    final baseRight = compactUi ? 14.0 : 18.0;
    final bottomReserve = isLandscape ? 92.0 : 132.0;
    return Positioned(
      right: baseRight,
      top: topInset,
      bottom: bottomInset + bottomReserve,
      child: Align(
        alignment: Alignment.center,
        child: PlayerFloatingLockButton(
          visible: _controlsVisible || _controlsAnimatingOut,
          compact: compactUi,
          locked: _playerUiLocked,
          onPressed: () =>
              unawaited(_playerUiLocked ? _unlockPlayerUi() : _lockPlayerUi()),
        ),
      ),
    );
  }

  Widget _buildInteractiveChromeLayer(
    BuildContext context, {
    required bool compactUi,
    required bool isLandscape,
    required double titleFontSize,
    required double timeFontSize,
  }) {
    return AnimatedBuilder(
      animation: _gestureController.seekListenable,
      builder: (context, _) {
        final overlaySuppressed =
            _playbackSettingsDrawerVisible ||
            _speedDialVisible ||
            _playerUiLocked;
        final minimalSeekMode =
            _gestureSeekActive ||
            (!_controlsVisible &&
                _gestureController.pendingSeekPosition != null);
        final controlsMounted =
            !overlaySuppressed &&
            (_controlsVisible || _controlsAnimatingOut || minimalSeekMode);
        final topBar = _buildTopBar(
          context,
          compactUi: compactUi,
          titleFontSize: titleFontSize,
          visible: !overlaySuppressed && _controlsVisible && !minimalSeekMode,
        );
        return ValueListenableBuilder<MpvPlayerValue>(
          valueListenable: _controller.value,
          builder: (context, value, _) {
            final duration = _effectiveDuration();
            final position = _displayPosition(value);
            final clampedPosition =
                duration > Duration.zero && position > duration
                ? duration
                : position;
            final bufferedPosition =
                duration > Duration.zero && value.bufferedPosition > duration
                ? duration
                : value.bufferedPosition;
            final visibleChapters = controlsMounted
                ? _visibleChaptersForDuration(duration)
                : const <MpvChapterItem>[];
            final activeChapterIndex = controlsMounted
                ? _activeChapterIndexForPosition(
                    visibleChapters,
                    clampedPosition,
                  )
                : -1;
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: controlsMounted,
                    child: _buildGestureLayer(duration: duration),
                  ),
                ),
                _buildControlsOverlay(
                  context,
                  value: value,
                  compactUi: compactUi,
                  isLandscape: isLandscape,
                  titleFontSize: titleFontSize,
                  timeFontSize: timeFontSize,
                  duration: duration,
                  clampedPosition: clampedPosition,
                  bufferedPosition: bufferedPosition,
                  visibleChapters: visibleChapters,
                  activeChapterIndex: activeChapterIndex,
                  overlayVisible:
                      !overlaySuppressed &&
                      (_controlsVisible || minimalSeekMode),
                  minimalSeekMode: minimalSeekMode,
                  showStatusCard: false,
                  topBar: topBar,
                ),
                AnimatedBuilder(
                  animation: _gestureController.overlayListenable,
                  builder: (context, _) {
                    return PlayerGestureOverlay(
                      adjustment: _gestureOverlayData,
                      speedBoostActive: _speedBoostActive,
                      statusMessage:
                          !_uiController.backgroundLoadingTransition &&
                              !_uiController.videoLoadingOverlayVisible &&
                              !(_uiController.qualitySwitchLoading ||
                                  _uiController.pendingLoadingTransition ||
                                  _uiController.awaitingVisualPlaybackStart) &&
                              (_uiController.subtitleSwitchMessage
                                      ?.trim()
                                      .isNotEmpty ??
                                  false)
                          ? _uiController.subtitleSwitchMessage
                          : _uiController.statusMessage,
                      statusLoading:
                          !_uiController.backgroundLoadingTransition &&
                          (_uiController.qualitySwitchLoading ||
                              _uiController.pendingLoadingTransition ||
                              _uiController.awaitingVisualPlaybackStart),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPlayerSurface() {
    final initialSource = _initialSourceLoadStarted
        ? _buildCurrentSource()
        : widget.source;
    return AndroidView(
      viewType: 'fly_player/mpv_view',
      layoutDirection: TextDirection.ltr,
      creationParams: initialSource.toMap(),
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _handlePlatformViewCreated,
    );
  }

  bool _shouldShowPerformanceOverlay() {
    if (!_performanceOverlayEnabled) return false;
    return !_exitInProgress;
  }

  Widget _buildPerformanceOverlay({
    required bool compactUi,
    required Size viewportSize,
  }) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        _performanceOverlayStatsNotifier,
        _performanceOverlayOffsetNotifier,
      ]),
      builder: (context, _) {
        final stats = _performanceOverlayStatsNotifier.value;
        final rows = <String>[];
        if (_performanceOverlayEnabled) {
          final cpu = _formatOverlayPercent(stats.cpuUsagePercent) ?? '--';
          final memory = _formatOverlayMemory(
            usedBytes: stats.appMemoryUsedBytes,
            totalBytes: stats.systemMemoryTotalBytes,
          );
          rows.add('CPU $cpu  MEM $memory');
        }
        final fontSize = compactUi ? 10.5 : 11.5;
        final overlayWidth = compactUi ? 190.0 : 220.0;
        const overlayHeight = 28.0;
        final offset = _clampedPerformanceOverlayOffset(
          viewportSize: viewportSize,
          overlayWidth: overlayWidth,
          overlayHeight: overlayHeight,
        );
        return Positioned(
          left: offset.dx,
          top: offset.dy,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (details) {
              final next = _clampedPerformanceOverlayOffset(
                viewportSize: viewportSize,
                overlayWidth: overlayWidth,
                overlayHeight: overlayHeight,
                candidate:
                    _performanceOverlayOffsetNotifier.value + details.delta,
              );
              if (_performanceOverlayOffsetNotifier.value == next) {
                return;
              }
              _performanceOverlayOffsetNotifier.value = next;
            },
            onPanEnd: (_) {
              unawaited(
                _persistPerformanceOverlayOffset(
                  _performanceOverlayOffsetNotifier.value,
                ),
              );
            },
            child: AnimatedOpacity(
              opacity: 1,
              duration: const Duration(milliseconds: 180),
              child: Container(
                constraints: BoxConstraints(maxWidth: overlayWidth),
                padding: EdgeInsets.symmetric(
                  horizontal: compactUi ? 7 : 8,
                  vertical: compactUi ? 4 : 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0x7A000000),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: rows
                      .map(
                        (row) => Text(
                          row,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontSize: fontSize,
                            fontWeight: FontWeight.w500,
                            height: 1.12,
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Offset _clampedPerformanceOverlayOffset({
    required Size viewportSize,
    required double overlayWidth,
    required double overlayHeight,
    Offset? candidate,
  }) {
    final raw = candidate ?? _performanceOverlayOffsetNotifier.value;
    final maxDx = (viewportSize.width - overlayWidth - 8).clamp(8.0, 9999.0);
    final maxDy = (viewportSize.height - overlayHeight - 8).clamp(8.0, 9999.0);
    return Offset(raw.dx.clamp(8.0, maxDx), raw.dy.clamp(8.0, maxDy));
  }

  String? _formatOverlayPercent(double? value) {
    if (value == null) return null;
    return '${value.clamp(0, 100).round()}%';
  }

  String _formatOverlayMemory({
    required int? usedBytes,
    required int? totalBytes,
  }) {
    final used = _formatMemoryUnit(usedBytes);
    final total = _formatMemoryUnit(totalBytes);
    return '$used/$total';
  }

  String _formatMemoryUnit(int? bytes) {
    if (bytes == null || bytes <= 0) return '--';
    const kb = 1024.0;
    const mb = kb * 1024.0;
    const gb = mb * 1024.0;
    final value = bytes.toDouble();
    if (value >= gb) {
      return '${(value / gb).toStringAsFixed(1)}G';
    }
    return '${(value / mb).toStringAsFixed(value >= mb * 100 ? 0 : 1)}M';
  }

  bool _isPointInsidePerformanceOverlay(Offset position) {
    if (!_shouldShowPerformanceOverlay()) return false;
    final media = MediaQuery.of(context);
    final compactUi = media.size.width < 900;
    final overlayWidth = compactUi ? 190.0 : 220.0;
    const overlayHeight = 28.0;
    final offset = _clampedPerformanceOverlayOffset(
      viewportSize: media.size,
      overlayWidth: overlayWidth,
      overlayHeight: overlayHeight,
    );
    final rect = Rect.fromLTWH(
      offset.dx,
      offset.dy,
      overlayWidth,
      overlayHeight,
    );
    return rect.inflate(10).contains(position);
  }

  Widget _buildControlsOverlay(
    BuildContext context, {
    required MpvPlayerValue value,
    required bool compactUi,
    required bool isLandscape,
    required double titleFontSize,
    required double timeFontSize,
    required Duration duration,
    required Duration clampedPosition,
    required Duration bufferedPosition,
    required List<MpvChapterItem> visibleChapters,
    required int activeChapterIndex,
    required bool overlayVisible,
    required bool minimalSeekMode,
    required bool showStatusCard,
    required Widget topBar,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = constraints.biggest;
        return IgnorePointer(
          ignoring: !overlayVisible,
          child: Opacity(
            opacity: overlayVisible ? 1 : 0,
            child: PlayerGestureLayer(
              onTap: _handleGestureTap,
              onDoubleTap: _handleGestureDoubleTap,
              onLongPressStart: _handleGestureLongPressStart,
              onLongPressEnd: _handleGestureLongPressEnd,
              onLongPressCancel: _handleGestureLongPressCancel,
              onHorizontalDragStart: (details) => _handleGestureHorizontalStart(
                details,
                duration,
                viewportSize,
              ),
              onHorizontalDragUpdate: (details) =>
                  _handleGestureHorizontalUpdate(
                    details,
                    duration,
                    viewportSize,
                  ),
              onHorizontalDragEnd: _handleGestureHorizontalEnd,
              onHorizontalDragCancel: _handleGestureHorizontalCancel,
              onVerticalDragStart: (details) =>
                  _handleGestureVerticalStart(details, viewportSize),
              onVerticalDragUpdate: (details) =>
                  _handleGestureVerticalUpdate(details, viewportSize),
              onVerticalDragEnd: _handleGestureVerticalEnd,
              onVerticalDragCancel: _handleGestureVerticalCancel,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: _listenVideoModeEnabled
                        ? const <Color>[
                            Color(0x00000000),
                            Color(0x08000000),
                            Color(0x0A13202F),
                            Color(0x4413202F),
                          ]
                        : const <Color>[
                            Color(0x90000000),
                            Color(0x24000000),
                            Color(0x10000000),
                            Color(0xB8000000),
                          ],
                    stops: const <double>[0.0, 0.18, 0.56, 1.0],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    // Gesture-nav devices often report a larger bottom gesture
                    // exclusion area than the regular safe padding.
                    padding: (() {
                      final media = MediaQuery.of(context);
                      final gestureInset =
                          media.systemGestureInsets.bottom >
                              media.padding.bottom
                          ? media.systemGestureInsets.bottom -
                                media.padding.bottom
                          : 0.0;
                      return EdgeInsets.fromLTRB(
                        20,
                        compactUi ? 2 : 4,
                        20,
                        (compactUi ? 8 : 10) + gestureInset,
                      );
                    })(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        topBar,
                        const Spacer(),
                        _buildBottomPanel(
                          value: value,
                          compactUi: compactUi,
                          isLandscape: isLandscape,
                          timeFontSize: timeFontSize,
                          duration: duration,
                          clampedPosition: clampedPosition,
                          bufferedPosition: bufferedPosition,
                          visibleChapters: visibleChapters,
                          activeChapterIndex: activeChapterIndex,
                          minimalSeekMode: minimalSeekMode,
                          showStatusCard: showStatusCard,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGestureLayer({required Duration duration}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = constraints.biggest;
        final gesturesEnabled = !_playerUiLocked;
        return PlayerGestureLayer(
          onTap: _handleGestureTap,
          onDoubleTap: gesturesEnabled ? _handleGestureDoubleTap : null,
          onLongPressStart: gesturesEnabled
              ? _handleGestureLongPressStart
              : null,
          onLongPressEnd: gesturesEnabled ? _handleGestureLongPressEnd : null,
          onLongPressCancel: gesturesEnabled
              ? _handleGestureLongPressCancel
              : null,
          onHorizontalDragStart: gesturesEnabled
              ? (details) => _handleGestureHorizontalStart(
                  details,
                  duration,
                  viewportSize,
                )
              : null,
          onHorizontalDragUpdate: gesturesEnabled
              ? (details) => _handleGestureHorizontalUpdate(
                  details,
                  duration,
                  viewportSize,
                )
              : null,
          onHorizontalDragEnd: gesturesEnabled
              ? _handleGestureHorizontalEnd
              : null,
          onHorizontalDragCancel: gesturesEnabled
              ? _handleGestureHorizontalCancel
              : null,
          onVerticalDragStart: gesturesEnabled
              ? (details) => _handleGestureVerticalStart(details, viewportSize)
              : null,
          onVerticalDragUpdate: gesturesEnabled
              ? (details) => _handleGestureVerticalUpdate(details, viewportSize)
              : null,
          onVerticalDragEnd: gesturesEnabled ? _handleGestureVerticalEnd : null,
          onVerticalDragCancel: gesturesEnabled
              ? _handleGestureVerticalCancel
              : null,
        );
      },
    );
  }

  void _handleGestureHorizontalStart(
    DragStartDetails details,
    Duration duration,
    Size viewportSize,
  ) {
    _restoreSpeedBoostIfNeeded();
    if (duration <= Duration.zero) return;
    if (_uiController.timelineInteractionActive) return;
    if (_isPointInsidePerformanceOverlay(details.localPosition)) return;
    _gestureController.handleHorizontalStart(
      details: details,
      currentPosition: _displayPosition(_controller.value.value),
      restoreControlsVisible: _controlsVisible,
      width: viewportSize.width,
    );
  }

  void _handleGestureHorizontalUpdate(
    DragUpdateDetails details,
    Duration duration,
    Size viewportSize,
  ) {
    if (duration <= Duration.zero) return;
    if (_uiController.timelineInteractionActive) return;
    _gestureController.handleHorizontalUpdate(
      details: details,
      width: viewportSize.width,
      duration: duration,
    );
  }

  void _handleGestureHorizontalEnd(DragEndDetails details) {
    if (_uiController.timelineInteractionActive) return;
    final result = _gestureController.completeHorizontalSeek();
    if (result == null) return;
    unawaited(_seekWithStats(result.target, userInitiated: true));
    if (result.restoreControlsVisible) {
      _showControls();
    }
  }

  void _handleGestureHorizontalCancel() {
    _restoreSpeedBoostIfNeeded();
    if (_uiController.timelineInteractionActive) return;
    _gestureController.cancelHorizontalSeek();
  }

  void _handleGestureVerticalStart(
    DragStartDetails details,
    Size viewportSize,
  ) {
    _restoreSpeedBoostIfNeeded();
    if (_isPointInsidePerformanceOverlay(details.localPosition)) return;
    final topInset = MediaQuery.viewPaddingOf(context).top;
    final guardHeight = (topInset + 56).clamp(64.0, 120.0);
    if (details.localPosition.dy <= guardHeight) {
      return;
    }
    _gestureController.handleVerticalStart(
      details: details,
      width: viewportSize.width,
      height: viewportSize.height,
    );
    unawaited(_syncDanmakuDynamicOcclusionConfig());
  }

  void _handleGestureVerticalUpdate(
    DragUpdateDetails details,
    Size viewportSize,
  ) {
    _gestureController.handleVerticalUpdate(
      details: details,
      height: viewportSize.height,
    );
  }

  void _handleGestureVerticalEnd(DragEndDetails details) {
    _gestureController.handleVerticalEnd();
    unawaited(_syncDanmakuDynamicOcclusionConfig());
  }

  void _handleGestureVerticalCancel() {
    _gestureController.cancelVerticalAdjustment();
    unawaited(_syncDanmakuDynamicOcclusionConfig());
  }

  void _handleGestureLongPressStart(LongPressStartDetails details) {
    if (_isPointInsidePerformanceOverlay(details.localPosition)) return;
    final started = _gestureController.beginSpeedBoost(_playbackSpeed);
    if (!started) return;
    unawaited(HapticFeedback.lightImpact());
    unawaited(_controller.setSpeed(2.0));
  }

  void _handleGestureLongPressEnd(LongPressEndDetails details) {
    _restoreSpeedBoostIfNeeded();
  }

  void _handleGestureLongPressCancel() {
    _restoreSpeedBoostIfNeeded();
  }

  void _handleGestureTap() {
    _restoreSpeedBoostIfNeeded();
    if (_controlsVisible) {
      _hideControlsAnimated();
      return;
    }
    _toggleControls();
  }

  void _handleGestureDoubleTap() {
    _restoreSpeedBoostIfNeeded();
    _togglePlayback();
  }

  void _restoreSpeedBoostIfNeeded() {
    final restoreSpeed = _gestureController.cancelSpeedBoost(_playbackSpeed);
    if (restoreSpeed == null) return;
    unawaited(HapticFeedback.selectionClick());
    unawaited(_controller.setSpeed(restoreSpeed));
  }

  // ignore: unused_element
  Future<void> _showAudioOutputPicker() async {
    return;
    /*
    _overlayState.cancelAutoHide();
    final devices = await _playerSystemController.listAudioOutputDevices();
    if (!mounted) return;
    if (devices.isEmpty) {
      final opened = await _playerSystemController.openAudioOutputSettings();
      if (!mounted) return;
      _showTopTip(
        opened ? '未检测到可用输出，已打开系统音频设置' : '当前未检测到可用音频输出',
        opened ? context.appColors.warning : context.appColors.danger,
      );
      if (_controlsVisible) {
        _scheduleControlsAutoHide();
      }
      return;
    }
    final selected = await PlayerAudioOutputPicker.show(
      context,
      devices: devices,
    );
    if (!mounted) return;
    if (selected == null) {
      if (_controlsVisible) {
        _scheduleControlsAutoHide();
      }
      return;
    }
    final result = await _playerSystemController.selectAudioOutputDevice(
      selected.id,
    );
    if (!mounted) return;
    final deviceName = result.deviceName.isNotEmpty
        ? result.deviceName
        : (selected.name.isNotEmpty ? selected.name : '当前设备');
    if (result.switched) {
      _showTopTip('已切换到 $deviceName', context.appColors.success);
    } else if (result.systemFallback) {
      _showTopTip('当前设备需在系统中完成切换', context.appColors.warning);
    } else {
      _showTopTip('切换音频输出失败', context.appColors.danger);
    }
    if (_controlsVisible) {
      _scheduleControlsAutoHide();
    }
    */
  }

  Widget _buildTopBar(
    BuildContext context, {
    required bool compactUi,
    required double titleFontSize,
    required bool visible,
  }) {
    final media = MediaQuery.of(context);
    final listenVideoActive = _listenVideoModeEnabled;
    final showDownloadedBadge = _currentSourceIsDownloadedFile;
    final showCacheDownloadAction =
        media.orientation == Orientation.landscape &&
        !showDownloadedBadge &&
        _cacheDownloadAvailable &&
        !listenVideoActive;
    return PlayerControlsTopBar(
      visible: visible,
      compactUi: compactUi,
      showSystemStatus: media.orientation == Orientation.landscape,
      titleFontSize: titleFontSize,
      title: _currentTitle,
      systemTimeLabel: _playerSystemTimeLabel,
      systemNetworkType: _playerSystemNetworkType,
      systemBatteryLevel: _playerSystemBatteryLevel,
      systemBatteryCharging: _playerSystemCharging,
      showDownloadedBadge: showDownloadedBadge,
      danmakuEnabled: _danmakuEnabled && !listenVideoActive,
      collapseActionsToSubtitleAndMore:
          media.orientation == Orientation.portrait,
      showPictureInPictureAction:
          !listenVideoActive && _shouldShowPictureInPictureButton(),
      showListenVideoAction: _shouldShowListenVideoAction(),
      listenVideoActive: _listenVideoModeEnabled,
      onBack: () => unawaited(_handleBackAction()),
      onPictureInPicture: () => unawaited(_enterPictureInPictureMode()),
      onToggleListenVideo: () => unawaited(_toggleListenVideoMode()),
      showFitModeAction: !listenVideoActive,
      captureFrameBusy: _captureFrameInFlight,
      onCaptureFrame: listenVideoActive
          ? null
          : () => unawaited(_captureCurrentFrame()),
      showCacheDownloadAction: showCacheDownloadAction,
      cacheDownloadBusy: _cacheDownloadImportInFlight,
      onCacheDownload: () => unawaited(_importCurrentPlaybackCacheToDownload()),
      abLoopLabel: _abLoopButtonLabel,
      abLoopActive: _abLoopButtonActive,
      onAbLoop: () => unawaited(_handleAbLoopButtonPressed()),
      onFitMode: () => _showTransientMessage('画面模式暂未接入'),
      onDanmakuSettings: () => unawaited(_openDanmakuSettings()),
      onMore: () => unawaited(_showPlaybackSettingsDrawer()),
    );
    /* if (!visible) {
      return const SizedBox.shrink();
    }
    return Row(
          children: [
            PlayerTopIconButton(
              icon: Icons.arrow_back_ios_new,
              onPressed: () => unawaited(_closePlayer()),
            ),
            SizedBox(width: compactUi ? 10 : 12),
            Expanded(
              child: Text(
                _currentTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(width: compactUi ? 8 : 10),
            PlayerTopIconButton(
              icon: Icons.fit_screen_outlined,
              onPressed: () => _showTransientMessage('画面模式暂未接入'),
            ),
            if (_danmakuEnabled) ...[
              SizedBox(width: compactUi ? 6 : 8),
              PlayerTopAssetButton(
                assetName: 'assets/icons/player_danmaku_settings.svg',
                onPressed: () => unawaited(_openDanmakuSettings()),
              ),
            ],
            SizedBox(width: compactUi ? 6 : 8),
            PlayerTopIconButton(
              icon: Icons.more_horiz,
              onPressed: () => unawaited(_showPlaybackSettingsDrawer()),
            ),
          ],
    ); */
  }

  bool _shouldShowListenVideoAction() {
    if (!_currentSourceHasVideoTrack()) {
      return false;
    }
    return !widget.pictureInPictureActive;
  }

  Future<void> _toggleListenVideoMode() async {
    _overlayState.cancelAutoHide();
    final targetEnabled = !_listenVideoModeEnabled;
    final result = await _controller.setListenVideoMode(targetEnabled);
    if (!mounted) return;
    if (result.success) {
      _updatePlayerState(() => _listenVideoModeEnabled = result.enabled);
      _showTopTip(
        result.enabled ? '已开启听视频模式' : '已恢复视频画面',
        context.appColors.success,
        revealControls: true,
      );
      if (_controlsVisible) {
        _scheduleControlsAutoHide();
      }
      return;
    }
    final message = result.message?.trim().isNotEmpty == true
        ? result.message!.trim()
        : (targetEnabled ? '听视频模式切换失败' : '视频画面恢复失败');
    _showTopTip(message, context.appColors.danger, revealControls: true);
  }

  Future<void> _captureCurrentFrame() async {
    if (_captureFrameInFlight) return;
    _updatePlayerState(() => _captureFrameInFlight = true);
    try {
      final settings = await _captureSettingsStore.load();
      final result = await _controller.captureFrame(
        includeSubtitles: settings.includeSubtitles,
        savePathMode: settings.savePathMode,
      );
      if (!mounted) return;
      final success = result['success'] == true;
      final code = result['code']?.toString().trim() ?? '';
      final rawMessage = result['message']?.toString().trim() ?? '';
      final message = _captureResultMessage(
        success: success,
        code: code,
        rawMessage: rawMessage,
      );
      _showTopTip(
        message,
        success ? context.appColors.success : context.appColors.warning,
      );
    } on MissingPluginException {
      if (!mounted) return;
      _showTopTip('截图模块未加载，请重启应用', context.appColors.warning);
    } catch (_) {
      if (!mounted) return;
      _showTopTip('截图失败', context.appColors.warning);
    } finally {
      if (mounted) {
        _updatePlayerState(() => _captureFrameInFlight = false);
      } else {
        _captureFrameInFlight = false;
      }
    }
  }

  String _captureResultMessage({
    required bool success,
    required String code,
    required String rawMessage,
  }) {
    if (success) {
      return '截图已保存';
    }
    switch (code) {
      case 'custom_directory_required':
        return '请先在截图设置里选择自定义目录';
      case 'custom_directory_unavailable':
        return '自定义目录不可用，请重新选择';
    }
    switch (rawMessage) {
      case 'capture unavailable':
        return '当前还不能截图';
      case 'capture failed':
        return '截图失败';
      case 'capture save failed':
        return '截图保存失败';
      case 'capture saved':
        return '截图已保存';
      case 'Please choose a custom screenshot directory first':
        return '请先在截图设置里选择自定义目录';
      case 'Custom screenshot directory is unavailable':
        return '自定义目录不可用，请重新选择';
      default:
        return rawMessage.isNotEmpty ? rawMessage : '截图失败';
    }
  }

  bool _shouldShowPictureInPictureButton() {
    if (!_pictureInPictureSupported) {
      return false;
    }
    if (widget.pictureInPictureActive) {
      return false;
    }
    if (widget.parallelLayoutMode != 'fullscreen') {
      return false;
    }
    if (_parallelWindowSupported && _parallelWindowEnabled) {
      return false;
    }
    return true;
  }

  Future<void> _handlePictureInPictureActivated() async {
    _controlsTimer?.cancel();
    _hideSpeedDialOverlay(restoreAutoHide: false);
    for (var index = 0; index < 4; index++) {
      final dismissed = await _dismissActiveTransientUi();
      if (!dismissed) break;
    }
    if (!mounted) return;
    _hideControlsImmediately();
  }

  Future<void> _enterPictureInPictureMode() async {
    if (!_shouldShowPictureInPictureButton()) {
      return;
    }
    await _handlePictureInPictureActivated();
    final entered = await PlayerHostBridge.enterPictureInPicture();
    if (!mounted || entered) {
      return;
    }
    _showTopTip('当前无法进入小窗播放', context.appColors.warning);
  }

  Widget _buildBottomPanel({
    required MpvPlayerValue value,
    required bool compactUi,
    required bool isLandscape,
    required double timeFontSize,
    required Duration duration,
    required Duration clampedPosition,
    required Duration bufferedPosition,
    required List<MpvChapterItem> visibleChapters,
    required int activeChapterIndex,
    required bool minimalSeekMode,
    required bool showStatusCard,
  }) {
    final panelVisible = _controlsVisible || minimalSeekMode;
    final extendedChromeVisible = _controlsVisible && !minimalSeekMode;
    return PlayerControlsBottomPanel(
      panelVisible: panelVisible,
      extendedChromeVisible: extendedChromeVisible,
      compactUi: compactUi,
      isLandscape: isLandscape,
      minimalSeekMode: minimalSeekMode,
      showStatusCard: showStatusCard,
      timeFontSize: timeFontSize,
      duration: duration,
      clampedPosition: clampedPosition,
      bufferedPosition: bufferedPosition,
      visibleChapters: visibleChapters,
      activeChapterIndex: activeChapterIndex,
      extraProgressMarkers: <PlayerProgressChapterMarker>[
        ..._bookmarkProgressMarkers(duration),
        ..._abLoopProgressMarkers(duration),
      ],
      progressHighlight: _abLoopProgressHighlight(duration),
      value: value,
      statusCard: _buildStatusCard(value),
      resumePrompt: _buildResumePromptData(duration),
      autoPlayPrompt: _buildAutoPlayPromptData(),
      bottomControls: _buildBottomControls(
        value: value,
        compactUi: compactUi,
        isLandscape: isLandscape,
      ),
      onTimelineInteractionStart: () {
        if (!mounted) return;
        _updatePlayerState(
          () => _uiController.timelineInteractionActive = true,
        );
      },
      onTimelineInteractionEnd: () {
        if (!mounted) return;
        _updatePlayerState(
          () => _uiController.timelineInteractionActive = false,
        );
      },
      onTimelineChangeStart: duration.inMilliseconds <= 0
          ? null
          : (fraction) {
              final next = Duration(
                milliseconds: (fraction * duration.inMilliseconds).round(),
              );
              _controlsTimer?.cancel();
              _gestureController.beginSliderDrag(next);
              _updatePlayerState(() => _uiController.draggingPosition = next);
            },
      onTimelineChanged: duration.inMilliseconds <= 0
          ? null
          : (fraction) {
              final next = Duration(
                milliseconds: (fraction * duration.inMilliseconds).round(),
              );
              _controlsTimer?.cancel();
              _gestureController.updateSliderDrag(next);
              _updatePlayerState(() => _uiController.draggingPosition = next);
            },
      onTimelineChangeEnd: duration.inMilliseconds <= 0
          ? null
          : (fraction) async {
              final target = Duration(
                milliseconds: (fraction * duration.inMilliseconds).round(),
              );
              _gestureController.completeSliderDrag(target);
              _updatePlayerState(() {
                _uiController.draggingPosition = null;
                _uiController.timelineInteractionActive = false;
              });
              await _seekWithStats(target, userInitiated: true);
              _showControls();
            },
      onToggleOrientation: _togglePlayerOrientation,
      formatDuration: _formatDuration,
    );
  }

  Widget _buildStatusCard(MpvPlayerValue value) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xA6000000),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value.statusText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (value.error != null && value.error!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                value.error!,
                style: const TextStyle(color: Color(0xFFFF9A9A), fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  PlayerResumePromptData? _buildResumePromptData(Duration duration) {
    if (!_overlayState.resumePromptVisible) {
      return null;
    }
    if (!_shouldShowResumePrompt(
      startPosition: _resumeStartPosition,
      durationSeconds: duration.inSeconds,
    )) {
      return null;
    }
    final resumeLabel = _formatDuration(_resumeStartPosition);
    return PlayerResumePromptData(
      message: _t(
        'player.play.resumePrompt',
        '继续播放到 {position}',
        params: <String, Object?>{'position': resumeLabel},
      ),
      restartLabel: _t('player.play.restartFromBeginning', '从头播放'),
      onRestart: () {
        unawaited(_restartFromBeginningFromResumePrompt());
      },
      onDismiss: () {
        _setResumePromptVisibility(false);
        _scheduleControlsAutoHide();
      },
    );
  }

  PlayerAutoPlayPromptData? _buildAutoPlayPromptData() {
    if (!_completionController.autoPlayPromptVisible ||
        !_completionController.completionHasNextEpisode) {
      return null;
    }
    final seconds = _completionController.autoPlayCountdownSeconds.clamp(1, 99);
    return PlayerAutoPlayPromptData(
      message: _t(
        'player.play.autoPlayPrompt',
        '{seconds} 秒后自动连播下一集',
        params: <String, Object?>{'seconds': seconds},
      ),
      onSkip: () {
        _cancelAutoPlayPrompt();
      },
      onReplay: () {
        unawaited(_replayCurrentEpisodeFromPrompt());
      },
    );
  }

  Widget _buildPlaybackCompletedOverlay({required bool compactUi}) {
    final data = _buildPlaybackCompletedData();
    if (data == null) {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.38),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compactUi ? 20 : 28,
              vertical: compactUi ? 20 : 28,
            ),
            child: PlayerPlaybackCompletedPanel(compact: compactUi, data: data),
          ),
        ),
      ),
    );
  }

  PlayerPlaybackCompletedData? _buildPlaybackCompletedData() {
    if (!_playbackCompleted) {
      return null;
    }
    final nasProvider = _nasProvider ?? context.read<NasProvider>();
    final token = nasProvider.token.trim();
    final posterUrls = _resolveSystemPlaybackArtworkUrls();
    final duration = _effectiveDuration();
    return PlayerPlaybackCompletedData(
      title: _currentTitle.trim().isEmpty ? '当前视频' : _currentTitle.trim(),
      durationLabel: _formatDuration(duration),
      posterUrls: posterUrls,
      token: token,
      onReplay: () {
        unawaited(_replayCompletedItem());
      },
      onBack: () {
        unawaited(_closePlayer());
      },
    );
  }

  void _cancelAutoPlayPrompt() {
    _completionController.suppressAutoPlayPromptForCurrentItem();
    _invalidateNextEpisodePreload();
    _overlayState.showControls();
    _overlayState.cancelAutoHide();
  }

  Future<void> _restartFromBeginningFromResumePrompt() async {
    _setResumePromptVisibility(false);
    _resumeStartPosition = Duration.zero;
    _gestureController.resetSeekTracking();
    await _seekWithStats(Duration.zero, userInitiated: false);
    if (!mounted) {
      return;
    }
    if (_controller.value.value.paused) {
      await _controller.play();
      if (!mounted) {
        return;
      }
    }
    _showControls();
    _scheduleControlsAutoHide();
  }

  Widget _buildBottomControls({
    required MpvPlayerValue value,
    required bool compactUi,
    required bool isLandscape,
  }) {
    final listenVideoActive = _listenVideoModeEnabled;
    final portraitTightControls = !isLandscape;
    final portraitBottomPadding = portraitTightControls
        ? (compactUi ? 6.0 : 8.0)
        : 0.0;
    final playControlScale = portraitTightControls ? 0.66 : 1.0;
    final sideControlScale = portraitTightControls ? 0.72 : 1.0;
    final portraitPlayMinSize = portraitTightControls ? 28.0 : null;
    final portraitSideMinSize = portraitTightControls ? 22.0 : null;
    final portraitControlPadding = portraitTightControls ? 1.0 : null;
    final actionButtons = <Widget>[
      PlayerActionTextButton(label: '重载', onPressed: _reloadCurrentSource),
      PlayerActionTextButton(label: '选集', onPressed: _showEpisodeSheet),
      PlayerActionTextButton(
        label: _speedLabel(_playbackSpeed),
        onPressed: _toggleSpeedDialOverlay,
      ),
      PlayerActionTextButton(label: '音轨', onPressed: _showAudioSheet),
      PlayerActionTextButton(
        label: (_currentSubtitleGuid ?? '').trim().isEmpty ? '字幕关' : '字幕',
        onPressed: _showSubtitleSheet,
      ),
      PlayerActionTextButton(
        label: _currentQualityButtonLabel(),
        onPressed: _showQualitySheet,
      ),
      if (_showCloudDriveUiEntry)
        PlayerActionIconChipButton(
          icon: Icons.cloud_queue_rounded,
          onPressed: () => unawaited(_showCloudDriveModeSheet()),
        ),
    ];
    if (listenVideoActive) {
      if (actionButtons.length > 5) {
        actionButtons.removeAt(5);
      }
      if (actionButtons.length > 4) {
        actionButtons.removeAt(4);
      }
    }
    if (!_shouldShowEpisodeEntry() && actionButtons.length > 1) {
      actionButtons.removeAt(1);
    }

    final leadingControls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlayerBottomControlButton(
          icon: value.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
          loading:
              !_uiController.backgroundLoadingTransition &&
              (_uiController.pendingLoadingTransition ||
                  _uiController.qualitySwitchLoading ||
                  _uiController.awaitingVisualPlaybackStart),
          compact: compactUi,
          emphasis: true,
          scale: playControlScale,
          minSizeOverride: portraitPlayMinSize,
          paddingOverride: portraitControlPadding,
          onPressed: _togglePlayback,
        ),
        SizedBox(width: portraitTightControls ? 1 : (compactUi ? 0 : 1)),
        PlayerBottomControlButton(
          icon: Icons.skip_next_rounded,
          compact: compactUi,
          scale: sideControlScale,
          minSizeOverride: portraitSideMinSize,
          paddingOverride: portraitControlPadding,
          onPressed: _showNextEpisode,
        ),
        if (!listenVideoActive) ...[
          SizedBox(width: portraitTightControls ? 1 : (compactUi ? 2 : 4)),
          PlayerBottomAssetControlButton(
            assetName: _danmakuToggleAsset,
            compact: compactUi,
            scale: sideControlScale,
            minSizeOverride: portraitSideMinSize,
            paddingOverride: portraitControlPadding,
            onPressed: () => unawaited(_toggleDanmakuEnabled()),
          ),
        ],
      ],
    );

    final actionGroup = Wrap(
      spacing: compactUi ? 8 : 10,
      runSpacing: compactUi ? 8 : 10,
      alignment: WrapAlignment.end,
      children: actionButtons,
    );

    if (portraitTightControls) {
      return Padding(
        padding: EdgeInsets.only(bottom: portraitBottomPadding),
        child: Row(
          children: [
            leadingControls,
            const SizedBox(width: 6),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < actionButtons.length; i++) ...[
                        actionButtons[i],
                        if (i != actionButtons.length - 1)
                          const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Transform.translate(
      offset: const Offset(0, -1),
      child: Row(
        children: [
          leadingControls,
          SizedBox(width: compactUi ? 6 : 12),
          Expanded(
            child: Align(alignment: Alignment.centerRight, child: actionGroup),
          ),
        ],
      ),
    );
  }

  Future<void> _showCloudDriveModeSheet() async {
    _hideSpeedDialOverlay(restoreAutoHide: false);
    _overlayState.cancelAutoHide();
    final restoreControls = _controlsVisible;
    if (restoreControls) {
      _hideControlsImmediately();
    }
    final directQuality = _cloudDriveDirectQualityOption();
    final proxyQuality = _cloudDriveProxyQualityOption();
    String? action;
    try {
      action = await PlayerNestedSheet.show<String>(
        context,
        initialPageId: _playerCloudDriveModePageId,
        barrierLabel: 'cloud drive mode drawer',
        pages: <PlayerNestedSheetPage<String>>[
          PlayerNestedSheetPage<String>(
            id: _playerCloudDriveModePageId,
            builder: (context, drawer) {
              return PlayerNestedSheetScaffold(
                header: PlayerNestedSheetHeader(
                  title: '网盘播放方式',
                  actions: <Widget>[
                    PlaybackSettingsHeaderAction(
                      icon: Icons.close_rounded,
                      label: '关闭',
                      onTap: drawer.close,
                    ),
                  ],
                ),
                child: PlayerCloudDriveSheet(
                  data: PlayerCloudDriveSheetData(
                    accountName: '网盘',
                    directPlaySelected: _isCloudDriveDirectSelected(),
                    proxyPlaySelected: _isCloudDriveProxySelected(),
                    directPlayEnabled: directQuality != null,
                    proxyPlayEnabled: proxyQuality != null,
                    onDirectPlayPressed: directQuality == null
                        ? null
                        : () => drawer.close(_playerCloudDriveActionDirect),
                    /*
                  _showTransientMessage('网盘播放方式切换待接入');
                },
                onProxyPlayPressed: () {
                  Navigator.of(dialogContext).pop();
                  _showTransientMessage('网盘播放方式切换待接入');
                },
              ),
            ),
          ),
        );
      },
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
                */
                    onProxyPlayPressed: proxyQuality == null
                        ? null
                        : () => drawer.close(_playerCloudDriveActionProxy),
                  ),
                ),
              );
            },
          ),
        ],
      );
    } finally {
      if (mounted && restoreControls) {
        _showControls();
      }
    }
    if (!mounted) return;
    if (action == _playerCloudDriveActionDirect) {
      await _switchCloudDrivePlaybackMode(direct: true);
    } else if (action == _playerCloudDriveActionProxy) {
      await _switchCloudDrivePlaybackMode(direct: false);
    }
  }

  bool _isCloudDriveDirectSelected() => _playbackMode.isDirectLink;

  bool _isCloudDriveProxySelected() {
    return !_playbackMode.isDirectLink && !_playbackMode.isServerManaged;
  }

  PlaybackQualityOption? _cloudDriveDirectQualityOption() {
    PlaybackQualityOption? current;
    PlaybackQualityOption? preferred;
    PlaybackQualityOption? fallback;
    for (final quality in _qualities) {
      if (!quality.isDirectLink) continue;
      fallback ??= quality;
      if (_currentDirectLinkQualityIndex != null &&
          quality.directLinkQualityIndex == _currentDirectLinkQualityIndex) {
        current = quality;
      }
      if (quality.isDefault == 1) {
        preferred ??= quality;
      }
    }
    return current ?? preferred ?? fallback;
  }

  PlaybackQualityOption? _cloudDriveProxyQualityOption() {
    for (final quality in _qualities) {
      if (quality.isOriginalProxy) return quality;
    }
    return null;
  }

  Future<void> _switchCloudDrivePlaybackMode({required bool direct}) async {
    final quality = direct
        ? _cloudDriveDirectQualityOption()
        : _cloudDriveProxyQualityOption();
    if (quality == null) {
      _showTransientMessage(direct ? '当前没有可用的网盘直链播放源' : '当前没有可用的 NAS 代理播放源');
      return;
    }
    final alreadySelected = direct
        ? _isCloudDriveDirectSelected() &&
              (_currentDirectLinkQualityIndex == quality.directLinkQualityIndex)
        : _isCloudDriveProxySelected();
    if (alreadySelected) {
      _showControls();
      return;
    }
    await _switchQuality(
      quality,
      loadingMessage: direct
          ? '正在为您切换至网盘直连播放，请稍候...'
          : '正在为您切换至 NAS 代理播放，请稍候...',
    );
  }

  List<MpvChapterItem> _visibleChaptersForDuration(Duration duration) {
    if (_chapters.isEmpty || duration <= Duration.zero) {
      return const <MpvChapterItem>[];
    }
    return _chapters
        .where((chapter) => chapter.time <= duration)
        .toList(growable: false);
  }

  int _activeChapterIndexForPosition(
    List<MpvChapterItem> visibleChapters,
    Duration position,
  ) {
    var activeChapterIndex = visibleChapters.isNotEmpty
        ? visibleChapters.first.index
        : -1;
    for (final chapter in visibleChapters) {
      if (position >= chapter.time) {
        activeChapterIndex = chapter.index;
      }
    }
    return activeChapterIndex;
  }
}
