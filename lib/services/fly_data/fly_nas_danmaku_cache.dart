import 'dart:async';
import 'dart:ui' show Color;

import '../../danmaku/models/danmaku_comment.dart';
import '../play_stats/play_stats_database.dart';
import '../play_stats/play_stats_service.dart';
import 'fly_data_api.dart';
import 'fly_data_service.dart';

/// A fast original source must not wait for an unavailable NAS cache.
Future<T?> firstAvailableDanmaku<T>(List<Future<T?>> requests) {
  if (requests.isEmpty) return Future.value(null);
  final result = Completer<T?>();
  var remaining = requests.length;
  void accept(T? value) {
    remaining--;
    if (result.isCompleted) return;
    if (value != null || remaining == 0) result.complete(value);
  }

  for (final request in requests) {
    unawaited(
      request.then(accept, onError: (Object _, StackTrace __) => accept(null)),
    );
  }
  return result.future;
}

class FlyNasDanmakuResult {
  const FlyNasDanmakuResult({
    required this.comments,
    required this.sourceKey,
    required this.isCurrent,
    this.sourceLabel = 'NAS 已确认弹幕',
  });
  final List<DanmakuComment> comments;
  final String sourceKey;
  final String sourceLabel;
  final bool Function() isCurrent;
}

/// Reads an already confirmed NAS cache. Never matches titles or schedules work.
/// Every request captures the Fly session and the source's original binding.
class FlyNasDanmakuCache {
  FlyNasDanmakuCache({
    FlyDataSession? Function()? sessionReader,
    String Function()? scopeReader,
    String Function()? scopeEpochReader,
    String Function()? bindingReader,
    FlyDataApi Function(String, String)? apiFactory,
    this.budget = const Duration(milliseconds: 1200),
  }) : _sessionReader =
           sessionReader ?? (() => FlyDataService.instance.session),
       _scopeReader =
           scopeReader ?? (() => PlayStatsService.instance.currentScope),
       _scopeEpochReader =
           scopeEpochReader ??
           scopeReader ??
           (() => FlyDataService.instance.scopeIdentity),
       _bindingReader = bindingReader ?? _currentBinding,
       _apiFactory =
           apiFactory ??
           ((url, token) => FlyDataApi(
             url,
             token: token,
             maxResponseBytes: 8 * 1024 * 1024,
           ));

  static final instance = FlyNasDanmakuCache();
  final FlyDataSession? Function() _sessionReader;
  final String Function() _scopeReader, _scopeEpochReader, _bindingReader;
  final FlyDataApi Function(String, String) _apiFactory;
  final Duration budget;

  static String _currentBinding() =>
      (PlayStatsService.instance.database as SqflitePlayStatsDatabase)
          .bindingReference['binding_id'] ??
      '';

  Future<FlyNasDanmakuResult?> resolve({
    required String statsScope,
    required String itemGuid,
    String mediaGuid = '',
    bool enabled = true,
    bool Function()? isCurrent,
  }) async {
    final session = _sessionReader();
    if (!enabled || session == null || itemGuid.isEmpty || statsScope.isEmpty) {
      return null;
    }
    final binding = _bindingReader();
    final epoch = _scopeEpochReader();
    if (binding.isEmpty ||
        statsScope != _scopeReader() ||
        statsScope !=
            PlayStatsService.scopeForBinding(session.accountKey, binding)) {
      return null;
    }
    bool valid() =>
        identical(session, _sessionReader()) &&
        statsScope == _scopeReader() &&
        epoch == _scopeEpochReader() &&
        binding == _bindingReader() &&
        (isCurrent?.call() ?? true);
    if (!valid()) return null;
    final api = _apiFactory(session.serverUrl, session.token);
    final elapsed = Stopwatch()..start();
    var expired = false;
    Future<FlyNasDanmakuResult?> load() async {
      final resolved = await api.get(
        '/danmaku/resolve',
        query: {
          'binding_id': binding,
          'remote_item_id': itemGuid,
          if (mediaGuid.isNotEmpty) 'remote_media_source_id': mediaGuid,
        },
      );
      if (expired || !valid() || resolved['status'] != 'ready') return null;
      final id = resolved['match_id'];
      final revision = resolved['revision'];
      final version = resolved['version_key'];
      if (id is! String ||
          id.isEmpty ||
          revision is! int ||
          revision < 1 ||
          version is! String ||
          version.isEmpty) {
        return null;
      }
      final path = '/danmaku/matches/${Uri.encodeComponent(id)}/payload';
      // Never send a bearer token to a URL supplied by a response.
      if (resolved['payload_url'] != '/api/v1$path?revision=$revision') {
        return null;
      }
      final payload = await api.get(path, query: {'revision': revision});
      if (expired ||
          !valid() ||
          payload['match_id'] != id ||
          payload['revision'] != revision ||
          payload['version_key'] != version) {
        return null;
      }
      final items = payload['items'];
      if (items is! List || items.isEmpty || items.length > 100000) return null;
      final comments = <DanmakuComment>[];
      for (final item in items) {
        if (elapsed.elapsed > budget) return null;
        if (item is! Map) return null;
        final time = item['time_ms'],
            color = item['color'],
            text = item['text'];
        final mode = item['mode'];
        if (time is! int ||
            time < 0 ||
            color is! int ||
            color < 0 ||
            color > 0xffffff ||
            text is! String ||
            text.length > 1000 ||
            ![1, 4, 5].contains(mode)) {
          return null;
        }
        comments.add(
          DanmakuComment(
            id: 'nas:$id:${comments.length}',
            timeMs: time,
            text: text,
            type: mode == 4
                ? DanmakuCommentType.bottom
                : mode == 5
                ? DanmakuCommentType.top
                : DanmakuCommentType.scroll,
            color: Color(0xff000000 | color),
          ),
        );
      }
      if (expired || !valid()) return null;
      return FlyNasDanmakuResult(
        comments: comments,
        sourceKey: 'nas:$id:$revision:$version',
        sourceLabel: _sourceLabel(payload['source_label']),
        isCurrent: valid,
      );
    }

    try {
      return await load().timeout(
        budget,
        onTimeout: () {
          expired = true;
          return null;
        },
      );
    } catch (_) {
      return null;
    } finally {
      expired = true;
      api.close();
    }
  }

  static String _sourceLabel(dynamic value) {
    if (value is! String) return 'NAS 已确认弹幕';
    final text = value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
    return text.isEmpty || text.length > 100 ? 'NAS 已确认弹幕' : text;
  }
}
