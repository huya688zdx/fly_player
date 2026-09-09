import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('media info metadata fetch checks mounted after async gaps', () {
    final source = File(
      'lib/screens/media_info_screen.dart',
    ).readAsStringSync();

    expect(source, contains('final info = await api.getStreamMetadata(guid);'));
    expect(source, contains('if (!mounted) return;'));
  });

  test('detail background fallback checks mounted before setState', () {
    final source = File(
      'lib/widgets/detail/immersive_detail_background.dart',
    ).readAsStringSync();

    expect(source, contains('void _nextFallbackImage(int failedIndex)'));
    expect(
      source,
      contains('if (!mounted || _index + 1 >= widget.images.urls.length)'),
    );
    expect(source, contains('if (failedIndex != _index) return;'));
  });

  test('收藏排序弹窗返回后先检查页面存活再应用选择', () {
    final source = File(
      'lib/screens/favorite_items_screen_sheets.dart',
    ).readAsStringSync();

    final openSheet = source.substring(
      source.indexOf('Future<void> _openSortSheet()'),
      source.indexOf('List<AppCatalogFilterSection> _buildFilterSections()'),
    );
    expect(openSheet, contains('if (!mounted || result == null) return;'));
    expect(
      openSheet.indexOf('if (!mounted || result == null) return;'),
      lessThan(openSheet.indexOf('await _applySortSelection(')),
    );
  });
}
