import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 收藏页与分类/媒体库页共用同一套多色氛围背景与协调按钮色组。
///
/// 注意两者的接入层次不同，断言要分开写：
/// - 分类/媒体库页（`CategoryItemsScreen`）直接 `AppAtmosphericBackground(` +
///   `AppAtmospherePalette.resolve(`；
/// - 收藏页已重构为共享包装 `AppAmbientPage(`——调色板解析与 `AppAtmosphericBackground`
///   都收在 `app_ambient_page.dart` 里（宽窗还会复用壳层整窗背景），页面文件本身不再出现
///   这两个符号。原先这里对两个文件用同一组断言，收藏页重构后就一直失败。
void main() {
  test('收藏和媒体库二级页共用多色氛围背景与协调按钮色组', () {
    final favorite = File(
      'lib/screens/favorite_items_screen_widgets.dart',
    ).readAsStringSync();
    final category = File(
      'lib/screens/category_items_screen.dart',
    ).readAsStringSync();

    // 收藏页：经共享包装接入氛围背景。
    expect(favorite, contains('AppAmbientPage('), reason: '收藏页未接入共享氛围包装');

    // 分类/媒体库页：直接使用氛围背景与调色板。
    expect(category, contains('AppAtmosphericBackground('));
    expect(category, contains('AppAtmospherePalette.resolve('));

    // 两页共用的部分：协调按钮色组 + 透明 Scaffold 背景。
    for (final source in <String>[favorite, category]) {
      expect(source, contains('AppTonalControlPalette.resolve('));
      expect(source, contains('backgroundColor: Colors.transparent'));
    }
  });

  test('共享包装内部确实解析调色板并套上氛围背景', () {
    final wrapper = File(
      'lib/widgets/common/app_ambient_page.dart',
    ).readAsStringSync();
    expect(wrapper, contains('AppAtmosphericBackground('));
    expect(wrapper, contains('AppAtmospherePalette.resolve('));
  });
}
