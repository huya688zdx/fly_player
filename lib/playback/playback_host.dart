import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../providers/media_backend_provider.dart';
import '../models/play_info.dart';
import '../media_backend/media_backend_kind.dart';
import '../providers/nas_provider.dart';
import 'playback_source.dart';

abstract interface class PlaybackHost {
  /// 只复用当前进程中同一服务器、账号下的最近一次播放。
  Future<bool> resume({
    required String itemGuid,
    String? mediaGuid,
    String? audioGuid,
    String? subtitleGuid,
    Duration? position,
  });

  Future<bool> launch({
    required MpvMediaSource source,
    List<Map<String, dynamic>>? episodes,
    PlayInfoData? initialPlayInfo,
    String? danmakuFilePath,
    String? startSource,
    NasProvider? nas,
    bool offline = false,
  });
}

String playbackSessionScope(BuildContext context) {
  final session = context.read<MediaBackendProvider>().sessionProvider;
  final connection = session?.currentConnection;
  if (session?.currentKind.isServerFamily == true && connection != null) {
    return '${connection.kind.name}:${connection.serverUrl}:${connection.userId}:${connection.userName}';
  }
  final nas = context.read<NasProvider>();
  return 'feiniu:${nas.baseUrl}:${nas.userName}';
}
