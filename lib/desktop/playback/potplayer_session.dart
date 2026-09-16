import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'external_player_adapter.dart';

/// 跟踪本次启动的进程；列表内切集先交接媒体身份，再接受新影片的真实采样。
class PotPlayerSession
    with WidgetsBindingObserver
    implements ExternalPlayerSession {
  PotPlayerSession({
    required this.pid,
    required this.mediaUrl,
    required this.isCurrentSession,
    required this.onProgress,
    required this.onFinished,
    required this.onError,
    this.onMediaChanged,
  });

  static const channel = MethodChannel('fly_player/potplayer');
  final int pid;
  @override
  String mediaUrl;
  final bool Function() isCurrentSession;
  final void Function(Duration position, Duration duration, bool paused)
  onProgress;
  final Future<void> Function() onFinished;
  final void Function(String message) onError;
  final Future<Duration?> Function(String mediaUrl)? onMediaChanged;
  Timer? _timer;
  bool _polling = false;
  bool _finished = false;
  bool _ready = false;
  int _failures = 0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _paused = false;
  Duration? _pendingPosition;
  DateTime? _seekRequestedAt;
  Future<void>? _finishing;

  @override
  bool get finished => _finished;

  @override
  bool get isCurrent => isCurrentSession();

  @override
  bool get hasPlaylist => onMediaChanged != null;

  // Native true means the command was delivered, not that playback changed.
  static Future<bool> sendCommand(
    String method,
    Map<String, Object?> args,
  ) async => await channel.invokeMethod<bool>(method, args) == true;

  static Future<void> requireCommand(
    String method,
    Map<String, Object?> args,
  ) async {
    if (!await sendCommand(method, args)) {
      throw PlatformException(
        code: 'potplayer_command_failed',
        message: 'PotPlayer 未接受控制命令：$method',
      );
    }
  }

  bool get _current => !_finished && isCurrentSession();

  void _checkCurrent() {
    if (!_current) throw StateError('播放会话已结束或账号已切换');
  }

  Future<Map<String, dynamic>> _snapshot() async => Map<String, dynamic>.from(
    await channel.invokeMapMethod<String, dynamic>('snapshot', {'pid': pid}) ??
        const {},
  );

  @override
  Future<void> start({
    required bool paused,
    required double speed,
    required Duration initialPosition,
    VoidCallback? onWaiting,
  }) async {
    // 蓝光原盘需要远距离探测封装和索引，实测 M2TS 解析与续播约 80 秒。
    final startedAt = DateTime.now();
    final deadline = startedAt.add(const Duration(minutes: 2));
    var waitingNotified = false;
    var configured = false;
    var sawPlayerWindow = false;
    var targetPosition = initialPosition;
    while (!_finished && DateTime.now().isBefore(deadline)) {
      if (!isCurrentSession()) throw StateError('播放账号已切换，请重新播放');
      if (!waitingNotified &&
          DateTime.now().difference(startedAt) >= const Duration(seconds: 10)) {
        waitingNotified = true;
        onWaiting?.call();
      }
      try {
        final state = await _snapshot();
        _checkCurrent();
        if (state['alive'] == true) {
          sawPlayerWindow = true;
        } else if (sawPlayerWindow) {
          throw StateError('PotPlayer 已关闭');
        }
        final file = '${state['file'] ?? ''}';
        if (state['alive'] == true &&
            file.isNotEmpty &&
            !sameMedia(file, mediaUrl) &&
            {1, 2}.contains(state['state']) &&
            ((state['durationMs'] as num?)?.toInt() ?? 0) > 0 &&
            onMediaChanged != null) {
          // 起播期间也可能在 PotPlayer 切集，先交接身份，不能一直等待原集。
          final position = await onMediaChanged!(file);
          _checkCurrent();
          if (position == null) {
            throw StateError('PotPlayer 已切换到列表外的媒体，请重新打开播放');
          }
          mediaUrl = file;
          targetPosition = position < Duration.zero ? Duration.zero : position;
          configured = false;
          // 交接可能等待字幕和片源；重新采样后才配置、接受新集进度。
          continue;
        }
        if (_matches(state) && (state['state'] == 1 || state['state'] == 2)) {
          if (!configured) {
            await requireCommand('configure', {
              'pid': pid,
              'paused': paused,
              'speed': speed,
              'mediaUrl': mediaUrl,
            });
            _checkCurrent();
            configured = true;
            if (targetPosition > Duration.zero) {
              await requireCommand('activate', {
                'pid': pid,
                'positionMs': targetPosition.inMilliseconds,
                'focus': false,
                'mediaUrl': mediaUrl,
              });
              _checkCurrent();
            }
            // Confirm the actual state after asynchronous configure/seek.
            continue;
          }
          if (state['state'] != (paused ? 1 : 2)) {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            _checkCurrent();
            continue;
          }
          final positionMs = (state['positionMs'] as num?)?.toInt() ?? 0;
          // 续播命令是异步的，不能先把加载阶段的零位置回写到 NAS。
          final targetMs = targetPosition.inMilliseconds;
          final minimumPositionMs = math.max(
            math.min(targetMs, 1000),
            targetMs - 3000,
          );
          if (targetMs > 0 && positionMs < minimumPositionMs) {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            _checkCurrent();
            continue;
          }
          _accept(state);
          _checkCurrent();
          _ready = true;
          WidgetsBinding.instance.addObserver(this);
          _timer = Timer.periodic(const Duration(seconds: 1), (_) {
            unawaited(poll());
          });
          return;
        }
      } on PlatformException catch (error) {
        if (!{
          'potplayer_timeout',
          'potplayer_file_unavailable',
          'potplayer_file_changed',
        }.contains(error.code)) {
          rethrow;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _checkCurrent();
    }
    throw StateError('未能确认 PotPlayer 正在播放此媒体，请检查播放地址或播放器权限');
  }

  bool _matches(Map<String, dynamic> state) =>
      state['alive'] == true && sameMedia('${state['file'] ?? ''}', mediaUrl);

  @override
  Future<bool> matchesMedia(String expectedUrl) async =>
      _current &&
      _matches(await _snapshot()) &&
      sameMedia(mediaUrl, expectedUrl);

  static bool sameMedia(String actual, String expected) {
    if (actual.isEmpty || expected.isEmpty) return false;
    String normalize(String value) {
      final uri = Uri.tryParse(value);
      if (uri?.scheme == 'http' || uri?.scheme == 'https') {
        return uri!.normalizePath().toString();
      }
      if (uri?.scheme == 'file') value = uri!.toFilePath(windows: true);
      return File(value).absolute.path.replaceAll('/', '\\').toLowerCase();
    }

    return normalize(actual) == normalize(expected);
  }

  void _accept(Map<String, dynamic> state) {
    final durationMs = (state['durationMs'] as num?)?.toInt() ?? 0;
    final positionMs = (state['positionMs'] as num?)?.toInt() ?? -1;
    if (durationMs <= 0 || positionMs < 0) return;
    _duration = Duration(milliseconds: durationMs);
    _position = Duration(milliseconds: positionMs.clamp(0, durationMs));
    _paused = state['state'] != 2;
    onProgress(_position, _duration, _paused);
  }

  @override
  Future<void> poll() async {
    if (_finished || _polling) return;
    _polling = true;
    try {
      if (!isCurrentSession()) {
        await finish(reportFinal: false);
        return;
      }
      final state = await _snapshot();
      if (_finished) return;
      if (!isCurrentSession()) {
        await finish(reportFinal: false);
        return;
      }
      if (state['alive'] != true) {
        await finish();
        return;
      }
      final file = '${state['file'] ?? ''}';
      if (file.isNotEmpty && !sameMedia(file, mediaUrl)) {
        final changeMedia = onMediaChanged;
        if (changeMedia == null) {
          onError('PotPlayer 已切换到其他媒体，已结束原影片的进度回报');
          await finish();
          return;
        }
        if (!{1, 2}.contains(state['state']) ||
            ((state['durationMs'] as num?)?.toInt() ?? 0) <= 0) {
          return;
        }
        if (_duration > Duration.zero) {
          onProgress(_position, _duration, true);
        }
        // 回调会替换业务媒体，等待期间也不能再向新身份发送旧采样。
        _position = Duration.zero;
        _duration = Duration.zero;
        _paused = true;
        _pendingPosition = null;
        _seekRequestedAt = null;
        Duration? position;
        try {
          position = await changeMedia(file);
        } catch (_) {
          onError('切换列表影片失败，已停止进度回报，请重新打开播放');
          await finish(reportFinal: false);
          return;
        }
        if (_finished) return;
        if (!isCurrentSession()) {
          await finish(reportFinal: false);
          return;
        }
        if (position == null) {
          onError('PotPlayer 已切换到列表外的媒体，已结束进度回报');
          await finish(reportFinal: false);
          return;
        }
        mediaUrl = file;
        _pendingPosition = position < Duration.zero ? Duration.zero : position;
        // 下一轮重新核对实际文件；回调等待期间可能已经连续切到另一集。
        return;
      }
      if (state['state'] == 0 && _ready) {
        // 停止时播放器可能已经把位置归零，保留最后一个有效采样。
        if (onMediaChanged != null) {
          if (!_paused && _duration > Duration.zero) {
            _paused = true;
            onProgress(_position, _duration, true);
          }
          _seekRequestedAt = null;
          return;
        }
        await finish();
        return;
      }
      if (!_matches(state) || !{1, 2}.contains(state['state'])) return;
      final pendingPosition = _pendingPosition;
      if (pendingPosition != null) {
        final durationMs = (state['durationMs'] as num?)?.toInt() ?? 0;
        if (durationMs <= 0) return;
        final targetMs = pendingPosition.inMilliseconds.clamp(0, durationMs);
        final requestedAt = _seekRequestedAt;
        if (requestedAt == null) {
          await requireCommand('activate', {
            'pid': pid,
            'positionMs': targetMs,
            'focus': false,
            'mediaUrl': mediaUrl,
          });
          if (!_current) return;
          // PotPlayer 切集加载后可能暂停，续播定位后明确恢复播放。
          await requireCommand('configure', {
            'pid': pid,
            'paused': false,
            'mediaUrl': mediaUrl,
          });
          if (!_current) return;
          _seekRequestedAt = DateTime.now();
          return;
        }
        final elapsed = DateTime.now().difference(requestedAt);
        final positionMs = (state['positionMs'] as num?)?.toInt() ?? -1;
        // 容纳关键帧误差与最高 12 倍速的真实走时，不把加载零位当成续播就绪。
        if (positionMs < 0 ||
            positionMs < targetMs - 3000 ||
            positionMs > targetMs + 3000 + elapsed.inMilliseconds * 12) {
          if (elapsed >= const Duration(seconds: 25)) {
            onError('未能确认切集后的续播位置，已停止进度回报，请重新打开播放');
            await finish(reportFinal: false);
          }
          return;
        }
        _pendingPosition = null;
        _seekRequestedAt = null;
      }
      _failures = 0;
      _accept(state);
    } on PlatformException {
      if (++_failures == 5) {
        onError('暂时无法读取 PotPlayer 进度，正在重试；不会推算播放位置');
      }
    } finally {
      _polling = false;
    }
  }

  @override
  Future<bool> setPaused(bool paused) async {
    if (!_current) return false;
    return await sendCommand('configure', {
      'pid': pid,
      'paused': paused,
      'mediaUrl': mediaUrl,
    });
  }

  @override
  Future<bool> seek(Duration position) async {
    if (!_current) return false;
    return await sendCommand('activate', {
      'pid': pid,
      'positionMs': position.inMilliseconds,
      'focus': false,
      'mediaUrl': mediaUrl,
    });
  }

  @override
  Future<bool> stepPlaylist(int direction) async {
    if (!_current) return false;
    return await sendCommand('stepPlaylist', {
      'pid': pid,
      'direction': direction,
      'mediaUrl': mediaUrl,
    });
  }

  @override
  Future<void> loadSubtitle({required String path, required String mediaUrl}) =>
      channel.invokeMethod<void>('subtitle', {
        'pid': pid,
        'path': path,
        'mediaUrl': mediaUrl,
      });

  @override
  Future<bool> activate({
    Duration? position,
    bool resumePlayback = true,
  }) async {
    if (!_current) return false;
    final expectedMedia = mediaUrl;
    bool current() => _current && sameMedia(mediaUrl, expectedMedia);
    final state = await _snapshot();
    if (!current() || !_matches(state) || !{1, 2}.contains(state['state'])) {
      return false;
    }
    if (position != null) {
      final previousPosition = _pendingPosition;
      final previousRequest = _seekRequestedAt;
      if (onMediaChanged != null) {
        // A concurrent poll must not restore the playlist's old resume target
        // while the explicit replay command is awaiting native delivery.
        _pendingPosition = position;
        _seekRequestedAt = DateTime.now();
      }
      var delivered = false;
      try {
        delivered = await sendCommand('activate', {
          'pid': pid,
          'positionMs': position.inMilliseconds,
          'focus': false,
          'mediaUrl': expectedMedia,
        });
      } finally {
        if (!delivered && current()) {
          _pendingPosition = previousPosition;
          _seekRequestedAt = previousRequest;
        }
      }
      if (!delivered || !current()) return false;
    }
    if (resumePlayback) {
      if (!await sendCommand('configure', {
            'pid': pid,
            'paused': false,
            'mediaUrl': expectedMedia,
          }) ||
          !current()) {
        return false;
      }
    }
    // Foreground activation has its own result; it cannot invalidate playback
    // already confirmed below or conceal a failed seek/configure command.
    final focused = await sendCommand('activate', {
      'pid': pid,
      'mediaUrl': expectedMedia,
    });
    if (!current()) return false;
    if (!resumePlayback && position == null) return focused;
    if (!focused) onError('未能将 PotPlayer 窗口切到前台');
    final confirmed = await confirmPlayback(
      position: position,
      paused: resumePlayback ? false : null,
    );
    if (confirmed && current() && position != null && onMediaChanged != null) {
      _pendingPosition = null;
      _seekRequestedAt = null;
    }
    return confirmed && current();
  }

  /// A sent Win32 message can precede its effect; confirm only actual samples.
  @override
  Future<bool> confirmPlayback({Duration? position, bool? paused}) async {
    final expectedMedia = mediaUrl;
    bool current() => _current && sameMedia(mediaUrl, expectedMedia);
    final startedAt = DateTime.now();
    final deadline = startedAt.add(const Duration(seconds: 3));
    while (current()) {
      final actual = await _snapshot();
      if (!current() || !_matches(actual)) return false;
      final actualMs = (actual['positionMs'] as num?)?.toInt() ?? -1;
      final targetMs = position?.inMilliseconds;
      if ({1, 2}.contains(actual['state']) &&
          (paused == null || actual['state'] == (paused ? 1 : 2)) &&
          (targetMs == null ||
              (actualMs >= 0 && (actualMs - targetMs).abs() <= 3000))) {
        _accept(actual);
        return current();
      }
      if (!DateTime.now().isBefore(deadline)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  @override
  Future<void> finish({
    bool reportFinal = true,
    bool closePlayer = false,
  }) async {
    if (closePlayer) {
      _finished = true;
      _timer?.cancel();
      WidgetsBinding.instance.removeObserver(this);
      try {
        // 已结束跟踪仍可关闭本次媒体，但不关闭用户后来手动打开的其他影片。
        if (!_ready || _matches(await _snapshot())) {
          if (!await sendCommand('close', {'pid': pid})) {
            onError('未能确认 PotPlayer 已关闭，请检查播放器窗口');
          }
        }
      } on PlatformException {
        // 已退出或暂时无响应的进程不影响会话收尾。
      }
    }
    await (_finishing ??= _finish(reportFinal: reportFinal));
  }

  Future<void> _finish({required bool reportFinal}) async {
    _finished = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (reportFinal && isCurrentSession() && _duration > Duration.zero) {
      onProgress(_position, _duration, true);
    }
    await onFinished();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await poll();
    await finish();
    return AppExitResponse.exit;
  }
}
