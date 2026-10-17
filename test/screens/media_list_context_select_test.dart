import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 首页 `context.select` 误用回归。
///
/// 现场：桌面端启动后首页三个海报行全部显示「加载失败」，日志刷
/// `Tried to use 'context.select' outside of the 'build' method of a widget`
/// （provider 断言 `widget is LayoutBuilder || debugDoingBuild`）。
///
/// 根因：`_MediaListScreenWidgets` 是 `extension on _MediaListScreenState`，里面的
/// `context` 是**页面 State 的 context**。而 `_buildPosterRow` / `_buildCatalogPreviews`
/// 等是在 sliver 的 itemBuilder 里被调用的，此时该 element 并不在 build 中，于是断言
/// 触发、整块区块被打成「加载失败」。
///
/// 修法：档位改在页面级 build（`_buildScreen`）里 `context.select` 一次缓存到
/// `_visualTier`，其余位置只读缓存值。
void main() {
  final widgets = File(
    'lib/screens/media_list_screen_widgets.dart',
  ).readAsStringSync();
  final screen = File('lib/screens/media_list_screen.dart').readAsStringSync();

  test('首页区块内不再直接调 context.select（会踩 provider 断言）', () {
    // 只允许「页面级 build 里赋值给 _visualTier」这一处；
    // 海报行 / 继续观看行 / 分类预览行等 sliver itemBuilder 内不得再出现。
    final occurrences = 'context.select<AppThemeProvider'
        .allMatches(widgets)
        .length;
    expect(
      occurrences,
      1,
      reason: '除 _buildScreen 里那一处，其余位置调 select 会让整块区块变「加载失败」',
    );
    expect(
      widgets,
      contains(
        '_visualTier = context.select<AppThemeProvider, AppVisualPerformanceTier>(',
      ),
      reason: '唯一那处必须是页面级 build 里对 _visualTier 的赋值',
    );
  });

  test('档位在页面级 build 里取一次并缓存', () {
    expect(
      screen,
      contains('AppVisualPerformanceTier _visualTier'),
      reason: '缺少缓存字段',
    );
    expect(
      widgets,
      contains(
        '_visualTier = context.select<AppThemeProvider, AppVisualPerformanceTier>(',
      ),
      reason: '页面级 build 未注册对档位的依赖，档位变化不会触发重建',
    );
    // 4 个解码宽度消费点都应改读缓存值。
    expect(
      '_visualTier'.allMatches(widgets).length,
      greaterThanOrEqualTo(4),
      reason: '仍有位置没改读 _visualTier',
    );
  });
}
