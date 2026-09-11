import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 播放页持有的 Windows 系统媒体会话，退出页面时撤销。
final class DesktopSystemMediaControls {
  DesktopSystemMediaControls({
    required Future<void> Function(bool playing) onPlaying,
    required Future<void> Function(Duration position) onSeek,
  }) {
    _channel.setMethodCallHandler((call) async {
      if (_disposed) return;
      switch (call.method) {
        case 'play':
          await onPlaying(true);
        case 'pause':
          await onPlaying(false);
        case 'seek':
          await onSeek(Duration(milliseconds: call.arguments as int));
      }
    });
  }

  static const _channel = MethodChannel('fly_player/system_media_controls');
  Map<String, Object>? _lastState;
  bool _disposed = false;
  bool _errorReported = false;

  Future<void> setMetadata({required String title, required String subtitle}) {
    _lastState = null;
    return _invoke('metadata', {'title': title, 'subtitle': subtitle});
  }

  Future<void> update({
    required String status,
    required Duration position,
    required Duration duration,
    required double rate,
  }) {
    final state = <String, Object>{
      'status': status,
      'position': position.inSeconds * 1000,
      'duration': duration.inMilliseconds,
      'rate': rate,
    };
    // 进度按秒去重，避免每帧通过平台通道刷新系统卡片。
    if (mapEquals(_lastState, state)) return Future<void>.value();
    _lastState = state;
    return _invoke('state', state);
  }

  Future<void> _invoke(String method, [Map<String, Object>? arguments]) async {
    if (_disposed) return;
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException catch (error) {
      if (!_errorReported) {
        debugPrint('[系统媒体会话] ${error.message}');
        _errorReported = true;
      }
    } on MissingPluginException {
      // 不支持此通道的测试宿主不影响播放器本身。
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _channel.setMethodCallHandler(null);
    final clearing = _invoke('clear');
    _disposed = true;
    await clearing;
  }
}
