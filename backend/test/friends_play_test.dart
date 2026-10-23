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
      if (status != 0) {
        expect(res.statusCode, status, reason: result.toString());
      } else {
        result['_status'] = res.statusCode;
      }
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
  test('friend requests require consent, same institution and compatible roles; blocking removes relationships', () async {
    final a = await register('alice@example.test'),
        b = await register('bob@example.test'),
        c = await register('carol@example.test'),
        outside = await register('outside@example.test', uni: 'alex');
    final at = a['token'] as String,
        bt = b['token'] as String,
        ct = c['token'] as String,
        aid = a['user']['id'] as String,
        bid = b['user']['id'] as String,
        cid = c['user']['id'] as String;
    await call('/friends/$aid', method: 'POST', token: at, status: 403);
    await call(
      '/friends/${outside['user']['id']}',
      method: 'POST',
      token: at,
      status: 404,
    );
    app.find('users', cid)!.addAll({'role': 'doctor', 'verified': true});
    await call('/friends/$cid', method: 'POST', token: at, status: 403);
    expect(
      ((await call('/friend-people', token: at))['items'] as List).map(
        (p) => p['id'],
      ),
      [bid],
    );
    final request = await call('/friends/$bid', method: 'POST', token: at);
    await call('/friends/$bid', method: 'POST', token: at);
    expect(app.rows('friends').length, 1);
    expect((await call('/friends', token: at))['items'], isEmpty);
    expect(((await call('/friends', token: bt))['incoming'] as List).length, 1);
    await call(
      '/friend-requests/${request['id']}/accept',
      method: 'POST',
      token: at,
      status: 404,
    );
    await call(
      '/friend-requests/${request['id']}/accept',
      method: 'POST',
      token: ct,
      status: 404,
    );
    await call('/friends/$aid', method: 'POST', token: bt, status: 409);
    await call(
      '/friend-requests/${request['id']}/accept',
      method: 'POST',
      token: bt,
    );
    expect(
      ((await call('/friends', token: at))['items'] as List)
          .single['person']['id'],
      bid,
    );
    expect(ClubServer(app.file.path).areFriends(aid, bid), true);
    await call('/blocks/$bid', method: 'POST', token: at);
    expect(app.areFriends(aid, bid), false);
    expect((await call('/friends', token: bt))['items'], isEmpty);
    await call('/friends/$aid', method: 'POST', token: bt, status: 403);
    await call('/blocks/$bid', method: 'DELETE', token: at);
    expect((await call('/friends', token: at))['items'], isEmpty);
    final again = await call('/friends/$bid', method: 'POST', token: at);
    await call('/friends/$aid', method: 'DELETE', token: bt);
    expect(app.find('friends', again['id']), isNull);
    await call('/friends/$bid', method: 'POST', token: at);
    await call('/friends/$bid', method: 'DELETE', token: at);
    expect(app.rows('friends'), isEmpty);
  });

  test('online XO validates invitation, participant, turn, concurrent moves, winner, expiry and deletion', () async {
    final a = await register('playerx@example.test'),
        b = await register('playero@example.test'),
        c = await register('spectator@example.test');
    final at = a['token'] as String,
        bt = b['token'] as String,
        ct = c['token'] as String,
        aid = a['user']['id'] as String,
        bid = b['user']['id'] as String;
    await call(
      '/duels',
      method: 'POST',
      token: at,
      data: {'target': bid},
      status: 403,
    );
    final request = await call('/friends/$bid', method: 'POST', token: at);
    await call(
      '/friend-requests/${request['id']}/accept',
      method: 'POST',
      token: bt,
    );
    final invite = await call(
      '/duels',
      method: 'POST',
      token: at,
      data: {'target': bid},
    );
    final gid = invite['id'];
    await call(
      '/duels',
      method: 'POST',
      token: at,
      data: {'target': bid},
      status: 409,
    );
    await call('/duels/$gid', token: ct, status: 404);
    await call('/duels/$gid/accept', method: 'POST', token: at, status: 409);
    await call(
      '/duels/$gid/move',
      method: 'POST',
      token: at,
      data: {'cell': 0},
      status: 409,
    );
    await call('/duels/$gid/accept', method: 'POST', token: bt);
    await call(
      '/duels/$gid/move',
      method: 'POST',
      token: bt,
      data: {'cell': 0},
      status: 409,
    );
    await call(
      '/duels/$gid/move',
      method: 'POST',
      token: at,
      data: {'cell': 99},
      status: 400,
    );
    final racing = await Future.wait([
      call(
        '/duels/$gid/move',
        method: 'POST',
        token: at,
        data: {'cell': 0},
        status: 0,
      ),
      call(
        '/duels/$gid/move',
        method: 'POST',
        token: at,
        data: {'cell': 1},
        status: 0,
      ),
    ]);
    expect(racing.map((r) => r['_status']).toList()..sort(), [200, 409]);
    final board = app.find('duels', gid)!['board'] as List;
    expect(board.where((v) => v == 'X').length, 1);
    final first = board.indexOf('X');
    await call(
      '/duels/$gid/move',
      method: 'POST',
      token: bt,
      data: {'cell': first},
      status: 409,
    );
    await call(
      '/duels/$gid/move',
      method: 'POST',
      token: bt,
      data: {'cell': 3},
    );
    await call(
      '/duels/$gid/move',
      method: 'POST',
      token: at,
      data: {'cell': first == 0 ? 1 : 0},
    );
    await call(
      '/duels/$gid/move',
      method: 'POST',
      token: bt,
      data: {'cell': 4},
    );
    final win = await call(
      '/duels/$gid/move',
      method: 'POST',
      token: at,
      data: {'cell': 2},
    );
    expect(win['state'], 'finished');
    expect(win['winner'], aid);
    await call(
      '/duels/$gid/move',
      method: 'POST',
      token: bt,
      data: {'cell': 5},
      status: 409,
    );
    expect(ClubServer(app.file.path).find('duels', gid)!['winner'], aid);
    final drawing = await call(
      '/duels',
      method: 'POST',
      token: at,
      data: {'target': bid},
    );
    await call('/duels/${drawing['id']}/accept', method: 'POST', token: bt);
    final drawMoves = [0, 1, 2, 4, 3, 5, 7, 6, 8];
    Map<String, dynamic> drawResult = {};
    for (var i = 0; i < drawMoves.length; i++) {
      drawResult = await call(
        '/duels/${drawing['id']}/move',
        method: 'POST',
        token: i.isEven ? at : bt,
        data: {'cell': drawMoves[i]},
      );
    }
    expect(drawResult['state'], 'finished');
    expect(drawResult['winner'], 'draw');
    final declined = await call(
      '/duels',
      method: 'POST',
      token: at,
      data: {'target': bid},
    );
    await call('/duels/${declined['id']}/cancel', method: 'POST', token: bt);
    expect(
      (await call('/duels/${declined['id']}', token: at))['state'],
      'cancelled',
    );
    await call(
      '/duels/${declined['id']}/accept',
      method: 'POST',
      token: bt,
      status: 409,
    );
    final expiring = await call(
      '/duels',
      method: 'POST',
      token: at,
      data: {'target': bid},
    );
    app.find('duels', expiring['id'])!['expires'] = DateTime.now()
        .toUtc()
        .subtract(const Duration(seconds: 1))
        .toIso8601String();
    await call(
      '/duels/${expiring['id']}/accept',
      method: 'POST',
      token: bt,
      status: 409,
    );
    expect(
      (await call('/duels/${expiring['id']}', token: at))['state'],
      'expired',
    );
    final cancelled = await call(
      '/duels',
      method: 'POST',
      token: at,
      data: {'target': bid},
    );
    await call('/duels/${cancelled['id']}/accept', method: 'POST', token: bt);
    await call('/blocks/$aid', method: 'POST', token: bt);
    expect(app.find('duels', cancelled['id'])!['state'], 'cancelled');
    await call('/duels/${cancelled['id']}', token: at, status: 403);
    await call(
      '/account/delete',
      method: 'POST',
      token: at,
      data: {'password': 'StrongPass123!'},
    );
    expect(app.rows('friends'), isEmpty);
    expect(app.rows('duels'), isEmpty);
  });
}
