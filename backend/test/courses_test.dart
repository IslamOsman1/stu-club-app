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
  test('official sections enforce admin enrollment, assigned teachers and institution isolation', () async {
    final admin = await register('admin@example.test');
    final teacher = await register('teacher@example.test');
    final student = await register('student@example.test');
    final other = await register('other@example.test');
    final outsider = await register('outsider@example.test', uni: 'alex');
    final at = admin['token'] as String,
        tt = teacher['token'] as String,
        st = student['token'] as String,
        nt = other['token'] as String,
        ot = outsider['token'] as String;
    final aid = admin['user']['id'] as String,
        tid = teacher['user']['id'] as String,
        sid = student['user']['id'] as String,
        nid = other['user']['id'] as String;
    app.find('users', aid)!['role'] = 'admin';
    app.find('users', tid)!.addAll({'role': 'doctor', 'verified': true});
    await call(
      '/courses',
      method: 'POST',
      token: tt,
      data: {'name': 'Programming', 'code': 'CS101'},
      status: 403,
    );
    await call('/courses/people', token: st, status: 403);
    final course = await call(
      '/courses',
      method: 'POST',
      token: at,
      data: {'name': 'Programming', 'code': 'CS101'},
    );
    final cid = course['id'];
    await call(
      '/courses',
      method: 'POST',
      token: at,
      data: {'name': 'duplicate', 'code': 'cs101'},
      status: 409,
    );
    await call(
      '/courses/$cid/sections',
      method: 'POST',
      token: at,
      data: {
        'name': 'A',
        'teachers': [tid],
        'students': [outsider['user']['id']],
      },
      status: 400,
    );
    expect(app.rows('sections'), isEmpty);
    final section = await call(
      '/courses/$cid/sections',
      method: 'POST',
      token: at,
      data: {
        'name': 'A',
        'teachers': [tid],
        'students': [sid],
      },
    );
    final sectionId = section['id'];
    expect(((await call('/courses', token: st))['items'] as List).length, 1);
    expect(((await call('/courses', token: nt))['items'] as List), isEmpty);
    expect(((await call('/courses', token: ot))['items'] as List), isEmpty);
    final teacherSection =
        ((await call('/courses', token: tt))['sections'] as List).single;
    expect(teacherSection['canPublish'], true);
    expect(teacherSection['students'], isEmpty);
    await call(
      '/sections/$sectionId',
      method: 'PATCH',
      token: tt,
      data: {
        'name': 'A',
        'teachers': [tid],
        'students': [sid, nid],
        'active': true,
      },
      status: 403,
    );
    await call(
      '/announcements',
      method: 'POST',
      token: tt,
      data: {
        'text': 'invalid audience',
        'section': sectionId,
        'group': 'anything',
      },
      status: 400,
    );
    final announcement = await call(
      '/announcements',
      method: 'POST',
      token: tt,
      data: {'text': 'CS101 room changed', 'section': sectionId},
    );
    final announceId = announcement['id'];
    expect(
      ((await call('/announcements', token: st))['items'] as List).single['id'],
      announceId,
    );
    expect((await call('/announcements', token: nt))['items'], isEmpty);
    await call(
      '/announcements/$announceId/view',
      method: 'POST',
      token: nt,
      status: 404,
    );
    expect((await call('/notifications', token: st))['items'], isNotEmpty);
    expect((await call('/notifications', token: nt))['items'], isEmpty);
    await call(
      '/sections/$sectionId',
      method: 'PATCH',
      token: at,
      data: {
        'name': 'A',
        'teachers': [tid],
        'students': [nid],
        'active': true,
      },
    );
    expect((await call('/announcements', token: st))['items'], isEmpty);
    expect((await call('/notifications', token: st))['items'], isEmpty);
    expect((await call('/announcements', token: nt))['items'], isNotEmpty);
    final saved = ClubServer(app.file.path);
    expect(saved.find('sections', sectionId)!['students'], [nid]);
    app.find('users', outsider['user']['id'] as String)!['role'] = 'admin';
    await call(
      '/sections/$sectionId',
      method: 'PATCH',
      token: ot,
      data: {
        'name': 'A',
        'teachers': [tid],
        'students': [],
        'active': true,
      },
      status: 404,
    );
    await call(
      '/sections/$sectionId',
      method: 'PATCH',
      token: at,
      data: {
        'name': 'A',
        'teachers': [],
        'students': [nid],
        'active': true,
      },
    );
    await call(
      '/announcements',
      method: 'POST',
      token: tt,
      data: {'text': 'revoked assignment', 'section': sectionId},
      status: 403,
    );
    expect((await call('/announcements', token: tt))['items'], isEmpty);
    await call(
      '/sections/$sectionId',
      method: 'PATCH',
      token: at,
      data: {
        'name': 'A',
        'teachers': [tid],
        'students': [nid],
        'active': false,
      },
    );
    expect((await call('/announcements', token: nt))['items'], isEmpty);
    await call(
      '/announcements',
      method: 'POST',
      token: tt,
      data: {'text': 'archived section', 'section': sectionId},
      status: 409,
    );
  });
}
