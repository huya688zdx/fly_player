part of '../../mpv_player_page.dart';

const String _playerCloudDriveModePageId = 'player_cloud_drive_mode';
const String _playerCloudDriveActionDirect = 'player_cloud_drive_action_direct';
const String _playerCloudDriveActionProxy = 'player_cloud_drive_action_proxy';

extension _MpvPlayerViewMixin on _MpvPlayerPageState {
  static const Color _videoBackgroundColor = Colors.black;
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
      backgroundColor: _videoBackgroundColor,
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
      child: ColoredBox(
        color: _videoBackgroundColor,
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            RepaintBoundary(
              child: _buildVideoViewportLayer(_buildPlayerSurface()),
            ),
            if (!widget.pictureInPictureActive && !listenVideoActive)
              RepaintBoundary(
                child: _buildVideoViewportLayer(_buildDanmakuLayer()),
              ),
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
                  opacity: _uiController.orientationTransitionMaskVisible
                      ? 1
                      : 0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: const ColoredBox(color: _videoBackgroundColor),
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
              if (_playbackCompleted)
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
              Positioned.fill(child: _buildWeakNetworkSuggestionOverlayLayer()),
              if (_speedDialVisible &&
                  !_playbackSettingsDrawerVisible &&
                  !_playbackCompleted)
                Positioned.fill(
                  child: PlayerSpeedDialOverlay(
                    visible: true,
                    speed: _playbackSpeed,
                    onSpeedChanged: _handleSpeedDialSpeedChanged,
                    onDismiss: _hideSpeedDialOverlay,
                    labelBuilder: _speedLabel,
                  ),
                ),
            ],
          ],
        ),
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
      parts.add(
        AppLocalizations.of(
          context,
        ).playerEpisodeSeasonTemplate(_currentSeasonNumber.toString()),
      );
    }
    if (_currentEpisodeNumber > 0) {
      parts.add(
        AppLocalizations.of(
          context,
        ).playerEpisodeNumberLabel(_currentEpisodeNumber),
      );
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
      animation: _danmakuLayerListenable,
      builder: (context, _) {
        final value = _controller.value.value;
        final duration = _effectiveDuration();
        final rawPlaybackPosition =
            duration > Duration.zero && value.position > duration
            ? duration
            : value.position;
        final sheetActive = AppSheetTransitions.activeSheetCount.value > 0;
        return DanmakuOverlay(
          controller: _danmakuController,
          position: rawPlaybackPosition,
          paused:
              sheetActive ||
              value.playbackPhase != MpvPlaybackPhase.playing,
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
              secondaryMessage: _videoLoadingOverlaySecondaryMessage(value),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWeakNetworkSuggestionOverlayLayer() {
    final suggestion = _uiController.weakNetworkSuggestion;
    return PlayerWeakNetworkSuggestionOverlay(
      visible: suggestion != null,
      title: suggestion?.title ?? '',
      subtitle: suggestion?.subtitle ?? '',
      onSwitch: () => unawaited(_applyWeakNetworkSuggestion()),
      onDismiss: _dismissWeakNetworkSuggestion,
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
    return AnimatedBuilder(
      animation: _overlayState,
      builder: (context, _) {
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
              onPressed: () => unawaited(
                _playerUiLocked ? _unlockPlayerUi() : _lockPlayerUi(),
              ),
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
    final chromeStack = Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: _buildGestureCaptureLayer()),
        _buildControlsChromeLayer(
          context,
          compactUi: compactUi,
          isLandscape: isLandscape,
          titleFontSize: titleFontSize,
          timeFontSize: timeFontSize,
        ),
        _buildGestureStatusLayer(),
      ],
    );
    return AnimatedBuilder(
      animation: AppSheetTransitions.activeSheetCount,
      child: chromeStack,
      builder: (context, child) {
        if (AppSheetTransitions.activeSheetCount.value > 0) {
          return TickerMode(
            enabled: false,
            child: Offstage(offstage: true, child: child),
          );
        }
        return child!;
      },
    );
  }

  Widget _buildGestureCaptureLayer() {
    return AnimatedBuilder(
      animation: _gestureCaptureLayerListenable,
      child: ValueListenableBuilder<MpvPlayerValue>(
        valueListenable: _controller.value,
        builder: (context, value, _) {
          final duration = _effectiveDuration();
          return RepaintBoundary(child: _buildGestureLayer(duration: duration));
        },
      ),
      builder: (context, child) {
        return IgnorePointer(
          ignoring: _shouldIgnoreGestureCaptureLayer(),
          child: child,
        );
      },
    );
  }

  Widget _buildControlsChromeLayer(
    BuildContext context, {
    required bool compactUi,
    required bool isLandscape,
    required double titleFontSize,
    required double timeFontSize,
  }) {
    final topChrome = RepaintBoundary(
      child: _buildTopChrome(
        context,
        compactUi: compactUi,
        titleFontSize: titleFontSize,
      ),
    );
    final bottomChrome = RepaintBoundary(
      child: _buildBottomChrome(
        compactUi: compactUi,
        isLandscape: isLandscape,
        timeFontSize: timeFontSize,
      ),
    );
    final background = RepaintBoundary(
      child: _buildControlsChromeBackground(
        compactUi: compactUi,
        isLandscape: isLandscape,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.of(context);
        final gestureInset =
            media.systemGestureInsets.bottom > media.padding.bottom
            ? media.systemGestureInsets.bottom - media.padding.bottom
            : 0.0;
        final contentPadding = EdgeInsets.fromLTRB(
          20,
          compactUi ? 2 : 4,
          20,
          (compactUi ? 8 : 10) + gestureInset,
        );
        return AnimatedBuilder(
          animation: _controlsChromeLayerListenable,
          builder: (context, _) {
            final overlayVisible = _controlsOverlayVisible;
            final topBarVisible = _controlsTopBarVisible;
            return IgnorePointer(
              ignoring: !_controlsInteractionEnabled,
              child: PlayerGestureLayer(
                onTap: _handleGestureTap,
                onDoubleTap: _enablePlaybackDoubleTap
                    ? _handleGestureDoubleTap
                    : null,
                deferSingleTapForDoubleTap: true,
                tapCoordinator: _gestureTapCoordinator,
                onLongPressStart: _handleGestureLongPressStart,
                onLongPressEnd: _handleGestureLongPressEnd,
                onLongPressCancel: _handleGestureLongPressCancel,
                onHorizontalDragStart: (details) =>
                    _handleGestureHorizontalStart(
                      details,
                      _effectiveDuration(),
                      constraints.biggest,
                    ),
                onHorizontalDragUpdate: (details) =>
                    _handleGestureHorizontalUpdate(
                      details,
                      _effectiveDuration(),
                      constraints.biggest,
                    ),
                onHorizontalDragEnd: _handleGestureHorizontalEnd,
                onHorizontalDragCancel: _handleGestureHorizontalCancel,
                onVerticalDragStart: (details) =>
                    _handleGestureVerticalStart(details, constraints.biggest),
                onVerticalDragUpdate: (details) =>
                    _handleGestureVerticalUpdate(details, constraints.biggest),
                onVerticalDragEnd: _handleGestureVerticalEnd,
                onVerticalDragCancel: _handleGestureVerticalCancel,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildAnimatedChromeBackground(
                      visible: overlayVisible,
                      child: background,
                    ),
                    SafeArea(
                      child: Padding(
                        padding: contentPadding,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildAnimatedChromeSlot(
                              visible: topBarVisible,
                              hiddenOffset: const Offset(0, -0.08),
                              child: topChrome,
                            ),
                            const Spacer(),
                            _buildAnimatedChromeSlot(
                              visible: overlayVisible,
                              hiddenOffset: const Offset(0, 0.08),
                              child: bottomChrome,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTopChrome(
    BuildContext context, {
    required bool compactUi,
    required double titleFontSize,
  }) {
    return _buildTopBar(
      context,
      compactUi: compactUi,
      titleFontSize: titleFontSize,
      visible: true,
    );
  }

  Widget _buildBottomChrome({
    required bool compactUi,
    required bool isLandscape,
    required double timeFontSize,
  }) {
    return AnimatedBuilder(
      animation: _bottomChromeListenable,
      builder: (context, _) {
        final minimalSeekMode = _controlsMinimalSeekMode;
        // Snapshot the current player value once per overlay/seek tick. The
        // bottom panel's position-driven leaves (time label, slider thumb)
        // subscribe to _controller.value internally, so this outer builder no
        // longer rebuilds the chapter list, controls or layout on every
        // ~160ms position publish.
        final value = _controller.value.value;
        final duration = _effectiveDuration();
        final clampedPosition = _clampPositionToDuration(value, duration);
        final visibleChapters = _controlsOverlayVisible || minimalSeekMode
            ? _visibleChaptersForDuration(duration)
            : const <MpvChapterItem>[];
        final activeChapterIndex =
            visibleChapters.isEmpty ||
                !(_controlsOverlayVisible || minimalSeekMode)
            ? -1
            : _activeChapterIndexForPosition(
                visibleChapters,
                clampedPosition,
              );
        return _buildBottomPanel(
          value: value,
          compactUi: compactUi,
          isLandscape: isLandscape,
          timeFontSize: timeFontSize,
          duration: duration,
          visibleChapters: visibleChapters,
          activeChapterIndex: activeChapterIndex,
          minimalSeekMode: minimalSeekMode,
          showStatusCard: false,
        );
      },
    );
  }

  Duration _clampPositionToDuration(MpvPlayerValue value, Duration duration) {
    final position = _displayPosition(value);
    if (duration > Duration.zero && position > duration) {
      return duration;
    }
    return position;
  }

  Duration _clampBufferedPositionToDuration(
    MpvPlayerValue value,
    Duration duration,
  ) {
    if (_currentSourceIsDownloadedFile) {
      return Duration.zero;
    }
    if (duration > Duration.zero && value.bufferedPosition > duration) {
      return duration;
    }
    return value.bufferedPosition;
  }

  Widget _buildControlsChromeBackground({
    required bool compactUi,
    required bool isLandscape,
  }) {
    final topHeight = compactUi
        ? (isLandscape ? 112.0 : 120.0)
        : (isLandscape ? 128.0 : 138.0);
    final bottomHeight = compactUi
        ? (isLandscape ? 146.0 : 162.0)
        : (isLandscape ? 170.0 : 188.0);
    final topColors = _listenVideoModeEnabled
        ? const <Color>[Color(0x5413202F), Color(0x18000000), Color(0x00000000)]
        : const <Color>[
            Color(0x78000000),
            Color(0x24000000),
            Color(0x00000000),
          ];
    final bottomColors = _listenVideoModeEnabled
        ? const <Color>[Color(0x00000000), Color(0x160B1119), Color(0x7813202F)]
        : const <Color>[
            Color(0x00000000),
            Color(0x18000000),
            Color(0x98000000),
          ];
    return Column(
      children: [
        SizedBox(
          height: topHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: topColors,
              ),
            ),
          ),
        ),
        const Spacer(),
        SizedBox(
          height: bottomHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: bottomColors,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnimatedChromeBackground({
    required bool visible,
    required Widget child,
  }) {
    return IgnorePointer(
      ignoring: true,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }

  Widget _buildAnimatedChromeSlot({
    required bool visible,
    required Offset hiddenOffset,
    required Widget child,
  }) {
    return AnimatedSlide(
      offset: visible ? Offset.zero : hiddenOffset,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }

  Widget _buildGestureStatusLayer() {
    return AnimatedBuilder(
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
                  (_uiController.subtitleSwitchMessage?.trim().isNotEmpty ??
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
    );
  }

  bool get _controlsOverlaySuppressed =>
      _playbackSettingsDrawerVisible || _speedDialVisible || _playerUiLocked;

  bool get _controlsMinimalSeekMode =>
      _gestureSeekActive ||
      (!_controlsVisible && _gestureController.pendingSeekPosition != null);

  bool get _controlsOverlayVisible =>
      !_controlsOverlaySuppressed &&
      (_controlsVisible || _controlsMinimalSeekMode);

  bool get _controlsTopBarVisible =>
      !_controlsOverlaySuppressed &&
      _controlsVisible &&
      !_controlsMinimalSeekMode;

  bool get _controlsMounted =>
      !_controlsOverlaySuppressed &&
      (_controlsVisible || _controlsAnimatingOut || _controlsMinimalSeekMode);

  bool get _controlsInteractionEnabled => _controlsOverlayVisible;

  bool _shouldIgnoreGestureCaptureLayer() {
    return _controlsMounted;
  }

  Widget _buildPlayerSurface() {
    if (!_platformViewAttached && !_initialDanmakuPreferencesLoaded) {
      return const ColoredBox(color: Colors.black);
    }

    final initialSource = _resolvedPlatformViewSource(
      _initialSourceLoadStarted ? _buildCurrentSource() : widget.source,
    );
    final platformViewBackend = initialSource.videoOutputBackend;
    final creationParams = initialSource.toMap();
    creationParams['enableNativeDanmakuRenderer'] = _useNativeDanmakuRenderer;
    return PlatformViewLink(
      key: ValueKey<String>('mpv_view_$platformViewBackend'),
      viewType: 'fly_player/mpv_view',
      surfaceFactory: (context, controller) {
        return AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        );
      },
      onCreatePlatformView: (params) {
        final controller = PlatformViewsService.initSurfaceAndroidView(
          id: params.id,
          viewType: 'fly_player/mpv_view',
          layoutDirection: TextDirection.ltr,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onFocus: () => params.onFocusChanged(true),
        );
        controller.addOnPlatformViewCreatedListener(
          params.onPlatformViewCreated,
        );
        controller.addOnPlatformViewCreatedListener(
          (viewId) =>
              _handlePlatformViewCreated(viewId, backend: platformViewBackend),
        );
        controller.create();
        return controller;
      },
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
      animation: _performanceOverlayListenable,
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

  Widget _buildGestureLayer({required Duration duration}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = constraints.biggest;
        final gesturesEnabled = !_playerUiLocked;
        return PlayerGestureLayer(
          onTap: _handleGestureTap,
          onDoubleTap: gesturesEnabled && _enablePlaybackDoubleTap
              ? _handleGestureDoubleTap
              : null,
          deferSingleTapForDoubleTap: true,
          tapCoordinator: _gestureTapCoordinator,
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

  bool get _enablePlaybackDoubleTap => true;

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
    unawaited(_syncNativeDanmakuRenderer());
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
    unawaited(_togglePlayback(revealControls: false));
  }

  void _restoreSpeedBoostIfNeeded() {
    final restoreSpeed = _gestureController.cancelSpeedBoost(_playbackSpeed);
    if (restoreSpeed == null) return;
    unawaited(HapticFeedback.selectionClick());
    unawaited(_controller.setSpeed(restoreSpeed));
    unawaited(_syncNativeDanmakuRenderer());
  }

  // ignore: unused_element
  Future<void> _showAudioOutputPicker() async {
    return;
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
      onFitMode: () => _showTransientMessage(
        AppLocalizations.of(context).playerFitModeUnavailable,
      ),
      onDanmakuSettings: () => unawaited(_openDanmakuSettings()),
      onMore: () => unawaited(_showPlaybackSettingsDrawer()),
    );
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
        result.enabled
            ? AppLocalizations.of(context).playerListenVideoEnabled
            : AppLocalizations.of(context).playerListenVideoRestored,
        context.appColors.success,
        revealControls: true,
      );
      if (_controlsVisible) {
        _scheduleControlsAutoHide();
      }
      return;
    }
    final message = _listenVideoResultMessage(
      targetEnabled: targetEnabled,
      rawMessage: result.message,
    );
    _showTopTip(message, context.appColors.danger, revealControls: true);
  }

  String _listenVideoResultMessage({
    required bool targetEnabled,
    String? rawMessage,
  }) {
    final l10n = AppLocalizations.of(context);
    final normalized = rawMessage?.trim() ?? '';
    if (normalized == 'player not ready') {
      return l10n.playerNotReady;
    }
    if (normalized.isNotEmpty) {
      return normalized;
    }
    return targetEnabled
        ? l10n.playerListenVideoSwitchFailed
        : l10n.playerVideoRestoreFailed;
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
      _showTopTip(
        AppLocalizations.of(context).playerScreenshotModuleMissing,
        context.appColors.warning,
      );
    } catch (_) {
      if (!mounted) return;
      _showTopTip(
        AppLocalizations.of(context).playerScreenshotFailed,
        context.appColors.warning,
      );
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
    final l10n = AppLocalizations.of(context);
    if (success) {
      return l10n.playerScreenshotSaved;
    }
    switch (code) {
      case 'custom_directory_required':
        return l10n.playerScreenshotCustomDirectoryRequired;
      case 'custom_directory_unavailable':
        return l10n.playerScreenshotCustomDirectoryUnavailable;
    }
    switch (rawMessage) {
      case 'player not ready':
        return l10n.playerNotReady;
      case 'capture unavailable':
        return l10n.playerScreenshotUnavailable;
      case 'capture failed':
        return l10n.playerScreenshotFailed;
      case 'capture save failed':
        return l10n.playerScreenshotSaveFailed;
      case 'capture saved':
        return l10n.playerScreenshotSaved;
      case 'Please choose a custom screenshot directory first':
        return l10n.playerScreenshotCustomDirectoryRequired;
      case 'Custom screenshot directory is unavailable':
        return l10n.playerScreenshotCustomDirectoryUnavailable;
      default:
        return rawMessage.isNotEmpty ? rawMessage : l10n.playerScreenshotFailed;
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
    _showTopTip(
      AppLocalizations.of(context).playerPictureInPictureUnavailable,
      context.appColors.warning,
    );
  }

  Widget _buildBottomPanel({
    required MpvPlayerValue value,
    required bool compactUi,
    required bool isLandscape,
    required double timeFontSize,
    required Duration duration,
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
      playerValueListenable: _controller.value,
      computeClampedPosition: (v) => _clampPositionToDuration(v, duration),
      computeBufferedPosition: (v) =>
          _clampBufferedPositionToDuration(v, duration),
      visibleChapters: visibleChapters,
      activeChapterIndex: activeChapterIndex,
      extraProgressMarkers: <PlayerProgressChapterMarker>[
        ..._bookmarkProgressMarkers(duration),
        ..._abLoopProgressMarkers(duration),
      ],
      progressHighlight: _abLoopProgressHighlight(duration),
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
    final l10n = AppLocalizations.of(context);
    return PlayerResumePromptData(
      message: l10n.playerResumePrompt(resumeLabel),
      restartLabel: l10n.playerRestartFromBeginning,
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
      message: AppLocalizations.of(context).playerAutoPlayNextPrompt(seconds),
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
      title: _currentTitle.trim().isEmpty
          ? AppLocalizations.of(context).playerCurrentVideo
          : _currentTitle.trim(),
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
    if (_controller.value.value.playbackPhase != MpvPlaybackPhase.playing) {
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
    final l10n = AppLocalizations.of(context);
    final actionButtons = <Widget>[
      PlayerActionTextButton(
        label: l10n.playerReloadAction,
        onPressed: _reloadCurrentSource,
      ),
      PlayerActionTextButton(
        label: l10n.playerEpisodeAction,
        onPressed: _showEpisodeSheet,
      ),
      PlayerActionTextButton(
        label: _speedLabel(_playbackSpeed),
        onPressed: _toggleSpeedDialOverlay,
      ),
      PlayerActionTextButton(
        label: l10n.playerAudioTrackAction,
        onPressed: _showAudioSheet,
      ),
      PlayerActionTextButton(
        label: (_currentSubtitleGuid ?? '').trim().isEmpty
            ? l10n.playerSubtitleOffAction
            : l10n.playerSubtitleAction,
        onPressed: _showSubtitleSheet,
      ),
      if (!_externalLocalSource)
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

    final showPauseAction = _playbackToggleShowsPause(value);
    final leadingControls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlayerBottomControlButton(
          icon: showPauseAction
              ? Icons.pause_rounded
              : Icons.play_arrow_rounded,
          loading:
              !_uiController.backgroundLoadingTransition &&
              (value.isTransientLoadingPhase ||
                  _uiController.pendingLoadingTransition ||
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
        if (_shouldShowEpisodeEntry())
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

  bool _playbackToggleShowsPause(MpvPlayerValue value) {
    if (value.playbackPhase == MpvPlaybackPhase.playing) {
      return true;
    }
    if (!value.paused && value.playbackPhase != MpvPlaybackPhase.paused) {
      return true;
    }
    final foregroundLoadInProgress =
        !_uiController.backgroundLoadingTransition &&
        (value.isTransientLoadingPhase ||
            _uiController.pendingLoadingTransition ||
            _uiController.qualitySwitchLoading ||
            _uiController.awaitingVisualPlaybackStart);
    return foregroundLoadInProgress &&
        !_uiController.pendingTransitionTargetPaused;
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
    final l10n = AppLocalizations.of(context);
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
                  title: l10n.playerCloudDriveModeTitle,
                  actions: <Widget>[
                    PlaybackSettingsHeaderAction(
                      icon: Icons.close_rounded,
                      label: l10n.mpvOptionOff,
                      onTap: drawer.close,
                    ),
                  ],
                ),
                child: PlayerCloudDriveSheet(
                  data: PlayerCloudDriveSheetData(
                    accountName: l10n.playerCloudDriveAccountName,
                    directPlaySelected: _isCloudDriveDirectSelected(),
                    proxyPlaySelected: _isCloudDriveProxySelected(),
                    directPlayEnabled: directQuality != null,
                    proxyPlayEnabled: proxyQuality != null,
                    onDirectPlayPressed: directQuality == null
                        ? null
                        : () => drawer.close(_playerCloudDriveActionDirect),
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
      if (mounted && !restoreControls) {
        _scheduleControlsAutoHide();
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
    final l10n = AppLocalizations.of(context);
    final quality = direct
        ? _cloudDriveDirectQualityOption()
        : _cloudDriveProxyQualityOption();
    if (quality == null) {
      _showTransientMessage(
        direct
            ? l10n.playerCloudDriveDirectUnavailable
            : l10n.playerCloudDriveProxyUnavailable,
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
          ? l10n.playerCloudDriveSwitchingDirect
          : l10n.playerCloudDriveSwitchingProxy,
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
