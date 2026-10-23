import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

class SqliteStore {
  final Database db;
  final Map<String, String> cache = {};
  final Map<String, int> positions = {};
  int revision = 0;
  SqliteStore(String path) : db = sqlite3.open(path) {
    db.execute('PRAGMA journal_mode=WAL');
    db.execute('PRAGMA synchronous=FULL');
    db.execute('PRAGMA busy_timeout=5000');
    db.execute('PRAGMA secure_delete=ON');
    db.execute(
      'CREATE TABLE IF NOT EXISTS records (collection TEXT NOT NULL, id TEXT NOT NULL, payload TEXT NOT NULL, position INTEGER NOT NULL, PRIMARY KEY(collection,id))',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value INTEGER NOT NULL)',
    );
    db.execute("INSERT OR IGNORE INTO metadata VALUES ('revision',0)");
    revision =
        db
                .select("SELECT value FROM metadata WHERE key='revision'")
                .first['value']
            as int;
  }
  Map<String, dynamic>? load() {
    final records = db.select(
      'SELECT collection,id,payload,position FROM records ORDER BY collection,position',
    );
    if (records.isEmpty) return revision > 0 ? <String, dynamic>{} : null;
    final data = <String, dynamic>{};
    for (final r in records) {
      final collection = r['collection'] as String;
      final payload = r['payload'] as String;
      (data.putIfAbsent(collection, () => <dynamic>[]) as List).add(
        jsonDecode(payload),
      );
      cache['$collection:${r['id']}'] = payload;
      positions['$collection:${r['id']}'] = r['position'] as int;
    }
    return data;
  }

  void save(Map<String, dynamic> data) {
    final next = <String, String>{};
    final nextPositions = <String, int>{};
    db.execute('BEGIN IMMEDIATE');
    try {
      if (db
              .select("SELECT value FROM metadata WHERE key='revision'")
              .first['value'] !=
          revision) {
        throw StateError(
          'A second server changed the database; restart this instance.',
        );
      }
      for (final e in data.entries) {
        if (e.value is! List) continue;
        var position = 0;
        for (final row in e.value as List) {
          final id = (row['id'] ?? position).toString(),
              key = '${e.key}:$id',
              payload = jsonEncode(row);
          next[key] = payload;
          if (cache[key] != payload || positions[key] != position) {
            db.execute(
              'INSERT INTO records VALUES (?,?,?,?) ON CONFLICT(collection,id) DO UPDATE SET payload=excluded.payload,position=excluded.position',
              [e.key, id, payload, position],
            );
          }
          nextPositions[key] = position;
          position++;
        }
      }
      for (final key in cache.keys.where((k) => !next.containsKey(k))) {
        final colon = key.indexOf(':');
        db.execute('DELETE FROM records WHERE collection=? AND id=?', [
          key.substring(0, colon),
          key.substring(colon + 1),
        ]);
      }
      db.execute("UPDATE metadata SET value=value+1 WHERE key='revision'");
      db.execute('COMMIT');
      revision++;
      positions
        ..clear()
        ..addAll(nextPositions);
      cache
        ..clear()
        ..addAll(next);
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void backup(String path) {
    if (File(path).existsSync()) throw StateError('Backup file already exists');
    db.execute('VACUUM INTO ?', [path]);
  }

  void close() => db.close();
}
