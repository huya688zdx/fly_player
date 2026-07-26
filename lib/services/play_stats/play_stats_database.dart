import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// 定义播放统计数据库访问层的统一接口。
abstract class PlayStatsDatabase {
  /// 打开底层数据库连接。
  Future<void> open();

  /// 绑定当前数据库实例所属的账号作用域。
  Future<void> bindOwnerScope(String ownerScope);

  /// 返回底层 `sqflite` 数据库实例。
  Future<Database> get rawDatabase;

  /// 在单个事务内执行给定数据库操作。
  Future<T> transaction<T>(Future<T> Function(DatabaseExecutor txn) action);

  /// 清空所有播放统计数据表。
  Future<void> clearAll();
}

/// 让并发的资源打开请求共享同一个进行中的 Future。
class FutureOpenGate<T> {
  Future<T>? _opening;

  Future<T> run(Future<T> Function() opener) {
    final current = _opening;
    if (current != null) {
      return current;
    }

    final opened = opener();
    late final Future<T> shared;
    shared = opened.whenComplete(() {
      if (identical(_opening, shared)) {
        _opening = null;
      }
    });
    _opening = shared;
    return shared;
  }
}

/// 基于 `sqflite` 的播放统计数据库实现。
class SqflitePlayStatsDatabase implements PlayStatsDatabase {
  static const String databaseName = 'play_stats.db';
  static const int databaseVersion = 3;

  Database? _database;
  String _ownerScope = '';
  final FutureOpenGate<Database> _openGate = FutureOpenGate<Database>();

  /// 见 [PlayStatsDatabase.open]。
  @override
  Future<void> open() async {
    await rawDatabase;
  }

  /// 见 [PlayStatsDatabase.bindOwnerScope]。
  @override
  Future<void> bindOwnerScope(String ownerScope) async {
    final normalized = ownerScope.trim().toLowerCase();
    if (_ownerScope == normalized) {
      return;
    }
    final existing = _database;
    _database = null;
    _ownerScope = normalized;
    if (existing != null && existing.isOpen) {
      await existing.close();
    }
  }

  /// 见 [PlayStatsDatabase.rawDatabase]。
  @override
  Future<Database> get rawDatabase async {
    final existing = _database;
    if (existing != null) return existing;
    return _openGate.run(_openDatabase);
  }

  Future<Database> _openDatabase() async {
    final existing = _database;
    if (existing != null) return existing;
    final databasesPath = await getDatabasesPath();
    final databasePath = p.join(databasesPath, _databaseFileNameForScope());
    final database = await openDatabase(
      databasePath,
      version: databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _applyMigrations(db, 0, version);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _applyMigrations(db, oldVersion, newVersion);
      },
    );
    _database = database;
    return database;
  }

  /// 见 [PlayStatsDatabase.transaction]。
  @override
  Future<T> transaction<T>(
    Future<T> Function(DatabaseExecutor txn) action,
  ) async {
    final database = await rawDatabase;
    return database.transaction<T>((txn) => action(txn));
  }

  /// 见 [PlayStatsDatabase.clearAll]。
  @override
  Future<void> clearAll() async {
    await transaction<void>((txn) async {
      await txn.delete('play_history');
      await txn.delete('video_credit_stats');
      await txn.delete('video_stats');
      await txn.delete('season_stats');
      await txn.delete('anime_stats');
    });
  }

  Future<void> _applyMigrations(
    DatabaseExecutor db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 1 && newVersion >= 1) {
      for (final statement in _schemaStatementsV1) {
        await db.execute(statement);
      }
    }
    if (oldVersion < 2 && newVersion >= 2) {
      for (final statement in _schemaStatementsV2) {
        await db.execute(statement);
      }
      await _ensureColumn(
        db,
        table: 'video_stats',
        column: 'country_codes_json',
        definition: "TEXT NOT NULL DEFAULT '[]'",
      );
      await _ensureColumn(
        db,
        table: 'video_stats',
        column: 'genre_ids_json',
        definition: "TEXT NOT NULL DEFAULT '[]'",
      );
      await _ensureColumn(
        db,
        table: 'play_history',
        column: 'country_codes_json',
        definition: "TEXT NOT NULL DEFAULT '[]'",
      );
      await _ensureColumn(
        db,
        table: 'play_history',
        column: 'genre_ids_json',
        definition: "TEXT NOT NULL DEFAULT '[]'",
      );
      await _ensureColumn(
        db,
        table: 'play_history',
        column: 'credits_json',
        definition: "TEXT NOT NULL DEFAULT '[]'",
      );
      await db.execute('''
UPDATE video_stats
SET country_codes_json = CASE
  WHEN TRIM(country) = '' THEN '[]'
  ELSE '["' || REPLACE(country, '"', '') || '"]'
END
WHERE COALESCE(country_codes_json, '') = ''
   OR country_codes_json = '[]'
''');
    }
    if (oldVersion < 3 && newVersion >= 3) {
      await _ensureColumn(
        db,
        table: 'video_stats',
        column: 'metadata_enriched',
        definition: 'INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  Future<void> _ensureColumn(
    DatabaseExecutor db, {
    required String table,
    required String column,
    required String definition,
  }) async {
    final rows = await db.rawQuery("PRAGMA table_info('$table')");
    final exists = rows.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  String _databaseFileNameForScope() {
    if (_ownerScope.isEmpty) {
      return databaseName;
    }
    final sanitized = _ownerScope.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final suffix = sanitized.replaceAll(RegExp(r'^_+|_+$'), '');
    final safeSuffix = suffix.isEmpty ? 'account' : suffix;
    final truncated = safeSuffix.length > 72
        ? safeSuffix.substring(0, 72)
        : safeSuffix;
    return 'play_stats_$truncated.db';
  }
}

const List<String> _schemaStatementsV1 = <String>[
  '''
CREATE TABLE IF NOT EXISTS video_stats (
  video_id TEXT PRIMARY KEY,
  anime_id TEXT NOT NULL,
  season_id TEXT NOT NULL,
  title TEXT NOT NULL DEFAULT '',
  anime_title TEXT NOT NULL DEFAULT '',
  season_title TEXT NOT NULL DEFAULT '',
  video_kind TEXT NOT NULL DEFAULT '',
  counts_toward_completion INTEGER NOT NULL DEFAULT 0,
  country TEXT NOT NULL DEFAULT '',
  country_codes_json TEXT NOT NULL DEFAULT '[]',
  genre_ids_json TEXT NOT NULL DEFAULT '[]',
  year INTEGER NOT NULL DEFAULT 0,
  media_duration_ms INTEGER NOT NULL DEFAULT 0,
  click_count INTEGER NOT NULL DEFAULT 0,
  auto_play_count INTEGER NOT NULL DEFAULT 0,
  view_count INTEGER NOT NULL DEFAULT 0,
  total_played_ms INTEGER NOT NULL DEFAULT 0,
  max_progress REAL NOT NULL DEFAULT 0,
  last_progress REAL NOT NULL DEFAULT 0,
  last_position_ms INTEGER NOT NULL DEFAULT 0,
  completed INTEGER NOT NULL DEFAULT 0,
  metadata_enriched INTEGER NOT NULL DEFAULT 0,
  last_played_at_ms INTEGER NOT NULL DEFAULT 0,
  credits_json TEXT NOT NULL DEFAULT '[]'
)
''',
  '''
CREATE TABLE IF NOT EXISTS anime_stats (
  anime_id TEXT PRIMARY KEY,
  title TEXT NOT NULL DEFAULT '',
  click_count INTEGER NOT NULL DEFAULT 0,
  view_count INTEGER NOT NULL DEFAULT 0,
  total_played_ms INTEGER NOT NULL DEFAULT 0,
  forward_seek_count INTEGER NOT NULL DEFAULT 0,
  backward_seek_count INTEGER NOT NULL DEFAULT 0,
  watched_episode_count INTEGER NOT NULL DEFAULT 0,
  completed_episode_count INTEGER NOT NULL DEFAULT 0,
  completed_season_count INTEGER NOT NULL DEFAULT 0,
  last_played_at_ms INTEGER NOT NULL DEFAULT 0
)
''',
  '''
CREATE TABLE IF NOT EXISTS season_stats (
  season_id TEXT PRIMARY KEY,
  anime_id TEXT NOT NULL,
  title TEXT NOT NULL DEFAULT '',
  total_episode_count INTEGER NOT NULL DEFAULT 0,
  watched_episode_count INTEGER NOT NULL DEFAULT 0,
  completed_episode_count INTEGER NOT NULL DEFAULT 0,
  is_completed INTEGER NOT NULL DEFAULT 0,
  last_played_at_ms INTEGER NOT NULL DEFAULT 0
)
''',
  '''
CREATE TABLE IF NOT EXISTS play_history (
  history_id TEXT PRIMARY KEY,
  video_id TEXT NOT NULL,
  anime_id TEXT NOT NULL,
  season_id TEXT NOT NULL,
  title TEXT NOT NULL DEFAULT '',
  anime_title TEXT NOT NULL DEFAULT '',
  season_title TEXT NOT NULL DEFAULT '',
  video_kind TEXT NOT NULL DEFAULT '',
  counts_toward_completion INTEGER NOT NULL DEFAULT 0,
  country_codes_json TEXT NOT NULL DEFAULT '[]',
  genre_ids_json TEXT NOT NULL DEFAULT '[]',
  credits_json TEXT NOT NULL DEFAULT '[]',
  start_source TEXT NOT NULL DEFAULT 'manual',
  started_at_ms INTEGER NOT NULL,
  ended_at_ms INTEGER NOT NULL,
  media_duration_ms INTEGER NOT NULL DEFAULT 0,
  watched_ms INTEGER NOT NULL DEFAULT 0,
  max_progress REAL NOT NULL DEFAULT 0,
  max_position_ms INTEGER NOT NULL DEFAULT 0,
  counted_as_view INTEGER NOT NULL DEFAULT 0,
  counted_as_completed INTEGER NOT NULL DEFAULT 0,
  op_detected INTEGER NOT NULL DEFAULT 0,
  ed_detected INTEGER NOT NULL DEFAULT 0,
  op_skipped INTEGER NOT NULL DEFAULT 0,
  ed_skipped INTEGER NOT NULL DEFAULT 0,
  op_not_skipped INTEGER NOT NULL DEFAULT 0,
  ed_not_skipped INTEGER NOT NULL DEFAULT 0,
  op_played_ms INTEGER NOT NULL DEFAULT 0,
  ed_played_ms INTEGER NOT NULL DEFAULT 0,
  forward_seek_count INTEGER NOT NULL DEFAULT 0,
  backward_seek_count INTEGER NOT NULL DEFAULT 0
)
''',
  '''
CREATE INDEX IF NOT EXISTS idx_video_stats_anime_season
ON video_stats(anime_id, season_id)
''',
  '''
CREATE INDEX IF NOT EXISTS idx_anime_stats_last_played_at
ON anime_stats(last_played_at_ms DESC)
''',
  '''
CREATE INDEX IF NOT EXISTS idx_season_stats_anime
ON season_stats(anime_id)
''',
  '''
CREATE INDEX IF NOT EXISTS idx_play_history_video_started_at
ON play_history(video_id, started_at_ms DESC)
''',
  '''
CREATE INDEX IF NOT EXISTS idx_play_history_anime_started_at
ON play_history(anime_id, started_at_ms DESC)
''',
  '''
CREATE INDEX IF NOT EXISTS idx_play_history_season_started_at
ON play_history(season_id, started_at_ms DESC)
''',
];

const List<String> _schemaStatementsV2 = <String>[
  '''
CREATE TABLE IF NOT EXISTS video_credit_stats (
  video_id TEXT NOT NULL,
  anime_id TEXT NOT NULL,
  season_id TEXT NOT NULL,
  person_id TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT '',
  role TEXT NOT NULL DEFAULT '',
  job TEXT NOT NULL DEFAULT '',
  credit_order INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (video_id, person_id, role, job)
)
''',
  '''
CREATE INDEX IF NOT EXISTS idx_video_credit_stats_video
ON video_credit_stats(video_id, credit_order ASC)
''',
  '''
CREATE INDEX IF NOT EXISTS idx_video_credit_stats_person
ON video_credit_stats(person_id)
''',
  '''
CREATE INDEX IF NOT EXISTS idx_video_credit_stats_anime
ON video_credit_stats(anime_id, season_id)
''',
];
