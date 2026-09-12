import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../playback/playback_source.dart';

/// 最近一次播放的内核与视频纹理；页面关闭后暂停保留，换片时释放。
class DesktopPlaybackSession {
  DesktopPlaybackSession(
    this.source, {
    this.danmakuFilePath,
    Player? player,
    VideoController? videoController,
  }) {
    // 由内核渲染 ASS/SSA 特效字幕，避免默认文字层丢失样式、定位和动画。
    this.player =
        player ??
        Player(configuration: const PlayerConfiguration(libass: true));
    this.videoController = videoController ?? VideoController(this.player);
  }

  late final Player player;
  late final VideoController videoController;
  MpvMediaSource source;
  String? danmakuFilePath;
  bool ready = false;
  bool active = true;
  bool disposed = false;
  bool retainedByHost = false;
  Future<void> paused = Future<void>.value();
  FutureOr<void> Function(MpvMediaSource)? releaseSource;
  Future<void> Function()? disposeResources;

  Future<void>? _disposeFuture;

  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    disposed = true;
    ready = false;
    retainedByHost = false;
    try {
      await paused;
    } finally {
      try {
        await player.dispose();
      } finally {
        try {
          await releaseSource?.call(source);
        } finally {
          await disposeResources?.call();
        }
      }
    }
  }
}
