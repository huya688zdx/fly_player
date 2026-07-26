import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../providers/app_theme_provider.dart';
import '../theme/app_theme.dart';
import '../theme/dynamic_theme_mapper.dart';
import '../theme/dynamic_theme_runtime_controller.dart';
import 'player_pane_host_scope.dart';

/// 列表点击 → push 详情前的取色预热 + 全局主题提前应用。
///
/// 两件事，都发生在 push 之前：
/// 1. **scheme 预热**：详情页 initState 同步命中 seed 缓存时，首帧 build 会冷跑
///    2 次 HCT 求解（各 ~16ms，见 [DynamicThemeMapper]）。tap 时按目标 pageKey
///    查 seed 并预热对应 scheme，push 后首帧即纯缓存命中。
/// 2. **全局运行时主题提前落地**：seed 已缓存时目标页配色是已知的。若等详情页
///    scope 在转场后才 sync 全局主题，用户看到的是"进页后整页配色晚一步跳变"；
///    在 push 前直接 [AppThemeProvider.setRuntimeDynamicTheme]，转场里新旧两页
///    就已经是目标配色。same-seed 幂等短路防重复；首次取色（无缓存）仍走详情页
///    原链路（网络解析天然晚，provider 发布口的转场收口兜底）。
///
/// 时序关键：`Navigator.push` **同步**就把转场计数置起（NavigatorObserver.didPush），
/// 其后的主题发布会被转场收口推迟——所以调用方必须 `await` 本方法完成后再 push。
/// 内部全是微任务/一次事件级等待，无可感延迟。
class DetailThemePrewarmer {
  const DetailThemePrewarmer._();

  /// [pageKey] 与目标页 DynamicPageThemeScope.pageKey 同键（通常是 itemGuid）。
  /// [imageUrl] 为可选回退：pageKey 未命中时按取色图 URL 查 seed 图缓存。
  static Future<void> warmUp(
    BuildContext context, {
    required String pageKey,
    String imageUrl = '',
  }) async {
    final normalizedKey = pageKey.trim();
    if (normalizedKey.isEmpty) {
      return;
    }
    final themeProvider = context.read<AppThemeProvider>();
    if (!themeProvider.dynamicThemeEnabled) {
      return;
    }
    final baseColors = context.baseAppColors;
    final intensity = themeProvider.dynamicThemeIntensity;
    final allowGlobalSync = intensity.allowsGlobalRuntimeThemeSync(
      inPlayerPaneHost: PlayerPaneHostScope.maybeOf(context) != null,
      isPane: false,
    );
    final seed = await DynamicThemeRuntimeController.instance.restoreCachedSeed(
      key: normalizedKey,
      imageUrl: imageUrl,
    );
    if (seed == null) {
      return;
    }
    if (!DynamicThemeMapper.isWarm(
      baseColors: baseColors,
      seed: seed,
      intensity: intensity,
    )) {
      DynamicThemeMapper.warmUp(
        baseColors: baseColors,
        seed: seed,
        intensity: intensity,
      );
    }
    if (!allowGlobalSync) {
      return;
    }
    // 发布（notifyListeners）在 broadcast 通道 await 之前同步完成；跨窗口
    // broadcast 的通道往返不阻塞导航——只等一次事件循环让发布跑完即可。
    unawaited(
      themeProvider.setRuntimeDynamicTheme(pageKey: normalizedKey, seed: seed),
    );
    await Future<void>.delayed(Duration.zero);
  }
}
