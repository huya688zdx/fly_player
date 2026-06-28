import 'package:flutter/foundation.dart';

import '../l10n/generated/app_localizations.dart';

/// 全局「液态玻璃」质感挡位。与「动态取色」强度挡位并列，挂在主题设置里。
///
/// - [off] 极简：纯色面板、关高光，开销最低；
/// - [frosted] 磨砂（默认）：静态磨砂渐变，滚动区零额外开销；
/// - [liquid] 液态：关键面（导航/详情按钮/版本chip/弹层）启用真实 [BackdropFilter]
///   背景模糊，最接近原生 iOS26，但每帧重算模糊、略增 GPU。
///
/// 设计上**只有显式声明了 `blurSigma` 的玻璃面**会在 [liquid] 挡位转为真模糊；
/// 滚动列表里的卡片（统计卡/分类卡/海报簇）一律保持静态磨砂，避免逐帧重算掉帧。
enum LiquidGlassLevel { off, frosted, liquid }

extension LiquidGlassLevelX on LiquidGlassLevel {
  String get storageValue => switch (this) {
    LiquidGlassLevel.off => 'off',
    LiquidGlassLevel.frosted => 'frosted',
    LiquidGlassLevel.liquid => 'liquid',
  };

  /// 设置项里展示的短标题。
  String title(AppLocalizations l10n) => switch (this) {
    LiquidGlassLevel.off => l10n.themeGlassLevelOffTitle,
    LiquidGlassLevel.frosted => l10n.themeGlassLevelFrostedTitle,
    LiquidGlassLevel.liquid => l10n.themeGlassLevelLiquidTitle,
  };

  /// 当前挡位的行为说明。
  String description(AppLocalizations l10n) => switch (this) {
    LiquidGlassLevel.off => l10n.themeGlassLevelOffDescription,
    LiquidGlassLevel.frosted => l10n.themeGlassLevelFrostedDescription,
    LiquidGlassLevel.liquid => l10n.themeGlassLevelLiquidDescription,
  };

  /// 是否启用真实背景模糊（仅 [liquid]）。
  bool get usesRealBlur => this == LiquidGlassLevel.liquid;

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
