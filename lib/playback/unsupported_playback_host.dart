import '../models/play_info.dart';
import '../providers/nas_provider.dart';
import 'playback_host.dart';
import 'playback_source.dart';

/// An unsupported platform must never fall through to Android channels.
final class UnsupportedPlaybackHost implements PlaybackHost {
  const UnsupportedPlaybackHost();

  @override
  Future<bool> resume({
    required String itemGuid,
    String? mediaGuid,
    String? audioGuid,
    String? subtitleGuid,
    Duration? position,
  }) async => false;

  @override
  Future<bool> launch({
    required MpvMediaSource source,
    List<Map<String, dynamic>>? episodes,
    PlayInfoData? initialPlayInfo,
    String? danmakuFilePath,
    String? startSource,
    NasProvider? nas,
    bool offline = false,
  }) async => false;
}
