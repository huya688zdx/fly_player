/// 桌面布局断点（与 design/desktop 原型 styles.css 对齐）。
///
/// 断点只约束"桌面端窗口"的布局形态；移动端布局分支不消费这些常量。
abstract final class DesktopBreakpoints {
  /// ≥ 此宽度显示左侧导航栏（替代底部胶囊导航）。
  static const double sidebarMinWidth = 1024;

  /// ≥ 此宽度允许开启「浏览 | 详情」分屏。
  static const double splitMinWidth = 1180;

  /// ≥ 此宽度使用更宽的货架密度档。
  static const double wideContentWidth = 1600;

  /// 分屏详情栏的最小可读宽度（低于此值自动回落整页打开）。
  static const double paneMinWidth = 380;
}
