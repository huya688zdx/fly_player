import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../providers/app_theme_provider.dart';
import '../theme/app_theme.dart';
import '../theme/dynamic_theme_mapper.dart';
import '../theme/dynamic_theme_runtime_controller.dart';

/// 列表点击 → push 详情前的取色 scheme 预热。
///
/// 详情页 initState 同步命中 seed 缓存时，首帧 build 会冷跑 2 次 HCT 求解
/// （各 ~16ms，见 [DynamicThemeMapper] 注释），正落在进场转场的第一帧。持久化
/// seed 缓存预载 256 条而 scheme 缓存冷启动，"seed 热 scheme 冷"是常态。
/// 在 onTap 时按目标 pageKey 查 seed 并预热对应 scheme，push 后首帧即纯缓存命中。
///
/// 时序：seed 查询在缓存已加载时于微任务内完成，随后的 warmUp 同样在 push
/// 排期的下一帧之前执行完——赶在路由首帧 build 之前，不占转场帧预算。
/// 仅预热同引擎页面（原生独立引擎详情的静态缓存不共享，白热一次也无害）。
class DetailThemePrewarmer {
  const DetailThemePrewarmer._();

  /// 按目标详情页的 [pageKey]（与 DynamicPageThemeScope.pageKey 同键，通常是
  /// itemGuid）预热 scheme。[imageUrl] 为可选回退：pageKey 未命中时按取色图
  /// URL 查 seed 图缓存（需与详情页取色 URL 同参才能命中）。
  /// 同步读取 context（provider / 主题），随后异步查缓存，不持有 context 跨 await。
  static void warmUp(
    BuildContext context, {
    required String pageKey,
    String imageUrl = '',
  }) {
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
    unawaited(
      DynamicThemeRuntimeController.instance
          .restoreCachedSeed(key: normalizedKey, imageUrl: imageUrl)
          .then((seed) {
            if (seed == null) {
              return;
            }
            if (DynamicThemeMapper.isWarm(
              baseColors: baseColors,
              seed: seed,
              intensity: intensity,
            )) {
              return;
            }
            DynamicThemeMapper.warmUp(
              baseColors: baseColors,
              seed: seed,
              intensity: intensity,
            );
          }),
    );
  }
}
