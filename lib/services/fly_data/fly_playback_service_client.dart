import 'dart:math';

import '../play_stats/play_stats_database.dart';
import '../play_stats/play_stats_service.dart';
import 'fly_data_service.dart';
import 'fly_oped.dart';

/// Thin existing-session adapter. It never receives provider keys or A paths.
class FlyPlaybackServiceClient {
  static final instance = FlyPlaybackServiceClient();
  static String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}';
  final Map<String, Future<bool>> _actions = {};
  String get epoch {
    try {
      return FlyDataService.instance.scopeIdentity;
    } catch (_) {
      return '';
    }
  }

  FlySourceRef? sourceRef({
    required String statsScope,
    required String itemGuid,
    String mediaGuid = '',
  }) {
    try {
      final session = FlyDataService.instance.session;
      final stats = PlayStatsService.instance;
      final binding =
          (stats.database as SqflitePlayStatsDatabase)
              .bindingReference['binding_id'] ??
          '';
      if (session == null ||
          itemGuid.isEmpty ||
          binding.isEmpty ||
          statsScope != stats.currentScope ||
          statsScope !=
              PlayStatsService.scopeForBinding(session.accountKey, binding)) {
        return null;
      }
      return FlySourceRef(
        bindingId: binding,
        remoteItemId: itemGuid,
        remoteMediaSourceId: mediaGuid.isEmpty ? null : mediaGuid,
      );
    } catch (_) {
      return null;
    }
  }

  Future<FlyOpedSet?> resolve({
    required String statsScope,
    required String itemGuid,
    String mediaGuid = '',
    required String contextId,
    required int generation,
  }) async {
    final source = sourceRef(
      statsScope: statsScope,
      itemGuid: itemGuid,
      mediaGuid: mediaGuid,
    );
    if (source == null) return null;
    final session = FlyDataService.instance.session;
    final capturedEpoch = epoch;
    try {
      final data = await FlyDataService.instance
          .request(
            '/oped/resolve',
            body: {
              'source_ref': source.toJson(),
              'playback_context_id': contextId,
              'generation': generation,
            },
          )
          .timeout(const Duration(seconds: 2));
      if (!identical(session, FlyDataService.instance.session) ||
          capturedEpoch != epoch) {
        return null;
      }
      return FlyOpedSet.parse(
        data,
        source: source,
        contextId: contextId,
        generation: generation,
      );
    } catch (_) {
      return null;
    }
  }

  /// Serialize an action's HTTP events so a fast seek cannot deliver terminal
  /// before intent. Network failure never holds the playback thread.
  Future<void> record(
    Map<String, dynamic> event, {
    required String statsScope,
  }) async {
    final source = event['source_ref'];
    if (source is! Map ||
        sourceRef(
              statsScope: statsScope,
              itemGuid: (source['remote_item_id'] ?? '').toString(),
              mediaGuid: (source['remote_media_source_id'] ?? '').toString(),
            )?.matches(source) !=
            true) {
      return;
    }
    final actionId = event['action_id'];
    final phase = event['phase'];
    if (actionId is! String ||
        !['intent', 'settled', 'failed', 'cancelled'].contains(phase)) {
      return;
    }
    final session = FlyDataService.instance.session;
    final capturedEpoch = epoch;
    final previous = _actions[actionId];
    if (phase != 'intent' && previous == null) return;
    if (phase == 'intent' && previous != null) return;
    Future<bool> send() async {
      if (previous != null && !await previous) return false;
      if (!identical(session, FlyDataService.instance.session) ||
          capturedEpoch != epoch) {
        return false;
      }
      try {
        final response = await FlyDataService.instance
            .request('/oped/actions', body: event)
            .timeout(const Duration(seconds: 4));
        return response['accepted'] == true;
      } catch (_) {
        return false;
      }
    }

    final pending = send();
    _actions[actionId] = pending;
    await pending;
    if (phase != 'intent') _actions.remove(actionId);
    // Bound abandoned intents without touching stored history.
    if (_actions.length > 128) _actions.remove(_actions.keys.first);
  }
}
