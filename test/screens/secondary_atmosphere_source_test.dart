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

    for (final source in <String>[favorite, category]) {
      expect(source, contains('AppAtmosphericBackground('));
      expect(source, contains('AppAtmospherePalette.resolve('));
      expect(source, contains('AppTonalControlPalette.resolve('));
      expect(source, contains('backgroundColor: Colors.transparent'));
    }
  });
}
