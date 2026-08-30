import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../models/play_info.dart';
import '../../playback/playback_host.dart';
import '../../playback/playback_source.dart';
import '../../providers/nas_provider.dart';
import 'desktop_playback_screen.dart';

/// Windows 桌面播放宿主：初始化桌面内核并把正式播放页推入根导航栈。
final class DesktopPlaybackHost implements PlaybackHost {
  const DesktopPlaybackHost(this.context);

  final BuildContext context;

  @override
  Future<bool> launch({
    required MpvMediaSource source,
    List<Map<String, dynamic>>? episodes,
    PlayInfoData? initialPlayInfo,
    String? danmakuFilePath,
    String? startSource,
    NasProvider? nas,
  }) async {
    if (!context.mounted) {
      return false;
    }

    // 只在 Windows 桌面播放真正启动时初始化，Android 主路径不会触发。
    MediaKit.ensureInitialized();
    unawaited(
      Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => DesktopPlaybackScreen(
            source: source,
            episodes: episodes,
            danmakuFilePath: danmakuFilePath,
          ),
        ),
      ),
    );
    return true;
  }
}
