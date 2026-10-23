import 'dart:convert';
import 'dart:io';

import '../bin/sqlite_store.dart';

void main(List<String> args) {
  if (args.isEmpty) throw ArgumentError('Existing account email required');
  final email = args.first.trim().toLowerCase();
  final file = File('data/club.json');
  Map<String, dynamic>? data;
  if (File('${file.path}.sqlite').existsSync()) {
    final store = SqliteStore('${file.path}.sqlite');
    try {
      data = store.load();
    } finally {
      store.close();
    }
  } else if (file.existsSync()) {
    data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }
  if (data == null ||
      !(data['users'] as List? ?? []).any((u) => u['email'] == email)) {
    throw StateError('Create this account in the application first.');
  }
  final configFile = File('data/operator.json');
  final config = configFile.existsSync()
      ? jsonDecode(configFile.readAsStringSync().replaceFirst('\uFEFF', ''))
            as Map<String, dynamic>
      : <String, dynamic>{};
  config['admins'] = {
    <String>{...(config['admins'] as List? ?? []).cast<String>(), email},
  }.expand((x) => x).toList();
  config['requireVerification'] =
      config['requireVerification'] == true ||
      args.contains('--require-verification');
  configFile.writeAsStringSync(jsonEncode(config));
  stdout.writeln(
    'Admin configuration saved. Restart the local server and sign in again.',
  );
}
