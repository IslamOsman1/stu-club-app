part of 'server.dart';

extension FriendsPlay on ClubServer {
  bool pair(Map<dynamic, dynamic> row, String a, String b) =>
      (row['from'] == a && row['to'] == b) ||
      (row['from'] == b && row['to'] == a);
  bool areFriends(String a, String b) =>
      rows('friends').any((r) => pair(r, a, b) && r['state'] == 'accepted');
  void clearRelationship(String a, String b) {
    rows('friends').removeWhere((r) => pair(r, a, b));
    for (final game in rows('duels').where(
      (r) => pair(r, a, b) && ['pending', 'playing'].contains(r['state']),
    )) {
      game['state'] = 'cancelled';
    }
    rows('notifications').removeWhere(
      (n) =>
          [
            'friend_request',
            'friend_accept',
            'game_invite',
          ].contains(n['type']) &&
          ((n['user'] == a && n['actor'] == b) ||
              (n['user'] == b && n['actor'] == a)),
    );
  }

  Map<String, dynamic> socialPeer(String target, Map<String, dynamic> u) {
    final peer = find('users', target);
    sameUniversity(peer, u);
    if (target == u['id'] ||
        peer!['disabled'] == true ||
        blocked(u['id'], target) ||
        (u['role'] == 'student') != (peer['role'] == 'student') ||
        !schoolSocial(u, peer) ||
        ((requireVerification || school(u)) && peer['verified'] != true)) {
      throw ApiError(403, 'التواصل غير متاح مع هذا الحساب');
    }
    return peer;
  }

  bool expiredGame(Map<String, dynamic> game) {
    if (['pending', 'playing'].contains(game['state']) &&
        DateTime.parse(game['expires']).isBefore(DateTime.now().toUtc())) {
      game['state'] = 'expired';
      return true;
    }
    return false;
  }

  Map<String, dynamic> duelView(Map<String, dynamic> g, String uid) => {
    ...g,
    'person': author(g['from'] == uid ? g['to'] : g['from']),
    'yourMark': g['from'] == uid ? 'X' : 'O',
    'incoming': g['to'] == uid,
  };
  Future<Map<String, dynamic>?> friendsPlay(
    HttpRequest req,
    Map<String, dynamic> u,
  ) async {
    final path = req.uri.path, method = req.method, uid = u['id'] as String;
    final p = req.uri.pathSegments;
    if (path == '/friend-people' && method == 'GET') {
      final q = (req.uri.queryParameters['q'] ?? '').toLowerCase();
      final items = <dynamic>[];
      for (final peer in rows('users')) {
        try {
          socialPeer(peer['id'], u);
        } on ApiError {
          continue;
        }
        if ((peer['name'] as String).toLowerCase().contains(q)) {
          items.add(author(peer['id']));
        }
        if (items.length >= 100) break;
      }
      return {'items': items};
    }
    if (path == '/friends' && method == 'GET') {
      final accepted = <dynamic>[],
          incoming = <dynamic>[],
          outgoing = <dynamic>[];
      for (final r in rows(
        'friends',
      ).where((r) => r['from'] == uid || r['to'] == uid)) {
        final peerId = (r['from'] == uid ? r['to'] : r['from']) as String;
        try {
          socialPeer(peerId, u);
        } on ApiError {
          continue;
        }
        final value = {
          'id': r['id'],
          'person': author(peerId),
          'created': r['created'],
        };
        if (r['state'] == 'accepted') {
          accepted.add(value);
        } else if (r['to'] == uid) {
          incoming.add(value);
        } else {
          outgoing.add(value);
        }
      }
      return {'items': accepted, 'incoming': incoming, 'outgoing': outgoing};
    }
    if (p.length == 2 &&
        p[0] == 'friends' &&
        ['POST', 'DELETE'].contains(method)) {
      socialPeer(p[1], u);
      if (method == 'DELETE') {
        clearRelationship(uid, p[1]);
        save();
        return {'ok': true};
      }
      final existing = rows('friends').where((r) => pair(r, uid, p[1]));
      if (existing.isNotEmpty) {
        if (existing.first['state'] == 'pending' &&
            existing.first['to'] == uid) {
          throw ApiError(
            409,
            'لديك طلب وارد من هذا الحساب؛ اقبله من طلبات الصداقة',
          );
        }
        return {'id': existing.first['id'], 'state': existing.first['state']};
      }
      final r = {
        'id': id(),
        'from': uid,
        'to': p[1],
        'state': 'pending',
        'created': now(),
      };
      rows('friends').add(r);
      notify(p[1], uid, 'friend_request', 'طلب صداقة جديد', target: uid);
      save();
      return {'id': r['id'], 'state': 'pending'};
    }
    if (p.length == 3 &&
        p[0] == 'friend-requests' &&
        p[2] == 'accept' &&
        method == 'POST') {
      final r = find('friends', p[1]);
      if (r == null || r['to'] != uid) throw ApiError(404, 'الطلب غير موجود');
      socialPeer(r['from'], u);
      if (r['state'] != 'pending') throw ApiError(409, 'الطلب تمت معالجته');
      r['state'] = 'accepted';
      notify(
        r['from'],
        uid,
        'friend_accept',
        'تم قبول طلب صداقتك',
        target: uid,
      );
      save();
      return {'ok': true};
    }
    if (path == '/duels' && method == 'GET') {
      final items = <dynamic>[];
      var changed = false;
      for (final raw in rows(
        'duels',
      ).where((r) => r['from'] == uid || r['to'] == uid)) {
        final g = raw as Map<String, dynamic>;
        if (expiredGame(g)) changed = true;
        final peer = (g['from'] == uid ? g['to'] : g['from']) as String;
        try {
          socialPeer(peer, u);
        } on ApiError {
          continue;
        }
        if (!areFriends(uid, peer) && !tournamentDuel(g, u)) continue;
        items.add(duelView(g, uid));
      }
      if (changed) save();
      return {'items': items.reversed.take(50).toList()};
    }
    if (path == '/duels' && method == 'POST') {
      final b = await body(req), target = field(b, 'target', max: 100);
      socialPeer(target, u);
      if (!areFriends(uid, target)) {
        throw ApiError(403, 'أضف صديقك واقبل الصداقة أولًا');
      }
      final active = rows('duels').where(
        (g) =>
            pair(g, uid, target) &&
            !expiredGame(g) &&
            ['pending', 'playing'].contains(g['state']),
      );
      if (active.isNotEmpty) {
        throw ApiError(409, 'توجد دعوة أو مباراة مفتوحة بينكما');
      }
      final g = {
        'id': id(),
        'from': uid,
        'to': target,
        'state': 'pending',
        'board': List.filled(9, ''),
        'turn': uid,
        'winner': null,
        'created': now(),
        'expires': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 10))
            .toIso8601String(),
      };
      rows('duels').add(g);
      notify(
        target,
        uid,
        'game_invite',
        'دعوة للعب XO مع صديق',
        target: g['id'] as String,
      );
      save();
      return {'id': g['id']};
    }
    if (p.length >= 2 && p[0] == 'duels') {
      final g = find('duels', p[1]);
      if (g == null || (g['from'] != uid && g['to'] != uid)) {
        throw ApiError(404, 'المباراة غير موجودة');
      }
      final peer = (g['from'] == uid ? g['to'] : g['from']) as String;
      socialPeer(peer, u);
      if (!areFriends(uid, peer) && !tournamentDuel(g, u)) {
        throw ApiError(403, 'الصداقة غير متاحة');
      }
      if (expiredGame(g)) save();
      if (p.length == 2 && method == 'GET') return duelView(g, uid);
      if (p.length == 3 && method == 'POST') {
        if (p[2] == 'accept') {
          if (g['to'] != uid || g['state'] != 'pending') {
            throw ApiError(409, 'لا يمكنك قبول هذه الدعوة');
          }
          g['state'] = 'playing';
          g['expires'] = DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String();
          save();
          return duelView(g, uid);
        }
        if (p[2] == 'cancel') {
          if (!['pending', 'playing'].contains(g['state'])) {
            throw ApiError(409, 'انتهت المباراة');
          }
          g['state'] = 'cancelled';
          save();
          return duelView(g, uid);
        }
        if (p[2] == 'move') {
          final b = await body(req), index = b['cell'];
          if (expiredGame(g)) save();
          socialPeer(peer, u);
          if (!areFriends(uid, peer) && !tournamentDuel(g, u)) {
            throw ApiError(403, 'الصداقة غير متاحة');
          }
          if (g['state'] != 'playing' || g['turn'] != uid) {
            throw ApiError(409, 'انتظر دورك في مباراة نشطة');
          }
          if (index is! int || index < 0 || index > 8) {
            throw ApiError(400, 'خانة غير صحيحة');
          }
          final board = g['board'] as List;
          if (board[index] != '') throw ApiError(409, 'الخانة مستخدمة');
          board[index] = g['from'] == uid ? 'X' : 'O';
          for (final line in [
            [0, 1, 2],
            [3, 4, 5],
            [6, 7, 8],
            [0, 3, 6],
            [1, 4, 7],
            [2, 5, 8],
            [0, 4, 8],
            [2, 4, 6],
          ]) {
            if (board[line[0]] != '' &&
                board[line[0]] == board[line[1]] &&
                board[line[1]] == board[line[2]]) {
              g['state'] = 'finished';
              g['winner'] = uid;
              break;
            }
          }
          if (g['state'] == 'playing' && !board.contains('')) {
            g['state'] = 'finished';
            g['winner'] = 'draw';
          }
          if (g['state'] == 'playing') g['turn'] = peer;
          save();
          return duelView(g, uid);
        }
      }
    }
    return null;
  }
}
