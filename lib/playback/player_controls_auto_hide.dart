import 'dart:async';

/// Auto-hide never interrupts a pointer gesture already operating the controls.
final class PlayerControlsAutoHide {
  PlayerControlsAutoHide({
    required this.delay,
    required this.canHide,
    required this.onHide,
  });

  final Duration delay;
  final bool Function() canHide;
  final void Function() onHide;
  final Set<int> _pointers = <int>{};
  Timer? _timer;
  bool _disposed = false;

  void schedule() {
    cancel();
    if (_disposed || _pointers.isNotEmpty || !canHide()) return;
    _timer = Timer(delay, () {
      _timer = null;
      if (!_disposed && _pointers.isEmpty && canHide()) onHide();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  // Pointer-down only holds the timer. Visibility remains the tap handler's job.
  void pointerDown(int pointer) {
    if (_disposed) return;
    _pointers.add(pointer);
    cancel();
  }

  void pointerEnded(int pointer) {
    if (_pointers.remove(pointer) && _pointers.isEmpty) schedule();
  }

  void dispose() {
    _disposed = true;
    _pointers.clear();
    cancel();
  }
}
