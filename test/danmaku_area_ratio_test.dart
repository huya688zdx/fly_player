import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/danmaku/models/danmaku_settings.dart';

void main() {
  group('resolveDanmakuCaptureAreaRatio', () {
    test('maps preset display areas to the next capture tier', () {
      expect(resolveDanmakuCaptureAreaRatio(0.10), 0.25);
      expect(resolveDanmakuCaptureAreaRatio(0.25), 0.50);
      expect(resolveDanmakuCaptureAreaRatio(0.50), 0.75);
      expect(resolveDanmakuCaptureAreaRatio(0.75), 1.0);
      expect(resolveDanmakuCaptureAreaRatio(1.0), 1.0);
    });

    test('rounds legacy values up to the next preset tier', () {
      expect(resolveDanmakuCaptureAreaRatio(0.33), 0.75);
      expect(resolveDanmakuCaptureAreaRatio(0.74), 1.0);
    });
  });

  group('resolveDanmakuMaskSourceCoverageRatio', () {
    test(
      'only uses the top portion of the capture mask that matches display area',
      () {
        expect(
          resolveDanmakuMaskSourceCoverageRatio(
            displayAreaRatio: 0.25,
            captureAreaRatio: 0.50,
          ),
          0.5,
        );
      },
    );

    test('keeps the full mask when display and capture areas match', () {
      expect(
        resolveDanmakuMaskSourceCoverageRatio(
          displayAreaRatio: 0.50,
          captureAreaRatio: 0.50,
        ),
        1.0,
      );
    });
  });
}
