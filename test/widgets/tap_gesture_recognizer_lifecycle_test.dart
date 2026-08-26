import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detail preview links avoid build-time TapGestureRecognizer leaks', () {
    for (final path in <String>[
      'lib/widgets/detail/description_section.dart',
      'lib/widgets/detail/tv_episode_browser_section.dart',
      'lib/screens/person_detail_screen.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('TapGestureRecognizer()')));
    }
  });
}
