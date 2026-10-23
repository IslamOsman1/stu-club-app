part of 'server.dart';

const productCollections = [
  'orgUnits',
  'membershipRequests',
  'invitations',
  'events',
  'eventRegistrations',
  'supportTickets',
  'appeals',
  'savedPosts',
  'notificationSettings',
  'voiceRooms',
  'voiceSignals',
  'chatPresence',
  'messageReceipts',
  'institutionSettings',
];
const institutionPermissions = [
  'users',
  'verification',
  'reports',
  'content',
  'courses',
  'announcements',
  'institutions',
  'events',
  'support',
  'audit',
];

extension ProductFoundation on ClubServer {
  void deleteProductData(String uid) {
    final eventIds = rows('events')
        .where((r) => r['user'] == uid)
        .map((r) => r['id'])
        .toSet();
    final voiceIds = rows('voiceAttachments')
        .where((r) => r['user'] == uid || r['attached']?['target'] == uid)
        .map((r) => r['id'])
        .toSet();
    for (final voice in voiceIds) {
      final disk = File('${file.parent.path}/voice/$voice.m4a');
      if (disk.existsSync()) disk.deleteSync();
    }
    rows('voiceAttachments').removeWhere((r) => voiceIds.contains(r['id']));
    for (final room in rows('voiceRooms')) {
      (room['participants'] as List).removeWhere((r) => r['user'] == uid);
      if (room['user'] == uid) {
        room['closed'] = true;
        (room['participants'] as List).clear();
      }
    }
    for (final group in rows('groups')) {
      (group['moderators'] as List?)?.remove(uid);
      if (group['owner'] == uid) {
        group['owner'] = (group['members'] as List).firstOrNull;
        group['moderators'] = [if (group['owner'] != null) group['owner']];
      }
    }
    rows('events').removeWhere((r) => eventIds.contains(r['id']));
    rows('eventRegistrations')
        .removeWhere((r) => r['user'] == uid || eventIds.contains(r['event']));
    for (final key in [
      'membershipRequests',
      'supportTickets',
      'appeals',
      'savedPosts',
      'chatPresence',
      'messageReceipts',
      'groupInvites',
    ]) {
      rows(key).removeWhere(
        (r) => r['user'] == uid || r['from'] == uid || r['to'] == uid,
      );
    }
    rows('notificationSettings').removeWhere((r) => r['id'] == uid);
    rows('voiceSignals')
        .removeWhere((r) => find('voiceRooms', r['room'])?['closed'] == true);
    for (final invitation in rows('invitations')) {
      (invitation['claimed'] as List?)?.remove(uid);
    }
  }

  bool owner(Map<String, dynamic> u) =>
      u['role'] == 'admin' &&
      !['institution_admin', 'moderator'].contains(u['managementRole']);
  bool manages(Map<String, dynamic> u, String permission) =>
      owner(u) ||
      (u['role'] == 'admin' &&
          (u['permissions'] as List? ?? []).contains(permission));
  void demand(Map<String, dynamic> u, String permission) {
    if (!manages(u, permission)) {
      throw ApiError(403, 'لا تملك صلاحية هذا الإجراء');
    }
  }

  void scoped(Map<String, dynamic>? target, Map<String, dynamic> u) {
    if (target == null) throw ApiError(404, 'العنصر غير موجود');
    if (!owner(u) && target['university'] != u['university']) {
      throw ApiError(403, 'العنصر خارج نطاق مؤسستك');
    }
  }

  Map<String, dynamic> institutionConfig(String institutionId) =>
      rows('institutionSettings')
          .cast<Map<String, dynamic>>()
          .where((r) => r['id'] == institutionId)
          .firstOrNull ??
      {};
  void auditAction(Map<String, dynamic> u, String action, String target) {
    rows('audit').add({
      'id': id(),
      'actor': u['id'],
      'university': u['university'],
      'action': action,
      'target': target,
      'created': now(),
    });
  }

  void productGuard(HttpRequest req, Map<String, dynamic> u) {
    if (u['role'] != 'admin' || owner(u)) return;
    final p = req.uri.pathSegments, path = req.uri.path;
    String? permission;
    if (path.startsWith('/admin/verification')) permission = 'verification';
    if (path.startsWith('/admin/users')) permission = 'users';
    if (path.startsWith('/admin/reports')) permission = 'reports';
    if (path.startsWith('/courses') || path.startsWith('/sections')) {
      permission = 'courses';
    }
    if (path.startsWith('/announcements') || path == '/announcement-reports') {
      permission = 'announcements';
    }
    if (path.startsWith('/institutions') && path != '/institutions/manage') {
      permission = 'institutions';
    }
    if (req.method != 'GET' &&
        p.isNotEmpty &&
        [
          'documents',
          'polls',
          'posts',
          'comments',
          'groups',
        ].contains(p.first)) {
      permission = 'content';
    }
    if (permission != null) demand(u, permission);
    if (path == '/institutions' && req.method == 'POST') {
      throw ApiError(403, 'إنشاء المؤسسات لمالك المنصة فقط');
    }
    if (p.length == 3 && p.first == 'admin' && req.method == 'POST') {
      final collection = {
        'users': 'users',
        'verification': 'verification',
        'reports': 'reports',
      }[p[1]];
      if (collection != null) {
        final target = find(collection, p[2]);
        if (collection == 'users') {
          scoped(target, u);
        } else {
          final person = find('users', target?['user'] ?? '');
          scoped(person, u);
        }
      }
    }
  }

  void moveInstitution(Map<String, dynamic> person, String target) {
    final previous = person['university'];
    if (previous == target) {
      person['membershipStatus'] = 'approved';
      return;
    }
    for (final s in rows('sections')) {
      (s['students'] as List).remove(person['id']);
      (s['teachers'] as List).remove(person['id']);
      syncSectionGroup(s as Map<String, dynamic>);
    }
    for (final g in rows('groups')) {
      (g['members'] as List).remove(person['id']);
    }
    rows(
      'friends',
    ).removeWhere((f) => f['from'] == person['id'] || f['to'] == person['id']);
    person['university'] = target;
    person['membershipStatus'] = 'approved';
    if (person['role'] == 'doctor') {
      person['verified'] = false;
    }
  }

  Future<Map<String, dynamic>?> product(
    HttpRequest req,
    Map<String, dynamic> u,
  ) async {
    final path = req.uri.path,
        p = req.uri.pathSegments,
        method = req.method,
        uid = u['id'];
    if (!path.startsWith('/product/')) return null;
    if (path == '/product/account' && method == 'GET') {
      return {
        'user': publicUser(u),
        'institutions': institutionList(),
        'membership': rows('membershipRequests')
            .where((r) => r['user'] == uid)
            .toList(),
        'preferences':
            rows('notificationSettings')
                .where((r) => r['id'] == uid)
                .firstOrNull ??
            {
              'id': uid,
              'push': true,
              'social': true,
              'academic': true,
              'messages': true,
            },
        'role': owner(u) ? 'owner' : u['managementRole'] ?? u['role'],
      };
    }
    if (path == '/product/preferences' && method == 'PATCH') {
      final b = await body(req), prefs = <String, dynamic>{'id': uid};
      for (final k in ['push', 'social', 'academic', 'messages']) {
        if (b[k] is! bool) throw ApiError(400, 'تفضيلات غير صحيحة');
        prefs[k] = b[k];
      }
      rows('notificationSettings').removeWhere((r) => r['id'] == uid);
      rows('notificationSettings').add(prefs);
      save();
      return {'ok': true};
    }
    if (path == '/product/sessions' && method == 'GET') {
      final current = await digest(
        (req.headers.value('authorization') ?? '').substring(7),
      );
      return {
        'items': rows('sessions')
            .where((s) => s['user'] == uid)
            .map(
              (s) => {
                'id': s['handle'],
                'device': s['device'] ?? 'جلسة تطبيق',
                'created': s['created'],
                'expires': s['expires'],
                'current': s['id'] == current,
              },
            )
            .toList(),
      };
    }
    if (p.length == 3 && p[1] == 'sessions' && method == 'DELETE') {
      final session = rows('sessions')
          .where((s) => s['handle'] == p[2] && s['user'] == uid)
          .firstOrNull;
      if (session == null) throw ApiError(404, 'الجلسة غير موجودة');
      rows('devices').removeWhere((d) => d['session'] == session['id']);
      rows('sessions').remove(session);
      save();
      return {'ok': true};
    }
    if (path == '/product/export' && method == 'GET') {
      return {
        'exported': now(),
        'profile': publicUser(u),
        'posts': rows('posts')
            .where((r) => r['user'] == uid)
            .map(
              (r) => {
                for (final k in [
                  'id',
                  'text',
                  'created',
                  'university',
                  'media',
                ])
                  k: r[k],
              },
            )
            .toList(),
        'comments': rows('comments').where((r) => r['user'] == uid).toList(),
        'documents': rows('documents')
            .where((r) => r['user'] == uid)
            .map(
              (r) => {
                for (final k in ['id', 'name', 'mime', 'created']) k: r[k],
              },
            )
            .toList(),
        'messages': rows('direct')
            .where((r) => r['from'] == uid)
            .map(
              (r) => {
                for (final k in ['id', 'text', 'to', 'created']) k: r[k],
              },
            )
            .toList(),
        'eventRegistrations': rows('eventRegistrations')
            .where((r) => r['user'] == uid)
            .toList(),
        'supportTickets': rows('supportTickets')
            .where((r) => r['user'] == uid)
            .toList(),
      };
    }
    if (path == '/product/membership' && method == 'POST') {
      if (u['role'] == 'admin') {
        throw ApiError(403, 'المشرف يبدّل المؤسسة من لوحة الإدارة');
      }
      final b = await body(req), target = field(b, 'institution');
      if (school({'university': target}) &&
          (b['birthYear'] is! int ||
              b['grade'] is! int ||
              b['birthYear'] < DateTime.now().year - 100 ||
              b['birthYear'] > DateTime.now().year - 5 ||
              b['grade'] < 1 ||
              b['grade'] > 12)) {
        throw ApiError(400, 'أدخل سنة الميلاد والصف لمراجعة المؤسسة');
      }
      if (institution(target) == null ||
          institution(target)?['kind'] == 'platform' ||
          institutionConfig(target)['active'] == false) {
        throw ApiError(404, 'المؤسسة غير متاحة');
      }
      if (rows('membershipRequests')
          .any((r) => r['user'] == uid && r['status'] == 'pending')) {
        throw ApiError(409, 'لديك طلب قيد المراجعة');
      }
      final r = {
        'id': id(),
        'user': uid,
        'university': target,
        'previous': u['university'],
        'birthYear': b['birthYear'],
        'grade': b['grade'],
        'note': field(b, 'note', min: 0, max: 500),
        'status': 'pending',
        'created': now(),
      };
      rows('membershipRequests').add(r);
      save();
      return {'id': r['id']};
    }
    if (path == '/product/invitation/claim' && method == 'POST') {
      final b = await body(req),
          hash = await digest(field(b, 'code', max: 100));
      final invitation = rows('invitations')
          .where((v) => v['digest'] == hash)
          .firstOrNull;
      if (invitation == null ||
          invitation['revoked'] == true ||
          DateTime.parse(invitation['expires'])
              .isBefore(DateTime.now().toUtc()) ||
          invitation['used'] >= invitation['limit']) {
        throw ApiError(400, 'الدعوة منتهية أو غير صالحة');
      }
      if ((invitation['claimed'] as List).contains(uid)) {
        throw ApiError(409, 'استخدمت الدعوة بالفعل');
      }
      if (institutionConfig(invitation['university'])['active'] == false) {
        throw ApiError(403, 'المؤسسة غير متاحة');
      }
      if (u['role'] == 'admin') throw ApiError(403, 'الدعوة ليست لحساب إدارة');
      if (school({'university': invitation['university']}) &&
          invitation['role'] == 'student') {
        throw ApiError(
          409,
          'الالتحاق المدرسي يحتاج طلب انضمام مع بيانات العمر والصف ومراجعة المشرف',
        );
      }
      moveInstitution(u, invitation['university']);
      if (invitation['role'] == 'doctor') {
        u['role'] = 'doctor';
        u['verified'] = true;
      }
      invitation['used']++;
      (invitation['claimed'] as List).add(uid);
      auditAction(u, 'invitation-claim', invitation['id']);
      save();
      return {'user': publicUser(u)};
    }
    if (path == '/product/support' && method == 'GET') {
      return {
        'items': rows('supportTickets')
            .where((r) => r['user'] == uid)
            .toList()
            .reversed
            .toList(),
      };
    }
    if (path == '/product/support' && method == 'POST') {
      final b = await body(req);
      if (rows('supportTickets')
              .where((r) => r['user'] == uid && r['status'] == 'open')
              .length >=
          5) {
        throw ApiError(429, 'تابع تذاكرك المفتوحة أولًا');
      }
      final r = {
        'id': id(),
        'user': uid,
        'university': u['university'],
        'subject': field(b, 'subject', max: 120),
        'text': field(b, 'text', max: 3000),
        'status': 'open',
        'replies': <dynamic>[],
        'created': now(),
      };
      rows('supportTickets').add(r);
      save();
      return {'id': r['id']};
    }
    if (p.length == 4 &&
        p[1] == 'support' &&
        p[3] == 'reply' &&
        method == 'POST') {
      final ticket = find('supportTickets', p[2]);
      if (ticket == null) throw ApiError(404, 'التذكرة غير موجودة');
      if (ticket['user'] != uid) {
        demand(u, 'support');
        scoped(ticket, u);
      }
      final b = await body(req);
      (ticket['replies'] as List).add({
        'id': id(),
        'user': uid,
        'text': field(b, 'text', max: 2000),
        'created': now(),
      });
      ticket['status'] = 'open';
      save();
      return {'ok': true};
    }
    if (path == '/product/appeals' && method == 'GET') {
      return {'items': rows('appeals').where((r) => r['user'] == uid).toList()};
    }
    if (path == '/product/appeals' && method == 'POST') {
      final b = await body(req),
          target = field(b, 'report'),
          report = find('reports', target);
      if (report == null ||
          report['status'] != 'remove' ||
          report['contentOwner'] != uid) {
        throw ApiError(403, 'لا يوجد قرار قابل للاستئناف لحسابك');
      }
      if (rows('appeals')
          .any((r) => r['report'] == target && r['status'] == 'pending')) {
        throw ApiError(409, 'الاستئناف قيد المراجعة');
      }
      final r = {
        'id': id(),
        'user': uid,
        'university': u['university'],
        'report': target,
        'text': field(b, 'text', max: 2000),
        'status': 'pending',
        'created': now(),
      };
      rows('appeals').add(r);
      save();
      return {'id': r['id']};
    }
    if (path == '/product/moderation-decisions' && method == 'GET') {
      return {
        'items': rows('reports')
            .where((r) => r['contentOwner'] == uid && r['status'] == 'remove')
            .map(
              (r) => {
                'id': r['id'],
                'reason': r['decisionReason'] ?? r['reason'],
                'created': r['created'],
              },
            )
            .toList(),
      };
    }
    if (path.startsWith('/product/manage/')) return manageProduct(req, u);
    if ((requireVerification || school(u)) &&
        u['verified'] != true &&
        u['role'] != 'admin') {
      throw ApiError(403, 'يجب اعتماد حسابك للوصول للمحتوى');
    }
    if (u['membershipStatus'] == 'pending' ||
        (u['role'] != 'admin' &&
            institutionConfig(u['university'])['active'] == false)) {
      throw ApiError(403, 'طلب الانضمام ينتظر اعتماد المؤسسة');
    }
    final eventResult = await productEvents(req, u);
    if (eventResult != null) return eventResult;
    final socialResult = await productSocial(req, u);
    if (socialResult != null) return socialResult;
    final voiceResult = await productVoice(req, u);
    if (voiceResult != null) return voiceResult;
    throw ApiError(404, 'الوظيفة غير موجودة');
  }

  Future<Map<String, dynamic>> manageProduct(
    HttpRequest req,
    Map<String, dynamic> u,
  ) async {
    final p = req.uri.pathSegments, method = req.method, path = req.uri.path;
    if (u['role'] != 'admin') throw ApiError(403, 'للمشرف فقط');
    if (path == '/product/manage/overview' && method == 'GET') {
      return {
        'owner': owner(u),
        'permissions': owner(u)
            ? institutionPermissions
            : u['permissions'] ?? [],
        'users': rows('users')
            .where(
              (r) =>
                  manages(u, 'users') &&
                  (owner(u) || r['university'] == u['university']),
            )
            .map((r) => publicUser(r as Map<String, dynamic>))
            .toList(),
        'institutions': institutionList()
            .where((r) => owner(u) || r['id'] == u['university'])
            .map((r) => {...r, ...institutionConfig(r['id'])})
            .toList(),
      };
    }
    if (path == '/product/manage/roles' && method == 'POST') {
      if (!owner(u)) throw ApiError(403, 'تعيين الصلاحيات لمالك المنصة فقط');
      final b = await body(req),
          target = find('users', field(b, 'user')),
          role = field(b, 'role');
      if (target == null || owner(target)) {
        throw ApiError(400, 'لا يمكن تغيير مالك المنصة');
      }
      if (![
        'institution_admin',
        'moderator',
        'student',
        'doctor',
      ].contains(role)) {
        throw ApiError(400, 'دور غير صالح');
      }
      target['role'] = ['institution_admin', 'moderator'].contains(role)
          ? 'admin'
          : role;
      target['managementRole'] = role;
      target['permissions'] = role == 'institution_admin'
          ? institutionPermissions
          : role == 'moderator'
          ? ['reports', 'content']
          : [];
      target['verified'] = role != 'student';
      rows('sessions').removeWhere((s) => s['user'] == target['id']);
      rows('devices').removeWhere((d) => d['user'] == target['id']);
      auditAction(u, 'role-change', target['id']);
      save();
      return {'ok': true};
    }
    if (path == '/product/manage/institutions' && method == 'PATCH') {
      demand(u, 'institutions');
      final b = await body(req), target = field(b, 'institution');
      if (institution(target) == null ||
          (!owner(u) && target != u['university'])) {
        throw ApiError(403, 'المؤسسة خارج نطاق الإدارة');
      }
      if (b['active'] is! bool || b['approvalRequired'] is! bool) {
        throw ApiError(400, 'إعدادات غير صحيحة');
      }
      final r = {
        'id': target,
        'name': field(b, 'name', max: 100),
        'active': b['active'],
        'approvalRequired': b['approvalRequired'],
      };
      rows('institutionSettings').removeWhere((s) => s['id'] == target);
      rows('institutionSettings').add(r);
      auditAction(u, 'institution-settings', target);
      save();
      return {'ok': true};
    }
    if (path == '/product/manage/units' && method == 'GET') {
      demand(u, 'institutions');
      return {
        'items': rows('orgUnits')
            .where((r) => r['university'] == u['university'])
            .toList(),
      };
    }
    if (path == '/product/manage/units' && method == 'POST') {
      demand(u, 'institutions');
      final b = await body(req), kind = field(b, 'kind'), parent = b['parent'];
      if (!['branch', 'faculty', 'department'].contains(kind)) {
        throw ApiError(400, 'نوع غير صحيح');
      }
      if (parent != null) {
        final parentUnit = find('orgUnits', parent);
        sameUniversity(parentUnit, u);
        if (parentUnit!['active'] != true ||
            ['branch', 'faculty', 'department'].indexOf(parentUnit['kind']) >=
                ['branch', 'faculty', 'department'].indexOf(kind)) {
          throw ApiError(400, 'اختر وحدة أعلى في الهيكل');
        }
      }
      final r = {
        'id': id(),
        'university': u['university'],
        'name': field(b, 'name', max: 100),
        'kind': kind,
        'parent': parent,
        'active': true,
      };
      rows('orgUnits').add(r);
      auditAction(u, 'unit-create', r['id']);
      save();
      return {'id': r['id']};
    }
    if (p.length == 5 &&
        p[2] == 'units' &&
        p[4] == 'archive' &&
        method == 'POST') {
      demand(u, 'institutions');
      final r = find('orgUnits', p[3]);
      sameUniversity(r, u);
      r!['active'] = false;
      auditAction(u, 'unit-archive', r['id']);
      save();
      return {'ok': true};
    }
    if (path == '/product/manage/membership' && method == 'GET') {
      demand(u, 'users');
      return {
        'items': rows('membershipRequests')
            .where((r) => owner(u) || r['university'] == u['university'])
            .map(
              (r) => {
                ...r as Map<String, dynamic>,
                'person': author(r['user']),
              },
            )
            .toList(),
      };
    }
    if (p.length == 4 && p[2] == 'membership' && method == 'POST') {
      demand(u, 'users');
      final r = find('membershipRequests', p[3]);
      scoped(r, u);
      if (r!['status'] != 'pending') throw ApiError(409, 'تمت مراجعة الطلب');
      final b = await body(req);
      if (b['approve'] is! bool) throw ApiError(400, 'قرار غير صحيح');
      final reason = field(b, 'reason', min: 0, max: 500);
      final person = find('users', r['user']);
      if (person == null || person['role'] == 'admin') {
        throw ApiError(400, 'الحساب غير متاح');
      }
      if (b['approve'] == true) {
        if (school({'university': r['university']}) &&
            r['birthYear'] is int &&
            r['grade'] is int) {
          person['birthYear'] = r['birthYear'];
          person['grade'] = r['grade'];
          person['verified'] = false;
        }
        if (school({'university': r['university']}) &&
            (person['birthYear'] is! int || person['grade'] is! int)) {
          throw ApiError(
            400,
            'أكمل بيانات الصف والعمر قبل اعتماد الانتقال لمدرسة',
          );
        }
        moveInstitution(person, r['university']);
      }
      r['status'] = b['approve'] == true ? 'approved' : 'rejected';
      r['reviewer'] = u['id'];
      r['reason'] = reason;
      auditAction(u, 'membership-decision', r['id']);
      notify(person['id'], u['id'], 'membership', 'تمت مراجعة طلب انضمامك');
      save();
      return {'ok': true};
    }
    if (path == '/product/manage/invitations' && method == 'GET') {
      demand(u, 'users');
      return {
        'items': rows('invitations')
            .where((r) => r['university'] == u['university'])
            .map(
              (r) => {
                for (final k in [
                  'id',
                  'role',
                  'expires',
                  'used',
                  'limit',
                  'revoked',
                ])
                  k: r[k],
              },
            )
            .toList(),
      };
    }
    if (path == '/product/manage/invitations' && method == 'POST') {
      demand(u, 'users');
      final b = await body(req), role = field(b, 'role'), limit = b['limit'];
      if (!['student', 'doctor'].contains(role) ||
          limit is! int ||
          limit < 1 ||
          limit > 500) {
        throw ApiError(400, 'دعوة غير صحيحة');
      }
      final code = id(), hash = await digest(code);
      final r = {
        'id': id(),
        'university': u['university'],
        'digest': hash,
        'role': role,
        'limit': limit,
        'used': 0,
        'claimed': <dynamic>[],
        'expires': DateTime.now()
            .toUtc()
            .add(const Duration(days: 7))
            .toIso8601String(),
        'revoked': false,
      };
      rows('invitations').add(r);
      auditAction(u, 'invitation-create', r['id']);
      save();
      return {'id': r['id'], 'code': code};
    }
    if (p.length == 4 && p[2] == 'invitations' && method == 'DELETE') {
      demand(u, 'users');
      final r = find('invitations', p[3]);
      sameUniversity(r, u);
      r!['revoked'] = true;
      auditAction(u, 'invitation-revoke', r['id']);
      save();
      return {'ok': true};
    }
    if (path == '/product/manage/support' && method == 'GET') {
      demand(u, 'support');
      return {
        'items': rows('supportTickets')
            .where((r) => owner(u) || r['university'] == u['university'])
            .map(
              (r) => {
                ...r as Map<String, dynamic>,
                'person': author(r['user']),
              },
            )
            .toList(),
      };
    }
    if (p.length == 4 && p[2] == 'support' && method == 'POST') {
      demand(u, 'support');
      final r = find('supportTickets', p[3]);
      scoped(r, u);
      final b = await body(req);
      if (!['open', 'closed'].contains(b['status'])) {
        throw ApiError(400, 'حالة غير صحيحة');
      }
      (r!['replies'] as List).add({
        'id': id(),
        'user': u['id'],
        'text': field(b, 'text', max: 2000),
        'created': now(),
      });
      r['status'] = b['status'];
      auditAction(u, 'support-reply', r['id']);
      notify(r['user'], u['id'], 'support', 'تم الرد على تذكرة الدعم');
      save();
      return {'ok': true};
    }
    if (path == '/product/manage/appeals' && method == 'GET') {
      demand(u, 'reports');
      return {
        'items': rows('appeals')
            .where((r) => owner(u) || r['university'] == u['university'])
            .toList(),
      };
    }
    if (p.length == 4 && p[2] == 'appeals' && method == 'POST') {
      demand(u, 'reports');
      final r = find('appeals', p[3]);
      scoped(r, u);
      final b = await body(req);
      if (!['accepted', 'rejected'].contains(b['status'])) {
        throw ApiError(400, 'قرار غير صحيح');
      }
      final response = field(b, 'response', max: 2000);
      if (r!['status'] != 'pending') {
        throw ApiError(409, 'تمت مراجعة الاستئناف');
      }
      r['status'] = b['status'];
      r['response'] = response;
      auditAction(u, 'appeal-decision', r['id']);
      notify(r['user'], u['id'], 'moderation', 'تم الرد على استئنافك');
      save();
      return {'ok': true};
    }
    if (path == '/product/manage/audit' && method == 'GET') {
      demand(u, 'audit');
      return {
        'items': rows('audit')
            .where((r) => owner(u) || r['university'] == u['university'])
            .toList()
            .reversed
            .take(500)
            .map(
              (r) => {
                ...r as Map<String, dynamic>,
                'person': author(r['actor']),
              },
            )
            .toList(),
      };
    }
    throw ApiError(404, 'إجراء الإدارة غير موجود');
  }
}
