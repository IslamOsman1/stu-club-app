part of 'server.dart';

extension CourseFeatures on ClubServer {
  bool sectionMember(Map<String, dynamic> section, Map<String, dynamic> user) =>
      section['university'] == user['university'] &&
      (user['role'] == 'admin' ||
          (section['active'] == true &&
              (((section['teachers'] as List).contains(user['id']) &&
                      user['role'] == 'doctor' &&
                      user['verified'] == true) ||
                  (section['students'] as List).contains(user['id']))));

  List<String> academicMembers(
    Map<String, dynamic> b,
    String key,
    Map<String, dynamic> admin, {
    required bool teacher,
  }) {
    final raw = b[key];
    if (raw is! List || raw.length > 500 || raw.any((v) => v is! String)) {
      throw ApiError(400, 'قائمة أعضاء غير صحيحة');
    }
    final ids = raw.cast<String>().toSet().toList();
    for (final member in ids) {
      final u = find('users', member);
      if (u == null ||
          u['university'] != admin['university'] ||
          u['disabled'] == true ||
          (teacher
              ? (u['role'] != 'doctor' || u['verified'] != true)
              : u['role'] != 'student')) {
        throw ApiError(
          400,
          teacher
              ? 'اختر مدرسين معتمدين من نفس المؤسسة'
              : 'اختر طلابًا من نفس المؤسسة',
        );
      }
    }
    return ids;
  }

  Future<Map<String, dynamic>?> courses(
    HttpRequest req,
    Map<String, dynamic> u,
  ) async {
    final path = req.uri.path, method = req.method;
    final admin = u['role'] == 'admin';
    if (path == '/courses' && method == 'GET') {
      final sections = rows('sections').where((s) => sectionMember(s, u)).map((
        raw,
      ) {
        final s = Map<String, dynamic>.from(raw);
        return {
          ...s,
          'courseName': find('courses', s['course'])?['name'] ?? '',
          'teachers': (s['teachers'] as List).map((id) => author(id)).toList(),
          'studentCount': (s['students'] as List).length,
          if (admin)
            'students': (s['students'] as List).map((id) => author(id)).toList()
          else
            'students': <dynamic>[],
          'canPublish': admin || (s['teachers'] as List).contains(u['id']),
        };
      }).toList();
      final visibleCourses = rows('courses')
          .where(
            (c) =>
                c['university'] == u['university'] &&
                (admin || sections.any((s) => s['course'] == c['id'])),
          )
          .toList();
      return {'items': visibleCourses, 'sections': sections, 'isAdmin': admin};
    }
    if (path == '/courses/people' && method == 'GET') {
      if (!admin) throw ApiError(403, 'إدارة التسجيل للمشرف فقط');
      return {
        'items': rows('users')
            .where(
              (v) => v['university'] == u['university'] && v['role'] != 'admin',
            )
            .map(
              (v) => {
                ...author(v['id']),
                'email': v['email'],
                'disabled': v['disabled'],
              },
            )
            .toList(),
      };
    }
    if (path == '/courses' && method == 'POST') {
      if (!admin) throw ApiError(403, 'إنشاء المواد للمشرف فقط');
      final b = await body(req),
          name = field(b, 'name', max: 100),
          code = field(b, 'code', max: 30).toUpperCase();
      if (rows(
        'courses',
      ).any((c) => c['university'] == u['university'] && c['code'] == code)) {
        throw ApiError(409, 'رمز المادة مستخدم في المؤسسة');
      }
      final c = {
        'id': id(),
        'university': u['university'],
        'name': name,
        'code': code,
        'created': now(),
      };
      rows('courses').add(c);
      save();
      return {'id': c['id']};
    }
    final p = req.uri.pathSegments;
    if (p.length == 3 &&
        p[0] == 'courses' &&
        p[2] == 'sections' &&
        method == 'POST') {
      if (!admin) throw ApiError(403, 'إنشاء الشعب للمشرف فقط');
      final c = find('courses', p[1]);
      sameUniversity(c, u);
      final b = await body(req, limit: 80000), name = field(b, 'name', max: 80);
      final teachers = academicMembers(b, 'teachers', u, teacher: true),
          students = academicMembers(b, 'students', u, teacher: false);
      if (rows('sections')
          .any((s) => s['course'] == p[1] && s['name'] == name)) {
        throw ApiError(409, 'اسم الشعبة مستخدم للمادة');
      }
      final s = {
        'id': id(),
        'course': p[1],
        'university': u['university'],
        'name': name,
        'teachers': teachers,
        'students': students,
        'active': true,
        'created': now(),
      };
      rows('sections').add(s);
      syncSectionGroup(s);
      save();
      return {'id': s['id']};
    }
    if (p.length == 2 && p[0] == 'sections' && method == 'PATCH') {
      if (!admin) throw ApiError(403, 'تعديل التسجيل للمشرف فقط');
      final s = find('sections', p[1]);
      sameUniversity(s, u);
      final b = await body(req, limit: 80000), name = field(b, 'name', max: 80);
      final teachers = academicMembers(b, 'teachers', u, teacher: true),
          students = academicMembers(b, 'students', u, teacher: false);
      if (b['active'] is! bool) throw ApiError(400, 'حالة الشعبة غير صحيحة');
      if (rows('sections').any(
        (v) =>
            v['id'] != s!['id'] &&
            v['course'] == s['course'] &&
            v['name'] == name,
      )) {
        throw ApiError(409, 'اسم الشعبة مستخدم للمادة');
      }
      s!.addAll({
        'name': name,
        'teachers': teachers,
        'students': students,
        'active': b['active'],
      });
      syncSectionGroup(s);
      rows('notifications').removeWhere((n) {
        if (n['type'] != 'announcement') return false;
        final announcement = find('announcements', n['target'] ?? '');
        final recipient = find('users', n['user']);
        return announcement?['section'] == s['id'] &&
            (recipient == null || !seesAnnouncement(announcement!, recipient));
      });
      rows('audit').add({
        'id': id(),
        'actor': u['id'],
        'action': 'section-membership',
        'target': s['id'],
        'created': now(),
      });
      save();
      return {'ok': true};
    }
    return null;
  }
}
