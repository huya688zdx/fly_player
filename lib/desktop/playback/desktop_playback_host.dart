import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import '../../controllers/item_playback_launcher.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../media_backend/media_backend.dart';
import '../../models/play_info.dart';
import '../../providers/media_backend_provider.dart';
import '../../playback/playback_host.dart';
import '../../playback/playback_source.dart';
import '../../providers/nas_provider.dart';
import '../../services/native_reentry_support.dart';
import '../../services/server_native_picker_support.dart';
import '../../services/server_reentry_support.dart';
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
    final backend = context.read<MediaBackendProvider>().backend;
    final effectiveNas = nas ?? context.read<NasProvider>();
    final l10n = AppLocalizations.of(context);
    final effectiveEpisodes = episodes?.isNotEmpty == true
        ? episodes
        : await _loadSeasonEpisodes(
            source: source,
            nas: effectiveNas,
            backend: backend,
          );
    if (!context.mounted) return false;
    unawaited(
      Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => DesktopPlaybackScreen(
            source: source,
            episodes: effectiveEpisodes,
            resolveEpisode:
                effectiveEpisodes == null || effectiveEpisodes.isEmpty
                ? null
                : (episode) async {
                    final itemGuid =
                        '${episode['itemGuid'] ?? episode['guid'] ?? ''}'
                            .trim();
                    if (itemGuid.isEmpty) return null;
                    final resolved = await const ItemPlaybackLauncher()
                        .resolveForNative(
                          effectiveNas,
                          backend: backend,
                          itemGuid: itemGuid,
                          fallbackTitle:
                              '${episode['title'] ?? episode['shortLabel'] ?? ''}',
                          episodes: effectiveEpisodes,
                          l10n: l10n,
                        );
                    final raw = resolved?['loadArgs'];
                    if (raw is! String || raw.isEmpty) return null;
                    return (
                      source: MpvMediaSource.fromMap(
                        jsonDecode(raw) as Map<String, dynamic>,
                      ),
                      danmakuFilePath: resolved?['danmakuFile']
                          ?.toString()
                          .trim(),
                    );
                  },
            reloadSource: (current, intent) async {
              final currentLoadArgs = jsonEncode(current.toMap());
              final result = backend.capabilities.usesLegacyFeiniuFlow
                  ? await NativeReentrySupport.reloadServerSession(
                      effectiveNas,
                      currentLoadArgs: currentLoadArgs,
                      intent: intent,
                    )
                  : await ServerReentrySupport.reloadServerSession(
                      backend,
                      currentLoadArgs: currentLoadArgs,
                      intent: intent,
                      l10n: l10n,
                    );
              final raw = result?['loadArgs'];
              if (raw is! String || raw.isEmpty) return null;
              return MpvMediaSource.fromMap(
                jsonDecode(raw) as Map<String, dynamic>,
              );
            },
            danmakuFilePath: danmakuFilePath,
          ),
        ),
      ),
    );
    return true;
  }

  Future<List<Map<String, dynamic>>?> _loadSeasonEpisodes({
    required MpvMediaSource source,
    required NasProvider nas,
    required MediaBackend backend,
  }) async {
    if (source.mediaType.trim().toLowerCase() != 'episode') return null;
    final seasonGuid = source.seasonGuid.trim();
    if (seasonGuid.isEmpty) return null;
    try {
      if (backend.capabilities.usesLegacyFeiniuFlow) {
        final result = await const ItemPlaybackLauncher().loadSeasonEpisodes(
          nas,
          seasonGuid,
        );
        return result.isEmpty ? null : result;
      }
      final result = await backend.getSeasonEpisodes(seasonGuid);
      if (result.isEmpty) return null;
      return ServerNativePickerSupport.nativeEpisodePayload(result, seasonGuid);
    } catch (_) {
      return null;
    }
  }
}
