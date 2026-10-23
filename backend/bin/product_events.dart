part of 'server.dart';

extension ProductEvents on ClubServer {
  bool eventHost(Map<String, dynamic> e, Map<String, dynamic> u) =>
      e['user'] == u['id'] ||
      (e['university'] == u['university'] && manages(u, 'events'));
  Map<String, dynamic> eventView(
    Map<String, dynamic> e,
    Map<String, dynamic> u,
  ) {
    final registrations = rows('eventRegistrations')
        .where((r) => r['event'] == e['id'] && r['status'] != 'cancelled')
        .toList();
    final mine = registrations.where((r) => r['user'] == u['id']).firstOrNull;
    return {
      for (final k in [
        'id',
        'title',
        'text',
        'location',
        'starts',
        'ends',
        'capacity',
        'cancelled',
        'section',
        'created',
      ])
        k: e[k],
      'author': author(e['user']),
      'registered': registrations.length,
      'mine': mine == null
          ? null
          : {
              for (final k in ['id', 'status', 'attended']) k: mine[k],
            },
      'canManage': eventHost(e, u),
      if (eventHost(e, u)) 'checkinCode': e['checkinCode'],
    };
  }

  Map<String, dynamic> eventFields(
    Map<String, dynamic> b,
    Map<String, dynamic> u,
  ) {
    final start = DateTime.tryParse(field(b, 'starts')),
        end = DateTime.tryParse(field(b, 'ends')),
        capacity = b['capacity'];
    if (start == null ||
        end == null ||
        !end.isAfter(start) ||
        end.difference(start) > const Duration(days: 30) ||
        !end.isAfter(DateTime.now().toUtc()) ||
        capacity is! int ||
        capacity < 1 ||
        capacity > 10000) {
      throw ApiError(400, 'أدخل وقتًا وسعة صحيحين');
    }
    final section = contentAudience(b, u);
    if (school(u) && section == null) {
      throw ApiError(400, 'اختر شعبة للفعالية المدرسية');
    }
    return {
      'title': field(b, 'title', max: 120),
      'text': field(b, 'text', max: 3000),
      'location': field(b, 'location', max: 200),
      'starts': start.toUtc().toIso8601String(),
      'ends': end.toUtc().toIso8601String(),
      'capacity': capacity,
      'section': section,
    };
  }

  void eventReminders() {
    var changed = false;
    final current = DateTime.now().toUtc();
    for (final e in rows('events').where((e) => e['cancelled'] != true)) {
      final start = DateTime.parse(e['starts']);
      if (start.isBefore(current) ||
          start.difference(current) > const Duration(hours: 1)) {
        continue;
      }
      for (final r in rows('eventRegistrations').where(
        (r) =>
            r['event'] == e['id'] &&
            r['status'] == 'registered' &&
            r['reminded'] != true,
      )) {
        final person = find('users', r['user']);
        if (person == null ||
            !contentVisible(e as Map<String, dynamic>, person)) {
          continue;
        }
        r['reminded'] = true;
        notify(
          r['user'],
          e['user'],
          'event',
          'تبدأ قريبًا: ${e['title']}',
          target: e['id'],
        );
        changed = true;
      }
    }
    if (changed) save();
  }

  Future<Map<String, dynamic>?> productEvents(
    HttpRequest req,
    Map<String, dynamic> u,
  ) async {
    final path = req.uri.path, p = req.uri.pathSegments, method = req.method;
    if (path == '/product/events' && method == 'GET') {
      final items =
          rows('events')
              .where((e) => contentVisible(e as Map<String, dynamic>, u))
              .toList()
            ..sort((a, b) => (a['starts'] as String).compareTo(b['starts']));
      return {
        'items': items
            .map((e) => eventView(e as Map<String, dynamic>, u))
            .toList(),
        'canCreate':
            manages(u, 'events') ||
            (u['role'] == 'doctor' && u['verified'] == true),
      };
    }
    if (path == '/product/events' && method == 'POST') {
      if (!manages(u, 'events') &&
          !(u['role'] == 'doctor' && u['verified'] == true)) {
        throw ApiError(403, 'إنشاء الفعاليات للمدرس أو مشرف الفعاليات');
      }
      final b = await body(req),
          fields = eventFields(b, u),
          e = {
            'id': id(),
            'user': u['id'],
            'university': u['university'],
            ...fields,
            'cancelled': false,
            'checkinCode': id(),
            'created': now(),
          };
      rows('events').add(e);
      auditAction(u, 'event-create', e['id'] as String);
      save();
      return {'id': e['id']};
    }
    if (p.length >= 3 && p[1] == 'events') {
      final e = find('events', p[2]);
      if (e == null || !contentVisible(e, u)) {
        throw ApiError(404, 'الفعالية غير موجودة');
      }
      if (p.length == 3 && method == 'PATCH') {
        if (!eventHost(e, u)) throw ApiError(403, 'إدارة الفعالية للمنظم');
        final b = await body(req), fields = eventFields(b, u);
        final registered = rows('eventRegistrations')
            .where((r) => r['event'] == e['id'] && r['status'] != 'cancelled')
            .length;
        if ((fields['capacity'] as int) < registered) {
          throw ApiError(409, 'السعة أقل من عدد المسجلين');
        }
        if (fields['section'] != e['section'] && registered > 0) {
          throw ApiError(409, 'لا يمكن تغيير الجمهور بعد بدء التسجيل');
        }
        e.addAll(fields);
        auditAction(u, 'event-update', e['id']);
        for (final r in rows(
          'eventRegistrations',
        ).where((r) => r['event'] == e['id'] && r['status'] != 'cancelled')) {
          r['reminded'] = false;
          notify(
            r['user'],
            u['id'],
            'event',
            'تم تحديث الفعالية: ${e['title']}',
            target: e['id'],
          );
        }
        save();
        return {'ok': true};
      }
      if (p.length == 4 && p[3] == 'registrations' && method == 'GET') {
        if (!eventHost(e, u)) throw ApiError(403, 'قائمة الحضور للمنظم');
        return {
          'items': rows('eventRegistrations')
              .where((r) => r['event'] == e['id'])
              .map(
                (r) => {
                  ...r as Map<String, dynamic>,
                  'person': author(r['user']),
                },
              )
              .toList(),
        };
      }
      if (p.length == 4 && p[3] == 'cancel' && method == 'POST') {
        if (!eventHost(e, u)) throw ApiError(403, 'للمنظم فقط');
        e['cancelled'] = true;
        for (final r in rows(
          'eventRegistrations',
        ).where((r) => r['event'] == e['id'] && r['status'] != 'cancelled')) {
          notify(
            r['user'],
            u['id'],
            'event',
            'أُلغيت الفعالية: ${e['title']}',
            target: e['id'],
          );
        }
        auditAction(u, 'event-cancel', e['id']);
        save();
        return {'ok': true};
      }
      if (p.length == 4 && p[3] == 'register' && method == 'POST') {
        if (e['cancelled'] == true ||
            DateTime.parse(e['ends']).isBefore(DateTime.now().toUtc())) {
          throw ApiError(409, 'الفعالية غير متاحة للتسجيل');
        }
        final existing = rows('eventRegistrations')
            .where((r) => r['event'] == e['id'] && r['user'] == u['id'])
            .firstOrNull;
        if (existing != null && existing['status'] != 'cancelled') {
          return {'id': existing['id']};
        }
        if (rows('eventRegistrations')
                .where(
                  (r) => r['event'] == e['id'] && r['status'] != 'cancelled',
                )
                .length >=
            e['capacity']) {
          throw ApiError(409, 'اكتمل عدد الحضور');
        }
        final r =
            existing ??
            {'id': id(), 'event': e['id'], 'user': u['id'], 'created': now()};
        r['status'] = 'registered';
        r['attended'] = false;
        r['reminded'] = false;
        if (existing == null) rows('eventRegistrations').add(r);
        save();
        return {'id': r['id']};
      }
      if (p.length == 4 && p[3] == 'unregister' && method == 'POST') {
        final r = rows('eventRegistrations')
            .where((r) => r['event'] == e['id'] && r['user'] == u['id'])
            .firstOrNull;
        if (r == null) throw ApiError(404, 'لست مسجلًا');
        if (r['attended'] == true) {
          throw ApiError(409, 'تم تسجيل الحضور بالفعل');
        }
        r['status'] = 'cancelled';
        save();
        return {'ok': true};
      }
      if (p.length == 4 && p[3] == 'checkin' && method == 'POST') {
        final current = DateTime.now().toUtc();
        if (e['cancelled'] == true ||
            current.isBefore(
              DateTime.parse(e['starts']).subtract(const Duration(minutes: 30)),
            ) ||
            current.isAfter(
              DateTime.parse(e['ends']).add(const Duration(hours: 1)),
            )) {
          throw ApiError(409, 'تسجيل الحضور غير مفتوح الآن');
        }
        final b = await body(req);
        if (b['code'] != e['checkinCode']) {
          throw ApiError(403, 'رمز الحضور غير صحيح');
        }
        final r = rows('eventRegistrations')
            .where(
              (r) =>
                  r['event'] == e['id'] &&
                  r['user'] == u['id'] &&
                  r['status'] == 'registered',
            )
            .firstOrNull;
        if (r == null) throw ApiError(403, 'سجّل في الفعالية أولًا');
        r['attended'] = true;
        r['attendedAt'] = now();
        save();
        return {'ok': true};
      }
    }
    return null;
  }
}
