import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('media info screen disposes its guid text controller', () {
    final source = File(
      'lib/screens/media_info_screen.dart',
    ).readAsStringSync();

    expect(source, contains('_guidController.dispose()'));
  });

  test('mpv audio eq preset dialog disposes its temporary text controller', () {
    final source = File(
      'lib/ui/mpv_audio_eq_advanced_panel.dart',
    ).readAsStringSync();

    expect(source, contains('controller.dispose()'));
  });
}
