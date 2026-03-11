class ActionRateLimiter {
  ActionRateLimiter({required this.cooldown});

  final Duration cooldown;
  DateTime _lastAcceptedAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool shouldBlock([DateTime? now]) {
    final current = now ?? DateTime.now();
    if (current.difference(_lastAcceptedAt) < cooldown) {
      return true;
    }
    _lastAcceptedAt = current;
    return false;
  }

  void reset() {
    _lastAcceptedAt = DateTime.fromMillisecondsSinceEpoch(0);
  }
}
