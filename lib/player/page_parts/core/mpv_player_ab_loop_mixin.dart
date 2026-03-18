part of mpv_player_page;

const Duration _abLoopMinimumSpan = Duration(milliseconds: 800);
const Duration _abLoopSeekLead = Duration(milliseconds: 160);
const Duration _abLoopSeekResetTolerance = Duration(milliseconds: 650);

extension _MpvPlayerAbLoopMixin on _MpvPlayerPageState {
  bool get _abLoopEnabled => _abLoopStart != null && _abLoopEnd != null;

  String get _abLoopButtonLabel {
    if (_abLoopEnabled) return 'A-B';
    if (_abLoopStart != null) return 'A点';
    return 'AB';
  }

  bool get _abLoopButtonActive => _abLoopEnabled || _abLoopStart != null;

  Duration _currentAbLoopAnchorPosition(Duration duration) {
    final base = _uiController.draggingPosition ?? _displayPosition(_controller.value.value);
    if (duration <= Duration.zero) {
      return base;
    }
    if (base <= Duration.zero) {
      return Duration.zero;
    }
    return base > duration ? duration : base;
  }

  Future<void> _handleAbLoopButtonPressed() async {
    final duration = _effectiveDuration();
    if (duration <= Duration.zero) {
      _showTopTip('当前时长不足，无法设置 A-B 循环', context.appColors.warning);
      return;
    }
    final position = _currentAbLoopAnchorPosition(duration);
    final start = _abLoopStart;
    final end = _abLoopEnd;
    if (start == null) {
      _updatePlayerState(() {
        _abLoopStart = position;
        _abLoopEnd = null;
        _abLoopSeekPending = false;
      });
      _showTopTip('A 点已设置到 ${_formatDuration(position)}', context.appColors.accent);
      return;
    }
    if (end == null) {
      var nextStart = start;
      var nextEnd = position;
      if (nextEnd < nextStart) {
        final temp = nextStart;
        nextStart = nextEnd;
        nextEnd = temp;
      }
      if (nextEnd - nextStart < _abLoopMinimumSpan) {
        _showTopTip('A-B 间隔至少需要 0.8 秒', context.appColors.warning);
        return;
      }
      _updatePlayerState(() {
        _abLoopStart = nextStart;
        _abLoopEnd = nextEnd;
        _abLoopSeekPending = false;
      });
      _showTopTip(
        'A-B 循环已设置 ${_formatDuration(nextStart)} - ${_formatDuration(nextEnd)}',
        context.appColors.success,
      );
      return;
    }
    _clearAbLoop(showMessage: true);
  }

  void _clearAbLoop({bool showMessage = false}) {
    final hadLoop = _abLoopStart != null || _abLoopEnd != null;
    if (!hadLoop) return;
    _updatePlayerState(() {
      _abLoopStart = null;
      _abLoopEnd = null;
      _abLoopSeekPending = false;
    });
    if (showMessage) {
      _showTopTip('A-B 循环已清除', context.appColors.warning);
    }
  }

  void _resetAbLoopForSourceChange() {
    _abLoopStart = null;
    _abLoopEnd = null;
    _abLoopSeekPending = false;
  }

  void _handleAbLoopRuntime(MpvPlayerValue value) {
    final start = _abLoopStart;
    final end = _abLoopEnd;
    if (start == null || end == null) return;
    if (!value.ready || !value.nativeLibLoaded || value.paused) return;
    if (_uiController.timelineInteractionActive ||
        _uiController.draggingPosition != null) {
      return;
    }
    if (_uiController.qualitySwitchLoading ||
        _uiController.pendingLoadingTransition ||
        _uiController.awaitingVisualPlaybackStart) {
      return;
    }
    if (_abLoopSeekPending) {
      if ((value.position - start).abs() <= _abLoopSeekResetTolerance ||
          value.position < end - _abLoopSeekLead) {
        _abLoopSeekPending = false;
      }
      return;
    }
    final trigger = end > _abLoopSeekLead ? end - _abLoopSeekLead : end;
    if (value.position < trigger) return;
    _abLoopSeekPending = true;
    _gestureController.resetSeekTracking();
    unawaited(_controller.seek(start));
  }

  List<PlayerProgressChapterMarker> _abLoopProgressMarkers(Duration duration) {
    if (duration <= Duration.zero) return const <PlayerProgressChapterMarker>[];
    final start = _abLoopStart;
    final end = _abLoopEnd;
    final markers = <PlayerProgressChapterMarker>[];
    if (start != null) {
      markers.add(
        PlayerProgressChapterMarker(
          fraction: start.inMilliseconds / duration.inMilliseconds.clamp(1, 1 << 30),
          active: true,
          kind: PlayerProgressMarkerKind.abLoop,
          snapTarget: false,
        ),
      );
    }
    if (end != null) {
      markers.add(
        PlayerProgressChapterMarker(
          fraction: end.inMilliseconds / duration.inMilliseconds.clamp(1, 1 << 30),
          active: true,
          kind: PlayerProgressMarkerKind.abLoop,
          snapTarget: false,
        ),
      );
    }
    return markers;
  }

  PlayerProgressRangeHighlight? _abLoopProgressHighlight(Duration duration) {
    final start = _abLoopStart;
    final end = _abLoopEnd;
    if (duration <= Duration.zero || start == null || end == null) {
      return null;
    }
    final totalMs = duration.inMilliseconds;
    if (totalMs <= 0) return null;
    final startFraction = (start.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final endFraction = (end.inMilliseconds / totalMs).clamp(0.0, 1.0);
    if (endFraction <= startFraction) return null;
    return PlayerProgressRangeHighlight(
      startFraction: startFraction,
      endFraction: endFraction,
    );
  }
}
