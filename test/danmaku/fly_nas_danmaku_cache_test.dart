import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/danmaku/models/danmaku_comment.dart';
import 'package:fly_player/services/fly_data/fly_data_api.dart';
import 'package:fly_player/services/fly_data/fly_data_service.dart';
import 'package:fly_player/services/fly_data/fly_nas_danmaku_cache.dart';
import 'package:fly_player/services/play_stats/play_stats_service.dart';

void main() {
  late FlyDataSession? session;
  late String scope;
  late _Api api;
  late FlyNasDanmakuCache cache;
  var current = true;
  setUp(() {
    session = FlyDataSession(
      serverUrl: 'https://fly.example',
      userId: 'viewer',
      username: 'viewer',
      deviceId: 'device',
      deviceName: 'Player',
      token: 'synthetic',
      installationId: 'install',
      serviceInstanceId: 'instance',
    );
    scope = PlayStatsService.scopeForBinding(session!.accountKey, 'binding');
    current = true;
    api = _Api();
    cache = FlyNasDanmakuCache(
      sessionReader: () => session,
      scopeReader: () => scope,
      bindingReader: () => 'binding',
      apiFactory: (_, _) => api,
      budget: const Duration(milliseconds: 40),
    );
  });

  Future<FlyNasDanmakuResult?> resolve({
    bool enabled = true,
    String? statsScope,
  }) => cache.resolve(
    statsScope: statsScope ?? scope,
    itemGuid: 'same/id',
    mediaGuid: 'file-2',
    enabled: enabled,
    isCurrent: () => current,
  );

  test('关闭、无会话和错误范围不发请求', () async {
    expect(await resolve(enabled: false), isNull);
    expect(await resolve(statsScope: 'foreign'), isNull);
    session = null;
    expect(await resolve(), isNull);
    expect(api.calls, isEmpty);
  });

  test('miss、disabled、stale 安全回退且不拉 payload', () async {
    for (final status in ['miss', 'disabled', 'stale']) {
      api.responses = [
        {'status': status},
      ];
      expect(await resolve(), isNull);
    }
    expect(api.calls.map((e) => e.$1), everyElement('/danmaku/resolve'));
    expect(api.calls.first.$2, {
      'binding_id': 'binding',
      'remote_item_id': 'same/id',
      'remote_media_source_id': 'file-2',
    });
  });

  test('手动获取能区分未关联、资源过期与未登录', () async {
    final statuses = <FlyNasDanmakuStatus>[];
    cache = FlyNasDanmakuCache(
      sessionReader: () => session,
      scopeReader: () => scope,
      bindingReader: () => 'binding',
      apiFactory: (_, _) => api,
      onStatus: statuses.add,
    );
    for (final status in ['miss', 'stale', 'disabled']) {
      api.responses = [
        {'status': status},
      ];
      expect(await resolve(), isNull);
    }
    session = null;
    expect(await resolve(), isNull);
    expect(statuses, [
      FlyNasDanmakuStatus.miss,
      FlyNasDanmakuStatus.stale,
      FlyNasDanmakuStatus.disabled,
      FlyNasDanmakuStatus.notSignedIn,
    ]);
  });

  test('自动超时后独立手动预算可取得同一绑定的弹幕', () async {
    final statuses = <FlyNasDanmakuStatus>[];
    FlyNasDanmakuCache reader(Duration budget) => FlyNasDanmakuCache(
      sessionReader: () => session,
      scopeReader: () => scope,
      bindingReader: () => 'binding',
      apiFactory: (_, _) => api,
      budget: budget,
      onStatus: statuses.add,
    );
    cache = reader(const Duration(milliseconds: 10));
    api.pending = Completer<Map<String, dynamic>>();
    expect(await resolve(), isNull);
    expect(statuses.last, FlyNasDanmakuStatus.timeout);
    expect(api.closed, isTrue);
    api = _Api()..payloadPending = Completer<Map<String, dynamic>>();
    cache = reader(const Duration(milliseconds: 200));
    final retry = resolve();
    await Future<void>.delayed(const Duration(milliseconds: 25));
    api.payloadPending!.complete(_payload);
    expect(await retry, isNotNull);
    expect(statuses.last, FlyNasDanmakuStatus.ready);
    expect(api.calls.first.$2?['binding_id'], 'binding');
    expect(api.calls.first.$2?['remote_media_source_id'], 'file-2');
  });

  test('媒体不在当前绑定目录时提示核对连接及同步目录', () async {
    final statuses = <FlyNasDanmakuStatus>[];
    cache = FlyNasDanmakuCache(
      sessionReader: () => session,
      scopeReader: () => scope,
      bindingReader: () => 'binding',
      apiFactory: (_, _) => api,
      onStatus: statuses.add,
    );
    api.pending = Completer<Map<String, dynamic>>()
      ..completeError(StateError('数据服务拒绝请求：NOT_FOUND'));
    expect(await resolve(), isNull);
    expect(statuses, [FlyNasDanmakuStatus.notFound]);
    expect(statuses.single.message, contains('同步目录'));
  });

  test('ready 保留服务端时间，仅转换滚动顶部底部及 RGB', () async {
    final result = await resolve();
    expect(result, isNotNull);
    expect(result!.comments.map((e) => e.timeMs), [1250, 2000, 3000]);
    expect(result.comments.map((e) => e.type), [
      DanmakuCommentType.scroll,
      DanmakuCommentType.bottom,
      DanmakuCommentType.top,
    ]);
    expect(result.comments.first.color.toARGB32(), 0xff123456);
    expect(result.comments.first.text, '<不是标记>');
    expect(result.sourceKey, contains('nas:'));
    expect(api.calls.last.$1, '/danmaku/matches/match/payload');
    expect(api.calls.last.$2, {'revision': 2});
    expect(api.closed, isTrue);
    session = null;
    expect(result.isCurrent(), isFalse);
  });

  test('延迟响应期间切账号，不再取 payload 或交付旧结果', () async {
    final pending = Completer<Map<String, dynamic>>();
    api.pending = pending;
    final result = resolve();
    await Future<void>.delayed(Duration.zero);
    session = null;
    pending.complete(_ready);
    expect(await result, isNull);
    expect(api.calls, hasLength(1));
  });

  test('来源摘要可直接显示，兼容旧 payload 的默认名称', () async {
    api.responses = [
      _ready,
      {..._payload, 'source_label': 'NAS 合并 · 3 个来源'},
    ];
    expect((await resolve())!.sourceLabel, 'NAS 合并 · 3 个来源');
    api.responses = [
      _ready,
      {..._payload, 'source_label': '\n\u0000'},
    ];
    expect((await resolve())!.sourceLabel, 'NAS 已确认弹幕');
  });

  test('同账号重新登录更换会话也拒绝迟到的来源摘要和评论', () async {
    final pending = Completer<Map<String, dynamic>>();
    api.payloadPending = pending;
    final result = resolve();
    await Future<void>.delayed(Duration.zero);
    session = FlyDataSession.fromJson({
      ...session!.toJson(),
      'token': 'replacement',
    });
    pending.complete(_payload);
    expect(await result, isNull);
  });

  test('payload 期间更换播放版本，丢弃迟到数据', () async {
    final pending = Completer<Map<String, dynamic>>();
    api.payloadPending = pending;
    final result = resolve();
    await Future<void>.delayed(Duration.zero);
    current = false;
    pending.complete(_payload);
    expect(await result, isNull);
  });

  test('完整两请求预算到期即关闭连接，迟到结果不可使用', () async {
    final pending = Completer<Map<String, dynamic>>();
    api.pending = pending;
    final result = await resolve();
    expect(result, isNull);
    expect(api.closed, isTrue);
    pending.complete(_ready);
    await Future<void>.delayed(Duration.zero);
    expect(api.calls, hasLength(1));
  });

  test('拒绝跨站 payload URL、错版本和非法评论', () async {
    api.responses = [
      {..._ready, 'payload_url': 'https://foreign.example/payload'},
    ];
    expect(await resolve(), isNull);
    expect(api.calls, hasLength(1));
    api.responses = [
      _ready,
      {..._payload, 'revision': 3},
    ];
    expect(await resolve(), isNull);
    api.responses = [
      _ready,
      {
        ..._payload,
        'items': [
          {'time_ms': -1, 'mode': 1, 'color': 0, 'text': 'bad'},
        ],
      },
    ];
    expect(await resolve(), isNull);
  });

  test('原源先可用时不额外等待 NAS，失败源不取消另一来源', () async {
    final slowNas = Completer<String?>();
    expect(
      await firstAvailableDanmaku<String>([
        slowNas.future,
        Future.value('original'),
      ]),
      'original',
    );
    slowNas.complete('late');
    expect(
      await firstAvailableDanmaku<String>([
        Future.error(StateError('offline')),
        Future.value('nas'),
      ]),
      'nas',
    );
    expect(
      await firstAvailableDanmaku<String>([
        Future.value(null),
        Future.value(null),
      ]),
      isNull,
    );
  });
}

const _ready = <String, dynamic>{
  'status': 'ready',
  'match_id': 'match',
  'revision': 2,
  'version_key': 'version',
  'payload_url': '/api/v1/danmaku/matches/match/payload?revision=2',
};
const _payload = <String, dynamic>{
  'match_id': 'match',
  'revision': 2,
  'version_key': 'version',
  'offset_ms': 1000,
  'items': [
    {'time_ms': 1250, 'mode': 1, 'color': 0x123456, 'text': '<不是标记>'},
    {'time_ms': 2000, 'mode': 4, 'color': 0xffffff, 'text': '底部'},
    {'time_ms': 3000, 'mode': 5, 'color': 0xffffff, 'text': '顶部'},
  ],
};

class _Api extends FlyDataApi {
  _Api() : super('https://fly.example');
  final calls = <(String, Map<String, dynamic>?)>[];
  List<Map<String, dynamic>> responses = [_ready, _payload];
  Completer<Map<String, dynamic>>? pending, payloadPending;
  bool closed = false;
  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    calls.add((path, query));
    if (pending != null) return pending!.future;
    if (path.endsWith('/payload') && payloadPending != null) {
      return payloadPending!.future;
    }
    return responses.removeAt(0);
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}
