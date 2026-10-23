import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../bin/server.dart';

void main() {
  late Directory temp;
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
      final body = jsonDecode(
        await utf8.decoder.bind(res).join(),
      ) as Map<String, dynamic>;
      expect(res.statusCode, status, reason: body.toString());
      return body;
    } finally {
      client.close(force: true);
    }
  }

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('stuclub-test-');
    app = ClubServer('${temp.path}/club.json');
    server = await app.start(port: 0);
    base = 'http://127.0.0.1:${server.port}';
  });
  tearDown(() async {
    await server.close(force: true);
    temp.deleteSync(recursive: true);
  });
  test('university authorization, sessions, groups and durable data', () async {
    Future<Map<String, dynamic>> register(String email, String university) =>
        call(
          '/auth/register',
          method: 'POST',
          data: {
            'name': 'Test Student',
            'email': email,
            'password': 'StrongPass123!',
            'university': university,
            'role': 'doctor',
          },
        );
    final a = await register('a@example.test', 'cairo');
    final b = await register('b@example.test', 'alex');
    final c = await register('c@example.test', 'cairo');
    final ta = a['token'] as String,
        tb = b['token'] as String,
        tc = c['token'] as String;
    expect(a['user']['role'], 'student');
    await call('/feed', status: 401);
    final post = await call(
      '/posts',
      method: 'POST',
      token: ta,
      data: {'text': 'Private to Cairo'},
    );
    expect((await call('/feed', token: tb))['posts'], isEmpty);
    await call(
      '/posts/${post['id']}/like',
      method: 'POST',
      token: tb,
      status: 404,
    );
    await call(
      '/posts/${post['id']}',
      method: 'DELETE',
      token: tc,
      status: 403,
    );
    await call('/posts/${post['id']}/like', method: 'POST', token: tc);
    expect((await call('/feed', token: ta))['posts'][0]['likeCount'], 1);
    expect(
      (await call('/feed', token: ta))['posts'][0].containsKey('likes'),
      false,
    );
    final group = (await call('/groups', token: ta))['items'][0];
    await call('/groups/${group['id']}/messages', token: ta, status: 403);
    await call('/groups/${group['id']}/membership', method: 'POST', token: ta);
    await call(
      '/groups/${group['id']}/membership',
      method: 'POST',
      token: tb,
      status: 404,
    );
    await call(
      '/groups/${group['id']}/messages',
      method: 'POST',
      token: ta,
      data: {'text': 'Hello group'},
    );
    await call('/groups/${group['id']}/messages', token: tb, status: 404);
    expect(
      (await call(
        '/groups/${group['id']}/messages',
        token: ta,
      ))['items'][0]['text'],
      'Hello group',
    );
    final story = await call(
      '/stories',
      method: 'POST',
      token: ta,
      data: {'text': 'A real story'},
    );
    expect((await call('/feed', token: tb))['stories'], isEmpty);
    app.find('stories', story['id'])!['expires'] = DateTime.now()
        .toUtc()
        .subtract(const Duration(seconds: 1))
        .toIso8601String();
    app.save();
    expect((await call('/feed', token: ta))['stories'], isEmpty);
    await call(
      '/me',
      method: 'PATCH',
      token: ta,
      data: {
        'name': 'Changed Name',
        'bio': 'Computer science',
        'university': 'alex',
        'role': 'doctor',
      },
    );
    final user = (await call('/me', token: ta))['user'];
    expect(user['university'], 'cairo');
    expect(user['role'], 'student');
    final score = await call(
      '/quiz/answer',
      method: 'POST',
      token: ta,
      data: {'id': 'stack-1', 'answer': 1},
    );
    expect(score['points'], 10);
    await call(
      '/quiz/answer',
      method: 'POST',
      token: ta,
      data: {'id': 'stack-1', 'answer': 1},
    );
    expect((await call('/leaderboard', token: ta))['items'][0]['points'], 10);
    final restored = ClubServer('${temp.path}/club.json');
    expect(restored.rows('posts').length, 1);
    expect(restored.rows('messages').length, 1);
    expect(restored.rows('users').first['name'], 'Changed Name');
    expect(
      File('${temp.path}/club.json')
          .readAsStringSync()
          .contains('StrongPass123!'),
      false,
    );
    await call('/auth/logout', method: 'POST', token: ta);
    await call('/me', token: ta, status: 401);
    await call(
      '/auth/login',
      method: 'POST',
      data: {'email': 'a@example.test', 'password': 'wrongpassword'},
      status: 401,
    );
    final login = await call(
      '/auth/login',
      method: 'POST',
      data: {'email': 'a@example.test', 'password': 'StrongPass123!'},
    );
    expect(login['user']['name'], 'Changed Name');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
