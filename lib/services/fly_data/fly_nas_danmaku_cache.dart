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
    this.sourceLabel = '服务弹幕',
  });
  final List<DanmakuComment> comments;
  final String sourceKey;
  final String sourceLabel;
  final bool Function() isCurrent;
}

/// A safe, actionable status; never contains addresses, credentials or raw errors.
enum FlyNasDanmakuStatus {
  notRequested,
  searching,
  downloading,
  ready,
  notSignedIn,
  notBound,
  notFound,
  miss,
  stale,
  needsReview,
  disabled,
  timeout,
  failed,
  invalidPayload;

  String get message => switch (this) {
    notRequested => '可从飞翔数据服务读取已保存并关联的弹幕。',
    searching => '已提交查找任务，飞翔后台正在查找弹幕。',
    downloading => '已提交获取任务，飞翔后台正在更新这集弹幕。',
    ready => '已成功读取 NAS 保存的弹幕。',
    notSignedIn => '请先登录飞翔账号，再选择已绑定的媒体连接。',
    notBound => '当前播放未关联飞翔媒体绑定，请从飞翔账号选择连接后重新播放。',
    notFound => '当前单集不在此连接的 NAS 目录中，请核对连接并在后台同步目录。',
    miss => '当前连接的这一集尚未关联可用弹幕。请到后台对应单集资料页获取或复用已保存弹幕。',
    stale => '当前文件的弹幕需要更新或重新确认，请在后台该单集资料页处理后重试。',
    needsReview => '飞翔后台未能自动确认这集的弹幕来源，需要核对匹配结果。',
    disabled => 'NAS 弹幕服务尚未启用，请在飞翔后台检查弹幕设置。',
    timeout => 'NAS 读取超时，可重新获取；也请检查飞翔服务的外网或 VPN 地址。',
    failed => '暂时无法读取 NAS 弹幕，请检查飞翔账号和服务连接后重试。',
    invalidPayload => 'NAS 弹幕内容或版本校验未通过，请在后台重新保存后重试。',
  };
}

/// 缓存读取与播放后的后台准备共用当前账号和精确媒体绑定。
class FlyNasDanmakuCache {
  FlyNasDanmakuCache({
    FlyDataSession? Function()? sessionReader,
    String Function()? scopeReader,
    String Function()? scopeEpochReader,
    String Function()? bindingReader,
    FlyDataApi Function(String, String)? apiFactory,
    this.budget = const Duration(milliseconds: 1200),
    this.onStatus,
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
  final void Function(FlyNasDanmakuStatus)? onStatus;

  static String _currentBinding() =>
      (PlayStatsService.instance.database as SqflitePlayStatsDatabase)
          .bindingReference['binding_id'] ??
      '';

  /// 由实际播放触发；服务端负责去重和判断是否首次查找。
  /// 等待期间不占用起播预算，切账号、切文件或手选来源即停止取用结果。
  Future<bool> prepareOnPlayback({
    required String statsScope,
    required String itemGuid,
    String mediaGuid = '',
    bool refreshExisting = false,
    required bool Function() isCurrent,
  }) async {
    final session = _sessionReader();
    if (session == null || statsScope.isEmpty || itemGuid.isEmpty) return false;
    final binding = _bindingReader();
    final epoch = _scopeEpochReader();
    bool current() =>
        isCurrent() &&
        identical(session, _sessionReader()) &&
        epoch == _scopeEpochReader() &&
        binding.isNotEmpty &&
        binding == _bindingReader() &&
        statsScope == _scopeReader() &&
        statsScope ==
            PlayStatsService.scopeForBinding(session.accountKey, binding);
    if (!current()) return false;
    final api = _apiFactory(session.serverUrl, session.token);
    try {
      final prepared = await api
          .post('/danmaku/ensure', {
            if (refreshExisting) 'refresh_existing': true,
            'source_ref': {
              'binding_id': binding,
              'remote_item_id': itemGuid,
              if (mediaGuid.isNotEmpty) 'remote_media_source_id': mediaGuid,
            },
          })
          .timeout(const Duration(seconds: 4));
      if (!current()) return false;
      if (prepared['status'] == 'ready') return true;
      final requestId = prepared['request_id'];
      final itemId = prepared['item_id'];
      final jobId = prepared['job_id'], matchId = prepared['match_id'];
      final downloading = jobId is String && jobId.isNotEmpty &&
          matchId is String && matchId.isNotEmpty;
      if (!['queued', 'running'].contains(prepared['status']) ||
          (!downloading && (requestId is! String || requestId.isEmpty ||
              itemId is! String || itemId.isEmpty))) {
        onStatus?.call(switch (prepared['status']) {
          'disabled' => FlyNasDanmakuStatus.disabled,
          'needs_review' => FlyNasDanmakuStatus.needsReview,
          'failed' => FlyNasDanmakuStatus.failed,
          _ => FlyNasDanmakuStatus.stale,
        });
        return false;
      }
      onStatus?.call(downloading ? FlyNasDanmakuStatus.downloading : FlyNasDanmakuStatus.searching);
      // 当前视频持续观察到任务终态，避免排队较久后漏掉完成结果；退出不取消服务端成果。
      while (current()) {
        await Future<void>.delayed(const Duration(seconds: 5));
        if (!current()) return false;
        final request = await api
            .get(downloading ? '/danmaku/jobs' : '/service-requests/${Uri.encodeComponent(requestId as String)}')
            .timeout(const Duration(seconds: 4));
        if (!current()) return false;
        if (downloading) {
          final jobs = (request['items'] as List? ?? []).whereType<Map>().where(
            (job) => job['id'] == jobId && job['match_id'] == matchId);
          if (jobs.length != 1) {
            onStatus?.call(FlyNasDanmakuStatus.failed);
            return false;
          }
          final status = jobs.single['status'];
          if (status == 'succeeded') return true;
          if (!['queued', 'running'].contains(status)) {
            onStatus?.call(FlyNasDanmakuStatus.failed);
            return false;
          }
          continue;
        }
        final items = (request['items'] as List? ?? []).whereType<Map>().where(
          (item) => item['id'] == itemId);
        if (items.length != 1 || items.single['resource_kind'] != 'danmaku') {
          onStatus?.call(FlyNasDanmakuStatus.stale);
          return false;
        }
        // 同批其他集可能仍需处理，只等待当前播放集自己的弹幕条目。
        final state = items.single['state'];
        if (state == 'ready') return true;
        if (!['pending', 'working', 'waiting'].contains(state)) {
          onStatus?.call(state == 'needs_decision'
              ? FlyNasDanmakuStatus.needsReview
              : state == 'failed' ? FlyNasDanmakuStatus.failed
              : FlyNasDanmakuStatus.stale);
          return false;
        }
        if (items.single['existing_job_kind'] == 'danmaku') {
          onStatus?.call(FlyNasDanmakuStatus.downloading);
        }
      }
    } catch (error) {
      // 网络、版本差异与服务故障不能打断正在播放的视频。
      if (current()) {
        onStatus?.call(error is TimeoutException
            ? FlyNasDanmakuStatus.timeout : FlyNasDanmakuStatus.failed);
      }
    } finally {
      api.close();
    }
    return false;
  }

  Future<FlyNasDanmakuResult?> resolve({
    required String statsScope,
    required String itemGuid,
    String mediaGuid = '',
    bool enabled = true,
    bool Function()? isCurrent,
  }) async {
    final session = _sessionReader();
    if (!enabled) return null;
    if (session == null) {
      onStatus?.call(FlyNasDanmakuStatus.notSignedIn);
      return null;
    }
    if (itemGuid.isEmpty || statsScope.isEmpty) {
      onStatus?.call(FlyNasDanmakuStatus.notBound);
      return null;
    }
    final binding = _bindingReader();
    final epoch = _scopeEpochReader();
    if (binding.isEmpty ||
        statsScope != _scopeReader() ||
        statsScope !=
            PlayStatsService.scopeForBinding(session.accountKey, binding)) {
      onStatus?.call(FlyNasDanmakuStatus.notBound);
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
    var status = FlyNasDanmakuStatus.invalidPayload;
    Future<FlyNasDanmakuResult?> load() async {
      final resolved = await api.get(
        '/danmaku/resolve',
        query: {
          'binding_id': binding,
          'remote_item_id': itemGuid,
          if (mediaGuid.isNotEmpty) 'remote_media_source_id': mediaGuid,
        },
      );
      if (expired || !valid()) return null;
      if (resolved['status'] != 'ready') {
        status = switch (resolved['status']) {
          'miss' => FlyNasDanmakuStatus.miss,
          'stale' => FlyNasDanmakuStatus.stale,
          'disabled' => FlyNasDanmakuStatus.disabled,
          _ => FlyNasDanmakuStatus.failed,
        };
        return null;
      }
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
      final result = decodePayload(
        payload,
        matchId: id,
        revision: revision,
        versionKey: version,
        isCurrent: valid,
        withinBudget: () => elapsed.elapsed <= budget,
      );
      if (elapsed.elapsed > budget) {
        status = FlyNasDanmakuStatus.timeout;
        return null;
      }
      if (expired || !valid() || result == null) return null;
      status = FlyNasDanmakuStatus.ready;
      return result;
    }

    try {
      return await load().timeout(
        budget,
        onTimeout: () {
          expired = true;
          status = FlyNasDanmakuStatus.timeout;
          return null;
        },
      );
    } catch (error) {
      status = error is StateError && error.message == '数据服务拒绝请求：NOT_FOUND'
          ? FlyNasDanmakuStatus.notFound
          : FlyNasDanmakuStatus.failed;
      return null;
    } finally {
      expired = true;
      api.close();
      if (valid()) onStatus?.call(status);
    }
  }

  /// 缓存直读和正式选源共用同一套身份、时间与评论格式校验。
  static FlyNasDanmakuResult? decodePayload(
    Map<String, dynamic> payload, {
    required String matchId,
    required int revision,
    required String versionKey,
    required bool Function() isCurrent,
    bool Function()? withinBudget,
  }) {
    if (!isCurrent() ||
        payload['match_id'] != matchId ||
        payload['revision'] != revision ||
        payload['version_key'] != versionKey) {
      return null;
    }
    final items = payload['items'];
    if (items is! List || items.isEmpty || items.length > 100000) return null;
    final comments = <DanmakuComment>[];
    for (final item in items) {
      if (withinBudget?.call() == false) return null;
      if (item is! Map) return null;
      final time = item['time_ms'], color = item['color'], text = item['text'];
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
          id: 'nas:$matchId:${comments.length}',
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
    if (!isCurrent()) return null;
    return FlyNasDanmakuResult(
      comments: comments,
      sourceKey: 'nas:$matchId:$revision:$versionKey',
      sourceLabel: _sourceLabel(payload['source_label']),
      isCurrent: isCurrent,
    );
  }

  static String _sourceLabel(dynamic value) {
    if (value is! String) return '服务弹幕';
    final text = value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
    return text.isEmpty || text.length > 100 ? '服务弹幕' : text;
  }
}
