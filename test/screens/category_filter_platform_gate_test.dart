import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 分类库筛选按钮按平台分支：桌面端用工具栏下内联面板，手机端保留筛选弹层。
///
/// 内联面板在 6968810e（feat(desktop)）引入时未加平台门，导致 Android
/// 也走了内联表现；收藏页（favorite_items_screen_sheets）一直按平台分支，
/// 此测试防止分类页再次回归成无差别内联。
void main() {
  test('分类库筛选按钮按 isDesktopPlatform 分支，手机端弹层仍存在', () {
    final source = File(
      'lib/screens/category_items_screen.dart',
    ).readAsStringSync();

    expect(source, contains('onTap: DesktopEnvironment.isDesktopPlatform'));
    expect(source, contains('_toggleFilterPanel'));
    expect(source, contains('_openFilterSheet'));
    expect(source, contains('AppCatalogFilterSheet.show('));
  });

  test('收藏页筛选同样按 isDesktopPlatform 分支（口径一致）', () {
    final source = File(
      'lib/screens/favorite_items_screen_sheets.dart',
    ).readAsStringSync();

    expect(source, contains('DesktopEnvironment.isDesktopPlatform'));
    expect(source, contains('AppCatalogFilterSheet.show('));
  });
}
