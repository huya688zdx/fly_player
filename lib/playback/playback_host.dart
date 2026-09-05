import '../models/play_info.dart';
import '../providers/nas_provider.dart';
import 'playback_source.dart';

abstract interface class PlaybackHost {
  Future<bool> launch({
    required MpvMediaSource source,
    List<Map<String, dynamic>>? episodes,
    PlayInfoData? initialPlayInfo,
    String? danmakuFilePath,
    String? startSource,
    NasProvider? nas,
  });
}
