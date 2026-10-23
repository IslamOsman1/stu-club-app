part of 'server.dart';

extension AcademicFeatures on ClubServer {
  void scheduledAnnouncements() {
    var changed = false;
    final current = DateTime.now().toUtc();
    for (final a in rows(
      'announcements',
    ).where((r) => r['notified'] == false)) {
      if (DateTime.parse(a['publishAt']).isAfter(current)) continue;
      a['notified'] = true;
      changed = true;
      if (a['expiresAt'] != null &&
          !DateTime.parse(a['expiresAt']).isAfter(current)) {
        continue;
      }
      for (final person in rows('users').where(
        (r) =>
            r['disabled'] != true &&
            seesAnnouncement(
              a as Map<String, dynamic>,
              r as Map<String, dynamic>,
            ),
      )) {
        notify(
          person['id'],
          a['user'],
          'announcement',
          'إعلان أكاديمي جديد',
          target: a['id'],
        );
      }
    }
    if (changed) save();
  }

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
    final current = DateTime.now().toUtc();
    if (a['user'] != u['id'] &&
        a['publishAt'] != null &&
        DateTime.parse(a['publishAt']).isAfter(current)) {
      return false;
    }
    if (a['user'] != u['id'] &&
        a['expiresAt'] != null &&
        !DateTime.parse(a['expiresAt']).isAfter(current)) {
      return false;
    }
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
      final publishAt = b['publishAt'] == null
          ? DateTime.now().toUtc()
          : DateTime.tryParse(b['publishAt'].toString());
      final expiresAt = b['expiresAt'] == null
          ? null
          : DateTime.tryParse(b['expiresAt'].toString());
      if (publishAt == null ||
          (b['expiresAt'] != null &&
              (expiresAt == null || !expiresAt.isAfter(publishAt)))) {
        throw ApiError(400, 'أوقات غير صحيحة');
      }
      final importance = b['importance'] ?? 'normal';
      if (!['normal', 'important', 'urgent'].contains(importance)) {
        throw ApiError(400, 'أهمية غير صحيحة');
      }
      final attachment = b['document'];
      if (attachment != null) {
        final doc = find('documents', attachment);
        if (doc == null || !contentVisible(doc, u)) {
          throw ApiError(400, 'مستند غير متاح');
        }
      }
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
        'publishAt': publishAt.toUtc().toIso8601String(),
        'expiresAt': expiresAt?.toUtc().toIso8601String(),
        'importance': importance,
        'document': attachment,
        'notified': !publishAt.isAfter(DateTime.now().toUtc()),
        'views': <dynamic>[],
      };
      rows('announcements').add(a);
      auditAction(u, 'announcement-create', a['id'] as String);
      for (final recipient in rows('users').where(
        (r) =>
            a['notified'] == true &&
            r['disabled'] != true &&
            seesAnnouncement(a, r),
      )) {
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
        final update = <String, dynamic>{};
        if (b.containsKey('pinned')) {
          if (b['pinned'] is! bool) {
            throw ApiError(400, 'حالة التثبيت غير صحيحة');
          }
          update['pinned'] = b['pinned'];
        }
        if (b.containsKey('text')) update['text'] = field(b, 'text', max: 3000);
        if (b.containsKey('importance')) {
          if (!['normal', 'important', 'urgent'].contains(b['importance'])) {
            throw ApiError(400, 'أهمية غير صحيحة');
          }
          update['importance'] = b['importance'];
        }
        if (b.containsKey('publishAt') || b.containsKey('expiresAt')) {
          final published = b.containsKey('publishAt')
              ? (b['publishAt'] == null
                    ? DateTime.now().toUtc()
                    : DateTime.tryParse(b['publishAt'].toString()))
              : DateTime.parse(a['publishAt'] ?? a['created']);
          final expiryRaw = b.containsKey('expiresAt')
              ? b['expiresAt']
              : a['expiresAt'];
          final expires = expiryRaw == null
              ? null
              : DateTime.tryParse(expiryRaw.toString());
          if (published == null ||
              (expiryRaw != null &&
                  (expires == null || !expires.isAfter(published)))) {
            throw ApiError(400, 'أوقات غير صحيحة');
          }
          update['publishAt'] = published.toUtc().toIso8601String();
          update['expiresAt'] = expires?.toUtc().toIso8601String();
          if (published.isAfter(DateTime.now().toUtc())) {
            update['notified'] = false;
          }
        }
        if (b.containsKey('document')) {
          final document = b['document'];
          final doc = document is String ? find('documents', document) : null;
          if (document != null && (doc == null || !contentVisible(doc, u))) {
            throw ApiError(400, 'مستند غير متاح');
          }
          update['document'] = document;
        }
        if (update.isEmpty) throw ApiError(400, 'لا توجد تعديلات صالحة');
        a.addAll(update);
        a['edited'] = now();
        auditAction(u, 'announcement-update', a['id']);
        save();
        return {'ok': true};
      }
      if (p.length == 2 && method == 'DELETE') {
        auditAction(u, 'announcement-delete', a['id']);
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
