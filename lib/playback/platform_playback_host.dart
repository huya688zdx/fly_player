import 'package:flutter/widgets.dart';

import '../desktop/desktop_environment.dart';
import '../desktop/playback/desktop_playback_host.dart';
import 'native_playback_host.dart';
import 'playback_host.dart';

/// 按当前平台选择唯一播放宿主；本轮仅 Windows 启用桌面播放页。
PlaybackHost playbackHostFor(BuildContext context) {
  if (DesktopEnvironment.isWindows) {
    return DesktopPlaybackHost(context);
  }
  return const NativePlaybackHost();
}
