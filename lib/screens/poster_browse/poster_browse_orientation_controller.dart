import 'package:flutter/services.dart';

abstract final class PosterBrowseDeviceProfile {
  static bool isPhone(Size logicalSize) => logicalSize.shortestSide < 600;
}

abstract interface class PosterBrowseSystemUi {
  Future<void> setOrientations(List<DeviceOrientation> orientations);

  Future<void> setMode(SystemUiMode mode);
}

final class FlutterPosterBrowseSystemUi implements PosterBrowseSystemUi {
  const FlutterPosterBrowseSystemUi();

  @override
  Future<void> setOrientations(List<DeviceOrientation> orientations) {
    return SystemChrome.setPreferredOrientations(orientations);
  }

  @override
  Future<void> setMode(SystemUiMode mode) {
    return SystemChrome.setEnabledSystemUIMode(mode);
  }
}

final class PosterBrowseOrientationController {
  const PosterBrowseOrientationController({
    PosterBrowseSystemUi systemUi = const FlutterPosterBrowseSystemUi(),
  }) : _systemUi = systemUi;

  final PosterBrowseSystemUi _systemUi;

  Future<void> enter({required bool isPhone}) async {
    await _systemUi.setOrientations(
      isPhone
          ? const [
              DeviceOrientation.portraitUp,
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ],
    );
    await _systemUi.setMode(SystemUiMode.immersiveSticky);
  }

  Future<void> restore() async {
    await _systemUi.setOrientations(const []);
    await _systemUi.setMode(SystemUiMode.edgeToEdge);
  }
}
