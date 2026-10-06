import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('收藏和媒体库二级页共用多色氛围背景与协调按钮色组', () {
    final favorite = File(
      'lib/screens/favorite_items_screen_widgets.dart',
    ).readAsStringSync();
    final category = File(
      'lib/screens/category_items_screen.dart',
    ).readAsStringSync();

    // 收藏页经 AppAmbientPage 共享壳层氛围背景（组件内部承载
    // AppAtmosphericBackground + AppAtmospherePalette.resolve）；媒体库页直接挂背景。
    expect(favorite, contains('AppAmbientPage('));
    expect(favorite, contains('AppTonalControlPalette.resolve('));
    expect(favorite, contains('backgroundColor: Colors.transparent'));
    expect(category, contains('AppAtmosphericBackground('));
    expect(category, contains('AppAtmospherePalette.resolve('));
    expect(category, contains('AppTonalControlPalette.resolve('));
    expect(category, contains('backgroundColor: Colors.transparent'));
  });
}
