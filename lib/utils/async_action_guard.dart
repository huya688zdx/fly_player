import 'dart:async';

class AsyncActionGuard {
  AsyncActionGuard._();

  static final Map<String, Future<Object?>> _inFlight =
      <String, Future<Object?>>{};

  static bool isRunning(String key) {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) {
      return false;
    }
    return _inFlight.containsKey(normalizedKey);
  }

  static Future<T> run<T>(
    String key, {
    required Future<T> Function() action,
    Duration settleDuration = Duration.zero,
  }) {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) {
      return action();
    }

    final existing = _inFlight[normalizedKey];
    if (existing != null) {
      return existing.then((value) => value as T);
    }

    final actionFuture = Future<T>.sync(action);
    final sharedFuture = actionFuture.then<Object?>((value) => value);
    _inFlight[normalizedKey] = sharedFuture;

    unawaited(
      sharedFuture.whenComplete(() async {
        if (settleDuration > Duration.zero) {
          await Future<void>.delayed(settleDuration);
        }
        if (identical(_inFlight[normalizedKey], sharedFuture)) {
          _inFlight.remove(normalizedKey);
        }
      }),
    );

    return actionFuture;
  }
}
