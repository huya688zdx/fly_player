import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import '../../api/feiniu_api.dart';
import '../../services/feiniu_segmented_subtitle.dart';
import '../../controllers/item_playback_launcher.dart';
import '../../controllers/local_download_source_resolver.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../media_backend/media_backend.dart';
import '../../media_backend/detail/media_season_summary.dart';
import '../../models/play_info.dart';
import '../../providers/media_backend_provider.dart';
import '../../playback/playback_host.dart';
import '../../playback/feiniu_playback_source_bridge.dart';
import '../../playback/playback_source.dart';
import '../../providers/nas_provider.dart';
import '../../services/native_reentry_support.dart';
import '../../services/native_playback_reentry.dart';
import '../../services/server_native_picker_support.dart';
import '../../services/server_reentry_support.dart';
import 'desktop_playback_screen.dart';
import 'desktop_playback_session.dart';

/// Windows 桌面播放宿主：初始化桌面内核并把正式播放页推入根导航栈。
final class DesktopPlaybackHost implements PlaybackHost {
  const DesktopPlaybackHost(this.context);

  final BuildContext context;
  static DesktopPlaybackSession? _session;
  static WidgetBuilder? _screenBuilder;
  static String? _scope;
  static MaterialPageRoute<void>? _route;

  @override
  Future<bool> resume({
    required String itemGuid,
    String? mediaGuid,
    String? audioGuid,
    String? subtitleGuid,
    Duration? position,
  }) async {
    final session = _session;
    final builder = _screenBuilder;
    // 弹出动画期间旧页面仍订阅内核，等它保存当前媒体并清理后再挂载。
    if (_route?.isActive == false) await _route!.completed;
    if (!context.mounted) return false;
    if (session == null ||
        builder == null ||
        session.disposed ||
        _scope != playbackSessionScope(context) ||
        itemGuid.trim().isEmpty ||
        session.source.itemGuid != itemGuid.trim() ||
        (mediaGuid?.isNotEmpty == true &&
            session.source.mediaGuid != mediaGuid) ||
        (audioGuid != null && session.source.audioTrackGuid != audioGuid) ||
        (subtitleGuid != null &&
            session.source.subtitleTrackGuid != subtitleGuid)) {
      return false;
    }
    if (session.active || !session.ready) return false;
    await session.paused;
    if (position != null) await session.player.seek(position);
    if (!context.mounted) return false;
    session.active = true;
    _route = MaterialPageRoute<void>(builder: builder);
    unawaited(Navigator.of(context, rootNavigator: true).push<void>(_route!));
    return true;
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
  }) async {
    if (!context.mounted) {
      return false;
    }

    // 只在 Windows 桌面播放真正启动时初始化，Android 主路径不会触发。
    MediaKit.ensureInitialized();
    if (_route?.isActive == false) await _route!.completed;
    await _session?.dispose();
    _session = null;
    _screenBuilder = null;
    if (!context.mounted) return false;
    final backend = context.read<MediaBackendProvider>().backend;
    final effectiveNas = nas ?? context.read<NasProvider>();
    final serverReporter = ServerPlaybackReporter(backend);
    final l10n = AppLocalizations.of(context);
    final effectiveEpisodes = episodes?.isNotEmpty == true
        ? episodes
        : offline
        ? null
        : await _loadSeasonEpisodes(
            source: source,
            nas: effectiveNas,
            backend: backend,
          );
    if (!context.mounted) return false;
    // 缓存与本次播放会话同寿命；重开面板、同季重复点击共用在途请求。
    final seasonEpisodes = <String, Future<List<Map<String, dynamic>>>>{
      if (effectiveEpisodes?.isNotEmpty == true)
        source.seasonGuid: Future.value(effectiveEpisodes),
    };
    Future<List<Map<String, dynamic>>> loadEpisodes(String seasonGuid) {
      return seasonEpisodes.putIfAbsent(seasonGuid, () async {
        final result = await _loadSeasonEpisodes(
          source: source,
          seasonGuid: seasonGuid,
          nas: effectiveNas,
          backend: backend,
        );
        if (result == null || result.isEmpty) {
          seasonEpisodes.remove(seasonGuid);
          throw StateError('加载该季剧集失败，请重试');
        }
        return [
          for (final episode in result) {...episode, 'seasonGuid': seasonGuid},
        ];
      });
    }

    Future<List<MediaSeasonSummary>>? seasonsRequest;
    Future<List<MediaSeasonSummary>> loadSeasons() {
      return seasonsRequest ??= () async {
        try {
          return await backend.getItemSeasons(source.seriesGuid);
        } catch (_) {
          seasonsRequest = null;
          rethrow;
        }
      }();
    }

    final subtitles = backend.capabilities.usesLegacyFeiniuFlow
        ? FeiniuSegmentedSubtitle(FeiniuApi(effectiveNas))
        : null;
    final session = DesktopPlaybackSession(
      source,
      danmakuFilePath: danmakuFilePath,
    )..disposeResources = subtitles?.dispose;
    _session = session;
    _scope = playbackSessionScope(context);
    _screenBuilder = (_) => DesktopPlaybackScreen(
      session: session,
      refreshDirectLink: backend.capabilities.usesLegacyFeiniuFlow
          ? (current) => const FeiniuPlaybackSourceBridge().refreshDirectLink(
              api: FeiniuApi(effectiveNas),
              source: current,
            )
          : null,
      resolveSegmentedSubtitle: subtitles?.resolve,
      releaseServerSession: backend.capabilities.usesLegacyFeiniuFlow
          ? (link) =>
                NativeReentrySupport.releaseServerSession(effectiveNas, link)
          : null,
      resolveSubtitleFile: backend.capabilities.usesLegacyFeiniuFlow
          ? (guid, {format}) => NativeReentrySupport.resolveSubtitleFile(
              effectiveNas,
              guid,
              format: format,
            )
          : (guid, {format}) =>
                backend.resolveExternalSubtitleFile(guid, format: format),
      onRecordProgress: backend.capabilities.usesLegacyFeiniuFlow
          ? (progress) =>
                NativeReentrySupport.recordProgress(effectiveNas, progress)
          : serverReporter.report,
      source: session.source,
      episodes: effectiveEpisodes,
      loadSeasons: offline || source.seriesGuid.isEmpty ? null : loadSeasons,
      loadSeasonEpisodes: offline ? null : loadEpisodes,
      resolveEpisode:
          (effectiveEpisodes?.isNotEmpty != true &&
              (offline || source.mediaType != 'episode'))
          ? null
          : (episode) async {
              final itemGuid = '${episode['itemGuid'] ?? episode['guid'] ?? ''}'
                  .trim();
              if (itemGuid.isEmpty) return null;
              final seasonGuid =
                  '${episode['seasonGuid'] ?? source.seasonGuid}';
              final selectedEpisodes = offline
                  ? effectiveEpisodes!
                  : await loadEpisodes(seasonGuid);
              final resolved = await const ItemPlaybackLauncher()
                  .resolveForNative(
                    effectiveNas,
                    backend: backend,
                    itemGuid: itemGuid,
                    fallbackTitle:
                        '${episode['title'] ?? episode['shortLabel'] ?? ''}',
                    episodes: selectedEpisodes,
                    allowNetwork: !offline,
                    l10n: l10n,
                  );
              final raw = resolved?['loadArgs'];
              if (raw is! String || raw.isEmpty) return null;
              return (
                source: MpvMediaSource.fromMap(
                  jsonDecode(raw) as Map<String, dynamic>,
                ),
                danmakuFilePath: resolved?['danmakuFile']?.toString().trim(),
                episodes: selectedEpisodes,
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
        return MpvMediaSource.fromMap(jsonDecode(raw) as Map<String, dynamic>);
      },
      danmakuFilePath: danmakuFilePath,
    );
    _route = MaterialPageRoute<void>(builder: _screenBuilder!);
    unawaited(Navigator.of(context, rootNavigator: true).push<void>(_route!));
    return true;
  }

  Future<List<Map<String, dynamic>>?> _loadSeasonEpisodes({
    required MpvMediaSource source,
    required NasProvider nas,
    required MediaBackend backend,
    String? seasonGuid,
  }) async {
    if (source.mediaType.trim().toLowerCase() != 'episode') return null;
    seasonGuid = (seasonGuid ?? source.seasonGuid).trim();
    if (seasonGuid.isEmpty) return null;
    try {
      if (backend.capabilities.usesLegacyFeiniuFlow) {
        final request = const ItemPlaybackLauncher().loadSeasonEpisodes(
          nas,
          seasonGuid,
        );
        final result = source.isDownloadedFile
            ? await request.timeout(
                localDownloadMetadataTimeout,
                onTimeout: () => const [],
              )
            : await request;
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
