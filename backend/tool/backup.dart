import 'dart:io';

import '../bin/sqlite_store.dart';

void main(List<String> args) {
  final source = File(Platform.environment['STU_DATA'] ?? 'data/club.json');
  final destination = Directory(
    args.isEmpty
        ? 'backups/${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}'
        : args.first,
  );
  if (destination.existsSync()) {
    throw StateError('Backup destination already exists');
  }
  destination.createSync(recursive: true);
  final database = File('${source.path}.sqlite');
  if (database.existsSync()) {
    final store = SqliteStore(database.path);
    try {
      store.backup('${destination.path}/club.json.sqlite');
    } finally {
      store.close();
    }
  } else {
    if (source.existsSync()) source.copySync('${destination.path}/club.json');
  }
  for (final name in ['media', 'documents']) {
    final directory = Directory('${source.parent.path}/$name');
    if (directory.existsSync()) {
      final target = Directory('${destination.path}/$name')..createSync();
      for (final file
          in directory.listSync(followLinks: false).whereType<File>()) {
        file.copySync('${target.path}/${file.uri.pathSegments.last}');
      }
    }
  }
  final operator = File('${source.parent.path}/operator.json');
  if (operator.existsSync()) {
    operator.copySync('${destination.path}/operator.json');
  }
  stdout.writeln(
    'Backup created. Keep this directory private: ${destination.path}',
  );
}
