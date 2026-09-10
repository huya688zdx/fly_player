import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../controllers/item_playback_launcher.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers/media_backend_provider.dart';
import '../services/native_playback_reentry.dart';
import '../models/play_info.dart';
import '../providers/nas_provider.dart';
import '../services/native_player_bridge.dart';
import 'playback_host.dart';
import 'playback_source.dart';

final class NativePlaybackHost implements PlaybackHost {
  const NativePlaybackHost(this.context);

  final BuildContext context;

  @override
  Future<bool> resume({
    required String itemGuid,
    String? mediaGuid,
    String? audioGuid,
    String? subtitleGuid,
    Duration? position,
  }) async {
    final resumed = await NativePlayerBridge.resume(
      scope: playbackSessionScope(context),
      itemGuid: itemGuid,
      mediaGuid: mediaGuid,
      audioGuid: audioGuid,
      subtitleGuid: subtitleGuid,
      position: position,
    );
    if (resumed && context.mounted) {
      // 原入口可能已销毁；恢复时重新接上当前引擎的进度、字幕和选集通道。
      final backend = context.read<MediaBackendProvider>().backend;
      final nas = context.read<NasProvider>();
      final l10n = AppLocalizations.of(context);
      NativePlaybackReentry.bind(
        backend: backend,
        nas: nas,
        l10n: l10n,
        onResolvePlayback:
            (
              itemGuid, {
              qualityIndex,
              qualityMediaGuid,
              startPositionMs,
              subtitleGuid,
              audioGuid,
              audioTrackIndex,
              subtitleTrackIndex,
              preferredQualityResolution,
            }) => const ItemPlaybackLauncher().resolveForNative(
              nas,
              backend: backend,
              itemGuid: itemGuid,
              qualityIndex: qualityIndex,
              qualityMediaGuid: qualityMediaGuid,
              startPositionMs: startPositionMs,
              subtitleGuid: subtitleGuid,
              audioGuid: audioGuid,
              l10n: l10n,
            ),
      );
    }
    return resumed;
  }

  @override
  Future<bool> launch({
    required MpvMediaSource source,
    List<Map<String, dynamic>>? episodes,
    PlayInfoData? initialPlayInfo,
    String? danmakuFilePath,
    String? startSource,
    NasProvider? nas,
    bool offline = false,
  }) {
    return NativePlayerBridge.maybeLaunch(
      {
        ...source.toMap(),
        'playbackSessionScope': playbackSessionScope(context),
      },
      episodes: episodes,
      initialPlayInfo: initialPlayInfo?.toJson(),
      danmakuFilePath: danmakuFilePath,
      startSource: startSource,
      nas: offline ? null : nas,
    );
  }
}
