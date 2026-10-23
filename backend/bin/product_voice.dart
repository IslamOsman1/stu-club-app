part of 'server.dart';

extension ProductVoice on ClubServer {
  List<dynamic> rtcServers() {
    final raw = Platform.environment['STU_ICE_SERVERS_JSON'];
    if (raw == null || raw.isEmpty) {
      return [
        {'urls': 'stun:stun.l.google.com:19302'},
      ];
    }
    try {
      final servers = jsonDecode(raw);
      if (servers is! List ||
          servers.isEmpty ||
          servers.length > 10 ||
          servers.any((s) => s is! Map || s['urls'] == null)) {
        throw const FormatException();
      }
      return servers;
    } catch (_) {
      throw ApiError(503, 'إعداد خوادم الصوت غير صحيح');
    }
  }

  void pruneVoice(Map<String, dynamic> room) {
    final current = DateTime.now().toUtc();
    (room['participants'] as List).removeWhere(
      (m) =>
          current.difference(DateTime.parse(m['lastSeen'])) >
          const Duration(seconds: 45),
    );
    rows('voiceSignals').removeWhere(
      (s) =>
          s['room'] == room['id'] &&
          current.difference(DateTime.parse(s['created'])) >
              const Duration(minutes: 3),
    );
  }

  Map<String, dynamic>? voiceMember(Map<String, dynamic> room, String uid) =>
      (room['participants'] as List)
          .cast<Map<String, dynamic>>()
          .where((m) => m['user'] == uid)
          .firstOrNull;
  Map<String, dynamic> roomView(
    Map<String, dynamic> r,
    Map<String, dynamic> u,
  ) => {
    for (final k in ['id', 'title', 'section', 'closed', 'created']) k: r[k],
    'host': author(r['user']),
    'count': (r['participants'] as List).length,
    'canManage': r['user'] == u['id'] || manages(u, 'content'),
  };
  Future<Map<String, dynamic>?> productVoice(
    HttpRequest req,
    Map<String, dynamic> u,
  ) async {
    final path = req.uri.path,
        p = req.uri.pathSegments,
        method = req.method,
        uid = u['id'] as String;
    if (path == '/product/rooms' && method == 'GET') {
      final rooms = rows('voiceRooms')
          .where(
            (r) =>
                r['closed'] != true &&
                contentVisible(r as Map<String, dynamic>, u),
          )
          .toList();
      for (final r in rooms) {
        pruneVoice(r as Map<String, dynamic>);
      }
      return {
        'items': rooms
            .map((r) => roomView(r as Map<String, dynamic>, u))
            .toList(),
        'canCreate':
            !school(u) || u['role'] == 'doctor' || manages(u, 'content'),
      };
    }
    if (path == '/product/rooms' && method == 'POST') {
      if (school(u) && u['role'] != 'doctor' && !manages(u, 'content')) {
        throw ApiError(403, 'الغرف المدرسية للحساب التعليمي والمشرف');
      }
      if (rows('voiceRooms')
              .where((r) => r['user'] == uid && r['closed'] != true)
              .length >=
          3) {
        throw ApiError(429, 'أغلق غرفة سابقة أولًا');
      }
      final b = await body(req), section = contentAudience(b, u);
      if (school(u) && section == null) {
        throw ApiError(400, 'اختر شعبة للغرفة المدرسية');
      }
      final r = {
        'id': id(),
        'user': uid,
        'university': u['university'],
        'title': field(b, 'title', max: 100),
        'section': section,
        'closed': false,
        'participants': <dynamic>[],
        'banned': <dynamic>[],
        'signalSeq': 0,
        'created': now(),
      };
      rows('voiceRooms').add(r);
      auditAction(u, 'voice-room-create', r['id'] as String);
      save();
      return {'id': r['id']};
    }
    if (p.length >= 3 && p[1] == 'rooms') {
      final room = find('voiceRooms', p[2]);
      if (room == null || !contentVisible(room, u) || room['closed'] == true) {
        throw ApiError(404, 'الغرفة غير متاحة');
      }
      pruneVoice(room);
      final host = room['user'] == uid || manages(u, 'content');
      if (p.length == 4 && p[3] == 'join' && method == 'POST') {
        if ((room['banned'] as List? ?? []).contains(uid)) {
          throw ApiError(403, 'أُزيل حسابك من الغرفة');
        }
        if ((room['participants'] as List).any(
          (m) => blocked(uid, m['user']),
        )) {
          throw ApiError(403, 'الغرفة تضم حسابًا محظورًا');
        }
        var member = voiceMember(room, uid);
        if (member == null && (room['participants'] as List).length >= 6) {
          throw ApiError(409, 'اكتملت الغرفة (6 مشاركين)');
        }
        final servers = rtcServers();
        if (member == null) {
          member = {
            'id': id(),
            'user': uid,
            'lastSeen': now(),
            'muted': true,
            'forcedMuted': false,
            'role': host ? 'speaker' : 'listener',
          };
          (room['participants'] as List).add(member);
        } else {
          member['lastSeen'] = now();
        }
        save();
        return {
          'room': roomView(room, u),
          'self': member,
          'iceServers': servers,
          'participants': (room['participants'] as List)
              .map(
                (m) => {
                  ...m as Map<String, dynamic>,
                  'person': author(m['user']),
                },
              )
              .toList(),
        };
      }
      if (p.length == 4 && p[3] == 'close' && method == 'POST') {
        if (!host) throw ApiError(403, 'إغلاق الغرفة للمضيف');
        room['closed'] = true;
        (room['participants'] as List).clear();
        rows('voiceSignals').removeWhere((s) => s['room'] == room['id']);
        auditAction(u, 'voice-room-close', room['id']);
        save();
        return {'ok': true};
      }
      final member = voiceMember(room, uid);
      if (member == null) throw ApiError(403, 'انضم إلى الغرفة أولًا');
      member['lastSeen'] = now();
      if (p.length == 4 && p[3] == 'state' && method == 'GET') {
        final after =
            int.tryParse(req.uri.queryParameters['after'] ?? '0') ?? 0;
        final signals = rows('voiceSignals')
            .where(
              (s) =>
                  s['room'] == room['id'] &&
                  s['to'] == member['id'] &&
                  s['seq'] > after,
            )
            .toList();
        save();
        return {
          'room': roomView(room, u),
          'self': member,
          'participants': (room['participants'] as List)
              .map(
                (m) => {
                  ...m as Map<String, dynamic>,
                  'person': author(m['user']),
                },
              )
              .toList(),
          'signals': signals,
          'cursor': room['signalSeq'],
        };
      }
      if (p.length == 4 && p[3] == 'leave' && method == 'POST') {
        (room['participants'] as List).remove(member);
        rows('voiceSignals').removeWhere(
          (s) =>
              s['room'] == room['id'] &&
              (s['from'] == member['id'] || s['to'] == member['id']),
        );
        save();
        return {'ok': true};
      }
      if (p.length == 4 && p[3] == 'mute' && method == 'POST') {
        final b = await body(req);
        if (b['muted'] is! bool) throw ApiError(400, 'حالة صوت غير صحيحة');
        if (b['muted'] == false &&
            (member['forcedMuted'] == true || member['role'] != 'speaker')) {
          throw ApiError(403, 'اطلب إذن التحدث من المضيف');
        }
        member['muted'] = b['muted'];
        save();
        return {'ok': true};
      }
      if (p.length == 4 && p[3] == 'hand' && method == 'POST') {
        member['hand'] = true;
        save();
        return {'ok': true};
      }
      if (p.length == 4 && p[3] == 'control' && method == 'POST') {
        if (!host) throw ApiError(403, 'إدارة المتحدثين للمضيف');
        final b = await body(req),
            target = (room['participants'] as List)
                .cast<Map<String, dynamic>>()
                .where((m) => m['id'] == b['participant'])
                .firstOrNull,
            action = field(b, 'action');
        if (target == null || target['user'] == room['user']) {
          throw ApiError(400, 'المشارك غير متاح لهذا الإجراء');
        }
        if (action == 'remove') {
          (room['participants'] as List).remove(target);
          (room.putIfAbsent('banned', () => <dynamic>[]) as List).add(
            target['user'],
          );
        } else if (action == 'speaker') {
          target['role'] = 'speaker';
          target['forcedMuted'] = false;
          target['hand'] = false;
        } else if (action == 'listener') {
          target['role'] = 'listener';
          target['muted'] = true;
          target['forcedMuted'] = true;
        } else if (action == 'mute') {
          target['muted'] = true;
          target['forcedMuted'] = true;
        } else if (action == 'allow') {
          target['forcedMuted'] = false;
        } else {
          throw ApiError(400, 'إجراء غير صحيح');
        }
        auditAction(u, 'voice-$action', target['user']);
        save();
        return {'ok': true};
      }
      if (p.length == 4 && p[3] == 'signal' && method == 'POST') {
        socialRate(u, 'voice-signal', limit: 600);
        final b = await body(req, limit: 90000),
            target = (room['participants'] as List)
                .cast<Map<String, dynamic>>()
                .where((m) => m['id'] == b['to'])
                .firstOrNull,
            type = field(b, 'type');
        if (target == null || target['id'] == member['id']) {
          throw ApiError(400, 'المشارك غير متاح');
        }
        Map<String, dynamic> payload;
        if (['offer', 'answer'].contains(type)) {
          payload = {'sdp': field(b, 'sdp', max: 60000), 'type': type};
        } else if (type == 'candidate') {
          final index = b['sdpMLineIndex'];
          if (index is! int || index < 0 || index > 20) {
            throw ApiError(400, 'ICE غير صالح');
          }
          payload = {
            'candidate': field(b, 'candidate', max: 3000),
            'sdpMid': field(b, 'sdpMid', min: 0, max: 80),
            'sdpMLineIndex': index,
          };
        } else {
          throw ApiError(400, 'إشارة غير صحيحة');
        }
        room['signalSeq']++;
        rows('voiceSignals').add({
          'id': id(),
          'seq': room['signalSeq'],
          'room': room['id'],
          'from': member['id'],
          'to': target['id'],
          'type': type,
          'payload': payload,
          'created': now(),
        });
        save();
        return {'ok': true};
      }
    }
    return null;
  }
}
