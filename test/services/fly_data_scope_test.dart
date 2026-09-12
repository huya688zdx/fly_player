import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/services/play_stats/native_play_stats_recorder.dart';
import 'package:fly_player/services/play_stats/play_stats_service.dart';
import 'package:fly_player/services/fly_data/fly_data_sync_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'confirmed Emby binding stamps facts and ignores late samples after switch',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fly_binding_stats_',
      );
      await databaseFactory.setDatabasesPath(directory.path);
      final service = PlayStatsService.instance;
      final recorder = NativePlayStatsRecorder();
      try {
        await service.bindMediaBinding(
          accountKey: 'instance|alice',
          bindingId: 'emby-a',
          backendKind: 'emby',
        );
        final oldScope = service.currentScope;
        final db = await service.database.rawDatabase;
        await recorder.onLaunch({
          'itemGuid': 'episode',
          'title': 'Emby episode',
          'statsScope': oldScope,
          'durationSeconds': 100,
        });
        await recorder.onProgress({
          'itemGuid': 'episode',
          'statsScope': oldScope,
          'ts': 0,
          'duration': 100,
        });
        await recorder.onProgress({
          'itemGuid': 'episode',
          'statsScope': oldScope,
          'ts': 2,
          'duration': 100,
        });
        await service.drainForManualSync();
        final envelope = jsonDecode(
          (await db.query('fly_record_provenance')).single['envelope_json']
              as String,
        );
        expect(envelope['source_ref'], containsPair('binding_id', 'emby-a'));
        expect(envelope['source_ref'], containsPair('backend_kind', 'emby'));
        expect(
          envelope['source_ref'],
          containsPair('remote_item_id', 'episode'),
        );
        final packet = await FlyDataSyncStore(service.database).preparePacket(
          accountKey: 'instance|alice',
          installationId: 'device',
          streamId: 'stream',
        );
        expect(jsonDecode(packet)['records'], hasLength(1));
        await service.bindMediaBinding(
          accountKey: 'instance|alice',
          bindingId: 'emby-b',
          backendKind: 'emby',
        );
        final nextScope = service.currentScope;
        await recorder.onLaunch({
          'itemGuid': 'episode',
          'statsScope': nextScope,
          'title': 'B same ID',
          'durationSeconds': 100,
        });
        await recorder.onProgress({
          'itemGuid': 'episode',
          'statsScope': nextScope,
          'ts': 0,
          'duration': 100,
        });
        await recorder.onProgress({
          'itemGuid': 'episode',
          'statsScope': nextScope,
          'ts': 1,
          'duration': 100,
        });
        await service.drainForManualSync();
        final nextDb = await service.database.rawDatabase;
        final before = (await nextDb.query(
          'play_history',
        )).single['watched_ms'];
        await recorder.onLaunch({
          'itemGuid': 'episode',
          'statsScope': oldScope,
          'startPositionMs': 90000,
          'durationSeconds': 100,
        });
        await recorder.onProgress({
          'itemGuid': 'episode',
          'statsScope': oldScope,
          'ts': 2,
          'duration': 100,
        });
        await recorder.onProgress({
          'itemGuid': 'episode',
          'ts': 3,
          'duration': 100,
        });
        await service.drainForManualSync();
        expect(await nextDb.query('play_history'), hasLength(1));
        expect(
          (await nextDb.query('play_history')).single['watched_ms'],
          before,
        );
      } finally {
        recorder.dispose();
        await service.bindOwnerScope('closed-binding');
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'an old desktop recorder exit cannot finish a different binding session',
    () async {
      final directory = await Directory.systemTemp.createTemp('fly_old_exit_');
      await databaseFactory.setDatabasesPath(directory.path);
      final service = PlayStatsService.instance;
      final old = NativePlayStatsRecorder(),
          current = NativePlayStatsRecorder();
      try {
        await service.bindMediaBinding(
          accountKey: 'instance|alice',
          bindingId: 'a',
          backendKind: 'emby',
        );
        await old.onLaunch({
          'itemGuid': 'same',
          'statsScope': service.currentScope,
          'durationSeconds': 100,
        });
        await service.bindMediaBinding(
          accountKey: 'instance|alice',
          bindingId: 'b',
          backendKind: 'emby',
        );
        final scope = service.currentScope;
        await current.onLaunch({
          'itemGuid': 'same',
          'statsScope': scope,
          'durationSeconds': 100,
        });
        await current.onProgress({
          'itemGuid': 'same',
          'statsScope': scope,
          'ts': 0,
          'duration': 100,
        });
        await current.onProgress({
          'itemGuid': 'same',
          'statsScope': scope,
          'ts': 1,
          'duration': 100,
        });
        await old.finishPlayback();
        await current.onProgress({
          'itemGuid': 'same',
          'statsScope': scope,
          'ts': 2,
          'duration': 100,
        });
        await service.drainForManualSync();
        expect(
          (await (await service.database.rawDatabase).query(
            'play_history',
          )).single['watched_ms'],
          2000,
        );
      } finally {
        old.dispose();
        current.dispose();
        await service.bindOwnerScope('closed-old-exit');
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'account switch drains active local recording into original statistics scope',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fly_scope_test_',
      );
      await databaseFactory.setDatabasesPath(directory.path);
      final service = PlayStatsService.instance;
      final recorder = NativePlayStatsRecorder();
      await service.bindOwnerScope('scope-a');
      final oldPath = (await service.database.rawDatabase).path;
      try {
        await recorder.onLaunch({
          'itemGuid': 'movie-a',
          'title': 'old account movie',
          'mediaType': 'movie',
          'durationSeconds': 100,
        });
        for (var second = 0; second <= 2; second++) {
          await recorder.onProgress({
            'itemGuid': 'movie-a',
            'ts': second,
            'duration': 100,
            'isPaused': false,
          });
        }
        await service.bindOwnerScope('scope-b');
        final old = await databaseFactory.openDatabase(oldPath);
        try {
          expect(await old.query('play_history'), hasLength(1));
          expect(
            (await old.query('play_history')).single['title'],
            'old account movie',
          );
          expect(
            (await old.query(
              'fly_record_provenance',
            )).single['record_revision'],
            1,
          );
        } finally {
          await old.close();
        }
        final next = await service.database.rawDatabase;
        expect(await next.query('play_history'), isEmpty);
        expect(await next.query('fly_record_provenance'), isEmpty);
        await service.drainForManualSync();
        expect(await next.query('play_history'), isEmpty);
      } finally {
        recorder.dispose();
        await service.bindOwnerScope('closed');
        await directory.delete(recursive: true);
      }
    },
  );
}
