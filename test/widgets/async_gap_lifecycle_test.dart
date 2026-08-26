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

  test(
    'favorite sort sheet does not read provider from popped sheet context',
    () {
      final source = File(
        'lib/screens/favorite_items_screen_sheets.dart',
      ).readAsStringSync();

      expect(
        source,
        contains('final nasProvider = context.read<NasProvider>();'),
      );
      expect(source, isNot(contains('context.read<NasProvider>(),')));
    },
  );
}
