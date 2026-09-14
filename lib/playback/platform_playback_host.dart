import 'package:flutter/widgets.dart';

import '../desktop/playback/desktop_playback_host.dart';
import 'native_playback_host.dart';
import 'playback_host.dart';
import 'playback_platform.dart';
import 'unsupported_playback_host.dart';

/// Android 使用原生 Activity；Windows / Apple 使用独立 media_kit 宿主。
PlaybackHost playbackHostFor(BuildContext context) {
  if (PlaybackPlatform.usesMediaKit) {
    return DesktopPlaybackHost(context);
  }
  if (PlaybackPlatform.usesAndroidHost) {
    return NativePlaybackHost(context);
  }
  return const UnsupportedPlaybackHost();
}
