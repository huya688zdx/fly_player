import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fly_player/danmaku/models/danmaku_comment.dart';
import 'package:fly_player/danmaku/models/danmaku_settings.dart';
import 'package:fly_player/services/fly_data/fly_nas_danmaku_cache.dart';
import 'package:fly_player/services/fly_data/fly_data_service.dart';
import 'package:fly_player/services/play_stats/play_stats_service.dart';
import 'package:fly_player/services/play_stats/play_stats_database.dart';
import 'package:fly_player/services/native_danmaku_prefetch.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _Cache cache;
  var originalCalls = 0;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final session = FlyDataSession(
      serverUrl: 'https://fly.example',
      userId: 'viewer',
      username: 'viewer',
      deviceId: 'device',
      deviceName: 'test',
      token: 'synthetic',
      installationId: 'installation',
      serviceInstanceId: 'service',
    );
    FlyDataService.instance.session = session;
    await PlayStatsService.instance.bindOwnerScope(
      PlayStatsService.scopeForBinding(session.accountKey, 'binding'),
    );
    (PlayStatsService.instance.database as SqflitePlayStatsDatabase)
        .bindingReference = {
      'binding_id': 'binding',
    };
    directory = await Directory.systemTemp.createTemp('service_refresh_');
    NativeDanmakuPrefetch.cacheRootOverrideForTest = directory.path;
    originalCalls = 0;
    NativeDanmakuPrefetch.originalConfiguredOverrideForTest = () async {
      originalCalls++;
      return false;
    };
    cache = _Cache();
  });
  tearDown(() async {
    NativeDanmakuPrefetch.cacheRootOverrideForTest = null;
    NativeDanmakuPrefetch.originalConfiguredOverrideForTest = null;
    FlyDataService.instance.session = null;
    await PlayStatsService.instance.bindOwnerScope('');
    await directory.delete(recursive: true);
  });
  Future<String?> refresh({bool Function()? current, String? scope}) =>
      NativeDanmakuPrefetch.resolveNasToFile(
        seriesTitle: 'series',
        seasonNumber: 1,
        episodeNumber: 2,
        tmdbId: '',
        itemGuid: 'episode',
        mediaGuid: 'file',
        statsScope: scope ?? PlayStatsService.instance.currentScope,
        // Manual source selection also works while the overlay is disabled.
        settings: DanmakuSettings.defaults.copyWith(
          enabled: false,
          sourceStrategy: DanmakuSourceStrategy.original,
        ),
        nasCache: cache,
        isCurrent: current,
      );

  test(
    'manual service selection returns current file payload without changing overlay preference',
    () async {
      final path = await refresh();
      final payload = jsonDecode(await File(path!).readAsString()) as Map;
      expect(payload['sourceLabel'], '服务弹幕');
      expect(payload['sourceKey'], 'nas:match:1:version');
      expect(payload['enabled'], false);
      expect(payload['commentsCompact'], hasLength(1));
      expect(cache.source, (
        PlayStatsService.instance.currentScope,
        'episode',
        'file',
      ));
      expect(originalCalls, 0);
    },
  );
  test(
    'empty cache does not invoke original online matching or write a payload',
    () async {
      cache.missing = true;
      expect(await refresh(), isNull);
      expect(originalCalls, 0);
      expect(directory.listSync(), isEmpty);
    },
  );
  test('missing scope or invalid request cannot read service cache', () async {
    expect(await refresh(scope: ''), isNull);
    expect(await refresh(current: () => false), isNull);
    (PlayStatsService.instance.database as SqflitePlayStatsDatabase)
            .bindingReference =
        {};
    expect(await refresh(), isNull);
    await PlayStatsService.instance.bindOwnerScope('');
    expect(FlyDataService.instance.session, isNotNull);
    expect(await refresh(scope: 'retained-fly-scope'), isNull);
    expect(cache.calls, 0);
  });
  test(
    'account or media invalidation during cache read drops late payload',
    () async {
      cache.pending = Completer<void>();
      var current = true;
      final pending = refresh(current: () => current);
      current = false;
      cache.pending!.complete();
      expect(await pending, isNull);
      expect(directory.listSync(), isEmpty);
    },
  );
  test('new service selection supersedes earlier request', () async {
    cache.pending = Completer<void>();
    final old = refresh();
    final completer = cache.pending!;
    cache.pending = null;
    expect(await refresh(), isNotNull);
    completer.complete();
    expect(await old, isNull);
    expect(directory.listSync().whereType<File>(), hasLength(1));
  });
}

class _Cache extends FlyNasDanmakuCache {
  int calls = 0;
  bool missing = false;
  Completer<void>? pending;
  (String, String, String)? source;
  @override
  Future<FlyNasDanmakuResult?> resolve({
    required String statsScope,
    required String itemGuid,
    String mediaGuid = '',
    bool enabled = true,
    bool Function()? isCurrent,
  }) async {
    calls++;
    source = (statsScope, itemGuid, mediaGuid);
    if (pending != null) await pending!.future;
    if (missing) return null;
    return FlyNasDanmakuResult(
      sourceKey: 'nas:match:1:version',
      isCurrent: isCurrent ?? () => true,
      comments: const [
        DanmakuComment(
          id: 'id',
          timeMs: 1000,
          text: 'comment',
          type: DanmakuCommentType.scroll,
          color: Color(0xffffffff),
        ),
      ],
    );
  }
}
