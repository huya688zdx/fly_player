import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/utils/async_action_guard.dart';

void main() {
  test('failed action does not leak a second unhandled async error', () async {
    final unhandledErrors = <Object>[];

    await runZonedGuarded<Future<void>>(
      () async {
        try {
          await AsyncActionGuard.run<void>(
            'failing-action',
            action: () async {
              throw StateError('boom');
            },
          );
          fail('action should throw');
        } on StateError catch (error) {
          expect(error.message, 'boom');
        }

        await Future<void>.delayed(Duration.zero);
      },
      (error, stackTrace) {
        unhandledErrors.add(error);
      },
    );

    expect(unhandledErrors, isEmpty);
  });
}
