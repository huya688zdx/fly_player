import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetBuilder;

/// 桌面「浏览 | 详情」分屏状态。
///
/// 侧栏开关（feat/desktop-nav 的 Shell）与分屏详情宿主（feat/desktop-detail-pane）
/// 共用同一实例，由桌面 Shell 以 Provider 注入；比例预设对齐
/// `parallel_window_settings_screen.dart` 的 42/58、50/50、35/65。
class DesktopSplitController extends ChangeNotifier {
  DesktopSplitController({
    bool enabled = false,
    double paneFraction = defaultPaneFraction,
  }) : _enabled = enabled,
       _paneFraction = paneFraction;

  static const double defaultPaneFraction = 0.50;

  /// 详情栏宽度占比预设，对应现有分屏设置页的比例档位。
  static const List<double> paneFractionPresets = <double>[0.42, 0.50, 0.65];

  /// 分屏详情宿主的构建器：由 desktop-detail-pane 在合入时接线；
  /// 未接线时开启开关只改变布局标记，右栏渲染占位，不崩溃。
  WidgetBuilder? paneHostBuilder;

  bool _enabled;
  double _paneFraction;

  bool get enabled => _enabled;

  double get paneFraction => _paneFraction;

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
  }

  void setPaneFraction(double value) {
    final clamped = value.clamp(0.30, 0.70);
    if ((_paneFraction - clamped).abs() < 0.001) return;
    _paneFraction = clamped;
    notifyListeners();
  }
}
