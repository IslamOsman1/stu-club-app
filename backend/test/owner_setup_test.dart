import 'dart:io';

import 'package:test/test.dart';

import '../bin/server.dart';

void main() {
  test('owner setup is operator-only, salted and repeatable without resetting passwords', () async {
    final dir = Directory.systemTemp.createTempSync('owner-test');
    try {
      final app = ClubServer('${dir.path}/club.json');
      await app.bootstrapOwner({});
      expect(app.rows('users'), isEmpty);
      const env = {
        'STU_OWNER_EMAIL': 'owner@example.org',
        'STU_OWNER_PASSWORD': 'private-owner-password',
      };
      await app.bootstrapOwner(env);
      final owner = app.rows('users').single;
      expect(owner['role'], 'admin');
      expect(owner['password'], isNot(env['STU_OWNER_PASSWORD']));
      final uid = owner['id'], hash = owner['password'];
      await app.bootstrapOwner(env);
      expect(app.rows('users').length, 1);
      expect(owner['id'], uid);
      expect(owner['password'], hash);
      owner['role'] = 'student';
      await expectLater(
        app.bootstrapOwner({
          ...env,
          'STU_OWNER_PASSWORD': 'incorrect-long-password',
        }),
        throwsStateError,
      );
      expect(owner['password'], hash);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
