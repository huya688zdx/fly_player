import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 只跟踪本次启动的进程和媒体，播放器内部换片后结束原条目的回报。
class PotPlayerSession with WidgetsBindingObserver {
  PotPlayerSession({
    required this.pid,
    required this.mediaUrl,
    required this.isCurrentSession,
    required this.onProgress,
    required this.onFinished,
    required this.onError,
  });

  static const channel = MethodChannel('fly_player/potplayer');
  final int pid;
  final String mediaUrl;
  final bool Function() isCurrentSession;
  final void Function(Duration position, Duration duration, bool paused)
  onProgress;
  final Future<void> Function() onFinished;
  final void Function(String message) onError;
  Timer? _timer;
  bool _polling = false;
  bool _finished = false;
  bool _ready = false;
  int _failures = 0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _paused = false;
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
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    var configured = false;
    while (!_finished && DateTime.now().isBefore(deadline)) {
      if (!isCurrentSession()) throw StateError('播放账号已切换，请重新播放');
      try {
        final state = await _snapshot();
        if (_matches(state) && (state['state'] == 1 || state['state'] == 2)) {
          if (!configured) {
            await channel.invokeMethod<void>('configure', {
              'pid': pid,
              'paused': paused,
              'speed': speed,
            });
            configured = true;
            if (initialPosition > Duration.zero) {
              await channel.invokeMethod<void>('activate', {
                'pid': pid,
                'positionMs': initialPosition.inMilliseconds,
              });
              continue;
            }
          }
          final positionMs = (state['positionMs'] as num?)?.toInt() ?? 0;
          // 续播命令是异步的，不能先把加载阶段的零位置回写到 NAS。
          if (initialPosition > const Duration(seconds: 3) &&
              positionMs < initialPosition.inMilliseconds - 3000) {
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
      if (state['alive'] != true) {
        await finish();
        return;
      }
      final file = '${state['file'] ?? ''}';
      if (file.isNotEmpty && !sameMedia(file, mediaUrl)) {
        onError('PotPlayer 已切换到其他媒体，已结束原影片的进度回报');
        await finish();
        return;
      }
      if (state['state'] == 0 && _ready) {
        // 停止时播放器可能已经把位置归零，保留最后一个有效采样。
        await finish();
        return;
      }
      if (!_matches(state) || !{1, 2}.contains(state['state'])) return;
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
    await channel.invokeMethod<void>('activate', {
      'pid': pid,
      if (position != null) 'positionMs': position.inMilliseconds,
    });
    await channel.invokeMethod<void>('configure', {
      'pid': pid,
      'paused': false,
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
