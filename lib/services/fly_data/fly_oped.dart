import 'dart:convert';

/// A/B shared source identifiers. These never manufacture a file identity.
class FlySourceRef {
  const FlySourceRef({
    required this.bindingId,
    required this.remoteItemId,
    this.remoteMediaSourceId,
  });
  final String bindingId, remoteItemId;
  final String? remoteMediaSourceId;
  Map<String, dynamic> toJson() => {
    'binding_id': bindingId,
    'remote_item_id': remoteItemId,
    'remote_media_source_id': remoteMediaSourceId,
  };
  bool matches(Object? value) =>
      value is Map &&
      value['binding_id'] == bindingId &&
      value['remote_item_id'] == remoteItemId &&
      value['remote_media_source_id'] == remoteMediaSourceId;
}

int? _milliseconds(Object? value) =>
    value is int && value >= 0 && value <= 9007199254740991 ? value : null;
String? _identifier(Object? value) =>
    value is String &&
        value.isNotEmpty &&
        value.length <= 500 &&
        value.trim() == value
    ? value
    : null;

class FlyOpedSegment {
  const FlyOpedSegment({
    required this.id,
    required this.kind,
    required this.startMs,
    required this.endMs,
    required this.policy,
  });
  final String id, kind, policy;
  final int startMs, endMs;
  bool contains(int positionMs) => positionMs >= startMs && positionMs < endMs;
}

/// A published set is accepted atomically, with current source/context and A's
/// verified file/coordinate. Malformed sets never partially enable skipping.
class FlyOpedSet {
  FlyOpedSet._(
    this.source,
    this.contextId,
    this.fileId,
    this.coordinateId,
    this.revision,
    this.durationMs,
    this.segments,
    this.wire,
  );
  final FlySourceRef source;
  final String contextId, fileId, coordinateId, revision;
  final int durationMs;
  final List<FlyOpedSegment> segments;
  final Map<String, dynamic> wire;
  bool samePublication(FlyOpedSet other) =>
      contextId == other.contextId &&
      fileId == other.fileId &&
      coordinateId == other.coordinateId &&
      revision == other.revision &&
      durationMs == other.durationMs &&
      source.matches(other.source.toJson()) &&
      jsonEncode(wire['segments']) == jsonEncode(other.wire['segments']) &&
      jsonEncode(wire['protected_ranges']) ==
          jsonEncode(other.wire['protected_ranges']);
  FlyOpedSegment? at(int positionMs, {bool enabled = true}) {
    if (!enabled) return null;
    for (final segment in segments) {
      if (segment.policy != 'never' &&
          ['op', 'ed'].contains(segment.kind) &&
          segment.contains(positionMs)) {
        return segment;
      }
    }
    return null;
  }

  static FlyOpedSet? parse(
    Map<String, dynamic> data, {
    required FlySourceRef source,
    required String contextId,
    required int generation,
  }) {
    if (data['status'] != 'published' ||
        data['playback_context_id'] != contextId ||
        data['generation'] != generation) {
      return null;
    }
    final context = data['file_context'];
    if (context is! Map ||
        context['identity_state'] != 'verified' ||
        !source.matches(context['source_ref'])) {
      return null;
    }
    final file = _identifier(context['file_revision_id']),
        coordinate = _identifier(context['media_coordinate_id']),
        revision = _identifier(data['set_revision']);
    final duration = _milliseconds(context['duration_ms']);
    if (file == null ||
        coordinate == null ||
        revision == null ||
        duration == null ||
        duration == 0) {
      return null;
    }
    final raw = data['segments'], protected = data['protected_ranges'];
    if (raw is! List ||
        raw.length > 64 ||
        protected is! List ||
        protected.length > 64) {
      return null;
    }
    final ranges = <(int, int)>[];
    for (final range in protected) {
      if (range is! Map) return null;
      final start = _milliseconds(range['start_ms']),
          end = _milliseconds(range['end_ms']);
      if (start == null || end == null || start >= end || end > duration) {
        return null;
      }
      ranges.add((start, end));
    }
    final segments = <FlyOpedSegment>[];
    final ids = <String>{};
    for (final item in raw) {
      if (item is! Map) return null;
      final id = _identifier(item['id']),
          start = _milliseconds(item['start_ms']),
          end = _milliseconds(item['end_ms']);
      final kind = item['kind'], policy = item['skip_policy'];
      if (id == null ||
          !ids.add(id) ||
          start == null ||
          end == null ||
          start >= end ||
          end > duration ||
          !['op', 'ed', 'recap', 'preview', 'post_credit'].contains(kind) ||
          !['auto', 'prompt_only', 'never'].contains(policy)) {
        return null;
      }
      if (policy != 'never' && ranges.any((r) => start < r.$2 && end > r.$1)) {
        return null;
      }
      if (segments.any((s) => start < s.endMs && end > s.startMs)) return null;
      segments.add(
        FlyOpedSegment(
          id: id,
          kind: kind as String,
          startMs: start,
          endMs: end,
          policy: policy as String,
        ),
      );
    }
    // Copy the JSON rather than retaining a mutable response shared with callers.
    final wire = Map<String, dynamic>.from(jsonDecode(jsonEncode(data)) as Map);
    return FlyOpedSet._(
      source,
      contextId,
      file,
      coordinate,
      revision,
      duration,
      List.unmodifiable(segments),
      wire,
    );
  }
}

/// Automatic crossing is allowed only during continuous forward playback.
/// Resume, any user seek, repeated entries and large discontinuities prompt.
class FlyOpedPlaybackPolicy {
  int? _previous;
  final Set<String> _entered = {};
  void userSeek() {
    _previous = null;
  }

  FlyOpedSegment? observe(FlyOpedSet set, int positionMs) {
    final previous = _previous;
    _previous = positionMs;
    final segment = set.at(positionMs);
    if (segment == null) return null;
    if (!_entered.add('${set.revision}:${segment.id}')) return null;
    if (previous == null ||
        positionMs < previous ||
        positionMs - previous > 2500 ||
        previous >= segment.startMs ||
        segment.policy != 'auto') {
      return null;
    }
    return segment;
  }
}

/// One action has one intent and at most one terminal observation. The event
/// retains the generation at intent; expectedGeneration is the actual seek epoch.
class FlyOpedAction {
  FlyOpedAction({
    required this.set,
    required this.segment,
    required this.generation,
    required this.positionMs,
    required this.actionId,
  });
  final FlyOpedSet set;
  final FlyOpedSegment segment;
  final int generation, positionMs;
  final String actionId;
  int? expectedGeneration;
  int? _terminalPositionMs;
  bool _terminal = false;
  String? finish(String phase) {
    if (_terminal || !['settled', 'failed', 'cancelled'].contains(phase)) {
      return null;
    }
    _terminal = true;
    return phase;
  }

  String? sample({
    required int positionMs,
    required bool engineAccepted,
    required int generation,
  }) {
    if (_terminal || expectedGeneration == null) return null;
    if (generation != expectedGeneration) return finish('cancelled');
    if (engineAccepted && (positionMs - segment.endMs).abs() <= 500) {
      _terminalPositionMs = positionMs;
      return finish('settled');
    }
    return null;
  }

  Map<String, dynamic> event(String phase) => {
    'action_id': actionId,
    'phase': phase,
    'source_ref': set.source.toJson(),
    'playback_context_id': set.contextId,
    'generation': generation,
    'file_revision_id': set.fileId,
    'media_coordinate_id': set.coordinateId,
    'set_revision': set.revision,
    'segment_id': segment.id,
    'position_ms': phase == 'settled' ? _terminalPositionMs : positionMs,
    'target_ms': segment.endMs,
  };
}
