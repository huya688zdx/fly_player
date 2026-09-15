import '../../services/fly_data/fly_data_api.dart';
import '../../services/fly_data/fly_data_service.dart';
import '../../services/fly_data/fly_nas_danmaku_cache.dart';
import '../../services/fly_data/fly_playback_service_client.dart';

/// 飞翔后端的正式查询、选集和获取接口；只向当前服务发送公开来源标识。
class FlyDanmakuApi {
  FlyDanmakuApi({
    required this.api,
    required this.sourceQuery,
    required this.scopeIdentity,
    required this.sessionIdentity,
    required this.isCurrent,
  });

  final FlyDataApi api;
  final Map<String, dynamic> sourceQuery;
  final String scopeIdentity;
  final int sessionIdentity;
  final bool Function() isCurrent;

  static FlyDanmakuApi? capture({
    required String statsScope,
    required String itemGuid,
    required String mediaGuid,
    required bool Function() isCurrent,
  }) {
    final service = FlyDataService.instance;
    final session = service.session;
    final client = FlyPlaybackServiceClient.instance;
    final source = client.sourceRef(
      statsScope: statsScope,
      itemGuid: itemGuid,
      mediaGuid: mediaGuid,
    );
    if (session == null || source == null || mediaGuid.isEmpty) return null;
    final epoch = service.scopeIdentity;
    return FlyDanmakuApi(
      api: FlyDataApi(
        session.serverUrl,
        token: session.token,
        maxResponseBytes: 8 * 1024 * 1024,
        receiveTimeout: const Duration(seconds: 150),
      ),
      sourceQuery: source.toJson(),
      scopeIdentity: epoch,
      sessionIdentity: identityHashCode(session),
      isCurrent: () =>
          isCurrent() &&
          identical(session, service.session) &&
          epoch == service.scopeIdentity &&
          client
                  .sourceRef(
                    statsScope: statsScope,
                    itemGuid: itemGuid,
                    mediaGuid: mediaGuid,
                  )
                  ?.matches(source.toJson()) ==
              true,
    );
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    if (!isCurrent()) throw StateError('播放来源已改变');
    final value = await api
        .get(path, query: query)
        .timeout(const Duration(seconds: 12));
    if (!isCurrent()) throw StateError('播放来源已改变');
    return value;
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (!isCurrent()) throw StateError('播放来源已改变');
    final value = await api.post(path, body).timeout(timeout);
    if (!isCurrent()) throw StateError('播放来源已改变');
    return value;
  }

  Future<Map<String, dynamic>> _context([
    Map<String, dynamic>? candidate,
  ]) async {
    if (candidate != null &&
        (candidate['source'] != 'fly' ||
            candidate['scopeIdentity'] != scopeIdentity ||
            candidate['sessionIdentity'] != sessionIdentity)) {
      throw StateError('候选来源已失效');
    }
    final context = await _get('/danmaku/context', query: sourceQuery);
    final media = context['media_id'], version = context['version_key'];
    if (context['enabled'] != true ||
        context['configured'] != true ||
        media is! String ||
        media.isEmpty ||
        version is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(version) ||
        (candidate != null &&
            (candidate['mediaId'] != media ||
                candidate['versionKey'] != version))) {
      throw StateError('当前播放文件无法用于弹幕查询');
    }
    return context;
  }

  List<Map<String, dynamic>> _candidates(
    Map<String, dynamic> response,
    Map<String, dynamic> context,
  ) {
    final items = response['items'];
    if (items is! List) return [];
    return [
      for (final row in items.whereType<Map>())
        if (['series', 'episode'].contains(row['kind']) &&
            row['provider_id'] is String &&
            row['remote_ref'] is String &&
            row['title'] is String)
          {
            'source': 'fly',
            'kind': row['kind'],
            'providerId': row['provider_id'],
            'remoteRef': row['remote_ref'],
            'mediaId': context['media_id'],
            'versionKey': context['version_key'],
            'scopeIdentity': scopeIdentity,
            'sessionIdentity': sessionIdentity,
            'title': row['title'],
            'subtitle': '飞翔后端 · ${row['provider_id']}',
          },
    ];
  }

  Future<List<Map<String, dynamic>>> search(String keyword) async {
    final context = await _context();
    final providers = await _get('/danmaku/providers');
    final ids = (providers['items'] as List? ?? [])
        .whereType<Map>()
        .where(
          (value) => value['enabled'] == true && value['configured'] == true,
        )
        .map((value) => value['id'])
        .whereType<String>()
        .toList();
    if (ids.isEmpty) return [];
    final response = await _post('/danmaku/search', {
      'media_id': context['media_id'],
      'query': keyword.trim(),
      'assist': true,
      'provider_ids': ids,
    }, timeout: const Duration(seconds: 150));
    return _candidates(response, context);
  }

  Future<List<Map<String, dynamic>>> expand(
    Map<String, dynamic> candidate,
  ) async {
    if (candidate['kind'] != 'series') return [];
    final context = await _context(candidate);
    final response = await _post('/danmaku/episodes', {
      'media_id': context['media_id'],
      'provider_id': candidate['providerId'],
      'remote_ref': candidate['remoteRef'],
    }, timeout: const Duration(seconds: 60));
    return _candidates(response, context);
  }

  bool _selected(Map match, Map candidate) {
    final sources = match['sources'];
    if (sources is! List || sources.length != 1 || sources.single is! Map) {
      return false;
    }
    final source = sources.single as Map;
    return source['provider_id'] == candidate['providerId'] &&
        source['remote_ref'] == candidate['remoteRef'] &&
        source['title'] == candidate['title'] &&
        source['offset_ms'] == 0;
  }

  Future<FlyNasDanmakuResult?> importCandidate(
    Map<String, dynamic> candidate,
  ) async {
    if (candidate['kind'] != 'episode') return null;
    final context = await _context(candidate);
    final matches = (context['matches'] as List? ?? []).whereType<Map>();
    final previous = matches.isEmpty ? null : matches.first;
    final reply = await _post('/danmaku/matches', {
      'media_id': context['media_id'],
      'version_key': context['version_key'],
      if (previous != null) 'expected_revision': previous['revision'],
      'sources': [
        {
          'provider_id': candidate['providerId'],
          'remote_ref': candidate['remoteRef'],
          'title': candidate['title'],
          'offset_ms': 0,
        },
      ],
    });
    final match = reply['match'], job = reply['job'];
    if (match is! Map ||
        match['id'] is! String ||
        match['revision'] is! int ||
        match['version_key'] != context['version_key'] ||
        !_selected(match, candidate)) {
      return null;
    }
    final id = match['id'] as String;
    var revision = match['revision'] as int;
    if (job is Map && job['id'] is String && job['match_id'] == id) {
      var succeeded = false;
      // 排队时继续观察本次选择，直到当前视频退出或下载进入终态。
      while (isCurrent()) {
        await Future<void>.delayed(const Duration(seconds: 2));
        final jobs = await _get('/danmaku/jobs');
        final current = (jobs['items'] as List? ?? []).whereType<Map>().where(
          (value) => value['id'] == job['id'] && value['match_id'] == id,
        );
        if (current.length != 1) return null;
        final status = current.single['status'];
        if (status == 'succeeded') {
          succeeded = true;
          break;
        }
        if (!['queued', 'running'].contains(status)) return null;
      }
      if (!succeeded) return null;
      revision++;
    } else if (reply['cached'] != true) {
      return null;
    }
    // 多源发布成功才会递增版本；旧 published 不能代替本次选择。
    final confirmed = await _context(candidate);
    final current = (confirmed['matches'] as List? ?? [])
        .whereType<Map>()
        .where((value) => value['id'] == id && value['revision'] == revision);
    if (current.length != 1 ||
        current.single['selection_pending'] == true ||
        !_selected(current.single, candidate) ||
        (job is Map &&
            (current.single['last_job'] as Map?)?['id'] != job['id'])) {
      return null;
    }
    final payload = await _get(
      '/danmaku/matches/${Uri.encodeComponent(id)}/payload',
      query: {'revision': revision},
    );
    if (!_selected({'sources': payload['sources']}, candidate)) return null;
    return FlyNasDanmakuCache.decodePayload(
      payload,
      matchId: id,
      revision: revision,
      versionKey: context['version_key'] as String,
      isCurrent: isCurrent,
    );
  }

  void close() => api.close();
}
