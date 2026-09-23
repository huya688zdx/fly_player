import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('继续观看只在首帧之后补全当前焦点，不再预取整行', () {
    final source = File(
      'lib/screens/poster_browse/poster_browse_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('_warmContinueWatchingRow(')));
    expect(source, isNot(contains('_precacheNeighbors(')));
    expect(source, contains('await WidgetsBinding.instance.endOfFrame;'));
    expect(source, contains('if (_enrichmentRunning) return;'));
    expect(
      source,
      contains('setState(() => _displayById[card.id] = enrichedDisplay);'),
    );
  });
}
