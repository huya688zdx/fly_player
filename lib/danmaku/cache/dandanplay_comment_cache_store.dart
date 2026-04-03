import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class DanDanPlayCommentCacheStore {
  static const String databaseName = 'dandanplay_comment_cache.db';
  static const int databaseVersion = 1;
  static const int _maxEntries = 24;

  static Database? _database;

  const DanDanPlayCommentCacheStore();

  Future<Database> get rawDatabase async {
    final existing = _database;
    if (existing != null) return existing;
    final databasesPath = await getDatabasesPath();
    final databasePath = p.join(databasesPath, databaseName);
    final database = await openDatabase(
      databasePath,
      version: databaseVersion,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE IF NOT EXISTS dandanplay_comment_cache (
  episode_id INTEGER PRIMARY KEY,
  content TEXT NOT NULL DEFAULT '',
  fetched_at_ms INTEGER NOT NULL DEFAULT 0,
  last_accessed_at_ms INTEGER NOT NULL DEFAULT 0
)
''');
      },
    );
    _database = database;
    return database;
  }

  Future<String?> loadComments(int episodeId) async {
    if (episodeId <= 0) return null;
    final database = await rawDatabase;
    final rows = await database.query(
      'dandanplay_comment_cache',
      columns: const <String>['content'],
      where: 'episode_id = ?',
      whereArgs: <Object>[episodeId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    await database.update(
      'dandanplay_comment_cache',
      <String, Object>{
        'last_accessed_at_ms': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'episode_id = ?',
      whereArgs: <Object>[episodeId],
    );
    final content = rows.first['content']?.toString().trim() ?? '';
    return content.isEmpty ? null : content;
  }

  Future<void> saveComments({
    required int episodeId,
    required String content,
  }) async {
    final normalizedContent = content.trim();
    if (episodeId <= 0 || normalizedContent.isEmpty) return;
    final database = await rawDatabase;
    final now = DateTime.now().millisecondsSinceEpoch;
    await database.transaction<void>((txn) async {
      await txn.insert(
        'dandanplay_comment_cache',
        <String, Object>{
          'episode_id': episodeId,
          'content': normalizedContent,
          'fetched_at_ms': now,
          'last_accessed_at_ms': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _prune(txn);
    });
  }

  Future<void> removeComments(int episodeId) async {
    if (episodeId <= 0) return;
    final database = await rawDatabase;
    await database.delete(
      'dandanplay_comment_cache',
      where: 'episode_id = ?',
      whereArgs: <Object>[episodeId],
    );
  }

  Future<void> clearAll() async {
    final database = await rawDatabase;
    await database.delete('dandanplay_comment_cache');
  }

  Future<void> _prune(DatabaseExecutor executor) async {
    final rows = await executor.query(
      'dandanplay_comment_cache',
      columns: const <String>['episode_id'],
      orderBy: 'last_accessed_at_ms DESC, fetched_at_ms DESC',
    );
    if (rows.length <= _maxEntries) return;
    final staleIds = rows
        .skip(_maxEntries)
        .map((row) => row['episode_id'])
        .whereType<int>()
        .toList(growable: false);
    if (staleIds.isEmpty) return;
    final placeholders = List<String>.filled(staleIds.length, '?').join(',');
    await executor.delete(
      'dandanplay_comment_cache',
      where: 'episode_id IN ($placeholders)',
      whereArgs: staleIds,
    );
  }
}
