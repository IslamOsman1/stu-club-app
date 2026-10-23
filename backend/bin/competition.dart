part of 'server.dart';

extension CompetitionFeatures on ClubServer {
  bool tournamentAccess(Map<String, dynamic> t, Map<String, dynamic> u) =>
      t['university'] == u['university'] &&
      (t['section'] == null
          ? (!school(u) || u['role'] == 'admin')
          : find('sections', t['section']) != null &&
                sectionMember(find('sections', t['section'])!, u));
  bool tournamentDuel(Map<String, dynamic> game, Map<String, dynamic> u) {
    final t = find('tournaments', game['tournament'] ?? '');
    return t != null &&
        tournamentAccess(t, u) &&
        (t['players'] as List).contains(u['id']);
  }

  Future<Map<String, dynamic>?> competitions(
    HttpRequest req,
    Map<String, dynamic> u,
  ) async {
    final path = req.uri.path, method = req.method, uid = u['id'] as String;
    if (path == '/games/memory/start' && method == 'POST') {
      final values = [
        for (var i = 0; i < 6; i++) ...[i, i],
      ]..shuffle(random);
      rows('memoryRounds').removeWhere((r) => r['user'] == uid);
      final round = {
        'id': id(),
        'user': uid,
        'values': values,
        'matched': <dynamic>[],
        'open': <dynamic>[],
        'attempts': 0,
        'expires': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 3))
            .toIso8601String(),
      };
      rows('memoryRounds').add(round);
      save();
      return memoryView(round);
    }
    final p = req.uri.pathSegments;
    if (p.length == 3 &&
        p[0] == 'memory' &&
        p[2] == 'flip' &&
        method == 'POST') {
      final r = find('memoryRounds', p[1]);
      if (r == null || r['user'] != uid) {
        throw ApiError(404, 'الجولة غير موجودة');
      }
      final b = await body(req), index = b['cell'];
      if (DateTime.parse(r['expires']).isBefore(DateTime.now().toUtc()) ||
          (r['matched'] as List).length == 12) {
        throw ApiError(409, 'انتهت الجولة');
      }
      if (index is! int || index < 0 || index > 11) {
        throw ApiError(400, 'بطاقة غير صحيحة');
      }
      final matched = r['matched'] as List, open = r['open'] as List;
      if (matched.contains(index) ||
          (open.length == 1 && open.contains(index))) {
        throw ApiError(409, 'البطاقة مفتوحة');
      }
      if (open.length == 2) open.clear();
      open.add(index);
      if (open.length == 2) {
        r['attempts'] = (r['attempts'] as int) + 1;
        if (r['values'][open[0]] == r['values'][open[1]]) {
          matched.addAll(open);
          open.clear();
        }
      }
      if (matched.length == 12) {
        final day = now().substring(0, 10), key = 'memory:$day';
        if (!rows('scores').any((s) => s['user'] == uid && s['quiz'] == key)) {
          rows('scores').add({
            'id': id(),
            'user': uid,
            'quiz': key,
            'points': max(10, 120 - (r['attempts'] as int) * 5),
          });
          recordActivity(uid);
        }
      }
      save();
      return memoryView(r);
    }
    if (path == '/tournaments' && method == 'GET') {
      return {
        'canCreate': canAnnounce(u),
        'items': rows('tournaments')
            .where((t) => tournamentAccess(t, u))
            .toList()
            .reversed
            .map((t) {
              final matches = rows('duels')
                  .where((g) => g['tournament'] == t['id'])
                  .toList();
              var changed = false;
              for (final g in matches) {
                if (expiredGame(g)) changed = true;
              }
              if (changed) save();
              final table =
                  (t['players'] as List)
                      .where((id) => find('users', id) != null)
                      .map((id) {
                        var points = 0, played = 0;
                        for (final g in matches.where(
                          (g) => g['from'] == id || g['to'] == id,
                        )) {
                          if (g['state'] == 'finished') {
                            played++;
                            points += g['winner'] == id
                                ? 3
                                : g['winner'] == 'draw'
                                ? 1
                                : 0;
                          }
                        }
                        return {
                          'person': author(id),
                          'points': points,
                          'played': played,
                        };
                      })
                      .toList()
                    ..sort(
                      (a, b) =>
                          (b['points'] as int).compareTo(a['points'] as int),
                    );
              return {
                ...t as Map<String, dynamic>,
                'players': table,
                'joined': (t['players'] as List).contains(uid),
                'canManage': t['user'] == uid || u['role'] == 'admin',
                'finished':
                    t['state'] == 'running' &&
                    matches.every(
                      (g) => !['pending', 'playing'].contains(g['state']),
                    ),
              };
            })
            .toList(),
      };
    }
    if (path == '/tournaments' && method == 'POST') {
      if (!canAnnounce(u)) {
        throw ApiError(403, 'إنشاء البطولات للمدرس المعتمد أو المشرف');
      }
      final b = await body(req),
          title = field(b, 'title', max: 100),
          section = contentAudience(b, u);
      final t = {
        'id': id(),
        'title': title,
        'user': uid,
        'university': u['university'],
        'section': section,
        'players': <dynamic>[],
        'state': 'open',
        'created': now(),
      };
      rows('tournaments').add(t);
      save();
      return {'id': t['id']};
    }
    if (p.length == 3 && p[0] == 'tournaments' && method == 'POST') {
      final t = find('tournaments', p[1]);
      if (t == null || !tournamentAccess(t, u)) {
        throw ApiError(404, 'البطولة غير موجودة');
      }
      final players = t['players'] as List;
      if (p[2] == 'join') {
        if (u['role'] != 'student') throw ApiError(403, 'المشاركة للطلاب');
        if (t['state'] != 'open') throw ApiError(409, 'بدأت البطولة');
        if (players.contains(uid)) {
          players.remove(uid);
        } else {
          if (players.length >= 8) throw ApiError(409, 'اكتمل عدد اللاعبين');
          if (players.any((p) => !schoolSocial(u, find('users', p)!))) {
            throw ApiError(403, 'البطولة لفئة عمرية وصف متوافقين');
          }
          players.add(uid);
        }
        save();
        return {'ok': true};
      }
      if (p[2] == 'start') {
        if (t['user'] != uid && u['role'] != 'admin') {
          throw ApiError(403, 'بدء البطولة للمنظّم');
        }
        if (t['state'] != 'open' || players.length < 2) {
          throw ApiError(409, 'تحتاج البطولة لاعبين على الأقل');
        }
        for (var i = 0; i < players.length; i++) {
          for (var j = i + 1; j < players.length; j++) {
            final a = find('users', players[i]), b = find('users', players[j]);
            if (a == null ||
                b == null ||
                a['disabled'] == true ||
                b['disabled'] == true ||
                blocked(a['id'], b['id']) ||
                !schoolSocial(a, b)) {
              throw ApiError(409, 'راجع المشاركين والحظر قبل البدء');
            }
          }
        }
        t['state'] = 'running';
        for (var i = 0; i < players.length; i++) {
          for (var j = i + 1; j < players.length; j++) {
            final game = {
              'id': id(),
              'from': players[i],
              'to': players[j],
              'tournament': t['id'],
              'state': 'playing',
              'board': List.filled(9, ''),
              'turn': players[i],
              'winner': null,
              'created': now(),
              'expires': DateTime.now()
                  .toUtc()
                  .add(const Duration(hours: 1))
                  .toIso8601String(),
            };
            rows('duels').add(game);
            for (final target in [players[i], players[j]]) {
              notify(
                target,
                uid,
                'game_invite',
                'بدأت مباراة في بطولة ${t['title']}',
                target: game['id'] as String,
              );
            }
          }
        }
        save();
        return {'ok': true};
      }
    }
    return null;
  }

  Map<String, dynamic> memoryView(Map<String, dynamic> r) => {
    'id': r['id'],
    'cards': List.generate(
      12,
      (i) =>
          (r['matched'] as List).contains(i) || (r['open'] as List).contains(i)
          ? r['values'][i]
          : null,
    ),
    'matched': r['matched'],
    'attempts': r['attempts'],
    'finished': (r['matched'] as List).length == 12,
    'expires': r['expires'],
  };
}
