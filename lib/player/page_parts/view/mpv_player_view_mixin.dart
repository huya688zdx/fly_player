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
    return WillPopScope(
      onWillPop: () async {
        await _closePlayer();
        return false;
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
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: Center(
            child: AspectRatio(
              aspectRatio: _videoAspectRatio(),
              child: ClipRect(child: _buildPlayerSurface()),
            ),
          ),
        ),
        _buildDanmakuLayer(),
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
          child: PlayerCenterMessageOverlay(
            message: _uiController.centerPopupMessage,
          ),
        ),
      ],
    );
  }

  Widget _buildDanmakuLayer() {
    return ValueListenableBuilder<MpvPlayerValue>(
      valueListenable: _controller.value,
      builder: (context, value, _) {
        final duration = _effectiveDuration();
        final rawPlaybackPosition =
            duration > Duration.zero && value.position > duration
            ? duration
            : value.position;
        return Positioned.fill(
          child: DanmakuOverlay(
            controller: _danmakuController,
            position: rawPlaybackPosition,
            paused: value.paused,
          ),
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

  Widget _buildInteractiveChromeLayer(
    BuildContext context, {
    required bool compactUi,
    required bool isLandscape,
    required double titleFontSize,
    required double timeFontSize,
  }) {
    return AnimatedBuilder(
      animation: _gestureController,
      builder: (context, _) {
        final overlaySuppressed = _playbackSettingsDrawerVisible;
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
                PlayerGestureOverlay(
                  adjustment: _gestureOverlayData,
                  speedBoostActive: _speedBoostActive,
                  statusMessage:
                      (_uiController.subtitleSwitchMessage?.trim().isNotEmpty ??
                          false)
                      ? _uiController.subtitleSwitchMessage
                      : _uiController.statusMessage,
                  statusLoading:
                      _uiController.qualitySwitchLoading ||
                      _uiController.pendingLoadingTransition ||
                      _uiController.awaitingVisualPlaybackStart,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPlayerSurface() {
    return AndroidView(
      viewType: 'fly_player/mpv_view',
      layoutDirection: TextDirection.ltr,
      creationParams: _buildCurrentSource().toMap(),
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _handlePlatformViewCreated,
    );
  }

  bool _shouldShowPerformanceOverlay() {
    if (!_performanceOverlayEnabled && !_fpsOverlayEnabled) return false;
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
          final gpu = _formatOverlayPercent(stats.gpuUsagePercent) ?? '--';
          rows.add('CPU $cpu  GPU $gpu');
        }
        if (_fpsOverlayEnabled) {
          final fps = _overlayFpsValue(stats);
          rows.add(
            fps == null
                ? 'FPS --'
                : 'FPS ${fps.toStringAsFixed(fps >= 100 ? 0 : 1)}',
          );
        }
        final fontSize = compactUi ? 10.5 : 11.5;
        final overlayWidth = compactUi ? 148.0 : 172.0;
        final overlayHeight = rows.length > 1 ? 42.0 : 28.0;
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

  double? _overlayFpsValue(MpvPerformanceOverlayStats stats) {
    return stats.estimatedVfFps ?? stats.containerFps ?? stats.displayFps;
  }

  bool _isPointInsidePerformanceOverlay(Offset position) {
    if (!_shouldShowPerformanceOverlay()) return false;
    final media = MediaQuery.of(context);
    final compactUi = media.size.width < 900;
    final overlayWidth = compactUi ? 148.0 : 172.0;
    final rowCount =
        (_performanceOverlayEnabled ? 1 : 0) + (_fpsOverlayEnabled ? 1 : 0);
    final overlayHeight = rowCount > 1 ? 42.0 : 28.0;
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
    return IgnorePointer(
      ignoring: !overlayVisible,
      child: Opacity(
        opacity: overlayVisible ? 1 : 0,
        child: PlayerGestureLayer(
          onTap: _controlsVisible ? _hideControlsAnimated : _toggleControls,
          onDoubleTap: _togglePlayback,
          onLongPressStart: _handleGestureLongPressStart,
          onLongPressEnd: _handleGestureLongPressEnd,
          onHorizontalDragStart: (details) =>
              _handleGestureHorizontalStart(details, duration),
          onHorizontalDragUpdate: (details) =>
              _handleGestureHorizontalUpdate(details, duration),
          onHorizontalDragEnd: _handleGestureHorizontalEnd,
          onHorizontalDragCancel: _handleGestureHorizontalCancel,
          onVerticalDragStart: _handleGestureVerticalStart,
          onVerticalDragUpdate: _handleGestureVerticalUpdate,
          onVerticalDragEnd: _handleGestureVerticalEnd,
          onVerticalDragCancel: _handleGestureVerticalCancel,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0x90000000),
                  Color(0x24000000),
                  Color(0x10000000),
                  Color(0xB8000000),
                ],
                stops: <double>[0.0, 0.18, 0.56, 1.0],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  compactUi ? 2 : 4,
                  20,
                  compactUi ? 8 : 10,
                ),
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
  }

  Widget _buildGestureLayer({required Duration duration}) {
    return PlayerGestureLayer(
      onTap: _toggleControls,
      onDoubleTap: _togglePlayback,
      onLongPressStart: _handleGestureLongPressStart,
      onLongPressEnd: _handleGestureLongPressEnd,
      onHorizontalDragStart: (details) =>
          _handleGestureHorizontalStart(details, duration),
      onHorizontalDragUpdate: (details) =>
          _handleGestureHorizontalUpdate(details, duration),
      onHorizontalDragEnd: _handleGestureHorizontalEnd,
      onHorizontalDragCancel: _handleGestureHorizontalCancel,
      onVerticalDragStart: _handleGestureVerticalStart,
      onVerticalDragUpdate: _handleGestureVerticalUpdate,
      onVerticalDragEnd: _handleGestureVerticalEnd,
      onVerticalDragCancel: _handleGestureVerticalCancel,
    );
  }

  void _handleGestureHorizontalStart(
    DragStartDetails details,
    Duration duration,
  ) {
    if (duration <= Duration.zero) return;
    if (_uiController.timelineInteractionActive) return;
    if (_isPointInsidePerformanceOverlay(details.localPosition)) return;
    _gestureController.handleHorizontalStart(
      details: details,
      currentPosition: _displayPosition(_controller.value.value),
      restoreControlsVisible: _controlsVisible,
    );
  }

  void _handleGestureHorizontalUpdate(
    DragUpdateDetails details,
    Duration duration,
  ) {
    if (duration <= Duration.zero) return;
    if (_uiController.timelineInteractionActive) return;
    final width = MediaQuery.sizeOf(context).width;
    _gestureController.handleHorizontalUpdate(
      details: details,
      width: width,
      duration: duration,
    );
  }

  void _handleGestureHorizontalEnd(DragEndDetails details) {
    if (_uiController.timelineInteractionActive) return;
    final result = _gestureController.completeHorizontalSeek();
    if (result == null) return;
    unawaited(_controller.seek(result.target));
    if (result.restoreControlsVisible) {
      _showControls();
    }
  }

  void _handleGestureHorizontalCancel() {
    if (_uiController.timelineInteractionActive) return;
    _gestureController.cancelHorizontalSeek();
  }

  void _handleGestureVerticalStart(DragStartDetails details) {
    final size = MediaQuery.sizeOf(context);
    if (_isPointInsidePerformanceOverlay(details.localPosition)) return;
    final topInset = MediaQuery.viewPaddingOf(context).top;
    final guardHeight = (topInset + 56).clamp(64.0, 120.0);
    if (details.localPosition.dy <= guardHeight) {
      return;
    }
    _gestureController.handleVerticalStart(
      details: details,
      width: size.width,
      height: size.height,
    );
  }

  void _handleGestureVerticalUpdate(DragUpdateDetails details) {
    final height = MediaQuery.sizeOf(context).height;
    _gestureController.handleVerticalUpdate(details: details, height: height);
  }

  void _handleGestureVerticalEnd(DragEndDetails details) {
    _gestureController.handleVerticalEnd();
  }

  void _handleGestureVerticalCancel() {
    _gestureController.cancelVerticalAdjustment();
  }

  void _handleGestureLongPressStart(LongPressStartDetails details) {
    if (_isPointInsidePerformanceOverlay(details.localPosition)) return;
    final started = _gestureController.beginSpeedBoost(_playbackSpeed);
    if (!started) return;
    unawaited(_controller.setSpeed(2.0));
  }

  void _handleGestureLongPressEnd(LongPressEndDetails details) {
    final restoreSpeed = _gestureController.endSpeedBoost(_playbackSpeed);
    unawaited(_controller.setSpeed(restoreSpeed));
  }

  Widget _buildTopBar(
    BuildContext context, {
    required bool compactUi,
    required double titleFontSize,
    required bool visible,
  }) {
    return PlayerControlsTopBar(
      visible: visible,
      compactUi: compactUi,
      titleFontSize: titleFontSize,
      title: _currentTitle,
      danmakuEnabled: _danmakuEnabled,
      onBack: () => unawaited(_closePlayer()),
      captureFrameBusy: _captureFrameInFlight,
      onCaptureFrame: () => unawaited(_captureCurrentFrame()),
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
      final rawMessage = result['message']?.toString().trim() ?? '';
      final message = rawMessage.isNotEmpty
          ? rawMessage
          : (success ? '截图已保存' : '截图失败');
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
              await _controller.seek(target);
              _showControls();
            },
      onToggleOrientation: !minimalSeekMode ? _togglePlayerOrientation : null,
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

  Widget _buildBottomControls({
    required MpvPlayerValue value,
    required bool compactUi,
    required bool isLandscape,
  }) {
    final portraitTightControls = !isLandscape;
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
        onPressed: _showSpeedSheet,
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
    if (!_shouldShowEpisodeEntry() && actionButtons.length > 1) {
      actionButtons.removeAt(1);
    }

    final leadingControls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlayerBottomControlButton(
          icon: value.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
          loading:
              _uiController.pendingLoadingTransition ||
              _uiController.qualitySwitchLoading ||
              _uiController.awaitingVisualPlaybackStart,
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
    );

    final actionGroup = Wrap(
      spacing: compactUi ? 8 : 10,
      runSpacing: compactUi ? 8 : 10,
      alignment: WrapAlignment.end,
      children: actionButtons,
    );

    return Transform.translate(
      offset: Offset(0, isLandscape ? -1 : 0),
      child: Row(
        children: [
          leadingControls,
          SizedBox(width: portraitTightControls ? 2 : (compactUi ? 6 : 12)),
          Expanded(
            child: Align(alignment: Alignment.centerRight, child: actionGroup),
          ),
        ],
      ),
    );
  }

  Future<void> _showCloudDriveModeSheet() async {
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
      _showTransientMessage(
        direct ? '当前没有可用的网盘直链播放源' : '当前没有可用的 NAS 代理播放源',
      );
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
