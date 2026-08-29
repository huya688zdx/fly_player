/// 桌面端视觉 token（对齐 design/desktop 原型）。
///
/// 只存放尺寸 / 圆角 / 动效；颜色一律经 AppThemeColors 读取，
/// 保证 7 套主题预设与亮暗模式自动生效（见 IMPLEMENTATION_PLAN.md 复用清单）。
abstract final class DesktopTokens {
  static const double sidebarWidth = 216;
  static const double sidebarItemHeight = 40;
  static const double sidebarItemRadius = 12;

  static const double cardRadius = 10;
  static const double menuRadius = 13;

  static const double hoverLiftScale = 1.03;
  static const Duration hoverDuration = Duration(milliseconds: 180);
}
