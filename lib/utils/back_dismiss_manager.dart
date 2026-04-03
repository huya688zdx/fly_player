import 'dart:async';

typedef BackDismissHandler = FutureOr<bool> Function();

class BackDismissManager {
  final Map<String, _BackDismissEntry> _entries = <String, _BackDismissEntry>{};
  int _registrationSeed = 0;

  void register({
    required String id,
    required BackDismissHandler handler,
    int priority = 0,
  }) {
    _entries[id] = _BackDismissEntry(
      handler: handler,
      priority: priority,
      registrationOrder: _registrationSeed++,
    );
  }

  void unregister(String id) {
    _entries.remove(id);
  }

  Future<bool> dismissActive() async {
    if (_entries.isEmpty) return false;
    final orderedEntries = _entries.entries.toList(growable: false)
      ..sort((left, right) {
        final priorityComparison = right.value.priority.compareTo(
          left.value.priority,
        );
        if (priorityComparison != 0) {
          return priorityComparison;
        }
        return right.value.registrationOrder.compareTo(
          left.value.registrationOrder,
        );
      });
    for (final entry in orderedEntries) {
      if (await entry.value.handler()) {
        return true;
      }
    }
    return false;
  }
}

class _BackDismissEntry {
  final BackDismissHandler handler;
  final int priority;
  final int registrationOrder;

  const _BackDismissEntry({
    required this.handler,
    required this.priority,
    required this.registrationOrder,
  });
}
