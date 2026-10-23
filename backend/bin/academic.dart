part of 'server.dart';

extension AcademicFeatures on ClubServer {
  void recordActivity(String uid) {
    final day = now().substring(0, 10);
    if (!rows('activity').any((r) => r['user'] == uid && r['day'] == day)) {
      rows('activity').add({'id': id(), 'user': uid, 'day': day});
    }
  }

  bool canAnnounce(Map<String, dynamic> u) =>
      u['role'] == 'admin' || (u['role'] == 'doctor' && u['verified'] == true);

  bool seesAnnouncement(Map<String, dynamic> a, Map<String, dynamic> u) {
    if (a['university'] != u['university']) return false;
    if (u['role'] == 'admin') return true;
    if (a['section'] != null) {
      final section = find('sections', a['section']);
      return section != null && sectionMember(section, u);
    }
    return a['user'] == u['id'] ||
        a['group'] == null ||
        (find('groups', a['group'])?['members'] as List? ?? []).contains(
          u['id'],
        );
  }

  Future<Map<String, dynamic>?> academic(
    HttpRequest req,
    Map<String, dynamic> u,
  ) async {
    final path = req.uri.path, method = req.method, uid = u['id'] as String;
    if (path == '/announcements' && method == 'GET') {
      final items = rows('announcements')
          .where((a) => seesAnnouncement(a, u))
          .map((raw) {
            final a = Map<String, dynamic>.from(raw);
            final views = a.remove('views') as List;
            return {
              ...a,
              'author': author(a['user']),
              if (a['section'] != null)
                'audience':
                    '${find('courses', find('sections', a['section'])?['course'] ?? '')?['name'] ?? ''} · ${find('sections', a['section'])?['name'] ?? ''}',
              'seen': views.contains(uid),
              if (a['user'] == uid || u['role'] == 'admin')
                'viewCount': views.length,
            };
          })
          .toList();
      items.sort((a, b) {
        final p = (b['pinned'] == true ? 1 : 0).compareTo(
          a['pinned'] == true ? 1 : 0,
        );
        return p != 0 ? p : (b['created'] as String).compareTo(a['created']);
      });
      return {'items': items, 'canPublish': canAnnounce(u)};
    }
    if (path == '/announcements' && method == 'POST') {
      if (!canAnnounce(u)) {
        throw ApiError(403, 'نشر الإعلانات للحسابات التعليمية المعتمدة فقط');
      }
      final b = await body(req), text = field(b, 'text', max: 3000);
      final group = b['group'];
      final section = b['section'];
      if (group != null && section != null) {
        throw ApiError(400, 'اختر جمهورًا واحدًا فقط');
      }
      if (section != null) {
        if (section is! String) throw ApiError(400, 'اختر شعبة صحيحة');
        final target = find('sections', section);
        sameUniversity(target, u);
        if (target!['active'] != true) throw ApiError(409, 'الشعبة مؤرشفة');
        if (u['role'] != 'admin') {
          if (!(target['teachers'] as List).contains(uid)) {
            throw ApiError(403, 'النشر للشعب المكلّف بها فقط');
          }
        }
      } else if (group == null && u['role'] != 'admin') {
        throw ApiError(
          403,
          'الإعلانات العامة للمؤسسة للمشرف؛ اختر شعبة مكلّفًا بها',
        );
      }
      if (group != null) {
        if (group is! String) throw ApiError(400, 'اختر مجموعة صحيحة');
        sameUniversity(find('groups', group), u);
        if (u['role'] != 'admin' &&
            !(find('groups', group)!['members'] as List).contains(uid)) {
          throw ApiError(403, 'انضم إلى المجموعة أولًا');
        }
      }
      final a = {
        'id': id(),
        'user': uid,
        'university': u['university'],
        'group': group,
        'section': section,
        'text': text,
        'created': now(),
        'pinned': b['pinned'] == true,
        'views': <dynamic>[],
      };
      rows('announcements').add(a);
      for (final recipient in rows(
        'users',
      ).where((r) => r['disabled'] != true && seesAnnouncement(a, r))) {
        notify(
          recipient['id'],
          uid,
          'announcement',
          'إعلان أكاديمي جديد: ${text.length > 70 ? text.substring(0, 70) : text}',
          target: a['id'] as String,
        );
      }
      save();
      return {'id': a['id']};
    }
    final p = req.uri.pathSegments;
    if (p.length >= 2 && p[0] == 'announcements') {
      final a = find('announcements', p[1]);
      if (a == null || !seesAnnouncement(a, u)) {
        throw ApiError(404, 'الإعلان غير موجود');
      }
      if (p.length == 3 && p[2] == 'view' && method == 'POST') {
        if (a['user'] != uid && !(a['views'] as List).contains(uid)) {
          (a['views'] as List).add(uid);
          (a.putIfAbsent('viewTimes', () => <String, dynamic>{}) as Map)[uid] =
              now();
        }
        save();
        return {'ok': true};
      }
      if (a['user'] != uid && u['role'] != 'admin') {
        throw ApiError(403, 'غير مسموح');
      }
      if (p.length == 2 && method == 'PATCH') {
        final b = await body(req);
        if (b['pinned'] is! bool) throw ApiError(400, 'حالة التثبيت غير صحيحة');
        a['pinned'] = b['pinned'];
        save();
        return {'ok': true};
      }
      if (p.length == 2 && method == 'DELETE') {
        rows('announcements').remove(a);
        save();
        return {'ok': true};
      }
    }
    if (path == '/streak/freeze' && method == 'POST') {
      final activity = rows('activity').where((r) => r['user'] == uid).toList();
      final earned = activity.where((r) => r['frozen'] != true).length ~/ 7;
      final used = activity.where((r) => r['frozen'] == true).length;
      final today = DateTime.now().toUtc();
      final yesterday = today
          .subtract(const Duration(days: 1))
          .toIso8601String()
          .substring(0, 10);
      final before = today
          .subtract(const Duration(days: 2))
          .toIso8601String()
          .substring(0, 10);
      if (earned <= used ||
          activity.any((r) => r['day'] == yesterday) ||
          !activity.any((r) => r['day'] == before)) {
        throw ApiError(
          409,
          'التجميد متاح ليوم أمس الفائت فقط، برصيد مكتسب وسلسلة سابقة',
        );
      }
      rows('activity')
          .add({'id': id(), 'user': uid, 'day': yesterday, 'frozen': true});
      save();
      return {'ok': true};
    }
    if (path == '/streak' && method == 'GET') {
      final days = rows('activity')
          .where((r) => r['user'] == uid)
          .map((r) => r['day'] as String)
          .toSet();
      var cursor = DateTime.utc(
        DateTime.now().toUtc().year,
        DateTime.now().toUtc().month,
        DateTime.now().toUtc().day,
      );
      String key(DateTime d) => d.toIso8601String().substring(0, 10);
      if (!days.contains(key(cursor))) {
        cursor = cursor.subtract(const Duration(days: 1));
      }
      var count = 0;
      while (days.contains(key(cursor))) {
        count++;
        cursor = cursor.subtract(const Duration(days: 1));
      }
      final activity = rows('activity').where((r) => r['user'] == uid).toList();
      final frozen = activity
          .where((r) => r['frozen'] == true)
          .map((r) => r['day'] as String)
          .toList();
      final available =
          activity.where((r) => r['frozen'] != true).length ~/ 7 -
          frozen.length;
      final today = DateTime.now().toUtc();
      final yesterday = key(today.subtract(const Duration(days: 1)));
      return {
        'freezes': available,
        'frozenDays': frozen,
        'canFreeze':
            available > 0 &&
            !days.contains(yesterday) &&
            days.contains(key(today.subtract(const Duration(days: 2)))),
        'count': count,
        'days': days.toList()..sort(),
        'today': days.contains(key(DateTime.now().toUtc())),
        'timezone': 'UTC',
      };
    }
    return null;
  }
}
