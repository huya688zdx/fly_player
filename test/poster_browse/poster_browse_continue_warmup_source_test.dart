import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('继续观看按表现档位限量后台补全并逐项刷新卡片', () {
    final source = File(
      'lib/screens/poster_browse/poster_browse_screen.dart',
    ).readAsStringSync();

    expect(source, contains("import 'poster_browse_row_artwork_warmup.dart';"));
    expect(source, contains('Future<void> _warmContinueWatchingRow('));
    expect(source, contains('PosterBrowseRowArtworkWarmup('));
    expect(source, contains('posterBrowseContinueWarmupLimit('));
    expect(source, contains('limit: warmupLimit'));
    expect(source, isNot(contains('_hydrateInitialVisibleArtwork')));
    expect(
      source,
      contains('setState(() => _displayById[card.id] = display);'),
    );
  });
}
