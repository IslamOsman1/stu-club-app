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
  test(
    'comments, direct messages, blocks and moderation enforce authorization',
    () async {
      final a = await register('alice@example.test'),
          b = await register('bob@example.test'),
          c = await register('carol@example.test', uni: 'alex');
      final ta = a['token'] as String,
          tb = b['token'] as String,
          tc = c['token'] as String;
      final aid = a['user']['id'] as String, bid = b['user']['id'] as String;
      final post = await call(
        '/posts',
        method: 'POST',
        token: ta,
        data: {'text': 'A university post'},
      );
      await call(
        '/posts/${post['id']}/comments',
        method: 'POST',
        token: tc,
        data: {'text': 'Forbidden'},
        status: 404,
      );
      final comment = await call(
        '/posts/${post['id']}/comments',
        method: 'POST',
        token: tb,
        data: {'text': 'Nice post'},
      );
      expect(
        (await call('/notifications', token: ta))['items'][0]['type'],
        'comment',
      );
      final message = await call(
        '/direct/$aid',
        method: 'POST',
        token: tb,
        data: {'text': 'Private hello'},
      );
      expect(message['ok'], true);
      final messages = (await call('/direct/$bid', token: ta))['items'] as List;
      expect(messages[0]['text'], 'Private hello');
      await call('/direct/$aid', token: tc, status: 404);
      await call('/admin/overview', token: tb, status: 403);
      await call('/blocks/$bid', method: 'POST', token: ta);
      await call(
        '/direct/$aid',
        method: 'POST',
        token: tb,
        data: {'text': 'Blocked'},
        status: 403,
      );
      expect((await call('/people', token: ta))['items'], isEmpty);
      expect(
        (await call('/posts/${post['id']}/comments', token: ta))['items'],
        isEmpty,
      );
      expect((await call('/feed', token: tb))['posts'], isEmpty);
      await call('/blocks/$bid', method: 'DELETE', token: ta);
      await call(
        '/verification',
        method: 'POST',
        token: tb,
        data: {'role': 'admin', 'reference': '123', 'note': ''},
        status: 400,
      );
      await call(
        '/verification',
        method: 'POST',
        token: tb,
        data: {
          'role': 'doctor',
          'reference': 'University directory reference',
          'note': 'Please review',
        },
      );
      await call(
        '/verification',
        method: 'POST',
        token: tb,
        data: {'role': 'doctor', 'reference': 'Second', 'note': ''},
        status: 409,
      );
      app.find('users', aid)!['role'] = 'admin';
      app.save();
      final overview = await call('/admin/overview', token: ta);
      final verification = overview['verification'][0];
      await call(
        '/admin/verification/${verification['id']}',
        method: 'POST',
        token: ta,
        data: {'approve': true},
      );
      final me = (await call('/me', token: tb))['user'];
      expect(me['role'], 'doctor');
      expect(me['verified'], true);
      await call(
        '/reports',
        method: 'POST',
        token: ta,
        data: {
          'type': 'comments',
          'target': comment['id'],
          'reason': 'Test moderation',
        },
      );
      final report = (await call('/admin/overview', token: ta))['reports'][0];
      await call(
        '/admin/reports/${report['id']}',
        method: 'POST',
        token: ta,
        data: {'action': 'remove'},
      );
      expect(
        (await call('/posts/${post['id']}/comments', token: ta))['items'],
        isEmpty,
      );
      await call(
        '/admin/users/$bid',
        method: 'POST',
        token: ta,
        data: {'disabled': true},
      );
      await call('/me', token: tb, status: 401);
      await call(
        '/auth/login',
        method: 'POST',
        data: {'email': 'bob@example.test', 'password': 'StrongPass123!'},
        status: 403,
      );
      await call(
        '/admin/users/$aid',
        method: 'POST',
        token: ta,
        data: {'disabled': true},
        status: 400,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'password rotation revokes sessions and deletion removes owned data',
    () async {
      final a = await register('owner@example.test'),
          b = await register('friend@example.test');
      final ta = a['token'] as String,
          tb = b['token'] as String,
          aid = a['user']['id'] as String;
      await call(
        '/posts',
        method: 'POST',
        token: ta,
        data: {'text': 'Owned post'},
      );
      await call(
        '/direct/$aid',
        method: 'POST',
        token: tb,
        data: {'text': 'Chat'},
      );
      await call(
        '/account/password',
        method: 'POST',
        token: ta,
        data: {'password': 'incorrect', 'newPassword': 'DifferentPass123!'},
        status: 400,
      );
      await call(
        '/account/password',
        method: 'POST',
        token: ta,
        data: {
          'password': 'StrongPass123!',
          'newPassword': 'DifferentPass123!',
        },
      );
      await call('/me', token: ta, status: 401);
      await call(
        '/auth/login',
        method: 'POST',
        data: {'email': 'owner@example.test', 'password': 'StrongPass123!'},
        status: 401,
      );
      final fresh = await call(
        '/auth/login',
        method: 'POST',
        data: {'email': 'owner@example.test', 'password': 'DifferentPass123!'},
      );
      await call(
        '/account/delete',
        method: 'POST',
        token: fresh['token'],
        data: {'password': 'DifferentPass123!'},
      );
      await call('/me', token: fresh['token'], status: 401);
      expect(app.find('users', aid), isNull);
      expect(app.rows('posts'), isEmpty);
      expect(app.rows('direct'), isEmpty);
      final restored = ClubServer('${dir.path}/club.json');
      expect(restored.find('users', aid), isNull);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test('recovery codes are single use and invalidate sessions', () async {
    final account = await register('recover@example.test');
    final token = account['token'] as String;
    final recovery = await call(
      '/account/recovery',
      method: 'POST',
      token: token,
      data: {'password': 'StrongPass123!'},
    );
    final code = recovery['code'];
    expect(
      File('${dir.path}/club.json').readAsStringSync().contains(code),
      false,
    );
    await call(
      '/auth/recover',
      method: 'POST',
      data: {
        'email': 'recover@example.test',
        'code': 'wrong',
        'newPassword': 'RecoveredPass123!',
      },
      status: 400,
    );
    await call(
      '/auth/recover',
      method: 'POST',
      data: {
        'email': 'recover@example.test',
        'code': code,
        'newPassword': 'RecoveredPass123!',
      },
    );
    await call('/me', token: token, status: 401);
    await call(
      '/auth/recover',
      method: 'POST',
      data: {
        'email': 'recover@example.test',
        'code': code,
        'newPassword': 'AnotherPass123!',
      },
      status: 400,
    );
    final fresh = await call(
      '/auth/login',
      method: 'POST',
      data: {'email': 'recover@example.test', 'password': 'RecoveredPass123!'},
    );
    expect(fresh['user']['email'], 'recover@example.test');
  }, timeout: const Timeout(Duration(minutes: 2)));
  test('required verification gates content and quiz questions advance without leaking answers', () async {
    final account = await register('verified@example.test');
    final token = account['token'] as String;
    app.requireVerification = true;
    await call('/feed', token: token, status: 403);
    await call(
      '/verification',
      method: 'POST',
      token: token,
      data: {
        'role': 'student',
        'reference': 'University reference',
        'note': '',
      },
    );
    await call('/me', token: token);
    app.find('users', account['user']['id'])!['verified'] = true;
    app.save();
    await call('/feed', token: token);
    for (var i = 0; i < questions.length; i++) {
      final quiz = await call('/quiz', token: token);
      expect(quiz.containsKey('answer'), false);
      expect(quiz['id'], questions[i]['id']);
      await call(
        '/quiz/answer',
        method: 'POST',
        token: token,
        data: {'id': quiz['id'], 'answer': questions[i]['answer']},
      );
    }
    expect((await call('/quiz', token: token))['done'], true);
    expect(
      (await call('/leaderboard', token: token))['items'][0]['points'],
      questions.length * 10,
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
  test(
    'math rounds have server deadlines, ownership and one daily reward',
    () async {
      final a = await register('mathplayer@example.test'),
          b = await register('otherplayer@example.test');
      final token = a['token'] as String;
      final round = await call(
        '/games/math/start',
        method: 'POST',
        token: token,
      );
      expect((round['questions'] as List).length, 10);
      expect(round.toString().contains('answer'), false);
      expect(
        (await call('/games/math/start', method: 'POST', token: token))['id'],
        round['id'],
      );
      final saved = app.find('rounds', round['id'])!;
      final answers = (saved['questions'] as List)
          .map((q) => q['answer'])
          .toList();
      await call(
        '/games/math/submit',
        method: 'POST',
        token: b['token'],
        data: {'id': round['id'], 'answers': answers},
        status: 404,
      );
      saved['expires'] = DateTime.now()
          .toUtc()
          .subtract(const Duration(seconds: 1))
          .toIso8601String();
      await call(
        '/games/math/submit',
        method: 'POST',
        token: token,
        data: {'id': round['id'], 'answers': answers},
        status: 400,
      );
      final fresh = await call(
        '/games/math/start',
        method: 'POST',
        token: token,
      );
      final expected = (app.find('rounds', fresh['id'])!['questions'] as List)
          .map((q) => q['answer'])
          .toList();
      final result = await call(
        '/games/math/submit',
        method: 'POST',
        token: token,
        data: {'id': fresh['id'], 'answers': expected},
      );
      expect(result['points'], 50);
      await call(
        '/games/math/submit',
        method: 'POST',
        token: token,
        data: {'id': fresh['id'], 'answers': expected},
      );
      expect(
        (await call('/games/math/start', method: 'POST', token: token))['done'],
        true,
      );
      expect(
        (await call('/leaderboard', token: token))['items'][0]['points'],
        50,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test('media is private before attachment, university scoped, deleted with owner content', () async {
    final a = await register('photo@example.test'),
        b = await register('viewer@example.test'),
        c = await register('outside@example.test', uni: 'alex');
    final ta = a['token'] as String,
        tb = b['token'] as String,
        tc = c['token'] as String;
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aPioAAAAASUVORK5CYII=';
    await call(
      '/media',
      method: 'POST',
      token: ta,
      data: {
        'data': base64Encode(utf8.encode('<script>not an image</script>')),
      },
      status: 400,
    );
    final media = await call(
      '/media',
      method: 'POST',
      token: ta,
      data: {'data': png},
    );
    final mid = media['id'] as String;
    Future<int> download(String token) async {
      final client = HttpClient();
      try {
        final req = await client.getUrl(Uri.parse('$base/media/$mid'));
        req.headers.set('Authorization', 'Bearer $token');
        final res = await req.close();
        await res.drain<void>();
        return res.statusCode;
      } finally {
        client.close(force: true);
      }
    }

    expect(await download(tb), 404);
    expect(await download(ta), 200);
    final post = await call(
      '/posts',
      method: 'POST',
      token: ta,
      data: {'text': '', 'media': mid},
    );
    expect(await download(tb), 200);
    app.requireVerification = true;
    expect(await download(tb), 403);
    app.requireVerification = false;
    expect(await download(tc), 404);
    await call(
      '/posts',
      method: 'POST',
      token: tb,
      data: {'text': 'Steal attachment', 'media': mid},
      status: 400,
    );
    await call('/posts/${post['id']}', method: 'DELETE', token: ta);
    expect(app.mediaFile(mid).existsSync(), false);
    expect(await download(ta), 404);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
