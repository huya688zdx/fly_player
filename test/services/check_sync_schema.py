"""SQLite behavioral smoke check; executable while Flutter SDK is unavailable."""
from pathlib import Path
import re
import sqlite3
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SyncSchemaTest(unittest.TestCase):
    def test_provenance_replacements_enrichment_and_rollback(self):
        source = (ROOT / 'lib/services/play_stats/play_stats_database.dart').read_text(encoding='utf-8')
        db = sqlite3.connect(':memory:')
        # Execute the real, literal schema statements consumed by the Dart migration.
        for statement in re.findall(r"'''(.*?)'''", source[source.index('const List<String> _schemaStatementsV1'):], re.S):
            db.execute(statement)
        tables = {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        self.assertIn('fly_record_provenance', tables)
        db.execute("INSERT INTO fly_datasets(id,label,origin_kind) VALUES('dataset','test','native')")
        db.execute("INSERT INTO fly_write_context(id,dataset_id) VALUES(1,'dataset')")
        values = ('history_old', 'v', '', '', 1, 100, 10)
        sql = 'INSERT OR REPLACE INTO play_history(history_id,video_id,anime_id,season_id,started_at_ms,ended_at_ms,watched_ms) VALUES(?,?,?,?,?,?,?)'
        db.execute(sql, values)
        db.execute(sql, (*values[:-1], 20))
        db.execute("UPDATE play_history SET title='metadata enriched'")
        db.commit()
        self.assertEqual(db.execute('SELECT dataset_id,record_revision FROM fly_record_provenance').fetchone(), ('dataset', 3))
        db.execute('UPDATE play_history SET watched_ms=99')
        db.rollback()
        self.assertEqual(db.execute('SELECT record_revision FROM fly_record_provenance').fetchone()[0], 3)
        self.assertEqual(db.execute('SELECT watched_ms FROM play_history').fetchone()[0], 20)

    def test_local_delete_does_not_forge_server_deletion_generation(self):
        source = (ROOT / 'lib/services/play_stats/play_stats_database.dart').read_text(encoding='utf-8')
        db = sqlite3.connect(':memory:')
        for statement in re.findall(r"'''(.*?)'''", source[source.index('const List<String> _schemaStatementsV1'):], re.S):
            db.execute(statement)
        db.execute("INSERT INTO fly_datasets(id,label,origin_kind) VALUES('dataset','test','native')")
        db.execute("INSERT INTO fly_write_context(id,dataset_id) VALUES(1,'dataset')")
        db.execute("INSERT INTO play_history(history_id,video_id,anime_id,season_id,started_at_ms,ended_at_ms) VALUES('old','v','','',1,2)")
        db.execute('DELETE FROM play_history')
        self.assertEqual(db.execute('SELECT deletion_generation FROM fly_datasets').fetchone()[0], 0)
        self.assertEqual(db.execute('SELECT export_revision FROM fly_datasets').fetchone()[0], 2)


if __name__ == '__main__':
    unittest.main()
