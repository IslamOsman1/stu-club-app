import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../bin/server.dart';

void main() {
  late Directory dir;
  late ClubServer app;
  late HttpServer server;
  Future<Map<String, dynamic>> call(
    String path, {
    String? token,
    String method = 'GET',
    Map<String, dynamic>? data,
    int status = 200,
  }) async {
    final client = HttpClient();
    try {
      final req = await client.openUrl(
        method,
        Uri.parse('http://127.0.0.1:${server.port}$path'),
      );
      req.headers.contentType = ContentType.json;
      if (token != null) req.headers.set('Authorization', 'Bearer $token');
      if (data != null) req.write(jsonEncode(data));
      final res = await req.close();
      final text = await utf8.decoder.bind(res).join();
      expect(res.statusCode, status, reason: '$method $path $text');
      return jsonDecode(text) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> reg(String name, {String uni = 'cairo'}) => call(
    '/auth/register',
    method: 'POST',
    data: {
      'name': name,
      'email': '$name@example.test',
      'password': 'StrongPass123!',
      'university': uni,
    },
  );
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('stu-product-');
    app = ClubServer('${dir.path}/club.json');
    server = await app.start(port: 0);
  });
  tearDown(() async {
    await server.close(force: true);
    dir.deleteSync(recursive: true);
  });
  test('production starts without fabricated institutions or groups', () async {
    final fresh = ClubServer('${dir.path}/fresh/club.json', seedCatalog: false);
    expect(fresh.rows('users'), isEmpty);
    expect(fresh.rows('groups'), isEmpty);
    expect(
      fresh.institutionList().where((i) => i['kind'] != 'platform'),
      isEmpty,
    );
  });
  test(
    'delegated roles scope management and session handles revoke independently',
    () async {
      final a = await reg('owner'),
          b = await reg('delegate'),
          c = await reg('outsider', uni: 'ain_shams');
      final at = a['token'] as String, bt = b['token'] as String;
      app.find('users', a['user']['id'])!['role'] = 'admin';
      await call(
        '/product/manage/roles',
        token: at,
        method: 'POST',
        data: {'user': b['user']['id'], 'role': 'moderator'},
      );
      await call('/product/account', token: bt, status: 401);
      final login = await call(
            '/auth/login',
            method: 'POST',
            data: {
              'email': 'delegate@example.test',
              'password': 'StrongPass123!',
            },
          ),
          mt = login['token'] as String;
      await call(
        '/product/manage/roles',
        token: mt,
        method: 'POST',
        data: {'user': c['user']['id'], 'role': 'institution_admin'},
        status: 403,
      );
      final scopedOverview = await call('/product/manage/overview', token: mt);
      expect(scopedOverview['users'], isEmpty);
      await call(
        '/admin/users/${c['user']['id']}',
        token: mt,
        method: 'PATCH',
        data: {'disabled': true},
        status: 403,
      );
      final sessions = await call('/product/sessions', token: mt);
      expect(jsonEncode(sessions), isNot(contains(mt)));
      final handle = sessions['items'][0]['id'];
      await call(
        '/product/sessions/$handle',
        token: at,
        method: 'DELETE',
        status: 404,
      );
      await call('/product/sessions/$handle', token: mt, method: 'DELETE');
      await call('/product/account', token: mt, status: 401);
    },
  );
  test(
    'events enforce capacity, private attendance codes and host control',
    () async {
      final a = await reg('host'),
          b = await reg('attendee'),
          c = await reg('late');
      final at = a['token'] as String,
          bt = b['token'] as String,
          ct = c['token'] as String;
      app.find('users', a['user']['id'])!['role'] = 'admin';
      final current = DateTime.now().toUtc();
      final event = await call(
        '/product/events',
        token: at,
        method: 'POST',
        data: {
          'title': 'لقاء حقيقي',
          'text': 'تفاصيل اللقاء',
          'location': 'قاعة الأنشطة',
          'starts': current.add(const Duration(minutes: 10)).toIso8601String(),
          'ends': current.add(const Duration(hours: 1)).toIso8601String(),
          'capacity': 1,
          'section': null,
        },
      );
      final eid = event['id'];
      await call('/product/events/$eid/register', token: bt, method: 'POST');
      await call('/product/events/$eid/register', token: bt, method: 'POST');
      await call(
        '/product/events/$eid/register',
        token: ct,
        method: 'POST',
        status: 409,
      );
      final shown = await call('/product/events', token: bt);
      expect(shown['items'][0].containsKey('checkinCode'), isFalse);
      await call('/product/events/$eid/registrations', token: bt, status: 403);
      await call(
        '/product/events/$eid/cancel',
        token: bt,
        method: 'POST',
        status: 403,
      );
      final host = await call('/product/events', token: at),
          code = host['items'][0]['checkinCode'];
      await call(
        '/product/events/$eid/checkin',
        token: bt,
        method: 'POST',
        data: {'code': 'wrong'},
        status: 403,
      );
      await call(
        '/product/events/$eid/checkin',
        token: bt,
        method: 'POST',
        data: {'code': code},
      );
      final list = await call('/product/events/$eid/registrations', token: at);
      expect(list['items'][0]['attended'], isTrue);
    },
  );
  test(
    'voice messages remain private; message edits and reads require ownership',
    () async {
      final a = await reg('sender'),
          b = await reg('receiver'),
          c = await reg('third');
      final at = a['token'] as String,
          bt = b['token'] as String,
          ct = c['token'] as String;
      final bytes = [0, 0, 0, 24, ...ascii.encode('ftypM4A '), 0, 0, 0, 0];
      final upload = await call(
            '/product/voice-files',
            token: at,
            method: 'POST',
            data: {'data': base64Encode(bytes)},
          ),
          vid = upload['id'];
      final msg = await call(
        '/product/chat/direct/${b['user']['id']}',
        token: at,
        method: 'POST',
        data: {'text': 'تسجيل', 'voice': vid},
      );
      await call('/product/voice-files/$vid', token: ct, status: 404);
      final list = await call(
        '/product/chat/direct/${a['user']['id']}',
        token: bt,
      );
      expect(list['items'].length, 1);
      final mid = list['items'][0]['id'];
      expect(msg['id'], mid);
      await call(
        '/product/messages/direct/$mid',
        token: ct,
        method: 'PATCH',
        data: {'text': 'hack'},
        status: 403,
      );
      await call(
        '/product/messages/direct/$mid',
        token: at,
        method: 'PATCH',
        data: {'text': 'تعديل حقيقي'},
      );
      await call(
        '/product/chat/direct/${a['user']['id']}/read',
        token: bt,
        method: 'POST',
        data: {},
      );
      final mine = await call(
        '/product/chat/direct/${b['user']['id']}',
        token: at,
      );
      expect(mine['items'][0]['readCount'], 1);
      await call(
        '/reports',
        token: bt,
        method: 'POST',
        data: {'type': 'direct', 'target': mid, 'reason': 'مراجعة تسجيل صوتي'},
      );
      app.find('users', c['user']['id'])!['role'] = 'admin';
      await call(
        '/admin/reports/${app.rows('reports').last['id']}',
        token: ct,
        method: 'POST',
        data: {'action': 'remove', 'reason': 'مخالفة قواعد المجتمع'},
      );
      await call('/product/voice-files/$vid', token: bt, status: 404);
      final appeal = await call(
        '/product/appeals',
        token: at,
        method: 'POST',
        data: {'report': app.rows('reports').last['id'], 'text': 'أطلب مراجعة القرار'},
      );
      await call(
        '/product/manage/appeals/${appeal['id']}',
        token: ct,
        method: 'POST',
        data: {
          'status': 'accepted',
          'response': 'تمت المراجعة والتواصل مع صاحب المحتوى',
        },
      );
      final appeals = await call('/product/appeals', token: at);
      expect(appeals['items'][0]['status'], 'accepted');
      await call(
        '/account/delete',
        token: at,
        method: 'POST',
        data: {'password': 'StrongPass123!'},
      );
      expect(app.rows('voiceAttachments'), isEmpty);
      expect(Directory('${dir.path}/voice').listSync(), isEmpty);
    },
  );
  test('voice rooms enforce speaker permission, private signaling and host removal', () async {
    final a = await reg('speaker'),
        b = await reg('listener'),
        c = await reg('unjoined');
    final at = a['token'] as String,
        bt = b['token'] as String,
        ct = c['token'] as String;
    final room = await call(
          '/product/rooms',
          token: at,
          method: 'POST',
          data: {'title': 'حوار', 'section': null},
        ),
        rid = room['id'];
    await call('/product/rooms/$rid/join', token: at, method: 'POST');
    final joined = await call(
      '/product/rooms/$rid/join',
      token: bt,
      method: 'POST',
    );
    await call('/product/rooms/$rid/state', token: ct, status: 403);
    await call(
      '/product/rooms/$rid/mute',
      token: bt,
      method: 'POST',
      data: {'muted': false},
      status: 403,
    );
    await call(
      '/product/rooms/$rid/control',
      token: bt,
      method: 'POST',
      data: {'participant': joined['self']['id'], 'action': 'speaker'},
      status: 403,
    );
    await call(
      '/product/rooms/$rid/control',
      token: at,
      method: 'POST',
      data: {'participant': joined['self']['id'], 'action': 'speaker'},
    );
    await call(
      '/product/rooms/$rid/mute',
      token: bt,
      method: 'POST',
      data: {'muted': false},
    );
    await call(
      '/product/rooms/$rid/control',
      token: at,
      method: 'POST',
      data: {'participant': joined['self']['id'], 'action': 'remove'},
    );
    await call(
      '/product/rooms/$rid/join',
      token: bt,
      method: 'POST',
      status: 403,
    );
  });
  test(
    'membership review and invitation quotas preserve institution isolation',
    () async {
      final a = await reg('membershipowner'), b = await reg('moving');
      final at = a['token'] as String, bt = b['token'] as String;
      app.find('users', a['user']['id'])!['role'] = 'admin';
      final created = await call(
            '/institutions',
            token: at,
            method: 'POST',
            data: {'name': 'مؤسسة فعلية', 'kind': 'university'},
          ),
          institution = created['id'];
      final request = await call(
        '/product/membership',
        token: bt,
        method: 'POST',
        data: {'institution': institution, 'note': 'طلب عضوية'},
      );
      await call(
        '/product/manage/membership/${request['id']}',
        token: bt,
        method: 'POST',
        data: {'approve': true, 'reason': ''},
        status: 403,
      );
      await call(
        '/product/manage/membership/${request['id']}',
        token: at,
        method: 'POST',
        data: {'approve': true, 'reason': 'تمت المراجعة'},
      );
      final account = await call('/product/account', token: bt);
      expect(account['user']['university'], institution);
      await call(
        '/institutions/select',
        token: at,
        method: 'POST',
        data: {'institution': institution},
      );
      final invitation = await call(
        '/product/manage/invitations',
        token: at,
        method: 'POST',
        data: {'role': 'doctor', 'limit': 1},
      );
      final c = await reg('invited');
      final ct = c['token'] as String;
      await call(
        '/product/invitation/claim',
        token: ct,
        method: 'POST',
        data: {'code': invitation['code']},
      );
      final teacher = await call('/product/account', token: ct);
      expect(teacher['user']['role'], 'doctor');
      expect(teacher['user']['verified'], isTrue);
      await call(
        '/product/invitation/claim',
        token: bt,
        method: 'POST',
        data: {'code': invitation['code']},
        status: 400,
      );
      final listed = await call('/product/manage/invitations', token: at);
      expect(jsonEncode(listed), isNot(contains(invitation['code'])));
      expect(jsonEncode(listed), isNot(contains('digest')));
    },
  );
  test('group invitations require recipient consent and replies stay in their thread', () async {
    final a = await reg('groupowner'),
        b = await reg('groupguest'),
        c = await reg('groupother');
    final at = a['token'] as String,
        bt = b['token'] as String,
        ct = c['token'] as String;
    final group = await call(
          '/product/groups',
          token: at,
          method: 'POST',
          data: {'name': 'مجموعة دراسة', 'description': 'مناقشة'},
        ),
        gid = group['id'];
    await call(
      '/product/groups/$gid/invite',
      token: at,
      method: 'POST',
      data: {'user': b['user']['id']},
    );
    expect(
      app.find('groups', gid)!['members'],
      isNot(contains(b['user']['id'])),
    );
    final invites = await call('/product/group-invites', token: bt),
        invite = invites['items'][0]['id'];
    await call(
      '/product/group-invites/$invite',
      token: ct,
      method: 'POST',
      data: {'accept': true},
      status: 404,
    );
    await call(
      '/product/group-invites/$invite',
      token: bt,
      method: 'POST',
      data: {'accept': true},
    );
    await call(
      '/product/chat/group/$gid',
      token: bt,
      method: 'POST',
      data: {'text': 'انضممت بإرادتي'},
    );
    final list = await call('/product/chat/group/$gid', token: at);
    expect(list['items'].length, 1);
    await call('/product/chat/group/$gid', token: ct, status: 403);
  });
  test(
    'scheduled announcements hide future content and notify once when due',
    () async {
      final a = await reg('announcementowner'), b = await reg('reader');
      final at = a['token'] as String, bt = b['token'] as String;
      app.find('users', a['user']['id'])!['role'] = 'admin';
      final later = DateTime.now().toUtc().add(const Duration(days: 1));
      final announcement = await call(
        '/announcements',
        token: at,
        method: 'POST',
        data: {
          'text': 'خبر مجدول',
          'importance': 'urgent',
          'publishAt': later.toIso8601String(),
        },
      );
      expect((await call('/announcements', token: bt))['items'], isEmpty);
      app.find(
        'announcements',
        announcement['id'],
      )!['publishAt'] = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 1))
          .toIso8601String();
      app.scheduledAnnouncements();
      app.scheduledAnnouncements();
      expect((await call('/announcements', token: bt))['items'].length, 1);
      expect(
        app
            .rows('notifications')
            .where(
              (r) =>
                  r['user'] == b['user']['id'] && r['type'] == 'announcement',
            )
            .length,
        1,
      );
    },
  );
}
