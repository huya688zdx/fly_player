import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/feiniu_api.dart';
import '../../controllers/item_playback_launcher.dart';
import '../../danmaku/settings/danmaku_settings_store.dart';
import '../../danmaku/models/danmaku_settings.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../media_backend/media_backend.dart';
import '../../media_backend/playback/media_session_reload.dart';
import '../../models/play_info.dart';
import '../../models/playback_stream.dart';
import '../../playback/feiniu_playback_source_bridge.dart';
import '../../playback/playback_host.dart';
import '../../playback/playback_source.dart';
import '../../providers/media_backend_provider.dart';
import '../../providers/nas_provider.dart';
import '../../services/native_danmaku_prefetch.dart';
import '../../services/native_playback_reentry.dart';
import '../../services/native_reentry_support.dart';
import '../../services/playback_progress_offline_queue.dart';
import '../../services/server_reentry_support.dart';
import 'external_playback_notice.dart';
import 'desktop_mpv_runtime.dart';
import 'desktop_playback_launch_guard.dart';
import 'desktop_playback_reporter.dart';
import 'external_player_media_proxy.dart';
import 'external_player_playlist.dart';
import 'external_player_settings.dart';
import 'external_player_subtitles.dart';
import 'potplayer_session.dart';

typedef _PreparedExternalItem = ({
  MpvMediaSource source,
  String? subtitle,
  String? danmaku,
  int count,
  String settings,
});

enum ExternalPlaybackPhase { preparing, ready, disconnected, ended }

/// 控制页只展示实际播放器采样和回报结果。
class ExternalPlaybackStatus {
  const ExternalPlaybackStatus({
    required this.source,
    required this.position,
    required this.duration,
    required this.paused,
    required this.danmakuEnabled,
    required this.danmakuLabel,
    required this.danmakuCount,
    this.phase = ExternalPlaybackPhase.ready,
    this.error,
    this.progressMessage = '等待进度回报',
    this.lastSyncedAt,
    this.progressResult,
    this.danmakuSettings = DanmakuSettings.defaults,
    this.playlist = const [],
  });
  final MpvMediaSource source;
  final Duration position;
  final Duration duration;
  final bool paused;
  final bool danmakuEnabled;
  final String danmakuLabel;
  final int danmakuCount;
  final ExternalPlaybackPhase phase;
  final String? error;
  final String progressMessage;
  final DateTime? lastSyncedAt;
  final PlaybackProgressResult? progressResult;
  final DanmakuSettings danmakuSettings;
  final List<ExternalPlaylistEpisode> playlist;

  bool get canControl => phase == ExternalPlaybackPhase.ready;

  ExternalPlaybackStatus withPhase(
    ExternalPlaybackPhase phase, {
    String? error,
  }) => ExternalPlaybackStatus(
    source: source,
    position: position,
    duration: duration,
    paused: paused,
    danmakuEnabled: danmakuEnabled,
    danmakuLabel: danmakuLabel,
    danmakuCount: danmakuCount,
    phase: phase,
    error: error,
    progressMessage: progressMessage,
    lastSyncedAt: lastSyncedAt,
    progressResult: progressResult,
    danmakuSettings: danmakuSettings,
    playlist: playlist,
  );
}

/// 外部播放器只消费已解析的播放源，沿用现有字幕、弹幕和后端回报链路。
final class ExternalPlaybackHost implements PlaybackHost {
  const ExternalPlaybackHost(this.context, {this.launchRequest});

  final BuildContext context;
  final DesktopPlaybackLaunchRequest? launchRequest;
  static PotPlayerSession? _session;
  static MpvMediaSource? _source;
  static String? _scope;
  static bool _launching = false;
  static Object? _launchOwner;
  static final status = ValueNotifier<ExternalPlaybackStatus?>(null);
  static Future<bool> Function(
    String?,
    String?,
    bool?,
    DanmakuSettings?,
    String?,
  )?
  _applyDanmaku;
  static Future<bool> Function()? _retryProgress;
  static bool _changingSource = false;
  static bool _offline = false;
  static String? _danmakuFilePath;

  static bool sourceInUse(String scope, String playLink) =>
      _scope == scope &&
      _session?.finished == false &&
      _source?.playLink?.trim() == playLink;

  Future<bool?> _runSourceChange(
    String title,
    Future<bool> Function(ExternalPlaybackHost host) action,
  ) => DesktopPlaybackLaunchGuard.run<bool>(
    context,
    title: title,
    sourceInUse: sourceInUse,
    action: (request) =>
        action(ExternalPlaybackHost(context, launchRequest: request)),
  );

  Duration? positionForLaunch({required String itemGuid}) {
    if (!context.mounted ||
        _scope != playbackSessionScope(context) ||
        !_controlsItem(itemGuid)) {
      return null;
    }
    final active = status.value;
    return active?.source.itemGuid == itemGuid ? active!.position : null;
  }

  static bool _controlsItem(String itemGuid) =>
      _session?.finished == false &&
      _session!.isCurrentSession() &&
      _source?.itemGuid == itemGuid &&
      status.value?.source.itemGuid == itemGuid &&
      status.value?.canControl == true;

  static Future<bool> activateCurrent({required String itemGuid}) async =>
      _controlsItem(itemGuid) &&
      await _session!.activate(resumePlayback: false);

  static Future<bool> setPaused(bool paused, {required String itemGuid}) async {
    if (!_controlsItem(itemGuid)) return false;
    final session = _session!;
    await session.poll();
    if (!_controlsItem(itemGuid) || !identical(_session, session)) return false;
    if (!await PotPlayerSession.sendCommand('configure', {
      'pid': session.pid,
      'paused': paused,
      'mediaUrl': session.mediaUrl,
    })) {
      return false;
    }
    if (!identical(_session, session) || !_controlsItem(itemGuid)) return false;
    return await session.confirmPlayback(paused: paused) &&
        identical(_session, session) &&
        _controlsItem(itemGuid);
  }

  static Future<bool> seek(
    Duration position, {
    required String itemGuid,
  }) async {
    if (!_controlsItem(itemGuid)) return false;
    final session = _session!;
    await session.poll();
    if (!_controlsItem(itemGuid) || !identical(_session, session)) return false;
    final target = Duration(
      milliseconds: position.inMilliseconds.clamp(
        0,
        status.value!.duration.inMilliseconds,
      ),
    );
    if (!await PotPlayerSession.sendCommand('activate', {
      'pid': session.pid,
      'positionMs': target.inMilliseconds,
      'focus': false,
      'mediaUrl': session.mediaUrl,
    })) {
      return false;
    }
    if (!identical(_session, session) || !_controlsItem(itemGuid)) return false;
    return await session.confirmPlayback(position: target) &&
        identical(_session, session) &&
        _controlsItem(itemGuid);
  }

  static Future<bool> applyDanmaku({
    required String itemGuid,
    String? path,
    String? label,
    bool? enabled,
  }) async {
    if (!_controlsItem(itemGuid)) return false;
    return await _applyDanmaku?.call(path, label, enabled, null, null) ?? false;
  }

  static Future<bool> applySettings({
    required String itemGuid,
    required DanmakuSettings settings,
    String? subtitleGuid,
  }) async {
    if (!_controlsItem(itemGuid)) return false;
    return await _applyDanmaku?.call(
          null,
          null,
          null,
          settings,
          subtitleGuid,
        ) ??
        false;
  }

  static Future<bool> retryProgress() async {
    final current = status.value;
    if (current == null || !_controlsItem(current.source.itemGuid)) {
      return false;
    }
    return await _retryProgress?.call() ?? false;
  }

  static Future<void> stop() async {
    // Invalidate even a launch that has not received its native PID yet.
    _launchOwner = null;
    await _stopSession();
  }

  static Future<void> _stopSession() async {
    final session = _session;
    if (session != null) {
      // Startup has no authoritative sample to refresh, and polling here would
      // make cancellation wait for the same unresponsive native boundary.
      if (status.value?.canControl == true) await session.poll();
      await session.finish(closePlayer: true);
    }
    if (identical(_session, session)) {
      _session = null;
      _source = null;
      status.value = null;
      _applyDanmaku = null;
      _retryProgress = null;
      _danmakuFilePath = null;
    }
  }

  Future<bool?> playEpisode({
    required String itemGuid,
    required String episodeGuid,
  }) => _runSourceChange(
    status.value?.playlist
            .where((entry) => entry.itemGuid == episodeGuid)
            .firstOrNull
            ?.title ??
        '所选剧集',
    (host) => host._playEpisode(itemGuid: itemGuid, episodeGuid: episodeGuid),
  );

  Future<bool> _playEpisode({
    required String itemGuid,
    required String episodeGuid,
  }) async {
    final active = status.value;
    if (!context.mounted ||
        active == null ||
        !_controlsItem(itemGuid) ||
        _changingSource ||
        _scope != playbackSessionScope(context)) {
      return false;
    }
    final target = active.playlist.indexWhere(
      (entry) => entry.itemGuid == episodeGuid,
    );
    final current = active.playlist.indexWhere(
      (entry) => entry.itemGuid == itemGuid,
    );
    if (target < 0 || current < 0) return false;
    if (target == current) return activateCurrent(itemGuid: itemGuid);
    // 已有 DPL 的相邻条目直接在当前进程切换，最终身份交接由真实采样确认。
    final session = _session!;
    if ((target - current).abs() == 1 && session.onMediaChanged != null) {
      _changingSource = true;
      status.value = active.withPhase(ExternalPlaybackPhase.preparing);
      try {
        if (!await PotPlayerSession.sendCommand('stepPlaylist', {
          'pid': session.pid,
          'mediaUrl': session.mediaUrl,
          'direction': target > current ? 1 : -1,
        })) {
          return false;
        }
        final deadline = DateTime.now().add(const Duration(minutes: 2));
        while (DateTime.now().isBefore(deadline)) {
          await session.poll();
          if (session.finished || !identical(_session, session)) {
            return false;
          }
          if (_source?.itemGuid == episodeGuid &&
              status.value!.duration > Duration.zero) {
            // 先确认新媒体身份，再取消；否则会把仍在交接的播放留在进程中。
            if (launchRequest?.cancelled == true) {
              await session.finish(closePlayer: true);
              return false;
            }
            return true;
          }
          if (launchRequest?.isCurrent == false &&
              launchRequest?.cancelled != true) {
            return false;
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        return false;
      } finally {
        _changingSource = false;
        // 成功状态仍从播放器重新采样，不能把异步命令投递当作切换完成。
        await session.poll();
      }
    }
    return _replaceMedia(active, episodeGuid: episodeGuid);
  }

  Future<bool?> changeQuality({
    required String itemGuid,
    required PlaybackQualityOption quality,
  }) => _runSourceChange(
    status.value?.source.title ?? '所选片源',
    (host) => host._changeQuality(itemGuid: itemGuid, quality: quality),
  );

  Future<bool> _changeQuality({
    required String itemGuid,
    required PlaybackQualityOption quality,
  }) async {
    final active = status.value;
    if (!context.mounted ||
        active == null ||
        !_controlsItem(itemGuid) ||
        _offline ||
        active.source.externalLocalSource ||
        _changingSource ||
        _scope != playbackSessionScope(context)) {
      return false;
    }
    final index = active.source.qualities.indexOf(quality);
    if (index < 0) return false;
    return _replaceMedia(active, qualityIndex: index);
  }

  Future<bool> _replaceMedia(
    ExternalPlaybackStatus active, {
    String? episodeGuid,
    int? qualityIndex,
  }) async {
    _changingSource = true;
    final expected = _source;
    final session = _session;
    final expectedUrl = session?.mediaUrl;
    try {
      final nas = context.read<NasProvider>();
      final backend = context.read<MediaBackendProvider>().backend;
      final l10n = AppLocalizations.of(context);
      final result = qualityIndex != null
          ? await _reloadQuality(
              active.source.copyWith(startPosition: active.position),
              qualityIndex: qualityIndex,
            )
          : await const ItemPlaybackLauncher().resolveForNative(
              nas,
              backend: backend,
              itemGuid: episodeGuid ?? active.source.itemGuid,
              fallbackTitle: active.source.title,
              // 不把另一版本、另一集的字幕 GUID 误套到新媒体。
              subtitleGuid: active.source.subtitleTrackGuid == '' ? '' : null,
              startPositionMs: episodeGuid == null
                  ? active.position.inMilliseconds
                  : null,
              l10n: l10n,
              allowNetwork: !_offline,
            );
      final raw = result?['loadArgs'];
      if (raw is! String || raw.isEmpty) return false;
      final resolved = MpvMediaSource.fromMap(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      launchRequest?.pendingSource = resolved;
      if (launchRequest?.isCurrent == false ||
          !context.mounted ||
          !identical(_source, expected) ||
          !identical(_session, session) ||
          _scope != playbackSessionScope(context)) {
        return false;
      }
      final snapshot = await PotPlayerSession.channel
          .invokeMapMethod<String, dynamic>('snapshot', {'pid': session!.pid});
      if (launchRequest?.isCurrent == false ||
          snapshot?['alive'] != true ||
          !PotPlayerSession.sameMedia(
            '${snapshot?['file'] ?? ''}',
            expectedUrl!,
          ) ||
          !identical(_source, expected) ||
          !identical(_session, session) ||
          !context.mounted ||
          _scope != playbackSessionScope(context)) {
        return false;
      }
      final selectedSource = episodeGuid == null
          ? resolved
          : ExternalPlayerPlaylist.inheritSubtitleSelection(
              active.source,
              resolved,
            );
      final next = selectedSource.copyWith(
        startPaused: episodeGuid == null ? status.value!.paused : false,
        startPosition: episodeGuid == null
            ? status.value!.position
            : resolved.startPosition,
        isDownloadedFile: qualityIndex != null
            ? false
            : resolved.isDownloadedFile,
        subtitleTrackGuid: active.source.subtitleTrackGuid == ''
            ? ''
            : selectedSource.subtitleTrackGuid,
      );
      return await launch(
        source: next,
        episodes: _episodeMaps(active.playlist),
        danmakuFilePath: qualityIndex != null
            ? _danmakuFilePath
            : result?['danmakuFile']?.toString(),
        offline: _offline,
      );
    } finally {
      _changingSource = false;
    }
  }

  Future<Map<String, dynamic>?> _reloadQuality(
    MpvMediaSource source, {
    int? qualityIndex,
  }) {
    final backend = context.read<MediaBackendProvider>().backend;
    final intent = MediaSessionReloadIntent(
      qualityIndex: qualityIndex,
      startPosition: source.startPosition,
      subtitleDisabled: source.subtitleTrackGuid == '',
    );
    return backend.capabilities.usesLegacyFeiniuFlow
        ? NativeReentrySupport.reloadServerSession(
            context.read<NasProvider>(),
            currentLoadArgs: jsonEncode(source.toMap()),
            intent: intent,
          )
        : ServerReentrySupport.reloadServerSession(
            backend,
            currentLoadArgs: jsonEncode(source.toMap()),
            intent: intent,
            l10n: AppLocalizations.of(context),
          );
  }

  static List<Map<String, dynamic>> _episodeMaps(
    List<ExternalPlaylistEpisode> entries,
  ) => [
    for (final entry in entries)
      {
        'itemGuid': entry.itemGuid,
        'title': entry.title,
        'seasonGuid': entry.seasonGuid,
        'seasonNumber': entry.seasonNumber,
        'episodeNumber': entry.episodeNumber,
      },
  ];

  Future<bool?> reconnect() => _runSourceChange(
    status.value?.source.title ?? '当前影片',
    (host) => host._reconnect(),
  );

  Future<bool> _reconnect() async {
    final active = status.value;
    if (!context.mounted ||
        active == null ||
        _launching ||
        _changingSource ||
        _scope != playbackSessionScope(context)) {
      return false;
    }
    final session = _session;
    if (session != null && !session.finished) {
      await session.poll();
      if (status.value?.canControl == true) return true;
      if (!session.finished) return false;
    }
    var source = active.source.copyWith(
      startPosition: active.position,
      startPaused: active.paused,
    );
    if (!_offline && source.serverPlaybackManaged) {
      final result = await _reloadQuality(source);
      final raw = result?['loadArgs'];
      if (raw is! String) return false;
      source = MpvMediaSource.fromMap(
        jsonDecode(raw) as Map<String, dynamic>,
      ).copyWith(startPaused: active.paused, isDownloadedFile: false);
      launchRequest?.pendingSource = source;
    }
    if (!context.mounted || launchRequest?.isCurrent == false) return false;
    return launch(
      source: source,
      episodes: _episodeMaps(active.playlist),
      danmakuFilePath: _danmakuFilePath,
      offline: _offline,
    );
  }

  @override
  Future<bool> resume({
    required String itemGuid,
    String? mediaGuid,
    String? audioGuid,
    String? subtitleGuid,
    Duration? position,
  }) async {
    final source = _source;
    final session = _session;
    if (launchRequest?.isCurrent == false ||
        !context.mounted ||
        session == null ||
        session.finished ||
        source == null ||
        _scope != playbackSessionScope(context) ||
        source.itemGuid != itemGuid ||
        (mediaGuid?.isNotEmpty == true && source.mediaGuid != mediaGuid) ||
        (audioGuid != null && source.audioTrackGuid != audioGuid) ||
        (subtitleGuid != null && source.subtitleTrackGuid != subtitleGuid)) {
      return false;
    }
    launchRequest?.onCancel = () => session.finish(closePlayer: true);
    return session.activate(position: position);
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
    if (!context.mounted || launchRequest?.isCurrent == false) return false;
    if (_launching) throw StateError('外部播放器正在启动，请稍候');
    _launching = true;
    final owner = Object();
    _launchOwner = owner;
    final requestedScope = playbackSessionScope(context);
    Directory? directory;
    ExternalPlayerMediaProxy? mediaProxy;
    PotPlayerSession? launched;
    Future<void> Function()? releaseUnlaunchedSource;
    var disposed = false;
    bool ownsLaunch() =>
        launchRequest?.isCurrent != false &&
        context.mounted &&
        identical(_launchOwner, owner) &&
        playbackSessionScope(context) == requestedScope;
    void checkLaunch() {
      if (!ownsLaunch() ||
          disposed ||
          launched?.finished == true ||
          (launched != null && !identical(_session, launched))) {
        throw StateError('外部播放启动已取消');
      }
    }

    launchRequest?.onCancel = () async {
      await launched?.finish(closePlayer: true);
    };

    try {
      void notify(String message) {
        showExternalPlaybackNotice(context, message);
      }

      final provider = context.read<MediaBackendProvider>();
      final backend = provider.backend;
      final effectiveNas = nas ?? context.read<NasProvider>();
      final l10n = AppLocalizations.of(context);
      final sessionScope = playbackSessionScope(context);
      final nasUrl = effectiveNas.baseUrl;
      final nasUser = effectiveNas.userName;
      final serverConnection = provider.sessionProvider?.currentConnection;
      final backendKind = provider.sessionProvider?.currentKind;
      bool isCurrentSession() =>
          provider.sessionProvider?.currentKind == backendKind &&
          effectiveNas.baseUrl == nasUrl &&
          effectiveNas.userName == nasUser &&
          provider.sessionProvider?.currentConnection?.serverUrl ==
              serverConnection?.serverUrl &&
          provider.sessionProvider?.currentConnection?.userId ==
              serverConnection?.userId &&
          provider.sessionProvider?.currentConnection?.userName ==
              serverConnection?.userName;

      final releasedLinks = <String>{};
      Future<void> releaseSource(MpvMediaSource owned) async {
        final link = owned.playLink?.trim() ?? '';
        bool canRelease() =>
            isCurrentSession() &&
            !(sourceInUse(sessionScope, link) &&
                !identical(_session, launched));
        if (offline ||
            !backend.capabilities.usesLegacyFeiniuFlow ||
            !canRelease() ||
            link.isEmpty ||
            !releasedLinks.add(link)) {
          return;
        }
        await NativeReentrySupport.releaseServerSession(
          effectiveNas,
          link,
          isCurrent: canRelease,
        );
      }

      releaseUnlaunchedSource = () => releaseSource(source);
      launchRequest?.pendingSource = null;
      final settings = await ExternalPlayerSettings.load();
      checkLaunch();
      final error = await ExternalPlayerSettings.validateExecutable(
        settings.executablePath,
      );
      checkLaunch();
      if (error != null) throw StateError(error);

      void publishPreparing() {
        status.value = ExternalPlaybackStatus(
          source: source,
          position: source.startPosition,
          duration: Duration(seconds: source.durationSeconds),
          paused: source.startPaused,
          danmakuEnabled: false,
          danmakuLabel: '',
          danmakuCount: 0,
          phase: ExternalPlaybackPhase.preparing,
          progressMessage: '等待播放器就绪',
        );
      }

      if (_session == null || _session!.finished) {
        _scope = sessionScope;
        publishPreparing();
      }

      if (!offline &&
          backend.capabilities.usesLegacyFeiniuFlow &&
          DesktopMpvRuntime.directLinkNeedsRefresh(source, DateTime.now())) {
        source = await const FeiniuPlaybackSourceBridge().refreshDirectLink(
          api: FeiniuApi(effectiveNas),
          source: source,
        );
        checkLaunch();
      }
      directory = await Directory.systemTemp.createTemp('fly_potplayer_');
      checkLaunch();
      final initialDanmakuSettings = await const DanmakuSettingsStore().load();
      checkLaunch();
      var initialDanmakuPath = danmakuFilePath;
      var initialDanmakuCount = 0;
      final subtitle = await _prepareSubtitle(
        source: source,
        backend: backend,
        nas: effectiveNas,
        offline: offline,
        directory: directory,
        danmakuFilePath: danmakuFilePath,
        notify: notify,
        danmakuSettings: initialDanmakuSettings,
        onDanmakuPrepared: (path, count) {
          initialDanmakuPath = path;
          initialDanmakuCount = count;
        },
      );
      checkLaunch();
      if (!context.mounted || !isCurrentSession()) {
        throw StateError('播放页面或账号已切换，请重新播放');
      }
      // 新启动前结束旧会话，避免两份定时器同时回报。
      await _stopSession();
      checkLaunch();
      _scope = sessionScope;
      _offline = offline;
      publishPreparing();
      final uri = Uri.tryParse(source.url);
      // 剧集目录不依赖当前集是网络文件还是下载文件。
      final catalog = await ExternalPlayerPlaylist.loadEpisodes(
        source: source,
        backend: backend,
        nas: effectiveNas,
        fallback: episodes,
        offline: offline,
        onWarning: notify,
      );
      checkLaunch();
      final isHttp = uri?.scheme == 'http' || uri?.scheme == 'https';
      if (catalog.length > 1 ||
          (isHttp && backend.capabilities.usesLegacyFeiniuFlow)) {
        final api = FeiniuApi(effectiveNas);
        mediaProxy = await ExternalPlayerMediaProxy.start(
          source: isHttp || uri?.scheme == 'file'
              ? uri!
              : Uri.file(source.url, windows: true),
          headers: source.headers,
          headersForUrl: backend.capabilities.usesLegacyFeiniuFlow
              ? (url) {
                  if (!isCurrentSession()) throw StateError('播放账号已切换');
                  return api.buildPlaybackHeadersForUrl(url.toString());
                }
              : null,
        );
        checkLaunch();
      }
      final playerUrl =
          mediaProxy?.url ??
          (uri?.scheme == 'file' ? uri!.toFilePath(windows: true) : source.url);
      final ownedDirectory = directory;
      final ownedServerSources = <String, MpvMediaSource>{
        if (source.playLink?.isNotEmpty == true) source.playLink!: source,
      };
      final prepared = <String, Future<_PreparedExternalItem>>{
        playerUrl: Future.value((
          source: source,
          subtitle: subtitle,
          danmaku: initialDanmakuPath,
          count: initialDanmakuCount,
          settings: initialDanmakuSettings.encode(),
        )),
      };
      final playlist = catalog;
      String? playlistPath;
      if (mediaProxy != null && catalog.length > 1) {
        final titles = <String, String>{};
        final proxy = mediaProxy;
        for (var index = 0; index < catalog.length; index++) {
          final episode = catalog[index];
          if (episode.itemGuid == source.itemGuid) {
            titles[playerUrl] = episode.title;
            continue;
          }
          final entryDirectory = Directory(
            '${ownedDirectory.path}/episode_$index',
          );
          late String entryUrl;
          Future<_PreparedExternalItem>
          loadEpisode() => prepared.putIfAbsent(entryUrl, () async {
            try {
              if (disposed || !isCurrentSession()) throw StateError('播放会话已结束');
              final result = await const ItemPlaybackLauncher()
                  .resolveForNative(
                    effectiveNas,
                    backend: backend,
                    itemGuid: episode.itemGuid,
                    fallbackTitle: episode.title,
                    // 先解析本集轨道，再按当前语言和格式匹配本集字幕 GUID。
                    subtitleGuid: source.subtitleTrackGuid == '' ? '' : null,
                    l10n: l10n,
                    allowNetwork: !offline,
                    episodes: _episodeMaps(catalog),
                  );
              final raw = result?['loadArgs'];
              if (raw is! String || raw.isEmpty) throw StateError('未能解析这一集');
              final next = ExternalPlayerPlaylist.inheritSubtitleSelection(
                source,
                MpvMediaSource.fromMap(jsonDecode(raw) as Map<String, dynamic>),
              );
              if (next.playLink?.isNotEmpty == true) {
                ownedServerSources[next.playLink!] = next;
              }
              if (disposed || !isCurrentSession()) {
                await releaseSource(next);
                throw StateError('播放会话已结束');
              }
              await entryDirectory.create(recursive: true);
              final nextSettings = await const DanmakuSettingsStore().load();
              var nextDanmaku = result?['danmakuFile']?.toString();
              var nextCount = 0;
              final nextSubtitle = await _prepareSubtitle(
                source: next,
                backend: backend,
                nas: effectiveNas,
                offline: offline,
                directory: entryDirectory,
                danmakuFilePath: result?['danmakuFile']?.toString(),
                notify: notify,
                danmakuSettings: nextSettings,
                onDanmakuPrepared: (path, count) {
                  nextDanmaku = path;
                  nextCount = count;
                },
              );
              if (disposed || !isCurrentSession()) {
                await _cleanDirectory(entryDirectory);
                throw StateError('播放会话已结束');
              }
              return (
                source: next,
                subtitle: nextSubtitle,
                danmaku: nextDanmaku,
                count: nextCount,
                settings: nextSettings.encode(),
              );
            } catch (_) {
              prepared.remove(entryUrl);
              if (!disposed && isCurrentSession()) {
                notify('这一集的播放信息或字幕未能加载，请从 Fly Player 重试');
              }
              rethrow;
            }
          });
          entryUrl = proxy.addMedia(() async {
            final entry = await loadEpisode();
            final uri = Uri.tryParse(entry.source.url);
            return (
              source:
                  uri != null && ['http', 'https', 'file'].contains(uri.scheme)
                  ? uri
                  : Uri.file(entry.source.url, windows: true),
              headers: entry.source.headers,
            );
          });
          titles[entryUrl] = episode.title;
        }
        if (titles.length > 1) {
          playlistPath = await ExternalPlayerPlaylist.write(
            directory: ownedDirectory,
            currentUrl: playerUrl,
            titlesByUrl: titles,
          );
          checkLaunch();
        }
      }
      if (!context.mounted || !isCurrentSession()) {
        throw StateError('播放页面或账号已切换，请重新播放');
      }
      final pid = await PotPlayerSession.channel.invokeMethod<int>('launch', {
        'executable': settings.executablePath,
        'url':
            playlistPath ??
            (uri?.scheme == 'file'
                ? uri!.toFilePath(windows: true)
                : playerUrl),
        'startMs': source.startPosition.inMilliseconds,
        'title': source.title,
        'headers': mediaProxy == null ? source.headers : <String, String>{},
      });
      if (pid == null || pid <= 0) throw StateError('未能启动 PotPlayer');

      final serverReporter = ServerPlaybackReporter(backend);
      var phase = ExternalPlaybackPhase.preparing;
      String? statusError;
      var startupComplete = false;
      var progressMessage = source.externalLocalSource
          ? '本地文件，无需回报服务器'
          : '等待进度回报';
      DateTime? lastSyncedAt;
      PlaybackProgressResult? lastProgressResult;
      VoidCallback? publish;
      var serverReportPending = false;
      final reporter = DesktopPlaybackReporter(
        reportProgress: (progress) async {
          void onResult(PlaybackProgressResult result) {
            if (disposed ||
                !isCurrentSession() ||
                progress['itemGuid'] != source.itemGuid ||
                progress['mediaGuid'] != source.mediaGuid) {
              return;
            }
            lastProgressResult = result;
            progressMessage = switch (result) {
              PlaybackProgressResult.synced => '进度已同步',
              PlaybackProgressResult.queued => '进度已保存，等待同步',
              PlaybackProgressResult.failed => '进度回报失败，可重试',
            };
            if (result == PlaybackProgressResult.synced) {
              lastSyncedAt = DateTime.now();
            }
            publish?.call();
          }

          try {
            if (!isCurrentSession()) return;
            if (offline) {
              if (backend.capabilities.usesLegacyFeiniuFlow) {
                await PlaybackProgressOfflineQueue.enqueue(
                  progress,
                  onResult: onResult,
                );
              } else {
                await PlaybackProgressOfflineQueue.enqueueServer(
                  itemId: '${progress['itemGuid']}',
                  mediaSourceId: '${progress['mediaGuid']}',
                  positionSeconds: (progress['ts'] as num).toInt(),
                  isPaused: progress['isPaused'] == true,
                  onResult: onResult,
                );
              }
            } else if (backend.capabilities.usesLegacyFeiniuFlow) {
              await NativeReentrySupport.recordProgress(
                effectiveNas,
                progress,
                onResult: onResult,
              );
            } else {
              await serverReporter.report(progress, onResult: onResult);
            }
          } catch (_) {
            onResult(PlaybackProgressResult.failed);
            rethrow;
          } finally {
            serverReportPending = false;
          }
        },
      );
      // PotPlayer 内部切轨没有可靠回调，不能把 Fly 中的原选择当成实际播放音轨。
      var reportedSource = source.copyWith(clearAudioTrackGuid: true);
      var lastPosition = Duration.zero;
      var lastDuration = Duration.zero;
      bool? lastPaused;
      DateTime? lastReportAt;
      var activeSubtitle = subtitle;
      var activeDanmakuPath = initialDanmakuPath;
      var activeDanmakuSettings = initialDanmakuSettings;
      var activeDanmakuLabel = initialDanmakuCount > 0 ? '自动匹配' : '尚未加载弹幕';
      var activeDanmakuCount = initialDanmakuCount;
      var subtitleRevision = 0;
      void publishStatus() {
        if (disposed || !identical(_session, launched) || !isCurrentSession()) {
          return;
        }
        status.value = ExternalPlaybackStatus(
          source: source,
          position: lastPosition,
          duration: lastDuration,
          paused: lastPaused ?? source.startPaused,
          danmakuEnabled: activeDanmakuSettings.enabled,
          danmakuLabel: activeDanmakuLabel,
          danmakuCount: activeDanmakuCount,
          phase: _changingSource && phase == ExternalPlaybackPhase.ready
              ? ExternalPlaybackPhase.preparing
              : phase,
          error: statusError,
          progressMessage: progressMessage,
          lastSyncedAt: lastSyncedAt,
          progressResult: lastProgressResult,
          danmakuSettings: activeDanmakuSettings,
          playlist: List.unmodifiable(playlist),
        );
      }

      publish = publishStatus;

      void recordServer(bool paused) {
        if (source.externalLocalSource ||
            lastDuration <= Duration.zero ||
            serverReportPending) {
          return;
        }
        // 慢网时保留最新采样，不堆积每五秒一笔的过时回报。
        serverReportPending = true;
        if (!offline) progressMessage = '正在同步进度';
        reporter.recordServer(
          reportedSource,
          position: lastPosition,
          duration: lastDuration,
          paused: paused,
          completed: false,
        );
        lastReportAt = DateTime.now();
      }

      final ownedProxy = mediaProxy;
      launched = PotPlayerSession(
        pid: pid,
        mediaUrl: playerUrl,
        isCurrentSession: () =>
            isCurrentSession() &&
            identical(_session, launched) &&
            (startupComplete || ownsLaunch()),
        onMediaChanged: playlistPath == null
            ? null
            : (url) async {
                final request = prepared[url];
                if (request == null) return null;
                var next = await request;
                final settings = await const DanmakuSettingsStore().load();
                final nextSource =
                    ExternalPlayerPlaylist.inheritSubtitleSelection(
                      source,
                      next.source,
                    );
                if (next.settings != settings.encode() ||
                    nextSource.subtitleTrackGuid !=
                        next.source.subtitleTrackGuid) {
                  final refreshedDirectory = await ownedDirectory.createTemp(
                    'subtitles_',
                  );
                  var path = next.danmaku;
                  var count = 0;
                  final refreshed = await _prepareSubtitle(
                    source: nextSource,
                    backend: backend,
                    nas: effectiveNas,
                    offline: offline,
                    directory: refreshedDirectory,
                    danmakuFilePath: path,
                    danmakuSettings: settings,
                    notify: notify,
                    onDanmakuPrepared: (loaded, loadedCount) {
                      path = loaded;
                      count = loadedCount;
                    },
                  );
                  if (disposed || !isCurrentSession()) {
                    await _cleanDirectory(refreshedDirectory);
                    return null;
                  }
                  next = (
                    source: nextSource,
                    subtitle: refreshed,
                    danmaku: path,
                    count: count,
                    settings: settings.encode(),
                  );
                  prepared[url] = Future.value(next);
                }
                await reporter.flushServer();
                recordServer(true);
                await reporter.flushServer();
                if (disposed ||
                    launched?.finished == true ||
                    !isCurrentSession()) {
                  return null;
                }
                if (launched != null && lastDuration > Duration.zero) {
                  prepared[launched.mediaUrl] = Future.value((
                    source: source.copyWith(startPosition: lastPosition),
                    subtitle: activeSubtitle,
                    danmaku: activeDanmakuPath,
                    count: activeDanmakuCount,
                    settings: activeDanmakuSettings.encode(),
                  ));
                }
                // DPL 会再次打开之前的条目；出流会话在整个列表结束时统一释放。
                source = next.source;
                activeSubtitle = next.subtitle;
                activeDanmakuPath = next.danmaku;
                _danmakuFilePath = activeDanmakuPath;
                activeDanmakuSettings = settings;
                activeDanmakuLabel = next.count > 0 ? '已加载弹幕' : '尚未加载弹幕';
                activeDanmakuCount = next.count;
                subtitleRevision++;
                reportedSource = source.copyWith(clearAudioTrackGuid: true);
                _source = source;
                lastPosition = Duration.zero;
                lastDuration = Duration.zero;
                lastPaused = null;
                lastReportAt = null;
                lastSyncedAt = null;
                lastProgressResult = null;
                progressMessage = '等待当前集进度回报';
                phase = ExternalPlaybackPhase.preparing;
                publishStatus();
                reporter.onLaunch(source);
                if (startupComplete && next.subtitle?.isNotEmpty == true) {
                  try {
                    await PotPlayerSession.channel.invokeMethod<void>(
                      'subtitle',
                      {'pid': pid, 'path': next.subtitle, 'mediaUrl': url},
                    );
                  } catch (_) {
                    // 快速再次切集时，原生桥拒绝向另一集投递旧字幕。
                    if (!disposed) notify('字幕或弹幕未能载入，请在 PotPlayer 检查字幕选项');
                  }
                }
                return source.startPosition;
              },
        onProgress: (position, duration, paused) {
          if (disposed ||
              !isCurrentSession() ||
              !identical(_session, launched)) {
            return;
          }
          if (startupComplete) {
            phase = ExternalPlaybackPhase.ready;
            statusError = null;
          }
          final seek =
              (position - lastPosition).abs() > const Duration(seconds: 3);
          lastPosition = position;
          lastDuration = duration;
          reporter.recordLocal(
            source,
            position: position,
            duration: duration,
            paused: paused,
          );
          if (lastReportAt == null ||
              lastPaused != paused ||
              seek ||
              DateTime.now().difference(lastReportAt!) >=
                  const Duration(seconds: 5)) {
            recordServer(paused);
          }
          lastPaused = paused;
          publishStatus();
        },
        onFinished: () async {
          if (identical(_session, launched)) {
            phase = ExternalPlaybackPhase.ended;
            if (isCurrentSession()) {
              publishStatus();
            } else {
              status.value = null;
              _source = null;
            }
            _applyDanmaku = null;
            _retryProgress = null;
          }
          disposed = true;
          try {
            await ownedProxy?.close();
            await reporter.flushServer();
            if (isCurrentSession() && lastDuration > Duration.zero) {
              recordServer(true);
            }
            await reporter.flushServer();
            await reporter.dispose();
            await releaseSource(source);
            for (final other in ownedServerSources.values.toList()) {
              await releaseSource(other);
            }
            if (!offline &&
                isCurrentSession() &&
                !source.externalLocalSource &&
                !backend.capabilities.usesLegacyFeiniuFlow &&
                lastDuration > Duration.zero) {
              await backend.reportPlaybackStopped(
                itemId: source.itemGuid,
                mediaSourceId: source.mediaGuid,
                positionSeconds: lastPosition.inSeconds,
              );
            }
          } catch (error, stack) {
            FlutterError.reportError(
              FlutterErrorDetails(exception: error, stack: stack),
            );
          } finally {
            await _cleanDirectory(ownedDirectory);
          }
        },
        onError: (message) {
          phase = ExternalPlaybackPhase.disconnected;
          statusError = message;
          publishStatus();
          notify(message);
        },
      );
      // The launch command may complete after stop; install only an owned PID.
      // The local session still owns cleanup in the catch path below.
      if (!ownsLaunch()) throw StateError('外部播放启动已取消');
      reporter.onLaunch(source);
      _session = launched;
      _source = source;
      _danmakuFilePath = activeDanmakuPath;
      publishStatus();
      await launched.start(
        paused: source.startPaused,
        speed: source.playbackSpeed,
        initialPosition: source.startPosition,
        onWaiting: () => notify('PotPlayer 正在解析文件，较大的蓝光原盘可能需要一分钟左右'),
      );
      checkLaunch();
      if (activeSubtitle?.isNotEmpty == true) {
        try {
          await PotPlayerSession.channel.invokeMethod<void>('subtitle', {
            'pid': pid,
            'path': activeSubtitle,
            'mediaUrl': launched.mediaUrl,
          });
        } catch (_) {
          if (ownsLaunch() && !disposed) {
            notify('字幕或弹幕未能载入，请在 PotPlayer 检查字幕选项');
          }
        }
        checkLaunch();
      }
      checkLaunch();
      _source = source;
      _scope = sessionScope;
      startupComplete = true;
      phase = ExternalPlaybackPhase.ready;
      _retryProgress = () async {
        if (disposed || !isCurrentSession() || source.externalLocalSource) {
          return false;
        }
        await reporter.flushServer();
        recordServer(lastPaused ?? true);
        await reporter.flushServer();
        return lastProgressResult != null &&
            lastProgressResult != PlaybackProgressResult.failed;
      };
      _applyDanmaku =
          (path, label, enabled, requestedSettings, subtitleGuid) async {
            final expectedSource = source;
            final revision = ++subtitleRevision;
            bool current() =>
                !disposed &&
                isCurrentSession() &&
                identical(_session, launched) &&
                identical(source, expectedSource) &&
                revision == subtitleRevision;
            Directory? updateDirectory;
            try {
              final settings =
                  (requestedSettings ??
                          await const DanmakuSettingsStore().load())
                      .copyWith(
                        enabled:
                            enabled ??
                            (path != null
                                ? true
                                : requestedSettings?.enabled ??
                                      activeDanmakuSettings.enabled),
                      );
              final selectedSource = subtitleGuid == null
                  ? expectedSource
                  : expectedSource.copyWith(
                      subtitleTrackGuid: subtitleGuid,
                      clearSubtitleTrackIndex: true,
                      preferExternalSubtitle: subtitleGuid.isNotEmpty,
                    );
              updateDirectory = await ownedDirectory.createTemp('subtitles_');
              var nextDanmaku = path ?? activeDanmakuPath;
              var nextCount = 0;
              var nextSubtitle = await _prepareSubtitle(
                source: selectedSource,
                backend: backend,
                nas: effectiveNas,
                offline: offline,
                directory: updateDirectory,
                danmakuFilePath: path ?? activeDanmakuPath,
                danmakuSettings: settings,
                notify: notify,
                requireDanmaku:
                    settings.enabled &&
                    (settings.scrollEnabled ||
                        settings.topEnabled ||
                        settings.bottomEnabled) &&
                    (path != null ||
                        activeDanmakuPath?.isNotEmpty == true ||
                        !activeDanmakuSettings.enabled),
                requireSubtitle:
                    subtitleGuid != null && subtitleGuid.isNotEmpty,
                onDanmakuPrepared: (loaded, count) {
                  nextDanmaku = loaded;
                  nextCount = count;
                },
              );
              if (!current()) {
                await _cleanDirectory(updateDirectory);
                return false;
              }
              if (nextSubtitle == null && settings.enabled) return false;
              if (nextSubtitle == null && activeSubtitle != null) {
                nextSubtitle = await ExternalPlayerSubtitles.writeEmpty(
                  updateDirectory,
                );
              }
              if (nextSubtitle != null) {
                await PotPlayerSession.channel.invokeMethod<void>('subtitle', {
                  'pid': pid,
                  'path': nextSubtitle,
                  'mediaUrl': launched!.mediaUrl,
                });
              }
              if (!current()) return false;
              source = selectedSource;
              _source = source;
              reportedSource = source.copyWith(clearAudioTrackGuid: true);
              activeSubtitle = nextSubtitle;
              activeDanmakuPath = nextDanmaku;
              _danmakuFilePath = activeDanmakuPath;
              activeDanmakuLabel = label ?? activeDanmakuLabel;
              activeDanmakuSettings = settings;
              activeDanmakuCount = nextCount;
              await const DanmakuSettingsStore().save(settings);
              publishStatus();
              return true;
            } catch (_) {
              if (current()) notify('弹幕未能应用，请重试');
              return false;
            }
          };
      publishStatus();
      checkLaunch();
      notify('已在 PotPlayer 播放；请保持 Fly Player 运行以同步进度');
      checkLaunch();
      return true;
    } catch (error) {
      final cancelled = !ownsLaunch() || disposed || launched?.finished == true;
      disposed = true;
      await launched?.finish(closePlayer: true);
      if (launched == null) await releaseUnlaunchedSource?.call();
      await mediaProxy?.close();
      await _cleanDirectory(directory);
      if (status.value?.source.itemGuid == source.itemGuid &&
          (_session == null || _session!.finished)) {
        status.value = status.value?.withPhase(
          ExternalPlaybackPhase.ended,
          error: cancelled ? null : '$error',
        );
      }
      if (cancelled) return false;
      rethrow;
    } finally {
      _launching = false;
    }
  }

  static Future<void> _cleanDirectory(Directory? directory) async {
    if (directory == null) return;
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on FileSystemException {
      // 播放器仍占用文件时留待系统临时目录清理。
    }
  }

  static Future<String?> _prepareSubtitle({
    required MpvMediaSource source,
    required MediaBackend backend,
    required NasProvider nas,
    required bool offline,
    required Directory directory,
    required void Function(String) notify,
    String? danmakuFilePath,
    DanmakuSettings? danmakuSettings,
    bool requireDanmaku = false,
    bool requireSubtitle = false,
    void Function(String path, int count)? onDanmakuPrepared,
  }) async {
    final sourceAtStart = _source;
    final sessionAtStart = _session;
    final settings =
        danmakuSettings ?? await const DanmakuSettingsStore().load();
    var payload = settings.enabled ? danmakuFilePath : null;
    if (settings.enabled &&
        (payload?.isEmpty ?? true) &&
        !offline &&
        source.danmakuAutoSearchAllowed) {
      payload = await NativeDanmakuPrefetch.resolveToFile(
        statsScope: source.statsScope,
        isCurrent: () =>
            identical(sourceAtStart, _source) &&
            identical(sessionAtStart, _session),
        seriesTitle: source.seriesTitle,
        itemTitle: source.title,
        seasonNumber: source.seasonNumber,
        episodeNumber: source.episodeNumber,
        tmdbId: source.tmdbId,
        settings: settings,
        itemGuid: source.itemGuid,
        mediaGuid: source.mediaGuid,
        seasonGuid: source.seasonGuid,
      );
    }
    final selectedGuid = source.subtitleTrackGuid ?? '';
    final track = source.subtitleTracks
        .where((track) => track.guid == selectedGuid)
        .firstOrNull;
    var subtitle = source.localSubtitleFiles[selectedGuid];
    if (subtitle?.isEmpty == true) subtitle = null;
    if (subtitle?.isNotEmpty == true) {
      try {
        if (await File(subtitle!).length() == 0) subtitle = null;
      } on FileSystemException {
        subtitle = null;
      }
      if (subtitle == null) {
        notify('所选本地字幕不存在或为空，视频将继续播放');
      }
    }
    if (requireSubtitle && (subtitle?.isEmpty ?? true)) {
      final known =
          track != null && (track.isExternal == 1 || track.extraFile == 1);
      if (!known) throw StateError('当前字幕不能从控制页载入，请在 PotPlayer 中切换');
    }
    if ((subtitle?.isEmpty ?? true) &&
        track != null &&
        !offline &&
        (track.isExternal == 1 || track.extraFile == 1)) {
      if (backend.capabilities.usesLegacyFeiniuFlow &&
          track.format.trim().toLowerCase() == 'sup') {
        // 飞牛当前接口只提供字幕文本，不能把 SUP 位图当作 SRT 下载。
        notify('所选 SUP 位图字幕暂不能接入，视频将继续播放');
      } else {
        try {
          subtitle =
              await (backend.capabilities.usesLegacyFeiniuFlow
                      ? NativeReentrySupport.resolveSubtitleFile(
                          nas,
                          selectedGuid,
                          format: track.format,
                        )
                      : backend.resolveExternalSubtitleFile(
                          selectedGuid,
                          format: track.format,
                        ))
                  .timeout(const Duration(seconds: 10), onTimeout: () => null);
        } catch (_) {
          subtitle = null;
        }
        if (subtitle == null || subtitle.isEmpty) {
          subtitle = null;
          notify('所选外挂字幕未能获取，视频将继续播放');
        }
      }
    }
    if ((subtitle?.isEmpty ?? true) &&
        track != null &&
        track.isExternal != 1 &&
        track.extraFile != 1 &&
        !selectedGuid.startsWith('local:') &&
        payload?.isNotEmpty == true) {
      notify('所选内封字幕暂不能与弹幕合并，本次保留内封字幕播放');
      return null;
    }
    if (requireSubtitle && (subtitle?.isEmpty ?? true)) {
      throw StateError('所选字幕未能获取，已保留当前字幕');
    }
    try {
      var exported = false;
      final prepared = await ExternalPlayerSubtitles.prepare(
        directory: directory,
        subtitlePath: subtitle,
        danmakuPath: payload,
        settings: settings,
        disableSubtitles: source.subtitleTrackGuid == '',
        onDanmakuPrepared: (count) {
          exported = true;
          onDanmakuPrepared?.call(payload!, count);
        },
      );
      if (requireDanmaku && !exported) {
        notify('未生成可用弹幕，请搜索或导入弹幕源');
        return null;
      }
      return prepared;
    } catch (_) {
      notify(
        subtitle?.isNotEmpty == true
            ? '字幕与弹幕未能合并，已保留原字幕继续播放'
            : '弹幕未能加载，视频将继续播放',
      );
      if (requireDanmaku) return null;
      return subtitle ??
          (source.subtitleTrackGuid == ''
              ? await ExternalPlayerSubtitles.writeEmpty(directory)
              : null);
    }
  }
}
