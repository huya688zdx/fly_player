import 'package:flutter/services.dart';

abstract final class PosterBrowseWindowProfile {
  static bool useMobileLayout(Size logicalSize) =>
      logicalSize.width <= logicalSize.height;
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

  Future<void> enter() async {
    await _systemUi.setOrientations(const <DeviceOrientation>[]);
    await _systemUi.setMode(SystemUiMode.immersiveSticky);
  }

  Future<void> restore() async {
    await _systemUi.setOrientations(const []);
    await _systemUi.setMode(SystemUiMode.edgeToEdge);
  }
}
