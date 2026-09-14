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
import '../../media_backend/media_image_ref.dart';
import '../../ui/detail_artwork_resolver.dart';
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
import 'external_playback_host.dart';
import 'external_player_settings.dart';

/// Windows / macOS / iOS 的 media_kit 播放宿主，共用换源与进度上报。
final class DesktopPlaybackHost implements PlaybackHost {
  const DesktopPlaybackHost(
    this.context, {
    this.createSession = _createSession,
  });

  final BuildContext context;
  final DesktopPlaybackSession Function(
    MpvMediaSource source, {
    String? danmakuFilePath,
  })
  createSession;

  static DesktopPlaybackSession _createSession(
    MpvMediaSource source, {
    String? danmakuFilePath,
  }) {
    MediaKit.ensureInitialized();
    return DesktopPlaybackSession(source, danmakuFilePath: danmakuFilePath);
  }

  static DesktopPlaybackSession? _session;
  static WidgetBuilder? _screenBuilder;
  static String? _scope;
  static MaterialPageRoute<void>? _route;
  static int _requestGeneration = 0;
  static MpvMediaSource? _requestedSource;
  static String? _requestedSourceScope;
  static int _sourceRequest = 0;

  void _presentScreen(WidgetBuilder builder) {
    final route = MaterialPageRoute<void>(builder: builder);
    _route = route;
    unawaited(
      route.completed.then((_) {
        if (identical(_route, route)) _route = null;
      }),
    );
    unawaited(Navigator.of(context, rootNavigator: true).push<void>(route));
  }

  bool _isCurrentRequest(int request, String scope) =>
      context.mounted &&
      request == _requestGeneration &&
      scope == playbackSessionScope(context);

  /// 先撤销认领再等待退出；晚完成的旧清理不能清除新请求的槽位。
  static Future<void> _retireSession() async {
    final session = _session;
    final route = _route;
    _session = null;
    _screenBuilder = null;
    _scope = null;
    _route = null;
    if (session != null) session.retainedByHost = false;
    if (route?.isActive == true) route!.navigator!.removeRoute(route);
    if (route != null) await route.completed;
    await session?.dispose();
  }

  @override
  Future<bool> resume({
    required String itemGuid,
    String? mediaGuid,
    String? audioGuid,
    String? subtitleGuid,
    Duration? position,
  }) async {
    if (!context.mounted) return false;
    final request = ++_requestGeneration;
    final requestScope = playbackSessionScope(context);
    final settings = await ExternalPlayerSettings.load();
    if (!context.mounted || !_isCurrentRequest(request, requestScope)) {
      return false;
    }
    if (settings.enabled) {
      return ExternalPlaybackHost(context).resume(
        itemGuid: itemGuid,
        mediaGuid: mediaGuid,
        audioGuid: audioGuid,
        subtitleGuid: subtitleGuid,
        position: position,
      );
    }
    // 弹出动画期间旧页面仍订阅内核，等它保存当前媒体并清理后再挂载。
    final route = _route;
    if (route?.isActive == false) await route!.completed;
    if (!context.mounted || !_isCurrentRequest(request, requestScope)) {
      return false;
    }
    final session = _session;
    final builder = _screenBuilder;
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
    bool isCurrent() =>
        _isCurrentRequest(request, requestScope) &&
        identical(_session, session) &&
        session.retainedByHost &&
        !session.disposed;
    await ExternalPlaybackHost.stop();
    if (!isCurrent()) return false;
    await session.paused;
    if (!isCurrent()) return false;
    if (position != null) {
      await session.player.seek(position);
      if (!isCurrent()) return false;
    }
    session.active = true;
    _presentScreen(builder);
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

    final request = ++_requestGeneration;
    final requestScope = playbackSessionScope(context);
    final provider = context.read<MediaBackendProvider>();
    final backend = provider.backend;
    final effectiveNas = nas ?? context.read<NasProvider>();
    final nasUrl = effectiveNas.baseUrl;
    final nasUser = effectiveNas.userName;
    final connection = provider.sessionProvider?.currentConnection;
    final backendKind = provider.sessionProvider?.currentKind;
    _requestedSource = source;
    _requestedSourceScope = requestScope;
    _sourceRequest = request;
    DesktopPlaybackSession? createdSession;
    var transferred = false;
    final releasedLinks = <String>{};
    bool resourceScopeIsCurrent() =>
        effectiveNas.baseUrl == nasUrl &&
        effectiveNas.userName == nasUser &&
        provider.sessionProvider?.currentKind == backendKind &&
        provider.sessionProvider?.currentConnection?.serverUrl ==
            connection?.serverUrl &&
        provider.sessionProvider?.currentConnection?.userId ==
            connection?.userId &&
        provider.sessionProvider?.currentConnection?.userName ==
            connection?.userName;
    Future<void> releaseLink(String link) async {
      link = link.trim();
      if (offline ||
          !backend.capabilities.usesLegacyFeiniuFlow ||
          link.isEmpty) {
        return;
      }
      // 新请求可能复用同一出流句柄，旧请求只释放已不再被认领的来源。
      bool canRelease() =>
          resourceScopeIsCurrent() &&
          !((_sourceRequest != request &&
                  _requestedSourceScope == requestScope &&
                  _requestedSource?.playLink?.trim() == link) ||
              (_session != null &&
                  !identical(_session, createdSession) &&
                  !_session!.disposed &&
                  _scope == requestScope &&
                  _session!.source.playLink?.trim() == link));
      if (!canRelease()) return;
      if (!releasedLinks.add(link)) return;
      await NativeReentrySupport.releaseServerSession(
        effectiveNas,
        link,
        isCurrent: canRelease,
      );
    }

    Future<void> releaseSource(MpvMediaSource owned) =>
        releaseLink(owned.playLink ?? '');
    try {
      final settings = await ExternalPlayerSettings.load();
      if (!context.mounted || !_isCurrentRequest(request, requestScope)) {
        return false;
      }
      if (settings.enabled) {
        await _retireSession();
        if (!context.mounted || !_isCurrentRequest(request, requestScope)) {
          return false;
        }
        transferred = true;
        return ExternalPlaybackHost(context).launch(
          source: source,
          episodes: episodes,
          initialPlayInfo: initialPlayInfo,
          danmakuFilePath: danmakuFilePath,
          startSource: startSource,
          nas: nas,
          offline: offline,
        );
      }

      // 只在 Windows 桌面播放真正启动时初始化，Android 主路径不会触发。
      await ExternalPlaybackHost.stop();
      if (!context.mounted || !_isCurrentRequest(request, requestScope)) {
        return false;
      }
      await _retireSession();
      if (!context.mounted || !_isCurrentRequest(request, requestScope)) {
        return false;
      }
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
      if (!context.mounted || !_isCurrentRequest(request, requestScope)) {
        return false;
      }
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
            for (final episode in result)
              {...episode, 'seasonGuid': seasonGuid},
          ];
        });
      }

      Future<List<MediaSeasonSummary>>? seasonsRequest;
      Future<List<MediaSeasonSummary>> loadSeasons() {
        return seasonsRequest ??= () async {
          try {
            var seriesGuid = source.seriesGuid.trim();
            if (seriesGuid.isEmpty) {
              seriesGuid = backend.capabilities.usesLegacyFeiniuFlow
                  ? await NativeReentrySupport.resolveSeriesGuid(
                      FeiniuApi(effectiveNas),
                      source.toMap(),
                      source.seasonGuid,
                    )
                  : (await backend.getItemDetail(source.itemGuid)).seriesId;
            }
            if (seriesGuid.isEmpty) throw StateError('未找到所属剧集，请重试');
            return await backend.getItemSeasons(seriesGuid);
          } catch (_) {
            seasonsRequest = null;
            rethrow;
          }
        }();
      }

      final subtitles = backend.capabilities.usesLegacyFeiniuFlow
          ? FeiniuSegmentedSubtitle(FeiniuApi(effectiveNas))
          : null;
      final session = createSession(source, danmakuFilePath: danmakuFilePath)
        ..releaseSource = releaseSource
        ..disposeResources = subtitles?.dispose;
      createdSession = session;
      _session = session;
      session.retainedByHost = true;
      _scope = requestScope;
      _screenBuilder = (_) => DesktopPlaybackScreen(
        session: session,
        resolveArtwork: (path) {
          final usesNas = backend.capabilities.usesLegacyFeiniuFlow;
          return DetailArtworkResolver(
            baseUrl: usesNas ? effectiveNas.baseUrl : '',
            token: usesNas ? effectiveNas.token : '',
            accessCode: usesNas ? effectiveNas.accessCode : '',
          ).resolveRef(MediaImageRef(url: path));
        },
        refreshDirectLink: backend.capabilities.usesLegacyFeiniuFlow
            ? (current) => const FeiniuPlaybackSourceBridge().refreshDirectLink(
                api: FeiniuApi(effectiveNas),
                source: current,
              )
            : null,
        resolveSegmentedSubtitle: subtitles?.resolve,
        releaseServerSession: backend.capabilities.usesLegacyFeiniuFlow
            ? releaseLink
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
        loadSeasons: offline || source.mediaType.toLowerCase() != 'episode'
            ? null
            : loadSeasons,
        loadSeasonEpisodes: offline ? null : loadEpisodes,
        resolveEpisode:
            (effectiveEpisodes?.isNotEmpty != true &&
                (offline || source.mediaType.toLowerCase() != 'episode'))
            ? null
            : (episode) async {
                final itemGuid =
                    '${episode['itemGuid'] ?? episode['guid'] ?? ''}'.trim();
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
          return MpvMediaSource.fromMap(
            jsonDecode(raw) as Map<String, dynamic>,
          );
        },
        danmakuFilePath: danmakuFilePath,
      );
      _presentScreen(_screenBuilder!);
      transferred = true;
      return true;
    } finally {
      if (!transferred) {
        final session = createdSession;
        if (session == null) {
          await releaseSource(source);
        } else {
          if (identical(_session, session)) {
            _session = null;
            _screenBuilder = null;
            _scope = null;
          }
          await session.dispose();
        }
      }
    }
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
