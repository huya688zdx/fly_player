import '../models/play_info.dart';
import '../providers/nas_provider.dart';
import '../services/native_player_bridge.dart';
import 'playback_host.dart';
import 'playback_source.dart';

final class NativePlaybackHost implements PlaybackHost {
  const NativePlaybackHost();

  @override
  Future<bool> launch({
    required MpvMediaSource source,
    List<Map<String, dynamic>>? episodes,
    PlayInfoData? initialPlayInfo,
    String? danmakuFilePath,
    String? startSource,
    NasProvider? nas,
  }) {
    return NativePlayerBridge.maybeLaunch(
      source.toMap(),
      episodes: episodes,
      initialPlayInfo: initialPlayInfo?.toJson(),
      danmakuFilePath: danmakuFilePath,
      startSource: startSource,
      nas: nas,
    );
  }
}
