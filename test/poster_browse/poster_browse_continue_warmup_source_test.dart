import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('继续观看整行在首屏后台限并发补全并逐项刷新卡片', () {
    final source = File(
      'lib/screens/poster_browse/poster_browse_screen.dart',
    ).readAsStringSync();

    expect(source, contains("import 'poster_browse_row_artwork_warmup.dart';"));
    expect(source, contains('Future<void> _warmContinueWatchingRow('));
    expect(source, contains('PosterBrowseRowArtworkWarmup('));
    expect(
      source,
      contains('setState(() => _displayById[card.id] = display);'),
    );
  });
}
