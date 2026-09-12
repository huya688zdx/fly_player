import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../play_stats/play_stats_database.dart';

/// Durable, account-scoped sync packets live alongside the source facts so a
/// failed request or app restart cannot change the bytes for an existing seq.
class FlyNoFactsToSync extends StateError {
  FlyNoFactsToSync() : super('当前范围没有可同步的播放历史。');
}

class FlyDataSyncStore {
  FlyDataSyncStore(this.database)
    : _scopeDigest = _digest(
        database is SqflitePlayStatsDatabase ? database.ownerScope : '',
      );
  FlyDataSyncStore.fromDatabase(Database db, {required String ownerScope})
    : database = _PinnedDatabase(db),
      _scopeDigest = _digest(ownerScope);
  final PlayStatsDatabase database;
  final String _scopeDigest;

  static String _digest(String ownerScope) =>
      sha256.convert(utf8.encode(ownerScope.trim().toLowerCase())).toString();

  Future<void> _checkScopeBinding(
    DatabaseExecutor txn, {
    bool confirm = false,
  }) async {
    final rows = await txn.query('fly_scope_binding', where: 'id=1');
    if (rows.isNotEmpty) {
      if (rows.single['scope_digest'] != _scopeDigest) {
        throw StateError(
          '这个本地统计文件曾在其他媒体帐号范围下确认，已阻止关联和上传。旧版文件名可能重合，请先核对历史归属；不能覆盖原范围绑定。',
        );
      }
      return;
    }
    if (!confirm) throw StateError('请先明确确认当前本地统计范围的归属。');
    await txn.insert('fly_scope_binding', {
      'id': 1,
      'scope_digest': _scopeDigest,
    });
  }

  Future<Map<String, Object?>?> state(String accountKey) async {
    final db = await database.rawDatabase;
    final rows = await db.query(
      'fly_sync_state',
      where: 'account_key = ?',
      whereArgs: [accountKey],
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<List<Map<String, Object?>>> localDatasets() async {
    final db = await database.rawDatabase;
    return db.rawQuery('''
SELECT d.*, COUNT(h.history_id) AS record_count FROM fly_datasets d
JOIN fly_record_provenance p ON p.dataset_id=d.id
JOIN play_history h ON h.history_id=p.history_id
GROUP BY d.id ORDER BY d.origin_kind,d.label
''');
  }

  Future<Set<String>> unlinkedRecordIds(String accountKey) async {
    final db = await database.rawDatabase;
    final rows = await db.rawQuery(
      '''
SELECT h.history_id FROM play_history h
JOIN fly_record_provenance p ON p.history_id=h.history_id
JOIN fly_datasets d ON d.id=p.dataset_id
WHERE d.confirmed_account<>?
''',
      [accountKey],
    );
    return rows.map((row) => row['history_id'] as String).toSet();
  }

  /// Call only after explicit ownership confirmation and remote overlap check.
  Future<void> confirmUnlinked(String accountKey) =>
      database.transaction((txn) async {
        await _checkScopeBinding(txn, confirm: true);
        final state = await txn.query(
          'fly_sync_state',
          where: 'pending_json IS NOT NULL',
        );
        if (state.isNotEmpty) throw StateError('有待重试快照，完成重试后才能更改历史关联。');
        final bound = await txn.rawQuery(
          '''
SELECT DISTINCT d.id FROM fly_datasets d
JOIN fly_record_provenance p ON p.dataset_id=d.id
JOIN play_history h ON h.history_id=p.history_id
WHERE d.confirmed_account<>'' AND d.confirmed_account<>?
''',
          [accountKey],
        );
        if (bound.isNotEmpty) throw StateError('本地历史已关联其他数据服务帐号，不能改绑。');
        await txn.rawUpdate(
          '''
UPDATE fly_datasets SET confirmed_account=? WHERE id IN (
SELECT p.dataset_id FROM fly_record_provenance p JOIN play_history h ON h.history_id=p.history_id)
''',
          [accountKey],
        );
      });

  /// Verify the selected import against current rows again inside the write
  /// transaction. Never change facts or guess that overlapping titles are equal.
  Future<int> adoptDataset(
    String accountKey,
    Map<String, dynamic> dataset,
    List<Map<String, dynamic>> remoteRows,
  ) => database.transaction((txn) async {
    await _checkScopeBinding(txn, confirm: true);
    if ((await txn.query(
      'fly_sync_state',
      where: 'pending_json IS NOT NULL',
    )).isNotEmpty) {
      throw StateError('有待重试快照，完成重试后才能关联导入历史。');
    }
    final matches =
        <({Map<String, Object?> local, Map<String, dynamic> remote})>[];
    final targetRows = await txn.query(
      'fly_datasets',
      where: 'id = ?',
      whereArgs: [dataset['id']],
    );
    if (targetRows.isNotEmpty &&
        targetRows.single['confirmed_account'] != accountKey) {
      throw StateError('所选来源已关联其他帐号，不能更改归属。');
    }
    for (final remote in remoteRows) {
      final rows = await txn.query(
        'play_history',
        where: 'history_id = ?',
        whereArgs: [remote['origin_record_id']],
      );
      if (rows.isEmpty) continue;
      final local = rows.single;
      final deleted = remote['tombstoned'] == true;
      final payload = deleted
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(remote['legacy_payload'] as Map);
      if (!deleted &&
          (payload['history_id'] != local['history_id'] ||
              payload['video_id'] != local['video_id'] ||
              payload['started_at_ms'] != local['started_at_ms'] ||
              payload.entries.any(
                (entry) =>
                    !local.containsKey(entry.key) ||
                    canonicalJson(entry.value) !=
                        canonicalJson(local[entry.key]),
              ))) {
        throw StateError('历史 ${local['history_id']} 与已导入事实不同，未更改关联。请在网页核对该记录。');
      }
      final provenance = (await txn.query(
        'fly_record_provenance',
        where: 'history_id = ?',
        whereArgs: [local['history_id']],
      )).single;
      final current = (await txn.query(
        'fly_datasets',
        where: 'id = ?',
        whereArgs: [provenance['dataset_id']],
      )).single;
      final owner = current['confirmed_account'];
      if (owner != '' &&
          (owner != accountKey || current['id'] != dataset['id'])) {
        throw StateError('这条历史已有来源关联，不能重新分配身份。');
      }
      matches.add((local: local, remote: remote));
    }
    if (matches.isEmpty) throw StateError('该数据集没有与当前本地历史 ID 和原始事实匹配的记录。');
    await txn.insert('fly_datasets', {
      'id': dataset['id'],
      'label': dataset['label'],
      'origin_kind': dataset['origin_kind'] ?? 'legacy_import',
      'source_schema_version': dataset['source_schema_version'] ?? 3,
      'export_revision': dataset['export_revision_watermark'] ?? 0,
      'deletion_generation': dataset['deletion_generation'] ?? 0,
      'confirmed_account': accountKey,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    var watermark = (dataset['export_revision_watermark'] as num? ?? 0).toInt();
    for (final match in matches) {
      final envelope = recordEnvelope(match.remote);
      final remotePayload = match.remote['legacy_payload'];
      final revision =
          (match.remote['record_revision'] as num? ?? 1).toInt() +
          (canonicalJson(remotePayload) == canonicalJson(match.local) ? 0 : 1);
      if (revision > watermark) watermark = revision;
      await txn.update(
        'fly_record_provenance',
        {
          'dataset_id': dataset['id'],
          'record_revision': revision,
          'envelope_json': jsonEncode(envelope),
        },
        where: 'history_id = ?',
        whereArgs: [match.local['history_id']],
      );
    }
    await txn.rawUpdate(
      'UPDATE fly_datasets SET export_revision=MAX(export_revision+?,?) WHERE id=?',
      [matches.length, watermark, dataset['id']],
    );
    return matches.length;
  });

  Future<String> preparePacket({
    required String accountKey,
    required String installationId,
    required String streamId,
  }) => database.transaction((txn) async {
    await _checkScopeBinding(txn);
    final states = await txn.query(
      'fly_sync_state',
      where: 'account_key = ?',
      whereArgs: [accountKey],
    );
    final state = states.isEmpty ? null : states.single;
    if (state != null &&
        state['installation_id'] != installationId &&
        state['pending_json'] != null) {
      throw StateError('恢复的快照属于另一设备。请先在原设备完成重试，当前设备没有发送。');
    }
    if (state?['pending_json'] != null) return state!['pending_json'] as String;
    final datasets = await txn.rawQuery('''
SELECT DISTINCT d.* FROM fly_datasets d
JOIN fly_record_provenance p ON p.dataset_id=d.id
JOIN play_history h ON h.history_id=p.history_id ORDER BY d.id
''');
    if (datasets.isEmpty) throw FlyNoFactsToSync();
    if (datasets.length > 4096) {
      throw StateError('当前范围的来源数超过 P1 上限（4096），未创建快照。');
    }
    if (datasets.any((row) => row['confirmed_account'] != accountKey)) {
      throw StateError('请先关联已经导入的历史，并明确确认当前本地范围的归属。');
    }
    final histories = await txn.query('play_history', orderBy: 'history_id');
    if (histories.length > 10000) {
      throw StateError('当前范围超过 P1 的 10000 条完整快照上限，未创建快照。');
    }
    final provenanceRows = await txn.query('fly_record_provenance');
    final provenance = {
      for (final row in provenanceRows) row['history_id']: row,
    };
    final sameDevice =
        state != null && state['installation_id'] == installationId;
    final seq = sameDevice ? state['next_seq'] as int : 1;
    final effectiveStream = sameDevice
        ? state['stream_id'] as String
        : streamId;
    final packet = jsonEncode({
      'schema_version': 'fly-snapshot/1',
      'stream_id': effectiveStream,
      'snapshot_seq': seq,
      'snapshot_created_at_ms': DateTime.now().millisecondsSinceEpoch,
      'consistency': 'per_dataset_transaction',
      'manifest': {
        'datasets': [
          for (final row in datasets)
            {
              'id': row['id'],
              'source_schema_version': row['source_schema_version'],
              'export_revision_watermark': row['export_revision'],
              'deletion_generation': row['deletion_generation'],
            },
        ],
      },
      'records': [
        for (final row in histories)
          {
            ...recordEnvelope(
              Map<String, dynamic>.from(
                jsonDecode(
                      provenance[row['history_id']]!['envelope_json'] as String,
                    )
                    as Map,
              ),
            ),
            'origin_dataset_id': provenance[row['history_id']]!['dataset_id'],
            'origin_record_id': row['history_id'],
            'record_revision':
                provenance[row['history_id']]!['record_revision'],
            'legacy_payload': row,
          },
      ],
    });
    if (utf8.encode(packet).length > 8 * 1024 * 1024) {
      throw StateError('当前完整快照超过 P1 的 8 MiB 上传上限，未创建快照。');
    }
    await txn.insert('fly_sync_state', {
      'account_key': accountKey,
      'installation_id': installationId,
      'stream_id': effectiveStream,
      'next_seq': seq,
      'pending_json': packet,
      'last_success_ms': state?['last_success_ms'],
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return packet;
  });

  Future<void> acceptReceipt(String accountKey, Map<String, dynamic> receipt) =>
      database.transaction((txn) async {
        final state = (await txn.query(
          'fly_sync_state',
          where: 'account_key = ?',
          whereArgs: [accountKey],
        )).single;
        if (receipt['status'] != 'applied' ||
            receipt['snapshot_seq'] != state['next_seq'] ||
            receipt['applied_at_ms'] is! num) {
          throw StateError('服务器未确认 applied；待重试快照已保留。');
        }
        await txn.update(
          'fly_sync_state',
          {
            'pending_json': null,
            'next_seq': (state['next_seq'] as int) + 1,
            'last_success_ms': receipt['applied_at_ms'],
          },
          where: 'account_key = ?',
          whereArgs: [accountKey],
        );
      });
}

/// A sync operation must never follow a mutable account binding to another DB.
class _PinnedDatabase implements PlayStatsDatabase {
  _PinnedDatabase(this.db);
  final Database db;
  @override
  Future<Database> get rawDatabase async => db;
  @override
  Future<T> transaction<T>(Future<T> Function(DatabaseExecutor) action) =>
      db.transaction((txn) => action(txn));
  @override
  Future<void> open() async {}
  @override
  Future<void> bindOwnerScope(String ownerScope) async =>
      throw UnsupportedError('Pinned sync scope');
  @override
  Future<void> clearAll() async => throw UnsupportedError('Pinned sync scope');
}

Map<String, dynamic> recordEnvelope(Map<String, dynamic> source) => {
  'metadata_snapshot': source['metadata_snapshot'] ?? <String, dynamic>{},
  'source_ref': source['source_ref'] ?? <String, dynamic>{},
  'quality_flags': source['quality_flags'] ?? ['legacy_media_delta'],
  'rules_version': source['rules_version'] ?? 'legacy-v3',
};

String canonicalJson(Object? value) {
  Object? sort(Object? item) {
    if (item is Map) {
      final keys = item.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: sort(item[key])};
    }
    if (item is List) return item.map(sort).toList();
    if (item is double && item == item.roundToDouble()) return item.toInt();
    return item;
  }

  return jsonEncode(sort(value));
}
