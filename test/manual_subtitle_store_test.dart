import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/services/manual_subtitle_store.dart';
import 'package:fly_player/utils/manual_subtitle_tracks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const store = ManualSubtitleStore();

  ManualSubtitleEntry entry({
    String guid = 'local:sub:11111111-2222-3333-4444-555555555555',
    String mediaGuid = 'media-1',
    String itemGuid = 'episode-1',
    String fileName = 'demo.sup',
    String path = '/data/subtitles/abc.sup',
    String format = 'sup',
    int importedAtMs = 1000,
  }) {
    return ManualSubtitleEntry(
      guid: guid,
      mediaGuid: mediaGuid,
      itemGuid: itemGuid,
      fileName: fileName,
      // 真实场景文件名是 UUID 不会撞；测试里默认 path 固定会触发按 path 去重误伤，
      // 这里让 path 随 guid 派生，贴合真实且避免误删。
      path: guid.startsWith('local:sub:') && path == '/data/subtitles/abc.sup'
          ? '/data/subtitles/${guid.substring(9)}.sup'
          : path,
      format: format,
      importedAtMs: importedAtMs,
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('add then loadForMedia returns entries for that media only', () async {
    await store.add(
      entry(guid: 'local:sub:a', mediaGuid: 'media-1', importedAtMs: 1000),
    );
    await store.add(
      entry(guid: 'local:sub:b', mediaGuid: 'media-2', importedAtMs: 2000),
    );

    final media1 = await store.loadForMedia('media-1');
    final media2 = await store.loadForMedia('media-2');
    expect(media1, hasLength(1));
    expect(media1.single.guid, 'local:sub:a');
    expect(media2, hasLength(1));
    expect(media2.single.guid, 'local:sub:b');
  });

  test('add with same path replaces existing entry (dedupe by path)', () async {
    await store.add(
      entry(guid: 'local:sub:old', path: '/data/subtitles/x.sup'),
    );
    await store.add(
      entry(
        guid: 'local:sub:new',
        path: '/data/subtitles/x.sup',
        importedAtMs: 2000,
      ),
    );

    final all = await store.loadAll();
    expect(all, hasLength(1));
    expect(all.single.guid, 'local:sub:new');
  });

  test('同一路径重新导入时清除旧 GUID 的选择记录', () async {
    const oldGuid = 'local:sub:old';
    await store.add(entry(guid: oldGuid, path: '/data/subtitles/x.sup'));
    await store.setSelectedGuid(
      itemGuid: 'episode-1',
      mediaGuid: 'media-1',
      guid: oldGuid,
    );

    await store.add(
      entry(
        guid: 'local:sub:new',
        path: '/data/subtitles/x.sup',
        importedAtMs: 2000,
      ),
    );

    expect(
      await store.selectedGuidForItem('episode-1', mediaGuid: 'media-1'),
      isNull,
    );
  });

  test('removeByGuid returns removed entry and drops from store', () async {
    await store.add(entry(guid: 'local:sub:del'));
    await store.add(entry(guid: 'local:sub:keep'));

    final removed = await store.removeByGuid('local:sub:del');
    expect(removed, isNotNull);
    expect(removed!.guid, 'local:sub:del');
    expect(removed.path, '/data/subtitles/:del.sup');

    final all = await store.loadAll();
    expect(all, hasLength(1));
    expect(all.single.guid, 'local:sub:keep');
  });

  test('removeByGuid returns null for missing guid', () async {
    final removed = await store.removeByGuid('local:sub:missing');
    expect(removed, isNull);
  });

  test('removeAllForMedia removes only that media entries', () async {
    await store.add(entry(guid: 'local:sub:a', mediaGuid: 'media-1'));
    await store.add(entry(guid: 'local:sub:b', mediaGuid: 'media-1'));
    await store.add(entry(guid: 'local:sub:c', mediaGuid: 'media-2'));

    final removed = await store.removeAllForMedia('media-1');
    expect(removed, hasLength(2));
    final all = await store.loadAll();
    expect(all, hasLength(1));
    expect(all.single.guid, 'local:sub:c');
  });

  test('isBitmap derived from format', () {
    expect(entry(format: 'sup').isBitmap, isTrue);
    expect(entry(format: 'pgs').isBitmap, isTrue);
    expect(entry(format: 'srt').isBitmap, isFalse);
    expect(entry(format: 'ass').isBitmap, isFalse);
  });

  test('读取 Kotlin 旧数组并按 itemGuid 优先匹配', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      ManualSubtitleStore.prefKey: jsonEncode(<Object?>[
        entry(
          guid: 'local:sub:srt',
          mediaGuid: 'media-old',
          itemGuid: 'episode-1',
          fileName: 'episode.srt',
          format: 'srt',
        ).toJson(),
      ]),
    });

    final entries = await store.loadForItem(
      'episode-1',
      mediaGuid: 'media-new',
    );

    expect(entries.single.guid, 'local:sub:srt');
  });

  test('读取 selectedByScope 中同一集最后选择', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      ManualSubtitleStore.prefKey: jsonEncode(<String, Object?>{
        'version': 2,
        'entries': <Object?>[
          entry(guid: 'local:sub:sup', itemGuid: 'episode-1').toJson(),
        ],
        'selectedByScope': <String, String>{'item:episode-1': 'local:sub:sup'},
      }),
    });

    expect(
      await store.selectedGuidForItem('episode-1', mediaGuid: 'media-1'),
      'local:sub:sup',
    );
  });

  test('详情页轨道映射同时展示 SRT、SUP 与 PGS', () {
    final tracks =
        manualSubtitleTracksForMedia('media-new', <ManualSubtitleEntry>[
          entry(guid: 'local:sub:srt', fileName: 'episode.srt', format: 'srt'),
          entry(guid: 'local:sub:sup', fileName: 'episode.sup', format: 'sup'),
          entry(guid: 'local:sub:pgs', fileName: 'episode.pgs', format: 'pgs'),
        ]);

    expect(tracks.map((track) => track.guid), <String>[
      'local:sub:srt',
      'local:sub:sup',
      'local:sub:pgs',
    ]);
    expect(tracks.map((track) => track.isBitmap), <int>[0, 1, 1]);
    expect(tracks.every((track) => track.mediaGuid == 'media-new'), isTrue);
  });

  for (final format in <String>['srt', 'sup', 'pgs']) {
    test('deleteByGuid 清理 $format 文件、元数据和选择', () async {
      final dir = Directory.systemTemp.createTempSync(
        'manual_subtitle_delete_$format',
      );
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final path = '${dir.path}${Platform.pathSeparator}episode.$format';
      File(path).writeAsBytesSync(<int>[0x50, 0x47]);
      final guid = 'local:sub:$format';
      await store.add(
        entry(
          guid: guid,
          itemGuid: 'episode-1',
          fileName: 'episode.$format',
          path: path,
          format: format,
        ),
      );
      await store.setSelectedGuid(
        itemGuid: 'episode-1',
        mediaGuid: 'media-1',
        guid: guid,
      );

      expect(await store.deleteByGuid(guid), isTrue);
      expect(File(path).existsSync(), isFalse);
      expect(await store.loadAll(), isEmpty);
      expect(
        await store.selectedGuidForItem('episode-1', mediaGuid: 'media-1'),
        isNull,
      );
    });
  }

  test('文件删除失败时保留 PGS 元数据和选择', () async {
    const guid = 'local:sub:pgs-failed';
    await store.add(
      entry(
        guid: guid,
        itemGuid: 'episode-1',
        fileName: 'failed.pgs',
        path: '/data/subtitles/failed.pgs',
        format: 'pgs',
      ),
    );
    await store.setSelectedGuid(
      itemGuid: 'episode-1',
      mediaGuid: 'media-1',
      guid: guid,
    );

    expect(
      await store.deleteByGuid(guid, deleteFile: (_) async => false),
      isFalse,
    );
    expect((await store.loadAll()).single.guid, guid);
    expect(
      await store.selectedGuidForItem('episode-1', mediaGuid: 'media-1'),
      guid,
    );
  });

  test('revision notifies on mutation', () async {
    var notified = 0;
    void listener() => notified++;
    store.revision.addListener(listener);
    addTearDown(() => store.revision.removeListener(listener));
    await store.add(entry(guid: 'local:sub:r1'));
    await store.removeByGuid('local:sub:r1');
    expect(notified, 2);
  });
}
