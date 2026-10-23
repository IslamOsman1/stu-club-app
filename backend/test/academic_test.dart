import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../bin/server.dart';

void main() {
  late Directory dir;
  late ClubServer app;
  late HttpServer server;
  late String base;
  Future<Map<String, dynamic>> call(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
    String? token,
    int status = 200,
  }) async {
    final client = HttpClient();
    try {
      final req = await client.openUrl(method, Uri.parse('$base$path'));
      req.headers.contentType = ContentType.json;
      if (token != null) req.headers.set('Authorization', 'Bearer $token');
      if (data != null) req.write(jsonEncode(data));
      final res = await req.close();
      final result = jsonDecode(
        await res.transform(utf8.decoder).join(),
      ) as Map<String, dynamic>;
      expect(res.statusCode, status, reason: result.toString());
      return result;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> register(String email, {String uni = 'cairo'}) =>
      call(
        '/auth/register',
        method: 'POST',
        data: {
          'name': email.split('@').first,
          'email': email,
          'password': 'StrongPass123!',
          'university': uni,
          if (uni == 'school_demo') 'birthYear': 2010,
          if (uni == 'school_demo') 'grade': 10,
        },
      );
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('stuclub-features-');
    app = ClubServer('${dir.path}/club.json');
    server = await app.start(port: 0);
    base = 'http://127.0.0.1:${server.port}';
  });
  tearDown(() async {
    await server.close(force: true);
    dir.deleteSync(recursive: true);
  });
  test('official announcements restrict publishing and target membership; views and activity persist', () async {
    final teacher = await register('teacher@example.test'),
        student = await register('student@example.test'),
        outsider = await register('outsider@example.test', uni: 'alex');
    final tt = teacher['token'] as String,
        st = student['token'] as String,
        ot = outsider['token'] as String;
    final tid = teacher['user']['id'] as String,
        sid = student['user']['id'] as String;
    await call(
      '/announcements',
      method: 'POST',
      token: st,
      data: {'text': 'not allowed'},
      status: 403,
    );
    app.find('users', tid)!['role'] = 'doctor';
    await call(
      '/announcements',
      method: 'POST',
      token: tt,
      data: {'text': 'unverified'},
      status: 403,
    );
    app.find('users', tid)!['verified'] = true;
    final groups = (await call('/groups', token: tt))['items'] as List;
    final gid = groups.first['id'];
    await call('/groups/$gid/membership', method: 'POST', token: tt);
    final created = await call(
      '/announcements',
      method: 'POST',
      token: tt,
      data: {'text': 'Room changed', 'group': gid, 'pinned': true},
    );
    final aid = created['id'];
    expect((await call('/announcements', token: st))['items'], isEmpty);
    await call(
      '/announcements/$aid/view',
      method: 'POST',
      token: ot,
      status: 404,
    );
    await call(
      '/announcements/$aid/view',
      method: 'POST',
      token: st,
      status: 404,
    );
    await call('/groups/$gid/membership', method: 'POST', token: st);
    final visible = (await call('/announcements', token: st))['items'] as List;
    expect(visible.single['text'], 'Room changed');
    expect(visible.single.containsKey('viewCount'), false);
    await call('/announcements/$aid/view', method: 'POST', token: st);
    await call('/announcements/$aid/view', method: 'POST', token: st);
    expect(
      ((await call('/announcements', token: tt))['items'] as List)
          .single['viewCount'],
      1,
    );
    await call(
      '/announcements/$aid',
      method: 'PATCH',
      token: st,
      data: {'pinned': false},
      status: 403,
    );
    await call(
      '/announcements/$aid',
      method: 'PATCH',
      token: tt,
      data: {'pinned': false},
    );
    expect((await call('/streak', token: st))['count'], 0);
    app.recordActivity(sid);
    app.recordActivity(sid);
    app.save();
    final streak = await call('/streak', token: st);
    expect(streak['count'], 1);
    expect((streak['days'] as List).length, 1);
    final reloaded = ClubServer(app.file.path);
    expect(reloaded.rows('announcements').length, 1);
    expect(reloaded.rows('activity').length, 1);
    app.rows('activity').removeWhere((r) => r['user'] == sid);
    for (var i = 2; i <= 8; i++) {
      app.rows('activity').add({
        'id': id(),
        'user': sid,
        'day': DateTime.now()
            .toUtc()
            .subtract(Duration(days: i))
            .toIso8601String()
            .substring(0, 10),
      });
    }
    final ready = await call('/streak', token: st);
    expect(ready['freezes'], 1);
    expect(ready['canFreeze'], true);
    await call('/streak/freeze', method: 'POST', token: st);
    final protected = await call('/streak', token: st);
    expect(protected['count'], 8);
    expect(protected['freezes'], 0);
    await call('/streak/freeze', method: 'POST', token: st, status: 409);
    final school = await register('school@example.test', uni: 'school_demo');
    await call('/groups', token: school['token'] as String, status: 403);
    app.find('users', school['user']['id'] as String)!['verified'] = true;
    expect(
      (await call('/announcements', token: school['token'] as String))['items'],
      isEmpty,
    );
    expect(
      (await call('/groups', token: school['token'] as String))['items'],
      isEmpty,
    );
  });
}
