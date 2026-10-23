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
  test('schools enforce grade and age cohorts; documents polls and academic reports enforce section access', () async {
    final admin = await register('admin@example.test');
    final at = admin['token'] as String;
    app.find('users', admin['user']['id'])!['role'] = 'admin';
    final inst = await call(
      '/institutions',
      method: 'POST',
      token: at,
      data: {'name': 'مدرسة اختبار', 'kind': 'school'},
    );
    final schoolId = inst['id'] as String;
    await call(
      '/auth/register',
      method: 'POST',
      data: {
        'name': 'invalid',
        'email': 'invalid@example.test',
        'password': 'StrongPass123!',
        'university': schoolId,
      },
      status: 400,
    );
    Future<Map<String, dynamic>> student(String name, int year, int grade) =>
        call(
          '/auth/register',
          method: 'POST',
          data: {
            'name': name,
            'email': '$name@example.test',
            'password': 'StrongPass123!',
            'university': schoolId,
            'birthYear': year,
            'grade': grade,
          },
        );
    final teacher = await student('teacher', 1990, 9),
        a = await student('alice', 2011, 9),
        b = await student('bob', 2011, 9),
        older = await student('older', 2008, 9),
        otherGrade = await student('othergrade', 2011, 8);
    for (final account in [teacher, a, b, older, otherGrade]) {
      app.find('users', account['user']['id'])!['verified'] = true;
    }
    final tid = teacher['user']['id'] as String,
        aid = a['user']['id'] as String,
        bid = b['user']['id'] as String,
        tt = teacher['token'] as String,
        ta = a['token'] as String,
        tb = b['token'] as String,
        to = older['token'] as String;
    app.find('users', tid)!['role'] = 'doctor';
    await call(
      '/institutions/select',
      method: 'POST',
      token: at,
      data: {'institution': schoolId},
    );
    await call(
      '/friends/${older['user']['id']}',
      method: 'POST',
      token: ta,
      status: 403,
    );
    await call(
      '/friends/${otherGrade['user']['id']}',
      method: 'POST',
      token: ta,
      status: 403,
    );
    await call('/friends/$bid', method: 'POST', token: ta);
    await call(
      '/direct/${older['user']['id']}',
      method: 'POST',
      token: ta,
      data: {'text': 'forbidden'},
      status: 403,
    );
    await call(
      '/direct/$aid',
      method: 'POST',
      token: tt,
      data: {'text': 'unassigned'},
      status: 403,
    );
    final course = await call(
      '/courses',
      method: 'POST',
      token: at,
      data: {'name': 'العلوم', 'code': 'SCI'},
    );
    final section = await call(
      '/courses/${course['id']}/sections',
      method: 'POST',
      token: at,
      data: {
        'name': 'أ',
        'teachers': [tid],
        'students': [aid, bid, older['user']['id'], otherGrade['user']['id']],
      },
    );
    final sid = section['id'];
    await call(
      '/direct/$aid',
      method: 'POST',
      token: tt,
      data: {'text': 'assigned teacher'},
    );
    final group = ((await call('/groups', token: ta))['items'] as List).single;
    await call(
      '/groups/${group['id']}/messages',
      method: 'POST',
      token: ta,
      data: {'text': 'cohort message'},
    );
    expect(
      (await call('/groups/${group['id']}/messages', token: to))['items'],
      isEmpty,
    );
    final pdf = await call(
      '/documents',
      method: 'POST',
      token: tt,
      data: {
        'name': 'lesson.pdf',
        'data': base64Encode(utf8.encode('%PDF-1.4\nlesson\n%%EOF')),
        'section': sid,
      },
    );
    await call(
      '/documents',
      method: 'POST',
      token: tt,
      data: {'name': '../evil.pdf', 'data': 'a', 'section': sid},
      status: 400,
    );
    final text = await call(
      '/documents',
      method: 'POST',
      token: ta,
      data: {
        'name': 'notes.txt',
        'data': base64Encode(utf8.encode('study notes')),
        'section': sid,
      },
    );
    final olderDocs = (await call('/documents', token: to))['items'] as List;
    expect(olderDocs.map((r) => r['id']), contains(pdf['id']));
    expect(olderDocs.map((r) => r['id']), isNot(contains(text['id'])));
    final client = HttpClient();
    final request = await client.getUrl(
      Uri.parse('$base/documents/${pdf['id']}/content'),
    );
    request.headers.set('Authorization', 'Bearer $ta');
    final response = await request.close();
    expect(response.statusCode, 200);
    expect(
      response.headers.value('content-disposition'),
      startsWith('attachment;'),
    );
    expect(await utf8.decoder.bind(response).join(), startsWith('%PDF-'));
    client.close();
    final poll = await call(
      '/polls',
      method: 'POST',
      token: tt,
      data: {
        'question': 'هل الموعد مناسب؟',
        'options': ['نعم', 'لا'],
        'section': sid,
      },
    );
    await call(
      '/polls/${poll['id']}/vote',
      method: 'POST',
      token: ta,
      data: {'choice': 0},
    );
    await call(
      '/polls/${poll['id']}/vote',
      method: 'POST',
      token: ta,
      data: {'choice': 1},
    );
    final results = ((await call('/polls', token: tb))['items'] as List).single;
    expect(results['total'], 1);
    expect(results['counts'], [0, 1]);
    expect(results['votes'], isNull);
    await call(
      '/polls/${poll['id']}/close',
      method: 'POST',
      token: ta,
      status: 403,
    );
    await call('/polls/${poll['id']}/close', method: 'POST', token: tt);
    await call(
      '/polls/${poll['id']}/vote',
      method: 'POST',
      token: ta,
      data: {'choice': 0},
      status: 409,
    );
    final ann = await call(
      '/announcements',
      method: 'POST',
      token: tt,
      data: {'text': 'إعلان دراسي', 'section': sid},
    );
    await call('/announcements/${ann['id']}/view', method: 'POST', token: ta);
    await call('/announcements/${ann['id']}/view', method: 'POST', token: ta);
    final report =
        ((await call('/announcement-reports', token: tt))['items'] as List)
            .single;
    expect(report['eligible'], 4);
    expect(report['seen'], 1);
    expect(report['percent'], 25);
    expect(report['averageSeconds'], isNonNegative);
    await call('/announcement-reports', token: ta, status: 403);
    await call('/documents/${text['id']}', method: 'DELETE', token: ta);
    expect(
      File('${app.file.parent.path}/documents/${text['id']}.bin').existsSync(),
      false,
    );
  });
  test('memory daily rewards and tournament games are scored by the server without friendship requirements', () async {
    final admin = await register('organizer@example.test'),
        a = await register('playerone@example.test'),
        b = await register('playertwo@example.test');
    final at = admin['token'] as String,
        ta = a['token'] as String,
        tb = b['token'] as String,
        aid = a['user']['id'] as String,
        bid = b['user']['id'] as String;
    app.find('users', admin['user']['id'])!['role'] = 'admin';
    for (var n = 0; n < 2; n++) {
      final round = await call(
        '/games/memory/start',
        method: 'POST',
        token: ta,
      );
      expect((round['cards'] as List).every((v) => v == null), true);
      final r = app.find('memoryRounds', round['id'])!;
      final values = r['values'] as List;
      for (var value = 0; value < 6; value++) {
        final indices = [
          for (var i = 0; i < 12; i++)
            if (values[i] == value) i,
        ];
        await call(
          '/memory/${round['id']}/flip',
          method: 'POST',
          token: ta,
          data: {'cell': indices[0]},
        );
        await call(
          '/memory/${round['id']}/flip',
          method: 'POST',
          token: ta,
          data: {'cell': indices[1]},
        );
      }
    }
    expect(
      app
          .rows('scores')
          .where(
            (r) =>
                r['user'] == aid && (r['quiz'] as String).startsWith('memory:'),
          )
          .length,
      1,
    );
    final tournament = await call(
      '/tournaments',
      method: 'POST',
      token: at,
      data: {'title': 'بطولة الاختبار'},
    );
    final tid = tournament['id'];
    await call('/tournaments/$tid/join', method: 'POST', token: ta);
    await call('/tournaments/$tid/join', method: 'POST', token: tb);
    await call(
      '/tournaments/$tid/start',
      method: 'POST',
      token: ta,
      status: 403,
    );
    await call('/tournaments/$tid/start', method: 'POST', token: at);
    final duel = ((await call('/duels', token: ta))['items'] as List).single;
    expect(duel['state'], 'playing');
    expect(app.areFriends(aid, bid), false);
    for (final step in [(ta, 0), (tb, 3), (ta, 1), (tb, 4), (ta, 2)]) {
      await call(
        '/duels/${duel['id']}/move',
        method: 'POST',
        token: step.$1,
        data: {'cell': step.$2},
      );
    }
    final table =
        ((await call('/tournaments', token: ta))['items'] as List).single;
    expect(table['finished'], true);
    expect((table['players'] as List).first['person']['id'], aid);
    expect((table['players'] as List).first['points'], 3);
  });
  test('email codes are private, one-use, rate limited and password reset revokes sessions', () async {
    final account = await register('mailowner@example.test');
    final token = account['token'] as String;
    String? message;
    app.mailTransport = (email, subject, text) async {
      message = text;
    };
    final response = await call(
      '/email/verify/request',
      method: 'POST',
      token: token,
    );
    expect(response.containsKey('code'), false);
    final code = RegExp(r'\d{6}').firstMatch(message!)!.group(0)!;
    await call(
      '/email/verify/confirm',
      method: 'POST',
      token: token,
      data: {'code': 'bad'},
      status: 400,
    );
    await call(
      '/email/verify/confirm',
      method: 'POST',
      token: token,
      data: {'code': code},
    );
    expect((await call('/services', token: token))['emailVerified'], true);
    await call(
      '/email/verify/confirm',
      method: 'POST',
      token: token,
      data: {'code': code},
      status: 400,
    );
    await call(
      '/auth/email-reset/request',
      method: 'POST',
      data: {'email': 'mailowner@example.test'},
    );
    final reset = RegExp(r'\d{6}').firstMatch(message!)!.group(0)!;
    await call(
      '/auth/email-reset/confirm',
      method: 'POST',
      data: {
        'email': 'mailowner@example.test',
        'code': reset,
        'password': 'ChangedPass123!',
      },
    );
    await call('/me', token: token, status: 401);
    await call(
      '/auth/login',
      method: 'POST',
      data: {'email': 'mailowner@example.test', 'password': 'ChangedPass123!'},
    );
    await call(
      '/auth/email-reset/confirm',
      method: 'POST',
      data: {
        'email': 'mailowner@example.test',
        'code': reset,
        'password': 'ChangedAgain123!',
      },
      status: 400,
    );
  });
}
