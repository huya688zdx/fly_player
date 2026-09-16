import 'dart:async';
import 'dart:math';
import 'fly_bif_service.dart';

/// A lease belongs to one immutable playback context. Pausing keeps it alive;
/// stopping is ordered after any in-flight update and cannot be undone locally.
class FlyPlaybackActivity {
  FlyPlaybackActivity({
    required Future<void> Function(Map<String, dynamic>) send,
    required bool Function() isCurrent,
    Map<String, dynamic>? source,
  }) : _send = send,
       _isCurrent = isCurrent,
       _source = source;
  final Future<void> Function(Map<String, dynamic>) _send;
  final bool Function() _isCurrent;
  final Map<String, dynamic>? _source;
  final String sessionId = newSessionId();
  Timer? _timer;
  Future<void> _pending = Future.value();
  bool _closed = false, _paused = true, _queued = false;

  static FlyPlaybackActivity forAccess(FlyBifAccess access) =>
      FlyPlaybackActivity(
        isCurrent: access.isCurrent,
        source: access.source.toJson(),
        send: (body) async {
          final api = access.session.createApi();
          try {
            await api
                .post('/playback/activity', body)
                .timeout(const Duration(seconds: 3));
          } finally {
            api.close();
          }
        },
      );

  void start({required bool paused}) {
    if (_closed || _timer != null) return;
    _paused = paused;
    _heartbeat();
    if (_closed) return;
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _heartbeat());
  }

  void update({required bool paused}) {
    if (_closed) return;
    final changed = _paused != paused;
    _paused = paused;
    if (changed) _heartbeat();
  }

  void _heartbeat() {
    if (_closed) return;
    if (!_isCurrent()) {
      unawaited(stop());
      return;
    }
    if (_queued) return;
    _queued = true;
    _pending = _pending
        .then((_) async {
          if (_closed || !_isCurrent()) return;
          try {
            await _send(_event(_paused ? 'paused' : 'playing'));
          } catch (_) {
            /* playback is independent */
          }
        })
        .whenComplete(() {
          _queued = false;
        });
  }

  Map<String, dynamic> _event(String state) => {
    'session_id': sessionId,
    'state': state,
    if (_source != null) 'source_ref': _source,
  };

  Future<void> stop() {
    if (_closed) return _pending;
    _closed = true;
    _timer?.cancel();
    _timer = null;
    return _pending = _pending.then((_) async {
      try {
        await _send(_event('stopped'));
      } catch (_) {
        /* lease expires server-side */
      }
    });
  }

  static String newSessionId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
