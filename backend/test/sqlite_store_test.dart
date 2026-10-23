import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../bin/server.dart';
import '../bin/sqlite_store.dart';

void main() {
  test('SQLite imports existing JSON once, persists new changes and creates a readable consistent backup', () {
    final dir = Directory.systemTemp.createTempSync('stuclub-sqlite-');
    final path = '${dir.path}/club.json';
    final original = ClubServer(path);
    original.rows('scores').add({
      'id': 'old',
      'user': 'u',
      'quiz': 'q',
      'points': 10,
    });
    original.save();
    final legacy = File(path).readAsStringSync();
    final migrated = ClubServer(path, sqlite: true);
    expect(migrated.rows('scores').single['id'], 'old');
    migrated.rows('scores').add({
      'id': 'new',
      'user': 'u',
      'quiz': 'q2',
      'points': 20,
    });
    migrated.save();
    expect(File(path).readAsStringSync(), legacy);
    final backup = '${dir.path}/backup.sqlite';
    migrated.store!.backup(backup);
    migrated.store!.close();
    final restored = ClubServer(path, sqlite: true);
    expect(restored.rows('scores').length, 2);
    restored.store!.close();
    final copy = SqliteStore(backup);
    expect((copy.load()!['scores'] as List).length, 2);
    copy.close();
    expect(
      utf8.decode(File('$path.sqlite').readAsBytesSync().take(15).toList()),
      'SQLite format 3',
    );
    dir.deleteSync(recursive: true);
  });
  test('SQLite rejects a stale second writer instead of overwriting committed changes', () {
    final dir = Directory.systemTemp.createTempSync('stuclub-writer-');
    final path = '${dir.path}/data.sqlite';
    final a = SqliteStore(path), b = SqliteStore(path);
    a.save({
      'items': [
        {'id': 'a', 'value': 1},
      ],
    });
    expect(
      () => b.save({
        'items': [
          {'id': 'b', 'value': 2},
        ],
      }),
      throwsStateError,
    );
    a.close();
    b.close();
    final check = SqliteStore(path);
    expect((check.load()!['items'] as List).single['id'], 'a');
    check.close();
    dir.deleteSync(recursive: true);
  });
}
