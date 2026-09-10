import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';

/// 桌面鼠标滚轮映射到横向浏览，并交由手势仲裁避免父子视图重复滚动。
void handleDesktopHorizontalWheel(
  PointerSignalEvent event,
  ValueChanged<double> onScroll,
) {
  if (defaultTargetPlatform != TargetPlatform.windows &&
      defaultTargetPlatform != TargetPlatform.macOS &&
      defaultTargetPlatform != TargetPlatform.linux) {
    return;
  }
  if (event is! PointerScrollEvent || event.kind != PointerDeviceKind.mouse) {
    return;
  }
  final delta = event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()
      ? event.scrollDelta.dx
      : event.scrollDelta.dy;
  if (delta == 0) return;
  GestureBinding.instance.pointerSignalResolver.register(
    event,
    (_) => onScroll(delta),
  );
}
