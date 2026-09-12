import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fly_player/danmaku/models/danmaku_comment.dart';
import 'package:fly_player/danmaku/models/danmaku_settings.dart';
import 'package:fly_player/danmaku/settings/danmaku_saved_source_store.dart';
import 'package:fly_player/services/fly_data/fly_nas_danmaku_cache.dart';
import 'package:fly_player/services/native_danmaku_prefetch.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late DanmakuSavedSourceStore store;
  late _Cache cache;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('fly_nas_danmaku_test_');
    await Directory('${directory.path}/sources').create();
    NativeDanmakuPrefetch.cacheRootOverrideForTest = directory.path;
    store = DanmakuSavedSourceStore(directoryPath: '${directory.path}/sources');
    cache = _Cache();
  });
  tearDown(() async {
    NativeDanmakuPrefetch.cacheRootOverrideForTest = null;
    await directory.delete(recursive: true);
  });
  Future<String?> resolve({bool enabled = true, bool Function()? current}) =>
      NativeDanmakuPrefetch.resolveToFile(
        seriesTitle: '',
        seasonNumber: 1,
        episodeNumber: 1,
        tmdbId: '',
        itemGuid: 'item',
        mediaGuid: 'file',
        statsScope: 'captured',
        nasCache: cache,
        isCurrent: current,
        settings: DanmakuSettings.defaults.copyWith(enabled: enabled),
        store: store,
      );

  test('ready NAS 转成原播放器 payload，保留设置与已调整时间', () async {
    final path = await resolve();
    expect(path, isNotNull);
    final payload = jsonDecode(await File(path!).readAsString()) as Map;
    expect(payload['sourceKey'], 'nas:confirmed');
    expect(payload['commentsCompact'], [
      ['nas:1', 1250, '已确认', 0, 0xffffffff],
    ]);
    expect(payload['opacity'], DanmakuSettings.defaults.opacity);
    expect(cache.source, ('captured', 'item', 'file'));
  });

  test('关闭与失效的播放请求不写 NAS 文件', () async {
    expect(await resolve(enabled: false), isNull);
    expect(cache.calls, 0);
    expect(await resolve(current: () => false), isNull);
    expect(directory.listSync().whereType<File>(), isEmpty);
  });

  test('NAS miss 时保留原链和已有自动匹配屏蔽记录', () async {
    cache.miss = true;
    const key = 'v2|item=item|media=file|season=|s=1|e=1';
    await store.saveAutoMatchBlockedReason(mediaKey: key, reason: 'previous');
    expect(await resolve(), isNull);
    expect(cache.calls, 1);
    expect(await store.loadAutoMatchBlockedReason(key), 'previous');
  });
}

class _Cache extends FlyNasDanmakuCache {
  int calls = 0;
  bool miss = false;
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
    if (miss || !(isCurrent?.call() ?? true)) return null;
    return FlyNasDanmakuResult(
      sourceKey: 'nas:confirmed',
      isCurrent: isCurrent ?? () => true,
      comments: const [
        DanmakuComment(
          id: 'nas:1',
          timeMs: 1250,
          text: '已确认',
          type: DanmakuCommentType.scroll,
          color: Color(0xffffffff),
        ),
      ],
    );
  }
}
