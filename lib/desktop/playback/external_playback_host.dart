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
import '../../models/play_info.dart';
import '../../playback/feiniu_playback_source_bridge.dart';
import '../../playback/playback_host.dart';
import '../../playback/playback_source.dart';
import '../../providers/media_backend_provider.dart';
import '../../providers/nas_provider.dart';
import '../../services/native_danmaku_prefetch.dart';
import '../../services/native_playback_reentry.dart';
import '../../services/native_reentry_support.dart';
import '../../services/playback_progress_offline_queue.dart';
import 'desktop_mpv_runtime.dart';
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

/// 详情页只展示实际播放器采样，不把未确认的控制命令当成播放进度。
class ExternalPlaybackStatus {
  const ExternalPlaybackStatus({
    required this.source,
    required this.position,
    required this.duration,
    required this.paused,
    required this.danmakuEnabled,
    required this.danmakuLabel,
    required this.danmakuCount,
  });
  final MpvMediaSource source;
  final Duration position;
  final Duration duration;
  final bool paused;
  final bool danmakuEnabled;
  final String danmakuLabel;
  final int danmakuCount;
}

/// 外部播放器只消费已解析的播放源，沿用现有字幕、弹幕和后端回报链路。
final class ExternalPlaybackHost implements PlaybackHost {
  const ExternalPlaybackHost(this.context);

  final BuildContext context;
  static PotPlayerSession? _session;
  static MpvMediaSource? _source;
  static String? _scope;
  static bool _launching = false;
  static final status = ValueNotifier<ExternalPlaybackStatus?>(null);
  static Future<bool> Function(String?, String?, bool?)? _applyDanmaku;

  static bool _controlsItem(String itemGuid) =>
      _session?.finished == false &&
      _session!.isCurrentSession() &&
      _source?.itemGuid == itemGuid &&
      status.value?.source.itemGuid == itemGuid;

  static Future<bool> activateCurrent({required String itemGuid}) async =>
      _controlsItem(itemGuid) && await _session!.activate();

  static Future<bool> setPaused(bool paused, {required String itemGuid}) async {
    if (!_controlsItem(itemGuid)) return false;
    final session = _session!;
    await session.poll();
    if (!_controlsItem(itemGuid) || !identical(_session, session)) return false;
    await PotPlayerSession.channel.invokeMethod<void>('configure', {
      'pid': session.pid,
      'paused': paused,
      'mediaUrl': session.mediaUrl,
    });
    await session.poll();
    return true;
  }

  static Future<bool> seek(
    Duration position, {
    required String itemGuid,
  }) async {
    if (!_controlsItem(itemGuid)) return false;
    final session = _session!;
    await session.poll();
    if (!_controlsItem(itemGuid) || !identical(_session, session)) return false;
    await PotPlayerSession.channel.invokeMethod<void>('activate', {
      'pid': session.pid,
      'positionMs': position.inMilliseconds.clamp(
        0,
        status.value!.duration.inMilliseconds,
      ),
      'focus': false,
      'mediaUrl': session.mediaUrl,
    });
    await session.poll();
    return true;
  }

  static Future<bool> applyDanmaku({
    required String itemGuid,
    String? path,
    String? label,
    bool? enabled,
  }) async {
    if (!_controlsItem(itemGuid)) return false;
    return await _applyDanmaku?.call(path, label, enabled) ?? false;
  }

  static Future<void> stop() async {
    final session = _session;
    if (session == null) return;
    await session.poll();
    await session.finish(closePlayer: true);
    if (identical(_session, session)) _session = null;
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
    if (!context.mounted ||
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
    if (!context.mounted) return false;
    if (_launching) throw StateError('外部播放器正在启动，请稍候');
    _launching = true;
    Directory? directory;
    ExternalPlayerMediaProxy? mediaProxy;
    PotPlayerSession? launched;
    var disposed = false;
    try {
      final settings = await ExternalPlayerSettings.load();
      final error = await ExternalPlayerSettings.validateExecutable(
        settings.executablePath,
      );
      if (error != null) throw StateError(error);
      if (!context.mounted) return false;
      final messenger = ScaffoldMessenger.maybeOf(context);
      void notify(String message) {
        if (messenger?.mounted == true) {
          messenger!.showSnackBar(SnackBar(content: Text(message)));
        }
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

      if (!offline &&
          backend.capabilities.usesLegacyFeiniuFlow &&
          DesktopMpvRuntime.directLinkNeedsRefresh(source, DateTime.now())) {
        source = await const FeiniuPlaybackSourceBridge().refreshDirectLink(
          api: FeiniuApi(effectiveNas),
          source: source,
        );
      }
      directory = await Directory.systemTemp.createTemp('fly_potplayer_');
      final initialDanmakuSettings = await const DanmakuSettingsStore().load();
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
      if (!context.mounted || !isCurrentSession()) {
        throw StateError('播放页面或账号已切换，请重新播放');
      }
      // 新启动前结束旧会话，避免两份定时器同时回报。
      await stop();
      final uri = Uri.tryParse(source.url);
      // 仅中转飞牛原画文件；HLS 清单仍需原始基地址解析分片。
      if (backend.capabilities.usesLegacyFeiniuFlow &&
          (uri?.scheme == 'http' || uri?.scheme == 'https') &&
          uri!.path.startsWith('/v/api/v1/media/range/')) {
        mediaProxy = await ExternalPlayerMediaProxy.start(
          source: uri,
          headers: source.headers,
        );
      }
      final playerUrl =
          mediaProxy?.url ??
          (uri?.scheme == 'file' ? uri!.toFilePath(windows: true) : source.url);
      final ownedDirectory = directory;
      final initialSource = source;
      final prepared = <String, Future<_PreparedExternalItem>>{
        playerUrl: Future.value((
          source: source,
          subtitle: subtitle,
          danmaku: initialDanmakuPath,
          count: initialDanmakuCount,
          settings: initialDanmakuSettings.encode(),
        )),
      };
      String? playlistPath;
      if (mediaProxy != null &&
          !offline &&
          source.mediaType.toLowerCase() == 'episode') {
        final catalog = await ExternalPlayerPlaylist.loadEpisodes(
          source: source,
          backend: backend,
          nas: effectiveNas,
          fallback: episodes,
          onWarning: notify,
        );
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
                    // 关闭字幕的明确选择随列表继承，其余使用每集自己的字幕轨。
                    subtitleGuid: initialSource.subtitleTrackGuid == ''
                        ? ''
                        : null,
                    l10n: l10n,
                  );
              final raw = result?['loadArgs'];
              if (raw is! String || raw.isEmpty) throw StateError('未能解析这一集');
              final next = MpvMediaSource.fromMap(
                jsonDecode(raw) as Map<String, dynamic>,
              );
              final nextUri = Uri.tryParse(next.url);
              if (next.serverPlaybackManaged ||
                  nextUri?.path.toLowerCase().endsWith('.m3u8') == true ||
                  nextUri?.path.toLowerCase().endsWith('.mpd') == true) {
                final link = next.playLink?.trim() ?? '';
                if (link.isNotEmpty && isCurrentSession()) {
                  await NativeReentrySupport.releaseServerSession(
                    effectiveNas,
                    link,
                  );
                }
                throw StateError('此集为分段转码流，请从 Fly Player 单独打开');
              }
              if (disposed || !isCurrentSession()) throw StateError('播放会话已结束');
              await entryDirectory.create(recursive: true);
              final nextSettings = await const DanmakuSettingsStore().load();
              var nextDanmaku = result?['danmakuFile']?.toString();
              var nextCount = 0;
              final nextSubtitle = await _prepareSubtitle(
                source: next,
                backend: backend,
                nas: effectiveNas,
                offline: false,
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
      var serverReportPending = false;
      final reporter = DesktopPlaybackReporter(
        reportProgress: (progress) async {
          try {
            if (!isCurrentSession()) return;
            if (offline) {
              if (backend.capabilities.usesLegacyFeiniuFlow) {
                await PlaybackProgressOfflineQueue.enqueue(progress);
              } else {
                await PlaybackProgressOfflineQueue.enqueueServer(
                  itemId: source.itemGuid,
                  mediaSourceId: source.mediaGuid,
                  positionSeconds: (progress['ts'] as num).toInt(),
                  isPaused: progress['isPaused'] == true,
                );
              }
            } else if (backend.capabilities.usesLegacyFeiniuFlow) {
              await NativeReentrySupport.recordProgress(effectiveNas, progress);
            } else {
              await serverReporter.report(progress);
            }
          } finally {
            serverReportPending = false;
          }
        },
        releaseServerSession:
            offline || !backend.capabilities.usesLegacyFeiniuFlow
            ? null
            : (link) async {
                if (isCurrentSession()) {
                  await NativeReentrySupport.releaseServerSession(
                    effectiveNas,
                    link,
                  );
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
        );
      }

      void recordServer(bool paused) {
        if (source.externalLocalSource ||
            lastDuration <= Duration.zero ||
            serverReportPending) {
          return;
        }
        // 慢网时保留最新采样，不堆积每五秒一笔的过时回报。
        serverReportPending = true;
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
        isCurrentSession: isCurrentSession,
        onMediaChanged: playlistPath == null
            ? null
            : (url) async {
                final request = prepared[url];
                if (request == null) return null;
                var next = await request;
                final settings = await const DanmakuSettingsStore().load();
                if (next.settings != settings.encode()) {
                  final refreshedDirectory = await ownedDirectory.createTemp(
                    'subtitles_',
                  );
                  var path = next.danmaku;
                  var count = 0;
                  final refreshed = await _prepareSubtitle(
                    source: next.source,
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
                    source: next.source,
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
                reporter.release(source, replacement: next.source);
                source = next.source;
                activeSubtitle = next.subtitle;
                activeDanmakuPath = next.danmaku;
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
                reporter.onLaunch(source);
                if (next.subtitle?.isNotEmpty == true) {
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
          disposed = true;
          if (identical(_session, launched)) {
            status.value = null;
            _applyDanmaku = null;
          }
          try {
            await ownedProxy?.close();
            await reporter.flushServer();
            if (isCurrentSession() && lastDuration > Duration.zero) {
              recordServer(true);
            }
            await reporter.flushServer();
            await reporter.dispose();
            reporter.release(source);
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
        onError: notify,
      );
      reporter.onLaunch(source);
      await launched.start(
        paused: source.startPaused,
        speed: source.playbackSpeed,
        initialPosition: source.startPosition,
        onWaiting: () => notify('PotPlayer 正在解析文件，较大的蓝光原盘可能需要一分钟左右'),
      );
      if (subtitle?.isNotEmpty == true) {
        try {
          await PotPlayerSession.channel.invokeMethod<void>('subtitle', {
            'pid': pid,
            'path': subtitle,
            'mediaUrl': playerUrl,
          });
        } catch (_) {
          notify('字幕或弹幕未能载入，请在 PotPlayer 检查字幕选项');
        }
      }
      _session = launched;
      _source = source;
      _scope = sessionScope;
      _applyDanmaku = (path, label, enabled) async {
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
          final settings = (await const DanmakuSettingsStore().load()).copyWith(
            enabled:
                enabled ??
                (path != null ? true : activeDanmakuSettings.enabled),
          );
          updateDirectory = await ownedDirectory.createTemp('subtitles_');
          var nextDanmaku = path ?? activeDanmakuPath;
          var nextCount = 0;
          var nextSubtitle = await _prepareSubtitle(
            source: expectedSource,
            backend: backend,
            nas: effectiveNas,
            offline: offline,
            directory: updateDirectory,
            danmakuFilePath: path ?? activeDanmakuPath,
            danmakuSettings: settings,
            notify: notify,
            requireDanmaku: settings.enabled,
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
          activeSubtitle = nextSubtitle;
          activeDanmakuPath = nextDanmaku;
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
      notify('已在 PotPlayer 播放；请保持 Fly Player 运行以同步进度');
      return true;
    } catch (_) {
      disposed = true;
      await launched?.finish(closePlayer: true);
      await mediaProxy?.close();
      await _cleanDirectory(directory);
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
    void Function(String path, int count)? onDanmakuPrepared,
  }) async {
    final settings =
        danmakuSettings ?? await const DanmakuSettingsStore().load();
    var payload = settings.enabled ? danmakuFilePath : null;
    if (settings.enabled &&
        (payload?.isEmpty ?? true) &&
        !offline &&
        source.danmakuAutoSearchAllowed) {
      payload = await NativeDanmakuPrefetch.resolveToFile(
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
