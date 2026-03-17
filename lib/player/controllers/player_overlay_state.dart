import 'dart:async';

import 'package:flutter/foundation.dart';

class PlayerOverlayStateController extends ChangeNotifier {
  final Duration autoHideDelay;

  PlayerOverlayStateController({
    this.autoHideDelay = const Duration(seconds: 4),
  });

  Timer? _autoHideTimer;
  bool _controlsVisible = true;
  bool _controlsAnimatingOut = false;
  bool _resumePromptVisible = false;

  bool get controlsVisible => _controlsVisible;
  bool get controlsAnimatingOut => _controlsAnimatingOut;
  bool get resumePromptVisible => _resumePromptVisible;

  void cancelAutoHide() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
  }

  void scheduleAutoHide({
    required bool ready,
    required bool gestureSeekActive,
    required VoidCallback onTimeout,
  }) {
    cancelAutoHide();
    if (!ready || gestureSeekActive) return;
    _autoHideTimer = Timer(autoHideDelay, onTimeout);
  }

  void setResumePromptVisible(bool visible) {
    if (_resumePromptVisible == visible) return;
    _resumePromptVisible = visible;
    notifyListeners();
  }

  bool showControls() {
    cancelAutoHide();
    if (_controlsVisible && !_controlsAnimatingOut) return false;
    _controlsVisible = true;
    _controlsAnimatingOut = false;
    notifyListeners();
    return true;
  }

  bool beginHide() {
    cancelAutoHide();
    if (!_controlsVisible && !_controlsAnimatingOut) return false;
    _controlsVisible = false;
    _controlsAnimatingOut = true;
    _resumePromptVisible = false;
    notifyListeners();
    return true;
  }

  void finishHide() {
    if (_controlsVisible || !_controlsAnimatingOut) return;
    _controlsAnimatingOut = false;
    notifyListeners();
  }

  void stopAnimatingOut() {
    if (!_controlsAnimatingOut) return;
    _controlsAnimatingOut = false;
    notifyListeners();
  }

  void hideImmediately() {
    cancelAutoHide();
    if (_controlsVisible || _controlsAnimatingOut || _resumePromptVisible) {
      _controlsVisible = false;
      _controlsAnimatingOut = false;
      _resumePromptVisible = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    cancelAutoHide();
    super.dispose();
  }
}
