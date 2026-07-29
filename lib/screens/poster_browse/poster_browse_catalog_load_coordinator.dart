class PosterBrowseCatalogLoadTicket<T> {
  const PosterBrowseCatalogLoadTicket._({
    required this.catalogId,
    required this.future,
    required this.ownsCompletion,
    required Object taskToken,
  }) : _taskToken = taskToken;

  final String catalogId;
  final Future<T> future;
  final bool ownsCompletion;
  final Object _taskToken;
}

class PosterBrowseCatalogLoadCoordinator<T> {
  final Map<String, _PosterBrowseCatalogLoadTask<T>> _tasks =
      <String, _PosterBrowseCatalogLoadTask<T>>{};
  String? _selectionIntent;

  PosterBrowseCatalogLoadTicket<T> acquire({
    required String catalogId,
    required bool selectWhenReady,
    required Future<T> Function() load,
  }) {
    final key = catalogId.trim();
    if (selectWhenReady) {
      _selectionIntent = key;
    }

    final existing = _tasks[key];
    if (existing != null) {
      return PosterBrowseCatalogLoadTicket<T>._(
        catalogId: key,
        future: existing.future,
        ownsCompletion: false,
        taskToken: existing,
      );
    }

    final task = _PosterBrowseCatalogLoadTask<T>(Future<T>.sync(load));
    _tasks[key] = task;
    return PosterBrowseCatalogLoadTicket<T>._(
      catalogId: key,
      future: task.future,
      ownsCompletion: true,
      taskToken: task,
    );
  }

  void select(String catalogId) {
    _selectionIntent = catalogId.trim();
  }

  void clearSelection() {
    _selectionIntent = null;
  }

  bool shouldSelect(String catalogId) {
    return _selectionIntent == catalogId.trim();
  }

  void release(PosterBrowseCatalogLoadTicket<T> ticket) {
    if (!ticket.ownsCompletion) return;
    final current = _tasks[ticket.catalogId];
    if (identical(current, ticket._taskToken)) {
      _tasks.remove(ticket.catalogId);
    }
  }

  void clear() {
    _tasks.clear();
    _selectionIntent = null;
  }
}

class _PosterBrowseCatalogLoadTask<T> {
  const _PosterBrowseCatalogLoadTask(this.future);

  final Future<T> future;
}
