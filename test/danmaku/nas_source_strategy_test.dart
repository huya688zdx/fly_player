import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:fly_player/danmaku/api/dandanplay_api.dart';
import 'package:fly_player/danmaku/api/fly_danmaku_api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fly_player/danmaku/models/danmaku_comment.dart';
import 'package:fly_player/danmaku/models/danmaku_saved_source.dart';
import 'package:fly_player/danmaku/models/danmaku_settings.dart';
import 'package:fly_player/danmaku/settings/danmaku_saved_source_store.dart';
import 'package:fly_player/danmaku/settings/danmaku_settings_store.dart';
import 'package:fly_player/desktop/playback/desktop_danmaku_overlay.dart';
import 'package:fly_player/services/fly_data/fly_nas_danmaku_cache.dart';
import 'package:fly_player/services/fly_data/fly_data_api.dart';
import 'package:fly_player/services/fly_data/fly_data_service.dart';
import 'package:fly_player/services/play_stats/play_stats_service.dart';
import 'package:fly_player/services/play_stats/play_stats_database.dart';
import 'package:fly_player/services/native_danmaku_prefetch.dart';

const _mediaKey = 'v2|item=item|media=file|season=|s=1|e=1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late DanmakuSavedSourceStore store;
  late _Cache cache;
  var originalAttempts = 0;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final session = _session();
    FlyDataService.instance.session = session;
    await PlayStatsService.instance.bindOwnerScope(
      PlayStatsService.scopeForBinding(session.accountKey, 'binding'),
    );
    (PlayStatsService.instance.database as SqflitePlayStatsDatabase)
        .bindingReference = {
      'binding_id': 'binding',
    };
    directory = await Directory.systemTemp.createTemp('nas_strategy_');
    await Directory('${directory.path}/sources').create();
    store = DanmakuSavedSourceStore(directoryPath: '${directory.path}/sources');
    NativeDanmakuPrefetch.cacheRootOverrideForTest = directory.path;
    cache = _Cache();
    originalAttempts = 0;
    NativeDanmakuPrefetch.originalConfiguredOverrideForTest = () async {
      originalAttempts++;
      return false;
    };
  });
  tearDown(() async {
    NativeDanmakuPrefetch.cacheRootOverrideForTest = null;
    NativeDanmakuPrefetch.originalConfiguredOverrideForTest = null;
    NativeDanmakuPrefetch.flyApiFactoryForTest = null;
    NativeDanmakuPrefetch.originalApiFactoryForTest = null;
    FlyDataService.instance.session = null;
    await PlayStatsService.instance.bindOwnerScope('');
    await directory.delete(recursive: true);
  });
  Future<String?> resolve(String strategy) =>
      NativeDanmakuPrefetch.resolveToFile(
        seriesTitle: '',
        seasonNumber: 1,
        episodeNumber: 1,
        tmdbId: '',
        itemGuid: 'item',
        mediaGuid: 'file',
        statsScope: PlayStatsService.instance.currentScope,
        nasCache: cache,
        store: store,
        settings: DanmakuSettings.fromJson({'sourceStrategy': strategy}),
      );
  Future<void> oldAutoSource() async {
    await store.saveSource(
      DanmakuSavedSource(
        type: DanmakuSavedSourceType.danDanPlay,
        mediaKey: _mediaKey,
        sourceKey: 'dandan:100',
        label: '旧自动来源',
        commentCount: 1,
        updatedAtMs: 1,
      ),
      activate: true,
    );
    final key = 'dandan:100'.hashCode.toUnsigned(32).toRadixString(16);
    await File(
      '${directory.path}/native_danmaku_cache_$key.json',
    ).writeAsString(
      jsonEncode([
        ['old', 1000, '原来源', 0, 0xffffffff],
      ]),
    );
  }

  test('保存的优先顺序决定真实查询来源，首选无结果后才回退', () async {
    final events = <String>[];
    final transport = _PriorityApi(events);
    NativeDanmakuPrefetch.originalConfiguredOverrideForTest = () async => true;
    NativeDanmakuPrefetch.originalApiFactoryForTest = () =>
        _OriginalApi(events);
    NativeDanmakuPrefetch.flyApiFactoryForTest = () => FlyDanmakuApi(
      api: transport,
      sourceQuery: {},
      scopeIdentity: 'test',
      sessionIdentity: 1,
      isCurrent: () => true,
    );
    for (final strategy in ['nasPreferred', 'nasOnly', 'original']) {
      await const DanmakuSettingsStore().save(
        DanmakuSettings.fromJson({'sourceStrategy': strategy}),
      );
      expect(
        (await const DanmakuSettingsStore().load()).toJson()['sourceStrategy'],
        strategy,
      );
      events.clear();
      final candidates = await NativeDanmakuPrefetch.searchCandidates(
        keyword: '作品',
      );
      expect(candidates.single['source'], 'fly');
      expect(events, [
        if (strategy == 'original') 'dandan:search',
        'fly:context',
        'fly:providers',
        'fly:search',
      ]);
    }
    await const DanmakuSettingsStore().save(DanmakuSettings.defaults);
    transport.empty = true;
    events.clear();
    expect(
      await NativeDanmakuPrefetch.searchCandidates(keyword: '作品'),
      isEmpty,
    );
    expect(events, [
      'fly:context',
      'fly:providers',
      'fly:search',
      'dandan:search',
    ]);
  });
  test('普通登录即使保留Fly账号和仅NAS偏好也能读取原缓存且不读NAS', () async {
    await PlayStatsService.instance.bindOwnerScope('');
    expect(FlyDataService.instance.session, isNotNull);
    await const DanmakuSettingsStore().save(
      DanmakuSettings.fromJson({'sourceStrategy': 'nasOnly'}),
    );
    await oldAutoSource();
    final path = await resolve('nasOnly');
    expect(path, isNotNull);
    final payload = jsonDecode(await File(path!).readAsString()) as Map;
    expect(payload['sourceKey'], 'dandan:100');
    expect(cache.calls, 0);
    expect(originalAttempts, 0);
    expect(
      (await const DanmakuSettingsStore().load()).sourceStrategy,
      DanmakuSourceStrategy.nasOnly,
    );
  });
  test('普通登录保留仅NAS偏好时原搜索与导入仍进入原配置检查', () async {
    await PlayStatsService.instance.bindOwnerScope('');
    expect(FlyDataService.instance.session, isNotNull);
    await const DanmakuSettingsStore().save(
      DanmakuSettings.fromJson({'sourceStrategy': 'nasOnly'}),
    );
    expect(
      await NativeDanmakuPrefetch.searchCandidates(keyword: '作品'),
      isEmpty,
    );
    expect(originalAttempts, 1);
    expect(
      await NativeDanmakuPrefetch.importEpisodeToFile(episodeId: 100),
      isNull,
    );
    expect(originalAttempts, 2);
    expect(cache.calls, 0);
    expect(
      (await const DanmakuSettingsStore().load()).sourceStrategy,
      DanmakuSourceStrategy.nasOnly,
    );
  });
  test('仅 NAS 不复用旧自动弹弹play来源', () async {
    await oldAutoSource();
    cache.miss = true;
    expect(await resolve('nasOnly'), isNull);
    expect(cache.calls, 1);
    expect(originalAttempts, 0);
  });
  test('仅 NAS 禁止自动回退与显式在线搜索、导入的弹弹play调用', () async {
    final settings = DanmakuSettings.fromJson({'sourceStrategy': 'nasOnly'});
    await const DanmakuSettingsStore().save(settings);
    cache.miss = true;
    expect(
      await NativeDanmakuPrefetch.resolveToFile(
        seriesTitle: '作品',
        seasonNumber: 1,
        episodeNumber: 1,
        tmdbId: '',
        settings: settings,
        itemGuid: 'item',
        statsScope: PlayStatsService.instance.currentScope,
        nasCache: cache,
        store: store,
      ),
      isNull,
    );
    expect(
      await NativeDanmakuPrefetch.searchCandidates(keyword: '作品'),
      isEmpty,
    );
    expect(
      await NativeDanmakuPrefetch.importEpisodeToFile(episodeId: 100),
      isNull,
    );
    expect(originalAttempts, 0);
  });
  test('NAS 等待期间切换账号会终止旧请求及原来源回退', () async {
    cache.gate = Completer<void>();
    cache.miss = true;
    final pending = resolve('nasPreferred');
    while (cache.calls == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    FlyDataService.instance.session = _session();
    cache.gate!.complete();
    expect(await pending, isNull);
    expect(originalAttempts, 0);
    expect(directory.listSync().whereType<File>(), isEmpty);
  });
  test('后端优先起播只等短预算，播放后查找失败才回退弹弹play', () async {
    final session = FlyDataService.instance.session!;
    final scope = PlayStatsService.instance.currentScope;
    final api = _PendingApi();
    final nas = FlyNasDanmakuCache(
      sessionReader: () => session,
      scopeReader: () => scope,
      bindingReader: () => 'binding',
      apiFactory: (_, _) => api,
      budget: const Duration(milliseconds: 40),
    );
    final elapsed = Stopwatch()..start();
    final path = await NativeDanmakuPrefetch.resolveToFile(
      seriesTitle: '作品',
      seasonNumber: 1,
      episodeNumber: 1,
      tmdbId: '',
      itemGuid: 'item',
      mediaGuid: 'file',
      statsScope: scope,
      nasCache: nas,
      store: store,
      settings: DanmakuSettings.defaults,
    );
    expect(elapsed.elapsedMilliseconds, greaterThanOrEqualTo(35));
    expect(elapsed.elapsedMilliseconds, lessThan(1000));
    expect(api.calls, 1);
    expect(api.closed, isTrue);
    expect(path, isNull);
    expect(originalAttempts, 0);
    api.pending.complete({'status': 'miss'});
    cache.miss = true;
    expect(
      await NativeDanmakuPrefetch.resolveOnPlaybackToFile(
        seriesTitle: '作品',
        seasonNumber: 1,
        episodeNumber: 1,
        tmdbId: '',
        itemGuid: 'item',
        mediaGuid: 'file',
        statsScope: scope,
        settings: DanmakuSettings.defaults,
        nasCache: cache,
        store: store,
      ),
      isNull,
    );
    expect(cache.prepares, 1);
    expect(originalAttempts, 1);
  });
  test('下一集预取不会取消当前播放集正在等待的后台弹幕', () async {
    cache.prepareGate = Completer<void>();
    final scope = PlayStatsService.instance.currentScope;
    final current = NativeDanmakuPrefetch.resolveOnPlaybackToFile(
      seriesTitle: '作品', seasonNumber: 1, episodeNumber: 1, tmdbId: '',
      itemGuid: 'item', mediaGuid: 'file', statsScope: scope,
      settings: DanmakuSettings.defaults, nasCache: cache, store: store,
      isCurrent: () => true,
    );
    expect(cache.prepares, 1);
    final nextCache = _Cache()..miss = true;
    expect(await NativeDanmakuPrefetch.resolveToFile(
      seriesTitle: '作品', seasonNumber: 1, episodeNumber: 2, tmdbId: '',
      itemGuid: 'next-item', mediaGuid: 'next-file', statsScope: scope,
      settings: DanmakuSettings.defaults, nasCache: nextCache, store: store,
      isCurrent: () => true,
    ), isNull);
    cache.prepareGate!.complete();
    final path = await current;
    expect(path, isNotNull);
    final payload = jsonDecode(await File(path!).readAsString()) as Map;
    expect(payload['sourceKey'], 'nas:confirmed');
    expect(payload['commentsCompact'], hasLength(1));
    expect(originalAttempts, 0);
  });
  test('NAS 优先时旧自动 active 不会抢先返回', () async {
    await oldAutoSource();
    final path = await resolve('nasPreferred');
    final payload = jsonDecode(await File(path!).readAsString()) as Map;
    expect(payload['sourceKey'], 'nas:confirmed');
    expect(cache.calls, 1);
  });
  test('已绑定 NAS 策略在 miss 后也不复用缺少账号归属的旧在线 active', () async {
    await oldAutoSource();
    cache.miss = true;
    expect(await resolve('nasPreferred'), isNull);
    expect(cache.calls, 1);
  });
  test('原有来源模式完全跳过 NAS', () async {
    expect(await resolve('original'), isNull);
    expect(cache.calls, 0);
  });
  test('桌面显示来源名称，保留内部身份只用于数据隔离', () async {
    final file = File('${directory.path}/named.json');
    await file.writeAsString(
      jsonEncode({
        'sourceKey': 'nas:internal:3:version',
        'sourceLabel': 'NAS 合并 · 3 个来源',
        'commentsCompact': [
          ['one', 1000, '测试', 0, 0xffffffff],
        ],
      }),
    );
    expect(
      (await DesktopDanmakuPayload.load(file.path)).sourceLabel,
      'NAS 合并 · 3 个来源',
    );
  });
}

class _Cache extends FlyNasDanmakuCache {
  int calls = 0;
  int prepares = 0;
  bool miss = false;
  Completer<void>? gate;
  Completer<void>? prepareGate;
  @override
  Future<bool> prepareOnPlayback({
    required String statsScope,
    required String itemGuid,
    String mediaGuid = '',
    bool refreshExisting = false,
    required bool Function() isCurrent,
  }) async {
    prepares++;
    if (prepareGate != null) await prepareGate!.future;
    return !miss && isCurrent();
  }

  @override
  Future<FlyNasDanmakuResult?> resolve({
    required String statsScope,
    required String itemGuid,
    String mediaGuid = '',
    bool enabled = true,
    bool Function()? isCurrent,
  }) async {
    calls++;
    if (gate != null) await gate!.future;
    if (miss) return null;
    return FlyNasDanmakuResult(
      comments: const [
        DanmakuComment(
          id: 'nas:1',
          timeMs: 1000,
          text: 'NAS 弹幕',
          type: DanmakuCommentType.scroll,
          color: Color(0xffffffff),
        ),
      ],
      sourceKey: 'nas:confirmed',
      isCurrent: isCurrent ?? () => true,
    );
  }
}

class _PriorityApi extends FlyDataApi {
  _PriorityApi(this.events) : super('https://fly.example');
  final List<String> events;
  bool empty = false;
  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    events.add('fly:${path.split('/').last}');
    if (path == '/danmaku/context') {
      return {
        'media_id': 'media',
        'version_key': 'a' * 64,
        'enabled': true,
        'configured': true,
      };
    }
    return {
      'items': [
        {'id': 'bilibili', 'enabled': true, 'configured': true},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> post(String path, Object body) async {
    events.add('fly:search');
    return {
      'items': [
        if (!empty)
          {
            'provider_id': 'bilibili',
            'remote_ref': 'series',
            'title': '作品',
            'kind': 'series',
          },
      ],
    };
  }
}

class _OriginalApi extends DanDanPlayApi {
  _OriginalApi(this.events) : super(appId: 'synthetic', appSecret: 'synthetic');
  final List<String> events;
  @override
  Future<Response<Map<String, dynamic>>> searchEpisodes({
    String anime = '',
    int? episode,
    int? tmdbId,
  }) async {
    events.add('dandan:search');
    return Response(
      requestOptions: RequestOptions(path: '/api/v2/search/episodes'),
      data: {'animes': []},
    );
  }
}

FlyDataSession _session() => FlyDataSession(
  serverUrl: 'https://fly.example',
  userId: 'viewer',
  username: 'viewer',
  deviceId: 'device',
  deviceName: 'test',
  token: 'synthetic',
  installationId: 'installation',
  serviceInstanceId: 'service',
);

class _PendingApi extends FlyDataApi {
  _PendingApi() : super('https://fly.example');
  final pending = Completer<Map<String, dynamic>>();
  int calls = 0;
  bool closed = false;
  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) {
    calls++;
    return pending.future;
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}
