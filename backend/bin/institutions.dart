part of 'server.dart';

extension InstitutionFeatures on ClubServer {
  List<Map<String, dynamic>> institutionList() => [
    ...universities.map(
      (v) => {
        'id': v['id'],
        'name': v['name'],
        'kind': v['id'] == 'school_demo' ? 'school' : 'university',
      },
    ),
    ...rows('institutions').cast<Map<String, dynamic>>(),
  ];
  Map<String, dynamic>? institution(String id) =>
      institutionList().where((v) => v['id'] == id).firstOrNull;
  bool school(Map<String, dynamic> u) =>
      institution(u['university'])?['kind'] == 'school';
  int? ageBand(Map<String, dynamic> u) {
    final year = u['birthYear'];
    if (year is! int) return null;
    final age = DateTime.now().toUtc().year - year;
    return age < 13
        ? 0
        : age < 18
        ? 1
        : 2;
  }

  bool schoolSocial(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (!school(a)) return true;
    if (a['role'] == 'admin' || b['role'] == 'admin') return true;
    if (a['role'] == 'student' && b['role'] == 'student') {
      return ageBand(a) != null &&
          ageBand(a) == ageBand(b) &&
          a['grade'] != null &&
          a['grade'] == b['grade'];
    }
    if (a['role'] != 'student' && b['role'] != 'student') return true;
    if ((a['role'] != 'student' && a['verified'] != true) ||
        (b['role'] != 'student' && b['verified'] != true)) {
      return false;
    }
    return rows('sections').any(
      (s) =>
          s['active'] == true &&
          s['university'] == a['university'] &&
          (((s['teachers'] as List).contains(a['id']) &&
                  (s['students'] as List).contains(b['id'])) ||
              ((s['teachers'] as List).contains(b['id']) &&
                  (s['students'] as List).contains(a['id']))),
    );
  }

  bool schoolGroup(Map<String, dynamic> g, Map<String, dynamic> u) {
    if (!school(u) || u['role'] == 'admin') return true;
    final section = find('sections', g['section'] ?? '');
    return section != null && sectionMember(section, u);
  }

  void syncSectionGroup(Map<String, dynamic> section) {
    var group = rows('groups')
        .where((g) => g['section'] == section['id'])
        .firstOrNull;
    if (group == null) {
      group = {
        'id': id(),
        'university': section['university'],
        'section': section['id'],
      };
      rows('groups').add(group);
    }
    group['name'] =
        '${find('courses', section['course'])?['name'] ?? ''} · ${section['name']}';
    group['members'] = [
      ...section['teachers'] as List,
      ...section['students'] as List,
    ];
  }

  Future<Map<String, dynamic>?> institutions(
    HttpRequest req,
    Map<String, dynamic> u,
  ) async {
    final path = req.uri.path, method = req.method;
    if (path == '/institutions/manage' && method == 'GET') {
      if (u['role'] != 'admin') throw ApiError(403, 'للمشرف فقط');
      return {
        'items': institutionList(),
        'people': rows('users')
            .where((p) => p['university'] == u['university'])
            .map((p) => publicUser(p))
            .toList(),
      };
    }
    if (path == '/institutions' && method == 'POST') {
      if (u['role'] != 'admin') {
        throw ApiError(403, 'إنشاء المؤسسات للمشرف فقط');
      }
      final b = await body(req),
          name = field(b, 'name', max: 100),
          kind = field(b, 'kind');
      if (!['school', 'university'].contains(kind)) {
        throw ApiError(400, 'نوع المؤسسة غير صحيح');
      }
      if (institutionList().any((v) => v['name'] == name)) {
        throw ApiError(409, 'المؤسسة موجودة');
      }
      final row = {'id': id(), 'name': name, 'kind': kind, 'created': now()};
      rows('institutions').add(row);
      save();
      return {'id': row['id']};
    }
    if (path == '/institutions/select' && method == 'POST') {
      if (u['role'] != 'admin') {
        throw ApiError(403, 'تبديل نطاق الإدارة للمشرف فقط');
      }
      final b = await body(req), target = field(b, 'institution');
      if (institution(target) == null) {
        throw ApiError(404, 'المؤسسة غير موجودة');
      }
      u['university'] = target;
      save();
      return {'user': publicUser(u)};
    }
    final p = req.uri.pathSegments;
    if (p.length == 3 &&
        p[0] == 'institutions' &&
        p[1] == 'students' &&
        method == 'PATCH') {
      if (u['role'] != 'admin') {
        throw ApiError(403, 'تعديل بيانات المدرسة للمشرف فقط');
      }
      final student = find('users', p[2]);
      sameUniversity(student, u);
      if (!school(student!) || student['role'] != 'student') {
        throw ApiError(400, 'الحساب ليس طالب مدرسة');
      }
      final b = await body(req), year = b['birthYear'], grade = b['grade'];
      if (year is! int ||
          year < DateTime.now().year - 100 ||
          year > DateTime.now().year - 5 ||
          grade is! int ||
          grade < 1 ||
          grade > 12) {
        throw ApiError(400, 'أدخل سنة ميلاد صحيحة وصفًا من ١ إلى ١٢');
      }
      student.addAll({'birthYear': year, 'grade': grade});
      for (final relation in List<Map<String, dynamic>>.from(
        rows(
          'friends',
        ).where((r) => r['from'] == student['id'] || r['to'] == student['id']),
      )) {
        final peer = find(
          'users',
          relation['from'] == student['id'] ? relation['to'] : relation['from'],
        );
        if (peer == null || !schoolSocial(student, peer)) {
          clearRelationship(student['id'], peer?['id'] ?? '');
        }
      }
      save();
      return {'ok': true};
    }
    return null;
  }
}
