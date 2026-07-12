import 'package:flutter/foundation.dart';

import '../l10n/generated/app_localizations.dart';

/// 全局「液态玻璃」质感挡位。与「动态取色」强度挡位并列，挂在主题设置里。
///
/// - [off] 极简：纯色面板、关高光，开销最低；
/// - [frosted] 磨砂（默认）：静态磨砂渐变，滚动区零额外开销。
///
/// 玻璃组件已经统一回归纯色面板，旧版本保存的 `liquid` 值会在读取时降级为
/// [frosted]，不再保留一个没有实际渲染效果的配置挡位。
enum LiquidGlassLevel { off, frosted }

extension LiquidGlassLevelX on LiquidGlassLevel {
  String get storageValue => switch (this) {
    LiquidGlassLevel.off => 'off',
    LiquidGlassLevel.frosted => 'frosted',
  };

  /// 设置项里展示的短标题。
  String title(AppLocalizations l10n) => switch (this) {
    LiquidGlassLevel.off => l10n.themeGlassLevelOffTitle,
    LiquidGlassLevel.frosted => l10n.themeGlassLevelFrostedTitle,
  };

  /// 当前挡位的行为说明。
  String description(AppLocalizations l10n) => switch (this) {
    LiquidGlassLevel.off => l10n.themeGlassLevelOffDescription,
    LiquidGlassLevel.frosted => l10n.themeGlassLevelFrostedDescription,
  };

  /// 是否绘制镜面高光（[off] 关闭以求素净/省一层）。
  bool get drawsSheen => this != LiquidGlassLevel.off;

  static LiquidGlassLevel fromStorageValue(String? value) {
    return LiquidGlassLevel.values.firstWhere(
      (level) => level.storageValue == value,
      orElse: () => LiquidGlassLevel.frosted,
    );
  }
}

/// 全局玻璃挡位单一真源。由 [AppThemeProvider] 在加载/设置时写入；所有玻璃组件
/// 监听它以决定渲染方式（无需把 provider 耦合进通用 widget）。
final ValueNotifier<LiquidGlassLevel> liquidGlassLevel =
    ValueNotifier<LiquidGlassLevel>(LiquidGlassLevel.frosted);
