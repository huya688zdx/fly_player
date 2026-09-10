import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../playback/playback_source.dart';

/// 最近一次播放的内核与视频纹理；页面关闭后暂停保留，换片时释放。
class DesktopPlaybackSession {
  DesktopPlaybackSession(this.source, {this.danmakuFilePath}) {
    player = Player();
    videoController = VideoController(player);
  }

  late final Player player;
  late final VideoController videoController;
  MpvMediaSource source;
  String? danmakuFilePath;
  bool ready = false;
  bool active = true;
  bool disposed = false;
  Future<void> paused = Future<void>.value();
  void Function(MpvMediaSource)? releaseSource;
  Future<void> Function()? disposeResources;

  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    ready = false;
    await paused;
    await player.dispose();
    releaseSource?.call(source);
    await disposeResources?.call();
  }
}
