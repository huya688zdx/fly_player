import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/services/fn_connect_web_session_service.dart';

void main() {
  group('FnConnectWebSessionService', () {
    test(
      'clearLoginState delegates to the configured cookie clearer',
      () async {
        var called = false;
        final cleared = await FnConnectWebSessionService.clearLoginState(
          clearCookies: () async {
            called = true;
            return true;
          },
        );

        expect(called, isTrue);
        expect(cleared, isTrue);
      },
    );

    test('clearLoginState reports false when no cookie was cleared', () async {
      final cleared = await FnConnectWebSessionService.clearLoginState(
        clearCookies: () async => false,
      );

      expect(cleared, isFalse);
    });
  });
}
