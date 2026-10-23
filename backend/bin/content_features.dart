part of 'server.dart';

extension ContentFeatures on ClubServer {
  bool contentVisible(Map<String, dynamic> row, Map<String, dynamic> u) =>
      row['university'] == u['university'] &&
      !blocked(row['user'], u['id']) &&
      (!school(u) || schoolSocial(u, find('users', row['user']) ?? u)) &&
      (row['section'] == null
          ? (!school(u) || u['role'] == 'admin' || row['user'] == u['id'])
          : find('sections', row['section']) != null &&
                sectionMember(find('sections', row['section'])!, u));
  String? contentAudience(Map<String, dynamic> b, Map<String, dynamic> u) {
    final target = b['section'];
    if (target == null) {
      if (school(u) && u['role'] != 'admin') {
        throw ApiError(400, 'اختر شعبة للمشاركة المدرسية');
      }
      return null;
    }
    if (target is! String) throw ApiError(400, 'اختر شعبة صحيحة');
    final s = find('sections', target);
    sameUniversity(s, u);
    if (!sectionMember(s!, u) || s['active'] != true) {
      throw ApiError(403, 'الشعبة غير متاحة');
    }
    return target;
  }

  Future<void> serveDocument(HttpRequest req) async {
    final u = await authenticated(req);
    if (u['role'] != 'admin' &&
        (u['membershipStatus'] == 'pending' ||
            institutionConfig(u['university'])['active'] == false)) {
      throw ApiError(403, 'المؤسسة غير متاحة');
    }
    if ((requireVerification || school(u)) &&
        u['verified'] != true &&
        u['role'] != 'admin') {
      throw ApiError(403, 'يجب اعتماد الحساب');
    }
    final row = find('documents', req.uri.pathSegments[1]);
    if (row == null || !contentVisible(row, u)) {
      throw ApiError(404, 'المستند غير موجود');
    }
    final disk = File('${file.parent.path}/documents/${row['id']}.bin');
    if (!disk.existsSync()) throw ApiError(404, 'المستند غير موجود');
    req.response.headers.contentType = ContentType.parse(row['mime']);
    req.response.headers.set('X-Content-Type-Options', 'nosniff');
    req.response.headers.set(
      'Content-Disposition',
      "attachment; filename*=UTF-8''${Uri.encodeComponent(row['name'])}",
    );
    req.response.contentLength = await disk.length();
    await req.response.addStream(disk.openRead());
  }

  Future<Map<String, dynamic>?> contentFeatures(
    HttpRequest req,
    Map<String, dynamic> u,
  ) async {
    final path = req.uri.path, method = req.method, uid = u['id'] as String;
    if (path == '/documents' && method == 'GET') {
      return {
        'items': rows('documents')
            .where((r) => contentVisible(r, u))
            .toList()
            .reversed
            .map(
              (r) => {
                ...r as Map<String, dynamic>,
                'author': author(r['user']),
                'canDelete': r['user'] == uid || u['role'] == 'admin',
              },
            )
            .toList(),
      };
    }
    if (path == '/documents' && method == 'POST') {
      final b = await body(req, limit: 15 * 1024 * 1024),
          name = field(b, 'name', max: 140),
          section = contentAudience(b, u);
      if (name.contains('/') ||
          name.contains('\\') ||
          name.contains('\r') ||
          name.contains('\n')) {
        throw ApiError(400, 'اسم ملف غير صحيح');
      }
      List<int> bytes;
      try {
        bytes = base64.decode(field(b, 'data', max: 14 * 1024 * 1024));
      } catch (_) {
        throw ApiError(400, 'ملف غير صحيح');
      }
      if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
        throw ApiError(413, 'الحد الأقصى للمستند ١٠ ميجابايت');
      }
      String? mime;
      final lower = name.toLowerCase();
      if (lower.endsWith('.pdf') &&
          bytes.length > 8 &&
          ascii.decode(bytes.take(5).toList(), allowInvalid: true) == '%PDF-') {
        mime = 'application/pdf';
      }
      if (lower.endsWith('.txt')) {
        try {
          final text = utf8.decode(bytes);
          if (!text.contains('\u0000')) mime = 'text/plain';
        } catch (_) {}
      }
      if (lower.endsWith('.docx') &&
          bytes.length > 4 &&
          bytes[0] == 80 &&
          bytes[1] == 75) {
        try {
          final zip = archive.ZipDecoder().decodeBytes(bytes);
          var size = 0;
          for (final f in zip) {
            size += f.size;
            if (size > 40 * 1024 * 1024 ||
                zip.length > 1000 ||
                f.name.toLowerCase().contains('vbaproject') ||
                f.name.toLowerCase().endsWith('.exe')) {
              throw const FormatException();
            }
          }
          if (zip.any((f) => f.name == '[Content_Types].xml') &&
              zip.any((f) => f.name == 'word/document.xml')) {
            mime = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
          }
        } catch (_) {
          throw ApiError(400, 'مستند Word غير صالح أو أكبر من الحد');
        }
      }
      if (mime == null) throw ApiError(400, 'الصيغ المدعومة PDF وDOCX وTXT');
      final total = [...rows('documents'), ...rows('media')]
          .where((r) => r['user'] == uid)
          .fold<int>(0, (sum, r) => sum + (r['size'] as int));
      if (total + bytes.length > 150 * 1024 * 1024) {
        throw ApiError(413, 'وصلت إلى حد التخزين للحساب');
      }
      final row = {
        'id': id(),
        'name': name,
        'mime': mime,
        'size': bytes.length,
        'user': uid,
        'university': u['university'],
        'section': section,
        'created': now(),
      };
      final disk = File('${file.parent.path}/documents/${row['id']}.bin');
      disk.parent.createSync(recursive: true);
      disk.writeAsBytesSync(bytes, flush: true);
      rows('documents').add(row);
      save();
      return {'id': row['id']};
    }
    if (path == '/polls' && method == 'GET') {
      return {
        'items': rows('polls')
            .where((r) => contentVisible(r, u))
            .toList()
            .reversed
            .map((r) {
              final votes = r['votes'] as Map;
              return {
                ...r as Map<String, dynamic>,
                'votes': null,
                'counts': List.generate(
                  (r['options'] as List).length,
                  (i) => votes.values.where((v) => v == i).length,
                ),
                'myVote': votes[uid],
                'total': votes.length,
                'author': author(r['user']),
                'canClose': r['user'] == uid || u['role'] == 'admin',
              };
            })
            .toList(),
      };
    }
    if (path == '/polls' && method == 'POST') {
      final b = await body(req),
          question = field(b, 'question', max: 250),
          section = contentAudience(b, u),
          options = b['options'];
      if (options is! List ||
          options.length < 2 ||
          options.length > 6 ||
          options.any(
            (v) => v is! String || v.trim().isEmpty || v.length > 100,
          ) ||
          options.map((v) => (v as String).trim()).toSet().length !=
              options.length) {
        throw ApiError(400, 'أدخل من خيارين إلى ٦ خيارات مختلفة');
      }
      final row = {
        'id': id(),
        'user': uid,
        'university': u['university'],
        'section': section,
        'question': question,
        'options': options.map((v) => (v as String).trim()).toList(),
        'votes': <String, dynamic>{},
        'closed': false,
        'created': now(),
      };
      rows('polls').add(row);
      save();
      return {'id': row['id']};
    }
    final p = req.uri.pathSegments;
    if (p.length == 3 && p[0] == 'polls' && method == 'POST') {
      final poll = find('polls', p[1]);
      if (poll == null || !contentVisible(poll, u)) {
        throw ApiError(404, 'الاستطلاع غير موجود');
      }
      if (p[2] == 'vote') {
        if (poll['closed'] == true) throw ApiError(409, 'أُغلق الاستطلاع');
        final b = await body(req), choice = b['choice'];
        if (choice is! int ||
            choice < 0 ||
            choice >= (poll['options'] as List).length) {
          throw ApiError(400, 'اختيار غير صحيح');
        }
        (poll['votes'] as Map)[uid] = choice;
        save();
        return {'ok': true};
      }
      if (p[2] == 'close') {
        if (poll['user'] != uid && u['role'] != 'admin') {
          throw ApiError(403, 'غير مسموح');
        }
        poll['closed'] = true;
        save();
        return {'ok': true};
      }
    }
    if (p.length == 2 &&
        ['documents', 'polls'].contains(p[0]) &&
        method == 'DELETE') {
      final row = find(p[0], p[1]);
      if (row == null || !contentVisible(row, u)) {
        throw ApiError(404, 'المحتوى غير موجود');
      }
      if (row['user'] != uid && u['role'] != 'admin') {
        throw ApiError(403, 'غير مسموح');
      }
      if (p[0] == 'documents') {
        final disk = File('${file.parent.path}/documents/${row['id']}.bin');
        if (disk.existsSync()) disk.deleteSync();
      }
      rows(p[0]).remove(row);
      save();
      return {'ok': true};
    }
    if (path == '/announcement-reports' && method == 'GET') {
      if (!canAnnounce(u)) throw ApiError(403, 'التقارير للناشر والمشرف فقط');
      return {
        'items': rows('announcements')
            .where(
              (a) =>
                  a['university'] == u['university'] &&
                  (u['role'] == 'admin' || a['user'] == uid),
            )
            .map((a) {
              final eligible = rows('users')
                  .where(
                    (r) =>
                        r['role'] == 'student' &&
                        (!(requireVerification || school(r)) ||
                            r['verified'] == true) &&
                        r['disabled'] != true &&
                        seesAnnouncement(a, r),
                  )
                  .toList();
              final seen = eligible
                  .where((r) => (a['views'] as List).contains(r['id']))
                  .length;
              final delays = (a['viewTimes'] as Map? ?? {}).entries
                  .where((e) => eligible.any((r) => r['id'] == e.key))
                  .map(
                    (e) =>
                        DateTime.parse(e.value)
                            .difference(DateTime.parse(a['created']))
                            .inSeconds,
                  )
                  .toList();
              return {
                'id': a['id'],
                'text': a['text'],
                'created': a['created'],
                'eligible': eligible.length,
                'seen': seen,
                'percent': eligible.isEmpty
                    ? 0
                    : (seen * 100 / eligible.length).round(),
                'averageSeconds': delays.isEmpty
                    ? null
                    : delays.reduce((a, b) => a + b) ~/ delays.length,
              };
            })
            .toList(),
      };
    }
    return null;
  }
}
