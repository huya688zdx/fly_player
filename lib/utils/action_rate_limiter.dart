class ActionRateLimiter {
  ActionRateLimiter({required this.cooldown});

  final Duration cooldown;
  DateTime _lastAcceptedAt = DateTime.fromMillisecondsSinceEpoch(0);

  Duration remaining([DateTime? now]) {
    final current = now ?? DateTime.now();
    final elapsed = current.difference(_lastAcceptedAt);
    if (elapsed >= cooldown) {
      return Duration.zero;
    }
    return cooldown - elapsed;
  }

  bool shouldBlock([DateTime? now]) {
    if (remaining(now) > Duration.zero) {
      return true;
    }
    _lastAcceptedAt = now ?? DateTime.now();
    return false;
  }

  void reset() {
    _lastAcceptedAt = DateTime.fromMillisecondsSinceEpoch(0);
  }
}
