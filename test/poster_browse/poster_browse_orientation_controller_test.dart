import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_orientation_controller.dart';

void main() {
  group('PosterBrowseWindowProfile', () {
    test('布局只跟随当前窗口方向而不跟随设备尺寸', () {
      expect(
        PosterBrowseWindowProfile.useMobileLayout(const Size(844, 390)),
        isFalse,
      );
      expect(
        PosterBrowseWindowProfile.useMobileLayout(const Size(390, 844)),
        isTrue,
      );
      expect(
        PosterBrowseWindowProfile.useMobileLayout(const Size(1280, 800)),
        isFalse,
      );
      expect(
        PosterBrowseWindowProfile.useMobileLayout(const Size(600, 900)),
        isTrue,
      );
    });
  });

  group('PosterBrowseOrientationController', () {
    test('进入时清空方向限制再启用沉浸模式', () async {
      final systemUi = RecordingSystemUi();
      final controller = PosterBrowseOrientationController(systemUi: systemUi);

      await controller.enter();

      expect(systemUi.calls, [
        isA<_OrientationsCall>().having(
          (call) => call.orientations,
          'orientations',
          isEmpty,
        ),
        isA<_ModeCall>().having(
          (call) => call.mode,
          'mode',
          SystemUiMode.immersiveSticky,
        ),
      ]);
    });

    test('恢复时先清空方向限制再恢复 edgeToEdge', () async {
      final systemUi = RecordingSystemUi();
      final controller = PosterBrowseOrientationController(systemUi: systemUi);

      await controller.restore();

      expect(systemUi.calls, [
        isA<_OrientationsCall>().having(
          (call) => call.orientations,
          'orientations',
          isEmpty,
        ),
        isA<_ModeCall>().having(
          (call) => call.mode,
          'mode',
          SystemUiMode.edgeToEdge,
        ),
      ]);
    });
  });
}

final class RecordingSystemUi implements PosterBrowseSystemUi {
  final calls = <Object>[];

  @override
  Future<void> setOrientations(List<DeviceOrientation> orientations) async {
    calls.add(_OrientationsCall(List<DeviceOrientation>.of(orientations)));
  }

  @override
  Future<void> setMode(SystemUiMode mode) async {
    calls.add(_ModeCall(mode));
  }
}

final class _OrientationsCall {
  const _OrientationsCall(this.orientations);

  final List<DeviceOrientation> orientations;
}

final class _ModeCall {
  const _ModeCall(this.mode);

  final SystemUiMode mode;
}
