import 'dart:async';

/// 焦点切换节流：快速连点/滑动时，背景大图与取色只在停留 [delay] 后触发一次。
class PosterBrowseFocusThrottle {
  PosterBrowseFocusThrottle({
    required this.onSettle,
    this.delay = const Duration(milliseconds: 300),
  });

  final void Function(String itemId) onSettle;
  final Duration delay;
  Timer? _timer;

  void schedule(String itemId) {
    _timer?.cancel();
    _timer = Timer(delay, () => onSettle(itemId));
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
