part of 'mpv_player_page.dart';

extension _MpvPlayerViewMixin on _MpvPlayerPageState {
  Widget _buildAndroidPlayerScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ValueListenableBuilder<MpvPlayerValue>(
        valueListenable: _controller.value,
        builder: (context, value, _) {
          return AnimatedBuilder(
            animation: _gestureController,
            builder: (context, _) {
              final media = MediaQuery.of(context);
              final screenWidth = media.size.width;
              final isLandscape = media.orientation == Orientation.landscape;
              final compactUi = screenWidth < 900;
              final titleFontSize = compactUi ? 14.0 : 15.5;
              final timeFontSize = compactUi ? 11.5 : 13.0;
              final duration = _effectiveDuration();
              final position = _displayPosition(value);
              final clampedPosition =
                  duration > Duration.zero && position > duration
                  ? duration
                  : position;
              final visibleChapters = _visibleChaptersForDuration(duration);
              final activeChapterIndex = _activeChapterIndexForPosition(
                visibleChapters,
                clampedPosition,
              );
              final activeSkipPrompt = _activeChapterSkipPrompt;
              final minimalSeekMode =
                  _gestureSeekActive ||
                  (!_controlsVisible &&
                      _gestureController.pendingSeekPosition != null);
              final controlsMounted =
                  _controlsVisible || _controlsAnimatingOut || minimalSeekMode;

              return Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: _videoAspectRatio(),
                      child: ClipRect(child: _buildPlayerSurface()),
                    ),
                  ),
                  if (_shouldShowVideoLoadingOverlay(value))
                    Positioned.fill(
                      child: ColoredBox(
                        color: const Color(0x66000000),
                        child: PlayerLoadingOverlay(
                          visible: true,
                          message: '视频加载中',
                        ),
                      ),
                    ),
                  IgnorePointer(
                    ignoring: !_orientationTransitionMaskVisible,
                    child: AnimatedOpacity(
                      opacity: _orientationTransitionMaskVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: const ColoredBox(color: Colors.black),
                    ),
                  ),
                  if (!controlsMounted)
                    Positioned.fill(
                      child: _buildGestureLayer(duration: duration),
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
                    visibleChapters: visibleChapters,
                    activeChapterIndex: activeChapterIndex,
                    overlayVisible: _controlsVisible || minimalSeekMode,
                    minimalSeekMode: minimalSeekMode,
                    showStatusCard: false,
                  ),
                  PlayerGestureOverlay(
                    adjustment: _gestureOverlayData,
                    speedBoostActive: _speedBoostActive,
                    statusMessage:
                        (_subtitleSwitchMessage?.trim().isNotEmpty ?? false)
                        ? _subtitleSwitchMessage
                        : _statusMessage,
                    statusLoading: _qualitySwitchLoading,
                  ),
                  Positioned.fill(
                    child: PlayerSkipPromptOverlay(
                      visible: activeSkipPrompt != null,
                      label: activeSkipPrompt == null
                          ? ''
                          : (activeSkipPrompt.isIntro ? '片头' : '片尾'),
                      countdownSeconds: _skipPromptCountdownSeconds,
                      onClose: _dismissCurrentChapterSkipPrompt,
                    ),
                  ),
                  Positioned.fill(
                    child: PlayerCenterMessageOverlay(
                      message: _centerPopupMessage,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
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

  Widget _buildControlsOverlay(
    BuildContext context, {
    required MpvPlayerValue value,
    required bool compactUi,
    required bool isLandscape,
    required double titleFontSize,
    required double timeFontSize,
    required Duration duration,
    required Duration clampedPosition,
    required List<MpvChapterItem> visibleChapters,
    required int activeChapterIndex,
    required bool overlayVisible,
    required bool minimalSeekMode,
    required bool showStatusCard,
  }) {
    return AnimatedOpacity(
      opacity: overlayVisible ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      child: IgnorePointer(
        ignoring: !overlayVisible,
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
                  compactUi ? 0 : 2,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTopBar(
                      context,
                      compactUi: compactUi,
                      titleFontSize: titleFontSize,
                      visible: _controlsVisible && !minimalSeekMode,
                    ),
                    const Spacer(),
                    _buildBottomPanel(
                      value: value,
                      compactUi: compactUi,
                      isLandscape: isLandscape,
                      timeFontSize: timeFontSize,
                      duration: duration,
                      clampedPosition: clampedPosition,
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
    final width = MediaQuery.sizeOf(context).width;
    _gestureController.handleHorizontalUpdate(
      details: details,
      width: width,
      duration: duration,
    );
  }

  void _handleGestureHorizontalEnd(DragEndDetails details) {
    final result = _gestureController.completeHorizontalSeek();
    if (result == null) return;
    unawaited(_controller.seek(result.target));
    if (result.restoreControlsVisible) {
      _showControls();
    }
  }

  void _handleGestureHorizontalCancel() {
    _gestureController.cancelHorizontalSeek();
  }

  void _handleGestureVerticalStart(DragStartDetails details) {
    final size = MediaQuery.sizeOf(context);
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
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, -0.12),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: Row(
          children: [
            PlayerTopIconButton(
              icon: Icons.arrow_back_ios_new,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            SizedBox(width: compactUi ? 10 : 12),
            Expanded(
              child: PlayerMarqueeText(
                text: _currentTitle,
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
              onPressed: () => _showTransientMessage('画面模式待接入'),
            ),
            SizedBox(width: compactUi ? 6 : 8),
            PlayerTopIconButton(
              icon: Icons.aspect_ratio_outlined,
              onPressed: () => _showTransientMessage('比例切换待接入'),
            ),
            SizedBox(width: compactUi ? 6 : 8),
            PlayerTopIconButton(
              icon: Icons.more_horiz,
              onPressed: () => unawaited(_showPlaybackSettingsDrawer()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomPanel({
    required MpvPlayerValue value,
    required bool compactUi,
    required bool isLandscape,
    required double timeFontSize,
    required Duration duration,
    required Duration clampedPosition,
    required List<MpvChapterItem> visibleChapters,
    required int activeChapterIndex,
    required bool minimalSeekMode,
    required bool showStatusCard,
  }) {
    final panelVisible = _controlsVisible || minimalSeekMode;
    final extendedChromeVisible = _controlsVisible && !minimalSeekMode;
    final panelContent = Transform.translate(
      offset: Offset(0, compactUi ? 4 : 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showStatusCard)
            IgnorePointer(
              ignoring: !extendedChromeVisible,
              child: AnimatedOpacity(
                opacity: extendedChromeVisible ? 1 : 0,
                duration: const Duration(milliseconds: 170),
                child: AnimatedSlide(
                  offset: extendedChromeVisible
                      ? Offset.zero
                      : const Offset(0, 0.06),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: _buildStatusCard(value),
                ),
              ),
            ),
          SizedBox(height: compactUi ? 5 : 7),
          Padding(
            padding: EdgeInsets.only(left: compactUi ? 2 : 4),
            child: Align(
              alignment: minimalSeekMode
                  ? Alignment.center
                  : Alignment.centerLeft,
              child: Transform.translate(
                offset: Offset(minimalSeekMode ? (compactUi ? 6 : 8) : 0, 0),
                child: Text(
                  '${_formatDuration(clampedPosition)}/${_formatDuration(duration)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: timeFontSize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: compactUi ? 3 : 4),
          _buildProgressRow(
            compactUi: compactUi,
            duration: duration,
            clampedPosition: clampedPosition,
            visibleChapters: visibleChapters,
            activeChapterIndex: activeChapterIndex,
            showOrientationButton: true,
            orientationVisible: !minimalSeekMode,
          ),
          SizedBox(height: compactUi ? 2 : 4),
          IgnorePointer(
            ignoring: !extendedChromeVisible,
            child: AnimatedOpacity(
              opacity: extendedChromeVisible ? 1 : 0,
              duration: const Duration(milliseconds: 170),
              child: AnimatedSlide(
                offset: extendedChromeVisible
                    ? Offset.zero
                    : const Offset(0, 0.08),
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                child: _buildBottomControls(
                  value: value,
                  compactUi: compactUi,
                  isLandscape: isLandscape,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return AnimatedSlide(
      offset: panelVisible ? Offset.zero : const Offset(0, 0.14),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: panelVisible ? 1 : 0,
        duration: const Duration(milliseconds: 170),
        child: panelContent,
      ),
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

  Widget _buildChapterChips({
    required bool compactUi,
    required Duration duration,
    required List<MpvChapterItem> visibleChapters,
    required int activeChapterIndex,
  }) {
    return SizedBox(
      height: compactUi ? 28 : 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: visibleChapters.length,
        separatorBuilder: (_, __) => SizedBox(width: compactUi ? 6 : 8),
        itemBuilder: (context, index) {
          final chapter = visibleChapters[index];
          final active = chapter.index == activeChapterIndex;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(_seekToChapter(chapter, duration)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(
                horizontal: compactUi ? 10 : 12,
                vertical: compactUi ? 5 : 6,
              ),
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFF1E7BFF)
                    : const Color(0xD9161B20),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: active
                      ? const Color(0xFF79B7FF)
                      : Colors.white.withAlpha(26),
                ),
              ),
              child: Text(
                _chapterLabel(chapter),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compactUi ? 11.5 : 12.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProgressRow({
    required bool compactUi,
    required Duration duration,
    required Duration clampedPosition,
    required List<MpvChapterItem> visibleChapters,
    required int activeChapterIndex,
    required bool showOrientationButton,
    required bool orientationVisible,
  }) {
    final markerData = duration.inMilliseconds <= 0
        ? const <PlayerProgressChapterMarker>[]
        : visibleChapters
              .where(
                (chapter) =>
                    chapter.time > Duration.zero && chapter.time < duration,
              )
              .map(
                (chapter) => PlayerProgressChapterMarker(
                  fraction:
                      chapter.time.inMilliseconds / duration.inMilliseconds,
                  active: chapter.index == activeChapterIndex,
                ),
              )
              .toList(growable: false);
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: compactUi ? 34 : 36,
            child: PlayerTimelineBar(
              value: duration.inMilliseconds > 0
                  ? clampedPosition.inMilliseconds
                        .clamp(0, duration.inMilliseconds)
                        .toDouble() /
                    duration.inMilliseconds
                  : 0,
              chapterMarkers: markerData,
              onChangeStart: duration.inMilliseconds <= 0
                  ? null
                  : (fraction) {
                      final next = Duration(
                        milliseconds: (fraction * duration.inMilliseconds)
                            .round(),
                      );
                      _controlsTimer?.cancel();
                      setState(() => _draggingPosition = next);
                    },
              onChanged: duration.inMilliseconds <= 0
                  ? null
                  : (fraction) {
                      final next = Duration(
                        milliseconds: (fraction * duration.inMilliseconds)
                            .round(),
                      );
                      _controlsTimer?.cancel();
                      setState(() => _draggingPosition = next);
                    },
              onChangeEnd: duration.inMilliseconds <= 0
                  ? null
                  : (fraction) async {
                      final target = Duration(
                        milliseconds: (fraction * duration.inMilliseconds)
                            .round(),
                      );
                      _gestureController.completeSliderDrag(target);
                      setState(() => _draggingPosition = null);
                      await _controller.seek(target);
                      _showControls();
                    },
            ),
          ),
        ),
        if (showOrientationButton) ...[
          SizedBox(width: compactUi ? 2 : 4),
          IgnorePointer(
            ignoring: !orientationVisible,
            child: AnimatedOpacity(
              opacity: orientationVisible ? 1 : 0,
              duration: const Duration(milliseconds: 170),
              child: PlayerProgressIconButton(
                onPressed: _togglePlayerOrientation,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildProgressMarkers({
    required Duration duration,
    required List<MpvChapterItem> visibleChapters,
    required int activeChapterIndex,
  }) {
    final progressMarkers = visibleChapters
        .where(
          (chapter) =>
              chapter.time > Duration.zero && chapter.time < duration,
        )
        .toList(growable: false);
    if (progressMarkers.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, markerConstraints) {
        final width = markerConstraints.maxWidth;
        if (width <= 0) {
          return const SizedBox.shrink();
        }
        return Stack(
          children: progressMarkers.map((chapter) {
            final left =
                (((chapter.time.inMilliseconds / duration.inMilliseconds) *
                            width) -
                        8)
                    .clamp(0.0, width - 16);
            final active = chapter.index == activeChapterIndex;
            return Positioned(
              left: left,
              top: -2,
              bottom: -2,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => unawaited(_seekToChapter(chapter, duration)),
                child: SizedBox(
                  width: 20,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: active ? 4 : 3,
                          height: active ? 18 : 15,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: const Color(0xCC0B1117),
                              width: 0.6,
                            ),
                            boxShadow: const <BoxShadow>[
                              BoxShadow(
                                color: Color(0x99000000),
                                blurRadius: 3,
                                spreadRadius: 0.2,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          width: active ? 6 : 5,
                          height: active ? 6 : 5,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: Color(0x99000000),
                                blurRadius: 3,
                                spreadRadius: 0.2,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildBottomControls({
    required MpvPlayerValue value,
    required bool compactUi,
    required bool isLandscape,
  }) {
    return Transform.translate(
      offset: Offset(compactUi ? -6 : -4, isLandscape ? -2 : 0),
      child: Row(
        children: [
          PlayerBottomControlButton(
            icon: value.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            compact: compactUi,
            emphasis: true,
            onPressed: _togglePlayback,
          ),
          SizedBox(width: compactUi ? 0 : 2),
          PlayerBottomControlButton(
            icon: Icons.skip_next_rounded,
            compact: compactUi,
            onPressed: _showNextEpisode,
          ),
          SizedBox(
            width: isLandscape ? (compactUi ? 8 : 18) : (compactUi ? 8 : 14),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: compactUi ? 8 : 10,
                runSpacing: compactUi ? 8 : 10,
                alignment: WrapAlignment.end,
                children: [
                  PlayerActionTextButton(
                    label: '重载',
                    onPressed: _reloadCurrentSource,
                  ),
                  PlayerActionTextButton(
                    label: '选集',
                    onPressed: _showEpisodeSheet,
                  ),
                  PlayerActionTextButton(
                    label: _speedLabel(_playbackSpeed),
                    onPressed: _showSpeedSheet,
                  ),
                  PlayerActionTextButton(
                    label: '音频',
                    onPressed: _showAudioSheet,
                  ),
                  PlayerActionTextButton(
                    label: (_currentSubtitleGuid ?? '').trim().isEmpty
                        ? '字幕关'
                        : '字幕',
                    onPressed: _showSubtitleSheet,
                  ),
                  PlayerActionTextButton(
                    label: _currentResolution.isNotEmpty
                        ? _currentResolution
                        : '原画',
                    onPressed: _showQualitySheet,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
