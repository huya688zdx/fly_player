import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/services/play_stats/play_stats_database.dart';
import 'package:fly_player/services/fly_data/fly_data_sync_store.dart';
import 'package:fly_player/services/play_stats/fly_sync_identity.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('new history/write identities are independent UUID v4 values', () {
    final values = List.generate(1000, (_) => newFlySyncId());
    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    expect(values.every(uuid.hasMatch), isTrue);
    expect(values.toSet(), hasLength(values.length));
  });
  late Directory directory;
  late SqflitePlayStatsDatabase store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fly_sync_test_');
    await databaseFactory.setDatabasesPath(directory.path);
    store = SqflitePlayStatsDatabase();
  });

  tearDown(() async {
    await (await store.rawDatabase).close();
    await directory.delete(recursive: true);
  });

  test(
    'schema migration preserves old history and marks legacy ownership unresolved',
    () async {
      final old = await databaseFactory.openDatabase(
        '${directory.path}/play_stats.db',
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE play_history (history_id TEXT PRIMARY KEY, video_id TEXT, title TEXT, started_at_ms INTEGER, ended_at_ms INTEGER, watched_ms INTEGER)',
            );
            await db.insert('play_history', history('history_old'));
          },
        ),
      );
      await old.close();
      final db = await store.rawDatabase;
      expect(await db.getVersion(), 4);
      expect((await db.query('play_history')).single, history('history_old'));
      final provenance = (await db.query('fly_record_provenance')).single;
      expect(provenance['history_id'], 'history_old');
      expect(provenance['record_revision'], 1);
      final datasets = await db.query(
        'fly_datasets',
        where: 'id = ?',
        whereArgs: [provenance['dataset_id']],
      );
      expect(datasets.single['origin_kind'], 'legacy_import');
      expect(datasets.single['confirmed_account'], '');
    },
  );

  test(
    'same-row replacement and metadata enrichment advance persistent revisions atomically',
    () async {
      final db = await store.rawDatabase;
      final row = {...history('one'), 'anime_id': '', 'season_id': ''};
      await db.insert('play_history', row);
      final first = (await db.query('fly_record_provenance')).single;
      await db.insert('play_history', {
        ...row,
        'watched_ms': 20,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await db.update(
        'play_history',
        {'title': 'enriched'},
        where: 'history_id = ?',
        whereArgs: ['one'],
      );
      final updated = (await db.query('fly_record_provenance')).single;
      expect(updated['dataset_id'], first['dataset_id']);
      expect(updated['record_revision'], 3);
      await expectLater(
        db.transaction((txn) async {
          await txn.update('play_history', {'watched_ms': 99});
          throw StateError('rollback');
        }),
        throwsStateError,
      );
      expect(
        (await db.query('fly_record_provenance')).single['record_revision'],
        3,
      );
      expect((await db.query('play_history')).single['watched_ms'], 20);
    },
  );

  test(
    'reopened/restored database preserves old provenance and new writes use a fresh namespace',
    () async {
      final db = await store.rawDatabase;
      await db.insert('play_history', {
        ...history('one'),
        'anime_id': '',
        'season_id': '',
      });
      final first = (await db.query('fly_record_provenance')).single;
      await db.close();
      store = SqflitePlayStatsDatabase();
      final reopened = await store.rawDatabase;
      await reopened.insert('play_history', {
        ...history('two'),
        'anime_id': '',
        'season_id': '',
      });
      final rows = await reopened.query(
        'fly_record_provenance',
        orderBy: 'history_id',
      );
      expect(rows.first['dataset_id'], first['dataset_id']);
      expect(rows.last['dataset_id'], isNot(first['dataset_id']));
    },
  );

  test(
    'unconfirmed history cannot produce a packet and pending retry remains byte-identical',
    () async {
      final db = await store.rawDatabase;
      await db.insert('play_history', {
        ...history('one'),
        'anime_id': '',
        'season_id': '',
      });
      final sync = FlyDataSyncStore(store);
      await expectLater(
        sync.preparePacket(
          accountKey: 'account',
          installationId: 'install',
          streamId: 'stream',
        ),
        throwsStateError,
      );
      await sync.confirmUnlinked('account');
      final packet = await sync.preparePacket(
        accountKey: 'account',
        installationId: 'install',
        streamId: 'stream',
      );
      await db.update('play_history', {'watched_ms': 50});
      final retry = await sync.preparePacket(
        accountKey: 'account',
        installationId: 'install',
        streamId: 'stream',
      );
      expect(retry, packet);
      expect(
        (jsonDecode(retry)['records'] as List)
            .single['legacy_payload']['watched_ms'],
        10,
      );
      await expectLater(
        sync.preparePacket(
          accountKey: 'account',
          installationId: 'other-install',
          streamId: 'other-stream',
        ),
        throwsStateError,
      );
      await expectLater(
        sync.acceptReceipt('account', {
          'status': 'superseded',
          'snapshot_seq': 1,
        }),
        throwsStateError,
      );
      expect((await sync.state('account'))!['pending_json'], packet);
      await sync.acceptReceipt('account', {
        'status': 'applied',
        'snapshot_seq': 1,
        'applied_at_ms': 123,
      });
      final next = jsonDecode(
        await sync.preparePacket(
          accountKey: 'account',
          installationId: 'install',
          streamId: 'stream',
        ),
      );
      expect(next['snapshot_seq'], 2);
      expect(next['records'].single['legacy_payload']['watched_ms'], 50);
    },
  );

  test(
    'adoption preserves imported identity and rejects conflicting old facts atomically',
    () async {
      final db = await store.rawDatabase;
      await db.insert('play_history', {
        ...history('one'),
        'anime_id': '',
        'season_id': '',
      });
      await db.insert('play_history', {
        ...history('two'),
        'anime_id': '',
        'season_id': '',
      });
      final sync = FlyDataSyncStore(store);
      final dataset = {
        'id': 'imported',
        'label': 'WIN01 / S01',
        'origin_kind': 'legacy_import',
        'source_schema_version': 3,
      };
      final remote = {
        'origin_record_id': 'one',
        'record_revision': 7,
        'legacy_payload': history('one'),
        'metadata_snapshot': <String, Object?>{},
        'source_ref': <String, Object?>{},
        'quality_flags': ['legacy_media_delta'],
        'rules_version': 'legacy-v3',
      };
      await expectLater(
        sync.adoptDataset('account', dataset, [
          remote,
          {
            ...remote,
            'origin_record_id': 'two',
            'legacy_payload': {...history('two'), 'watched_ms': 99},
          },
        ]),
        throwsStateError,
      );
      expect(
        await db.query(
          'fly_datasets',
          where: 'id = ?',
          whereArgs: ['imported'],
        ),
        isEmpty,
      );
      expect(await sync.adoptDataset('account', dataset, [remote]), 1);
      await sync.confirmUnlinked('account');
      final packet = jsonDecode(
        await sync.preparePacket(
          accountKey: 'account',
          installationId: 'install',
          streamId: 'stream',
        ),
      );
      final adopted = (packet['records'] as List).firstWhere(
        (row) => row['origin_record_id'] == 'one',
      );
      expect(adopted['origin_dataset_id'], 'imported');
      expect(adopted['record_revision'], 8);
    },
  );

  test(
    'explicit adoption retains known server tombstone identity instead of assigning a fresh origin',
    () async {
      final db = await store.rawDatabase;
      await db.insert('play_history', {
        ...history('deleted-old'),
        'anime_id': '',
        'season_id': '',
      });
      final sync = FlyDataSyncStore(store);
      await sync.adoptDataset(
        'account',
        {
          'id': 'original-import',
          'label': 'WIN01 / S01',
          'origin_kind': 'legacy_import',
        },
        [
          {'origin_record_id': 'deleted-old', 'tombstoned': true},
        ],
      );
      final packet = jsonDecode(
        await sync.preparePacket(
          accountKey: 'account',
          installationId: 'install',
          streamId: 'stream',
        ),
      );
      expect(packet['records'].single['origin_dataset_id'], 'original-import');
      expect(packet['records'].single['origin_record_id'], 'deleted-old');
      expect(packet['records'].single.containsKey('wall_watch_ms'), isFalse);
    },
  );

  test(
    'adoption watermark covers remote revisions and local schema enrichment',
    () async {
      final db = await store.rawDatabase;
      await db.insert('play_history', {
        ...history('old'),
        'anime_id': '',
        'season_id': '',
      });
      final sync = FlyDataSyncStore(store);
      await sync.adoptDataset(
        'account',
        {
          'id': 'imported',
          'label': 'old import',
          'origin_kind': 'legacy_import',
          'export_revision_watermark': 10,
          'deletion_generation': 0,
        },
        [
          {
            'origin_record_id': 'old',
            'record_revision': 10,
            'legacy_payload': history('old'),
          },
        ],
      );
      final packet = jsonDecode(
        await sync.preparePacket(
          accountKey: 'account',
          installationId: 'install',
          streamId: 'stream',
        ),
      );
      expect(packet['records'].single['record_revision'], 11);
      expect(
        packet['manifest']['datasets'].single['export_revision_watermark'],
        greaterThanOrEqualTo(11),
      );
    },
  );
  test(
    'colliding legacy database filenames cannot rebind or retry another media scope',
    () async {
      await store.bindOwnerScope('media-a');
      final firstDb = await store.rawDatabase;
      await firstDb.insert('play_history', {
        ...history('old'),
        'anime_id': '',
        'season_id': '',
      });
      final first = FlyDataSyncStore(store);
      await first.confirmUnlinked('account');
      final pending = await first.preparePacket(
        accountKey: 'account',
        installationId: 'install',
        streamId: 'stream',
      );
      final firstPath = firstDb.path;
      await store.bindOwnerScope('media_a');
      expect((await store.rawDatabase).path, firstPath);
      final other = FlyDataSyncStore(store);
      final wrongScope = isA<StateError>().having(
        (error) => error.message,
        'scope explanation',
        contains('其他媒体帐号'),
      );
      await expectLater(
        other.preparePacket(
          accountKey: 'account',
          installationId: 'install',
          streamId: 'stream',
        ),
        throwsA(wrongScope),
      );
      await expectLater(other.confirmUnlinked('account'), throwsA(wrongScope));
      await expectLater(
        other.adoptDataset('account', {'id': 'remote', 'label': 'remote'}, []),
        throwsA(wrongScope),
      );
      expect((await other.state('account'))!['pending_json'], pending);
    },
  );
}

Map<String, Object?> history(String id) => {
  'history_id': id,
  'video_id': 'v1',
  'title': 'Example',
  'started_at_ms': 1,
  'ended_at_ms': 100,
  'watched_ms': 10,
};
