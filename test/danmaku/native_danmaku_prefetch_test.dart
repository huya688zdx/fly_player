import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/danmaku/models/danmaku_saved_source.dart';
import 'package:fly_player/danmaku/models/danmaku_settings.dart';
import 'package:fly_player/danmaku/settings/danmaku_saved_source_store.dart';
import 'package:fly_player/services/native_danmaku_prefetch.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory cacheDir;
  late DanmakuSavedSourceStore store;
  var secretChannelCalls = 0;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('danmaku_prefetch_store_');
    cacheDir = await Directory.systemTemp.createTemp('danmaku_prefetch_cache_');
    NativeDanmakuPrefetch.cacheRootOverrideForTest = cacheDir.path;
    store = DanmakuSavedSourceStore(directoryPath: tempDir.path);
    secretChannelCalls = 0;
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    // 测试环境非 Android，DanDanPlayConfig.ensureLoaded 不会真正走平台通道；这里仍挂
    // mock 作为「未配置凭据」的兜底答案，并用计数器断言本地新鲜路径完全不触碰凭据。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('fly_player/secret_store'),
          (call) async {
            if (call.method == 'getDanDanPlayConfig') {
              secretChannelCalls++;
              return <String, Object>{
                'configured': false,
                'appId': '',
                'appSecrets': <String>[],
                'statusCode': 'missing_build_credentials',
              };
            }
            return null;
          },
        );
  });

  tearDown(() async {
    NativeDanmakuPrefetch.cacheRootOverrideForTest = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('fly_player/secret_store'),
          null,
        );
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    if (await cacheDir.exists()) await cacheDir.delete(recursive: true);
  });

  test('弹幕总开关关闭时不做任何解析', () async {
    final xml = await _writeDanmakuXml(tempDir, 'ep1.xml');
    await _seedDownloadedSource(
      store,
      filePath: xml.path,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    final path = await NativeDanmakuPrefetch.resolveToFile(
      seriesTitle: '测试动画',
      itemTitle: '第1话',
      seasonNumber: 1,
      episodeNumber: 1,
      tmdbId: '',
      settings: DanmakuSettings.defaults.copyWith(enabled: false),
      itemGuid: 'item-1',
      mediaGuid: 'media-1',
      store: store,
    );

    expect(path, isNull);
  });

  test('随片下载源新鲜时直接本地起播，不触发在线凭据解析', () async {
    final xml = await _writeDanmakuXml(tempDir, 'ep1.xml');
    await _seedDownloadedSource(
      store,
      filePath: xml.path,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    final path = await NativeDanmakuPrefetch.resolveToFile(
      seriesTitle: '测试动画',
      itemTitle: '第1话',
      seasonNumber: 1,
      episodeNumber: 1,
      tmdbId: '',
      settings: DanmakuSettings.defaults,
      itemGuid: 'item-1',
      mediaGuid: 'media-1',
      store: store,
    );

    expect(path, isNotNull);
    expect(File(path!).existsSync(), isTrue);
    expect(secretChannelCalls, 0);
  });

  test('随片下载源过期且回源不可用时，仍落回本地旧弹幕且不写入屏蔽标记', () async {
    final xml = await _writeDanmakuXml(tempDir, 'ep1.xml');
    await _seedDownloadedSource(
      store,
      filePath: xml.path,
      updatedAtMs:
          DateTime.now().millisecondsSinceEpoch -
          const Duration(hours: 49).inMilliseconds,
    );

    final path = await NativeDanmakuPrefetch.resolveToFile(
      seriesTitle: '测试动画',
      itemTitle: '第1话',
      seasonNumber: 1,
      episodeNumber: 1,
      tmdbId: '',
      settings: DanmakuSettings.defaults,
      itemGuid: 'item-1',
      mediaGuid: 'media-1',
      store: store,
    );

    expect(path, isNotNull);
    expect(File(path!).existsSync(), isTrue);
    // 回源失败（未配置凭据）不能顺手写成「无结果」屏蔽标记，否则网络恢复后 6h 内也无法重试。
    expect(await store.loadAutoMatchBlockedReason(_mediaKey), isNull);
  });

  test('随片下载源本地文件缺失且在线不可用时安全返回无弹幕', () async {
    await _seedDownloadedSource(
      store,
      filePath: '${tempDir.path}/missing.xml',
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    final path = await NativeDanmakuPrefetch.resolveToFile(
      seriesTitle: '测试动画',
      itemTitle: '第1话',
      seasonNumber: 1,
      episodeNumber: 1,
      tmdbId: '',
      settings: DanmakuSettings.defaults,
      itemGuid: 'item-1',
      mediaGuid: 'media-1',
      store: store,
    );

    expect(path, isNull);
  });

  test('激活的弹弹play源命中新鲜评论缓存时直接使用，不联网', () async {
    await store.saveSource(_danDanPlaySource('dandan:10001'), activate: true);
    final cacheFile = await _seedCommentCache(
      cacheDir,
      'dandan:10001',
      modifiedAt: DateTime.now(),
    );

    final path = await NativeDanmakuPrefetch.resolveToFile(
      seriesTitle: '测试动画',
      itemTitle: '第1话',
      seasonNumber: 1,
      episodeNumber: 1,
      tmdbId: '',
      settings: DanmakuSettings.defaults,
      itemGuid: 'item-1',
      mediaGuid: 'media-1',
      store: store,
    );

    expect(path, isNotNull);
    expect(secretChannelCalls, 0);
    expect(await cacheFile.exists(), isTrue);
  });

  test('激活源缓存过期且回源失败时，落回过期缓存且缓存文件不被删除', () async {
    await store.saveSource(_danDanPlaySource('dandan:10002'), activate: true);
    final cacheFile = await _seedCommentCache(
      cacheDir,
      'dandan:10002',
      modifiedAt: DateTime.now().subtract(const Duration(hours: 7)),
    );

    final path = await NativeDanmakuPrefetch.resolveToFile(
      seriesTitle: '测试动画',
      itemTitle: '第1话',
      seasonNumber: 1,
      episodeNumber: 1,
      tmdbId: '',
      settings: DanmakuSettings.defaults,
      itemGuid: 'item-1',
      mediaGuid: 'media-1',
      store: store,
    );

    expect(path, isNotNull);
    // 过期缓存必须保留：它是回源失败时离线兜底的唯一来源。
    expect(await cacheFile.exists(), isTrue);
  });
}

/// 与 `NativeDanmakuPrefetch._buildMediaKey` 的 v2 规则保持一致（兼容性契约）。
String get _mediaKey => <String>[
  'v2',
  'item=item-1',
  'media=media-1',
  'season=',
  's=1',
  'e=1',
].join('|');

Future<File> _writeDanmakuXml(Directory dir, String fileName) async {
  final file = File('${dir.path}/$fileName');
  await file.writeAsString(
    '<i>'
    '<d p="1.0,1,25,16777215,0,0,0,1">弹幕一</d>'
    '<d p="2.0,1,25,16777215,0,0,0,2">弹幕二</d>'
    '</i>',
  );
  return file;
}

Future<void> _seedDownloadedSource(
  DanmakuSavedSourceStore store, {
  required String filePath,
  required int updatedAtMs,
}) async {
  await store.saveSource(
    DanmakuSavedSource(
      type: DanmakuSavedSourceType.downloadedFile,
      mediaKey: _mediaKey,
      sourceKey: filePath,
      label: '随片弹幕.xml',
      detail: filePath,
      seriesTitle: '测试动画',
      itemTitle: '第1话',
      itemGuid: 'item-1',
      mediaGuid: 'media-1',
      seasonNumber: 1,
      episodeNumber: 1,
      commentCount: 2,
      updatedAtMs: updatedAtMs,
    ),
  );
}

DanmakuSavedSource _danDanPlaySource(String sourceKey) {
  return DanmakuSavedSource(
    type: DanmakuSavedSourceType.danDanPlay,
    mediaKey: _mediaKey,
    sourceKey: sourceKey,
    label: '测试动画 第1话',
    seriesTitle: '测试动画',
    itemTitle: '第1话',
    itemGuid: 'item-1',
    mediaGuid: 'media-1',
    seasonNumber: 1,
    episodeNumber: 1,
    commentCount: 2,
    updatedAtMs: 1,
  );
}

/// 预置一条评论缓存（格式对齐 `NativeDanmakuPrefetch._cacheComments`）。
Future<File> _seedCommentCache(
  Directory cacheDir,
  String sourceKey, {
  required DateTime modifiedAt,
}) async {
  final safeKey = sourceKey.hashCode.toUnsigned(32).toRadixString(16);
  final file = File('${cacheDir.path}/native_danmaku_cache_$safeKey.json');
  await file.writeAsString(
    jsonEncode([
      <Object?>['c1', 1000, '弹幕一', 0, 0xFFFFFFFF],
      <Object?>['c2', 2000, '弹幕二', 1, 0xFF00FF00],
    ]),
  );
  await file.setLastModified(modifiedAt);
  return file;
}
