import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/player_gesture_overlay.dart';
import '../widgets/player_system_controls.dart';

class PlayerHorizontalSeekResult {
  final Duration target;
  final bool restoreControlsVisible;

  const PlayerHorizontalSeekResult({
    required this.target,
    required this.restoreControlsVisible,
  });
}

class PlayerGestureController extends ChangeNotifier {
  static const Duration _adjustmentCommitInterval = Duration(milliseconds: 96);
  static const double _adjustmentUiStep = 0.02;

  final PlayerSystemController _systemController;

  PlayerGestureController({required PlayerSystemController systemController})
    : _systemController = systemController;

  Timer? _gestureOverlayTimer;
  Timer? _pendingSeekTimer;
  Timer? _systemAdjustmentTimer;
  PlayerAdjustmentOverlayData? _gestureOverlayData;
  PlayerAdjustmentType? _activeAdjustmentType;
  PlayerAdjustmentType? _pendingAdjustmentType;
  bool _gestureSeekActive = false;
  bool _gestureSeekRestoreControlsVisible = false;
  bool _speedBoostActive = false;
  Duration? _draggingPosition;
  Duration? _pendingSeekPosition;
  Duration _gestureSeekBasePosition = Duration.zero;
  double _brightnessLevel = 0.5;
  double _volumeLevel = 0.5;
  double _gestureSeekStartDx = 0;
  double _gestureCurrentDy = 0;
  double _gestureStartLevel = 0.5;
  double _gestureStartDy = 0;
  double? _pendingAdjustmentValue;
  int _adjustmentSessionId = 0;
  double? _speedBoostRestoreSpeed;
  final ValueNotifier<int> _overlayRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> _seekRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> _speedBoostRevision = ValueNotifier<int>(0);

  PlayerAdjustmentOverlayData? get gestureOverlayData => _gestureOverlayData;
  bool get gestureSeekActive => _gestureSeekActive;
  bool get isSeekDragging => _draggingPosition != null;
  bool get speedBoostActive => _speedBoostActive;
  Duration? get pendingSeekPosition => _pendingSeekPosition;
  bool get adjustmentActive => _activeAdjustmentType != null;
  Listenable get overlayListenable => _overlayRevision;
  Listenable get seekListenable => _seekRevision;
  Listenable get speedBoostListenable => _speedBoostRevision;

  Future<void> primeSystemSnapshot() async {
    final snapshot = await _systemController.readSnapshot();
    _brightnessLevel = snapshot.brightness;
    _volumeLevel = snapshot.volume;
  }

  Duration displayPosition(Duration position) {
    return _draggingPosition ?? _pendingSeekPosition ?? position;
  }

  void acknowledgeSeekPosition(Duration position) {
    final pendingSeekPosition = _pendingSeekPosition;
    if (pendingSeekPosition == null) return;
    if ((position - pendingSeekPosition).inMilliseconds.abs() > 900) return;
    _pendingSeekTimer?.cancel();
    _pendingSeekPosition = null;
    _notifySeekChanged();
  }

  void resetSeekTracking() {
    _draggingPosition = null;
    _setPendingSeekPosition(null);
    _notifySeekChanged();
  }

  void beginSliderDrag(Duration position) {
    _draggingPosition = position;
    _setPendingSeekPosition(null);
    _notifySeekChanged();
  }

  void updateSliderDrag(Duration position) {
    _draggingPosition = position;
    _notifySeekChanged();
  }

  void completeSliderDrag(Duration position) {
    _draggingPosition = null;
    _setPendingSeekPosition(position);
    _notifySeekChanged();
  }

  void clearTransientVisuals() {
    _gestureOverlayTimer?.cancel();
    final overlayChanged = _gestureOverlayData != null || _speedBoostActive;
    final seekChanged =
        _gestureSeekActive ||
        _gestureSeekRestoreControlsVisible ||
        _draggingPosition != null ||
        _pendingSeekPosition != null;
    _gestureSeekActive = false;
    _gestureSeekRestoreControlsVisible = false;
    _activeAdjustmentType = null;
    _gestureOverlayData = null;
    if (overlayChanged) {
      _notifyOverlayChanged();
      _notifySpeedBoostChanged();
    }
    if (seekChanged) {
      _notifySeekChanged();
    }
  }

  void hideOverlay() {
    _gestureOverlayTimer?.cancel();
    if (_gestureOverlayData == null) return;
    _gestureOverlayData = null;
    _notifyOverlayChanged();
  }

  void handleVerticalStart({
    required DragStartDetails details,
    required double width,
    required double height,
  }) {
    final type = details.localPosition.dx < width / 2
        ? PlayerAdjustmentType.brightness
        : PlayerAdjustmentType.volume;
    final sessionId = ++_adjustmentSessionId;
    _activeAdjustmentType = type;
    _gestureStartDy = details.localPosition.dy;
    _gestureCurrentDy = _gestureStartDy;
    _gestureStartLevel = type == PlayerAdjustmentType.brightness
        ? _brightnessLevel
        : _volumeLevel;
    _showAdjustmentOverlay(type, _gestureStartLevel);
    unawaited(_syncAdjustmentBaseline(type, sessionId, height));
  }

  void handleVerticalUpdate({
    required DragUpdateDetails details,
    required double height,
  }) {
    final type = _activeAdjustmentType;
    if (type == null) return;
    _gestureCurrentDy = details.localPosition.dy;
    final nextValue =
        (_gestureStartLevel +
                ((_gestureStartDy - _gestureCurrentDy) /
                        (height <= 0 ? 1 : height)) *
                    1.6)
            .clamp(0.0, 1.0);
    _applySystemAdjustment(type, nextValue);
  }

  void handleVerticalEnd() {
    _flushPendingSystemAdjustment();
    _adjustmentSessionId++;
    _activeAdjustmentType = null;
    _scheduleGestureOverlayHide();
  }

  void cancelVerticalAdjustment() {
    if (_activeAdjustmentType == null) return;
    _flushPendingSystemAdjustment();
    _adjustmentSessionId++;
    _activeAdjustmentType = null;
    _scheduleGestureOverlayHide();
  }

  void handleHorizontalStart({
    required DragStartDetails details,
    required Duration currentPosition,
    required bool restoreControlsVisible,
    required double width,
  }) {
    _gestureOverlayTimer?.cancel();
    _setPendingSeekPosition(null);
    _gestureSeekActive = true;
    _gestureSeekRestoreControlsVisible = restoreControlsVisible;
    _gestureSeekStartDx = details.localPosition.dx.clamp(0.0, width);
    _gestureSeekBasePosition = currentPosition;
    _draggingPosition = currentPosition;
    _gestureOverlayData = null;
    _notifySeekChanged();
    _notifyOverlayChanged();
  }

  void handleHorizontalUpdate({
    required DragUpdateDetails details,
    required double width,
    required Duration duration,
  }) {
    if (!_gestureSeekActive || duration <= Duration.zero) return;
    final safeWidth = width <= 0 ? 1.0 : width;
    final deltaX = details.localPosition.dx - _gestureSeekStartDx;
    final deadZone = safeWidth * 0.028;
    final absDelta = deltaX.abs();
    final effectiveDelta = absDelta <= deadZone ? 0.0 : absDelta - deadZone;
    final effectiveWidth = (safeWidth - deadZone).clamp(1.0, double.infinity);
    final normalizedDelta = (effectiveDelta / effectiveWidth).clamp(0.0, 1.0);
    final dampedRatio = deltaX == 0
        ? 0.0
        : deltaX.sign * normalizedDelta * normalizedDelta;
    final windowSeconds = duration.inSeconds <= 0
        ? 150.0
        : duration.inSeconds.clamp(60, 360).toDouble();
    final deltaMilliseconds = (dampedRatio * windowSeconds * 1000).round();
    final nextMilliseconds =
        (_gestureSeekBasePosition.inMilliseconds + deltaMilliseconds).clamp(
          0,
          duration.inMilliseconds,
        );
    _draggingPosition = Duration(milliseconds: nextMilliseconds);
    _notifySeekChanged();
  }

  PlayerHorizontalSeekResult? completeHorizontalSeek() {
    if (!_gestureSeekActive) return null;
    final result = PlayerHorizontalSeekResult(
      target: _draggingPosition ?? _gestureSeekBasePosition,
      restoreControlsVisible: _gestureSeekRestoreControlsVisible,
    );
    _gestureSeekActive = false;
    _gestureSeekRestoreControlsVisible = false;
    _draggingPosition = null;
    _setPendingSeekPosition(result.target);
    _notifySeekChanged();
    return result;
  }

  void cancelHorizontalSeek() {
    if (!_gestureSeekActive && _draggingPosition == null) return;
    _gestureSeekActive = false;
    _gestureSeekRestoreControlsVisible = false;
    _draggingPosition = null;
    _notifySeekChanged();
  }

  bool beginSpeedBoost(double playbackSpeed) {
    _gestureOverlayTimer?.cancel();
    if (_speedBoostActive) return false;
    _speedBoostRestoreSpeed = playbackSpeed;
    _speedBoostActive = true;
    _gestureOverlayData = null;
    _notifyOverlayChanged();
    _notifySpeedBoostChanged();
    return true;
  }

  double endSpeedBoost(double playbackSpeed) {
    final restoreSpeed = _speedBoostRestoreSpeed ?? playbackSpeed;
    _speedBoostRestoreSpeed = null;
    if (_speedBoostActive) {
      _speedBoostActive = false;
      _notifyOverlayChanged();
      _notifySpeedBoostChanged();
    }
    return restoreSpeed;
  }

  double? cancelSpeedBoost(double playbackSpeed) {
    if (!_speedBoostActive && _speedBoostRestoreSpeed == null) {
      return null;
    }
    return endSpeedBoost(playbackSpeed);
  }

  Future<void> _syncAdjustmentBaseline(
    PlayerAdjustmentType type,
    int sessionId,
    double height,
  ) async {
    final snapshot = await _systemController.readSnapshot();
    if (_adjustmentSessionId != sessionId || _activeAdjustmentType != type) {
      return;
    }
    final baseline = type == PlayerAdjustmentType.brightness
        ? snapshot.brightness
        : snapshot.volume;
    _gestureStartLevel = baseline;
    final nextValue =
        (baseline +
                ((_gestureStartDy - _gestureCurrentDy) /
                        (height <= 0 ? 1 : height)) *
                    1.6)
            .clamp(0.0, 1.0);
    final hasDragged = (_gestureCurrentDy - _gestureStartDy).abs() > 0.5;
    if (!hasDragged) {
      _brightnessLevel = snapshot.brightness;
      _volumeLevel = snapshot.volume;
      _gestureOverlayData = PlayerAdjustmentOverlayData(
        type: type,
        value: baseline,
      );
      _notifyOverlayChanged();
      return;
    }
    _applySystemAdjustment(type, nextValue);
  }

  void _showAdjustmentOverlay(PlayerAdjustmentType type, double value) {
    _gestureOverlayTimer?.cancel();
    _gestureOverlayData = PlayerAdjustmentOverlayData(type: type, value: value);
    _notifyOverlayChanged();
  }

  void _scheduleGestureOverlayHide() {
    _gestureOverlayTimer?.cancel();
    _gestureOverlayTimer = Timer(const Duration(milliseconds: 700), () {
      _gestureOverlayData = null;
      _notifyOverlayChanged();
    });
  }

  void _setPendingSeekPosition(Duration? position) {
    _pendingSeekTimer?.cancel();
    final changed = _pendingSeekPosition != position;
    _pendingSeekPosition = position;
    if (changed) {
      _notifySeekChanged();
    }
    if (position == null) return;
    _pendingSeekTimer = Timer(const Duration(milliseconds: 1800), () {
      if (_pendingSeekPosition != position) return;
      _pendingSeekPosition = null;
      _notifySeekChanged();
    });
  }

  void _applySystemAdjustment(PlayerAdjustmentType type, double value) {
    final normalized = value.clamp(0.0, 1.0);
    final quantized = _quantizeAdjustmentValue(normalized);
    var shouldNotify = false;
    if (type == PlayerAdjustmentType.brightness) {
      if ((_brightnessLevel - quantized).abs() >= _adjustmentUiStep / 2) {
        _brightnessLevel = quantized;
        shouldNotify = true;
      }
    } else {
      if ((_volumeLevel - quantized).abs() >= _adjustmentUiStep / 2) {
        _volumeLevel = quantized;
        shouldNotify = true;
      }
    }
    final previousOverlay = _gestureOverlayData;
    final nextOverlay = PlayerAdjustmentOverlayData(
      type: type,
      value: quantized,
    );
    if (previousOverlay?.type != nextOverlay.type ||
        ((previousOverlay?.value ?? -1) - nextOverlay.value).abs() >=
            _adjustmentUiStep / 2) {
      _gestureOverlayData = nextOverlay;
      shouldNotify = true;
    }
    _scheduleSystemAdjustment(type, normalized);
    if (shouldNotify) {
      _notifyOverlayChanged();
    }
  }

  void _notifyOverlayChanged() {
    _overlayRevision.value += 1;
  }

  void _notifySeekChanged() {
    _seekRevision.value += 1;
  }

  void _notifySpeedBoostChanged() {
    _speedBoostRevision.value += 1;
  }

  double _quantizeAdjustmentValue(double value) {
    final bucket = (value / _adjustmentUiStep).roundToDouble();
    return (bucket * _adjustmentUiStep).clamp(0.0, 1.0);
  }

  void _scheduleSystemAdjustment(PlayerAdjustmentType type, double value) {
    _pendingAdjustmentType = type;
    _pendingAdjustmentValue = value.clamp(0.0, 1.0);
    if (_systemAdjustmentTimer != null) return;
    _systemAdjustmentTimer = Timer(_adjustmentCommitInterval, () {
      _systemAdjustmentTimer = null;
      _flushPendingSystemAdjustment();
    });
  }

  void _flushPendingSystemAdjustment() {
    _systemAdjustmentTimer?.cancel();
    _systemAdjustmentTimer = null;
    final type = _pendingAdjustmentType;
    final value = _pendingAdjustmentValue;
    _pendingAdjustmentType = null;
    _pendingAdjustmentValue = null;
    if (type == null || value == null) return;
    if (type == PlayerAdjustmentType.brightness) {
      unawaited(_systemController.setBrightness(value));
      return;
    }
    unawaited(_systemController.setVolume(value));
  }

  @override
  void dispose() {
    _gestureOverlayTimer?.cancel();
    _pendingSeekTimer?.cancel();
    _systemAdjustmentTimer?.cancel();
    _overlayRevision.dispose();
    _seekRevision.dispose();
    _speedBoostRevision.dispose();
    super.dispose();
  }
}
