import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/feiniu_api.dart';
import '../../controllers/item_playback_launcher.dart';
import '../../danmaku/settings/danmaku_settings_store.dart';
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

typedef _PreparedExternalItem = ({MpvMediaSource source, String? subtitle});

/// 外部播放器只消费已解析的播放源，沿用现有字幕、弹幕和后端回报链路。
final class ExternalPlaybackHost implements PlaybackHost {
  const ExternalPlaybackHost(this.context);

  final BuildContext context;
  static PotPlayerSession? _session;
  static MpvMediaSource? _source;
  static String? _scope;
  static bool _launching = false;

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
      final subtitle = await _prepareSubtitle(
        source: source,
        backend: backend,
        nas: effectiveNas,
        offline: offline,
        directory: directory,
        danmakuFilePath: danmakuFilePath,
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
      final playerUrl = mediaProxy?.url ?? source.url;
      final ownedDirectory = directory;
      final initialSource = source;
      final prepared = <String, Future<_PreparedExternalItem>>{
        playerUrl: Future.value((source: source, subtitle: subtitle)),
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
              final nextSubtitle = await _prepareSubtitle(
                source: next,
                backend: backend,
                nas: effectiveNas,
                offline: false,
                directory: entryDirectory,
                danmakuFilePath: result?['danmakuFile']?.toString(),
              );
              if (disposed || !isCurrentSession()) {
                await _cleanDirectory(entryDirectory);
                throw StateError('播放会话已结束');
              }
              return (source: next, subtitle: nextSubtitle);
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
        if (playlistPath == null && subtitle?.isNotEmpty == true)
          'subtitlePath': subtitle,
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
                final next = await request;
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
                  ));
                }
                reporter.release(source, replacement: next.source);
                source = next.source;
                activeSubtitle = next.subtitle;
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
        },
        onFinished: () async {
          disposed = true;
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
      );
      if (playlistPath != null && subtitle?.isNotEmpty == true) {
        await PotPlayerSession.channel.invokeMethod<void>('subtitle', {
          'pid': pid,
          'path': subtitle,
          'mediaUrl': playerUrl,
        });
      }
      _session = launched;
      _source = source;
      _scope = sessionScope;
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
    String? danmakuFilePath,
  }) async {
    final settings = await const DanmakuSettingsStore().load();
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
    if (subtitle?.isNotEmpty == true && !await File(subtitle!).exists()) {
      throw StateError('所选本地字幕不存在，请重新选择字幕');
    }
    if ((subtitle?.isEmpty ?? true) &&
        track != null &&
        !offline &&
        (track.isExternal == 1 || track.extraFile == 1)) {
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
      if (subtitle == null || subtitle.isEmpty) {
        throw StateError('所选外挂字幕未能获取，请重试或使用内置播放器');
      }
    }
    if ((subtitle?.isEmpty ?? true) &&
        track != null &&
        payload?.isNotEmpty == true) {
      throw UnsupportedError(
        '所选字幕没有可合并的独立文件，请选择外挂 SRT/ASS/VTT 字幕，或关闭弹幕后使用 PotPlayer',
      );
    }
    return ExternalPlayerSubtitles.prepare(
      directory: directory,
      subtitlePath: subtitle,
      danmakuPath: payload,
      settings: settings,
    );
  }
}
