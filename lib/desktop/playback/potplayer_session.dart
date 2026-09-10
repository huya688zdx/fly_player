import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 跟踪本次启动的进程；列表内切集先交接媒体身份，再接受新影片的真实采样。
class PotPlayerSession with WidgetsBindingObserver {
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

  bool get finished => _finished;

  Future<Map<String, dynamic>> _snapshot() async => Map<String, dynamic>.from(
    await channel.invokeMapMethod<String, dynamic>('snapshot', {'pid': pid}) ??
        const {},
  );

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
    while (!_finished && DateTime.now().isBefore(deadline)) {
      if (!isCurrentSession()) throw StateError('播放账号已切换，请重新播放');
      if (!waitingNotified &&
          DateTime.now().difference(startedAt) >= const Duration(seconds: 10)) {
        waitingNotified = true;
        onWaiting?.call();
      }
      try {
        final state = await _snapshot();
        if (state['alive'] == true) {
          sawPlayerWindow = true;
        } else if (sawPlayerWindow) {
          throw StateError('PotPlayer 已关闭');
        }
        if (_matches(state) && (state['state'] == 1 || state['state'] == 2)) {
          if (!configured) {
            await channel.invokeMethod<void>('configure', {
              'pid': pid,
              'paused': paused,
              'speed': speed,
              'mediaUrl': mediaUrl,
            });
            configured = true;
            if (initialPosition > Duration.zero) {
              await channel.invokeMethod<void>('activate', {
                'pid': pid,
                'positionMs': initialPosition.inMilliseconds,
                'mediaUrl': mediaUrl,
              });
              continue;
            }
          }
          final positionMs = (state['positionMs'] as num?)?.toInt() ?? 0;
          // 续播命令是异步的，不能先把加载阶段的零位置回写到 NAS。
          final targetMs = initialPosition.inMilliseconds;
          final minimumPositionMs = math.max(
            math.min(targetMs, 1000),
            targetMs - 3000,
          );
          if (targetMs > 0 && positionMs < minimumPositionMs) {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            continue;
          }
          _accept(state);
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
    }
    throw StateError('未能确认 PotPlayer 正在播放此媒体，请检查播放地址或播放器权限');
  }

  bool _matches(Map<String, dynamic> state) =>
      state['alive'] == true && sameMedia('${state['file'] ?? ''}', mediaUrl);

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
          await channel.invokeMethod<void>('activate', {
            'pid': pid,
            'positionMs': targetMs,
            'focus': false,
            'mediaUrl': mediaUrl,
          });
          // PotPlayer 切集加载后可能暂停，续播定位后明确恢复播放。
          await channel.invokeMethod<void>('configure', {
            'pid': pid,
            'paused': false,
            'mediaUrl': mediaUrl,
          });
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

  Future<bool> activate({Duration? position}) async {
    if (_finished || !isCurrentSession()) return false;
    final state = await _snapshot();
    if (!_matches(state) || !{1, 2}.contains(state['state'])) return false;
    if (position != null && onMediaChanged != null) {
      // 切集等待续播时，详情页的「从头播放」以本次明确选择为准。
      _pendingPosition = position;
      _seekRequestedAt = DateTime.now();
    }
    await channel.invokeMethod<void>('activate', {
      'pid': pid,
      if (position != null) 'positionMs': position.inMilliseconds,
      'mediaUrl': mediaUrl,
    });
    await channel.invokeMethod<void>('configure', {
      'pid': pid,
      'paused': false,
      'mediaUrl': mediaUrl,
    });
    return true;
  }

  Future<void> finish({
    bool reportFinal = true,
    bool closePlayer = false,
  }) async {
    if (closePlayer) {
      _finished = true;
      try {
        // 已结束跟踪仍可关闭本次媒体，但不关闭用户后来手动打开的其他影片。
        if (!_ready || _matches(await _snapshot())) {
          await channel.invokeMethod<void>('close', {'pid': pid});
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
