part of 'server.dart';

const questions = <Map<String, dynamic>>[
  {
    'id': 'stack-1',
    'question': 'أي بنية بيانات تعمل بمبدأ آخر داخل، أول خارج؟',
    'choices': ['Queue — الطابور', 'Stack — المكدس', 'Array — المصفوفة'],
    'answer': 1,
    'explanation': 'المكدس يخرج آخر عنصر تمت إضافته أولًا.',
  },
  {
    'id': 'net-1',
    'question': 'ما البروتوكول الذي يشفر اتصال الموقع؟',
    'choices': ['HTTP', 'FTP', 'HTTPS'],
    'answer': 2,
    'explanation': 'HTTPS يستخدم TLS لحماية الاتصال.',
  },
  {
    'id': 'math-1',
    'question': 'ما ناتج ١٢ × ٨؟',
    'choices': ['٩٦', '٨٨', '١٠٢'],
    'answer': 0,
    'explanation': '١٢ × ٨ = ٩٦.',
  },
  {
    'id': 'science-1',
    'question': 'ما وحدة قياس شدة التيار الكهربائي؟',
    'choices': ['الفولت', 'الأمبير', 'الأوم'],
    'answer': 1,
    'explanation': 'الأمبير وحدة شدة التيار الكهربائي.',
  },
  {
    'id': 'code-1',
    'question': 'أي بحث يحتاج بيانات مرتبة؟',
    'choices': ['البحث الخطي', 'البحث العشوائي', 'البحث الثنائي'],
    'answer': 2,
    'explanation': 'البحث الثنائي يقسم نطاق البحث المرتب في كل خطوة.',
  },
  {
    'id': 'math-2',
    'question': 'ما احتمال ظهور صورة عند رمي عملة عادلة؟',
    'choices': ['نصف', 'ربع', 'واحد'],
    'answer': 0,
    'explanation': 'للعملة نتيجتان متساويتان في الاحتمال.',
  },
  {
    'id': 'logic-1',
    'question': 'كل الطلاب يتعلمون. أحمد طالب. ماذا نستنتج؟',
    'choices': ['أحمد لا يتعلم', 'أحمد يتعلم', 'لا يمكن الاستنتاج'],
    'answer': 1,
    'explanation': 'أحمد ينتمي لمجموعة الطلاب التي ينطبق عليها الوصف.',
  },
  {
    'id': 'web-1',
    'question': 'ما الوظيفة الأساسية لـ CSS؟',
    'choices': ['حفظ كلمات المرور', 'تنسيق صفحات الويب', 'إرسال البريد'],
    'answer': 1,
    'explanation': 'CSS تحدد مظهر وعرض عناصر صفحة الويب.',
  },
  {
    'id': 'science-2',
    'question': 'أي كوكب يُعرف بالكوكب الأحمر؟',
    'choices': ['الزهرة', 'المشتري', 'المريخ'],
    'answer': 2,
    'explanation': 'يبدو المريخ أحمر بسبب أكاسيد الحديد على سطحه.',
  },
  {
    'id': 'study-1',
    'question': 'أي أسلوب يساعد على تثبيت التعلم طويلًا؟',
    'choices': [
      'المراجعة المتباعدة',
      'القراءة مرة واحدة',
      'المذاكرة بلا فواصل',
    ],
    'answer': 0,
    'explanation': 'توزيع المراجعة على فترات يساعد على الاحتفاظ بالمعلومات.',
  },
];

extension ClubFeatures on ClubServer {
  Future<Map<String, dynamic>?> mathGame(
    HttpRequest req,
    Map<String, dynamic> user,
  ) async {
    final uid = user['id'] as String,
        day = DateTime.now().toUtc().toIso8601String().substring(0, 10),
        scoreKey = 'math:$day';
    if (req.uri.path == '/games/math/start' && req.method == 'POST') {
      final scored = rows('scores')
          .where((s) => s['user'] == uid && s['quiz'] == scoreKey);
      if (scored.isNotEmpty) {
        return {
          'done': true,
          'points': scored.first['points'],
          'correctCount': scored.first['correctCount'],
        };
      }
      final pending = rows('rounds').where(
        (r) =>
            r['user'] == uid &&
            r['day'] == day &&
            DateTime.parse(r['expires']).isAfter(DateTime.now().toUtc()),
      );
      Map<String, dynamic> round;
      if (pending.isNotEmpty) {
        round = pending.first as Map<String, dynamic>;
      } else {
        final challenges = List.generate(10, (_) {
          final a = 2 + random.nextInt(19),
              b = 2 + random.nextInt(19),
              op = random.nextInt(2);
          return {
            'text': op == 0 ? '$a + $b = ؟' : '$a × $b = ؟',
            'answer': op == 0 ? a + b : a * b,
          };
        });
        round = {
          'id': id(),
          'user': uid,
          'day': day,
          'expires': DateTime.now()
              .toUtc()
              .add(const Duration(seconds: 90))
              .toIso8601String(),
          'questions': challenges,
        };
        rows('rounds').removeWhere((r) => r['user'] == uid);
        rows('rounds').add(round);
        save();
      }
      return {
        'id': round['id'],
        'expires': round['expires'],
        'questions': (round['questions'] as List)
            .map((q) => q['text'])
            .toList(),
      };
    }
    if (req.uri.path == '/games/math/submit' && req.method == 'POST') {
      final b = await body(req), round = find('rounds', field(b, 'id'));
      if (round == null || round['user'] != uid) {
        throw ApiError(404, 'الجولة غير موجودة');
      }
      final key = 'math:${round['day']}',
          old = rows('scores')
              .where((s) => s['user'] == uid && s['quiz'] == key);
      if (old.isNotEmpty) {
        return {
          'done': true,
          'points': old.first['points'],
          'correctCount': old.first['correctCount'],
        };
      }
      if (DateTime.parse(round['expires']).isBefore(DateTime.now().toUtc())) {
        throw ApiError(400, 'انتهى الوقت، ابدأ جولة جديدة');
      }
      final answers = b['answers'];
      if (answers is! List ||
          answers.length != 10 ||
          answers.any((a) => a is! int)) {
        throw ApiError(400, 'أجب عن الأسئلة العشرة');
      }
      var correct = 0;
      for (var i = 0; i < 10; i++) {
        if (answers[i] == round['questions'][i]['answer']) correct++;
      }
      rows('scores').add({
        'id': id(),
        'user': uid,
        'quiz': key,
        'points': correct * 5,
        'correctCount': correct,
      });
      save();
      recordActivity(uid);
      save();
      return {'done': true, 'points': correct * 5, 'correctCount': correct};
    }
    return null;
  }

  Future<Map<String, dynamic>> recover(HttpRequest req) async {
    final ip = 'recover:${req.connectionInfo?.remoteAddress.address}';
    final times = attempts.putIfAbsent(ip, () => []);
    times.removeWhere(
      (t) => t.isBefore(DateTime.now().subtract(const Duration(minutes: 15))),
    );
    if (times.length >= 8) throw ApiError(429, 'محاولات كثيرة، انتظر ١٥ دقيقة');
    times.add(DateTime.now());
    final b = await body(req),
        email = field(b, 'email', max: 180).toLowerCase(),
        code = field(b, 'code', max: 100),
        next = field(b, 'newPassword', min: 10, max: 128);
    final hash = await digest(code);
    final matches = rows('users')
        .where(
          (u) =>
              u['email'] == email &&
              u['recoveryHash'] == hash &&
              u['disabled'] != true,
        )
        .toList();
    if (matches.isEmpty) {
      throw ApiError(400, 'البريد أو كود الاستعادة غير صحيح');
    }
    final user = matches.first as Map<String, dynamic>;
    final salt = List.generate(24, (_) => random.nextInt(256));
    final newHash = await kdf.deriveKeyFromPassword(
      password: next,
      nonce: salt,
    );
    if (user['recoveryHash'] != hash || find('users', user['id']) == null) {
      throw ApiError(400, 'الكود لم يعد صالحًا');
    }
    user['salt'] = base64.encode(salt);
    user['password'] = base64.encode(await newHash.extractBytes());
    user.remove('recoveryHash');
    rows('sessions').removeWhere((s) => s['user'] == user['id']);
    save();
    return {'ok': true};
  }

  bool blocked(String a, String b) => rows('blocks').any(
    (r) =>
        (r['user'] == a && r['target'] == b) ||
        (r['user'] == b && r['target'] == a),
  );
  void notify(
    String recipient,
    String actor,
    String text,
    String description, {
    String? target,
  }) {
    if (recipient == actor || blocked(recipient, actor)) return;
    final prefs = rows('notificationSettings')
        .where((r) => r['id'] == recipient)
        .firstOrNull;
    final category = ['announcement', 'event'].contains(text)
        ? 'academic'
        : text == 'message'
        ? 'messages'
        : [
            'like',
            'comment',
            'friend',
            'game',
            'friend_request',
            'friend_accept',
            'game_invite',
            'group_invite',
          ].contains(text)
        ? 'social'
        : null;
    if (category != null && prefs?[category] == false) return;
    if (pushReady && prefs?['push'] != false) pendingPush.add(recipient);
    rows('notifications').add({
      'id': id(),
      'user': recipient,
      'actor': actor,
      'type': text,
      'text': description,
      'target': target,
      'read': false,
      'created': now(),
    });
  }

  void removeContent(String type, Map<String, dynamic> row) {
    if (row['voice'] != null) {
      final disk = File('${file.parent.path}/voice/${row['voice']}.m4a');
      if (disk.existsSync()) disk.deleteSync();
      rows('voiceAttachments').removeWhere((v) => v['id'] == row['voice']);
    }
    if (type == 'posts') {
      rows('savedPosts').removeWhere((s) => s['post'] == row['id']);
      rows('comments').removeWhere((c) => c['post'] == row['id']);
    }
    if (row['media'] != null) {
      final media = find('media', row['media']);
      if (media != null) {
        final disk = mediaFile(media['id']);
        if (disk.existsSync()) disk.deleteSync();
        rows('media').remove(media);
      }
    }
    rows(type).remove(row);
  }

  File mediaFile(String mediaId) =>
      File('${file.parent.path}/media/$mediaId.bin');
  Future<void> verifyPassword(
    Map<String, dynamic> user,
    String password,
  ) async {
    final expected = user['password'] as String;
    final hash = await kdf.deriveKeyFromPassword(
      password: password,
      nonce: base64.decode(user['salt']),
    );
    final actual = await hash.extractBytes(), saved = base64.decode(expected);
    var diff = 0;
    for (var i = 0; i < 32; i++) {
      diff |= actual[i] ^ saved[i];
    }
    if (diff != 0 ||
        user['password'] != expected ||
        find('users', user['id']) == null) {
      throw ApiError(400, 'كلمة المرور الحالية غير صحيحة');
    }
  }

  Future<void> serveMedia(HttpRequest request) async {
    final user = await authenticated(request), uid = user['id'] as String;
    if (user['role'] != 'admin' &&
        (user['membershipStatus'] == 'pending' ||
            institutionConfig(user['university'])['active'] == false)) {
      throw ApiError(403, 'المؤسسة غير متاحة');
    }
    if ((requireVerification || school(user)) &&
        user['verified'] != true &&
        user['role'] != 'admin') {
      throw ApiError(403, 'يجب اعتماد الحساب قبل عرض وسائط الجامعة');
    }
    final row = find('media', request.uri.pathSegments[1]);
    sameUniversity(row, user);
    if (blocked(uid, row!['user'])) throw ApiError(404, 'الملف غير موجود');
    final attached = row['attached'];
    if (attached == null) {
      if (row['user'] != uid) throw ApiError(404, 'الملف غير موجود');
    } else {
      final parent = find(attached['type'], attached['id']);
      if (parent == null ||
          (attached['type'] == 'stories' &&
              DateTime.parse(parent['expires'])
                  .isBefore(DateTime.now().toUtc()))) {
        throw ApiError(404, 'الملف غير موجود');
      }
    }
    final disk = mediaFile(row['id']);
    if (!disk.existsSync()) throw ApiError(404, 'الملف غير موجود');
    request.response.headers.contentType = ContentType.parse(row['mime']);
    request.response.headers.set('X-Content-Type-Options', 'nosniff');
    request.response.contentLength = await disk.length();
    await request.response.addStream(disk.openRead());
  }

  Future<Map<String, dynamic>?> features(
    HttpRequest req,
    Map<String, dynamic> user,
  ) async {
    final path = req.uri.path,
        p = req.uri.pathSegments,
        method = req.method,
        uid = user['id'] as String;
    final math = await mathGame(req, user);
    if (math != null) return math;
    if (path == '/account/recovery' && method == 'POST') {
      final b = await body(req);
      await verifyPassword(user, field(b, 'password', min: 1, max: 128));
      final code = id();
      user['recoveryHash'] = await digest(code);
      save();
      return {'code': code};
    }
    if (path == '/account/password' && method == 'POST') {
      final b = await body(req);
      final current = field(b, 'password', min: 1, max: 128),
          next = field(b, 'newPassword', min: 10, max: 128);
      await verifyPassword(user, current);
      if (current == next) throw ApiError(400, 'اختر كلمة مرور مختلفة');
      final salt = List.generate(24, (_) => random.nextInt(256));
      final hash = await kdf.deriveKeyFromPassword(password: next, nonce: salt);
      if (find('users', uid) == null) throw ApiError(401, 'الحساب غير موجود');
      user['salt'] = base64.encode(salt);
      user['password'] = base64.encode(await hash.extractBytes());
      rows('sessions').removeWhere((s) => s['user'] == uid);
      rows('devices').removeWhere((s) => s['user'] == uid);
      save();
      return {'ok': true};
    }
    if (path == '/account/delete' && method == 'POST') {
      final b = await body(req);
      await verifyPassword(user, field(b, 'password', min: 1, max: 128));
      for (final type in ['posts', 'stories']) {
        for (final row in List<Map<String, dynamic>>.from(
          rows(type).where((r) => r['user'] == uid),
        )) {
          removeContent(type, row);
        }
      }
      for (final m in List<Map<String, dynamic>>.from(
        rows('media').where((r) => r['user'] == uid),
      )) {
        final disk = mediaFile(m['id']);
        if (disk.existsSync()) disk.deleteSync();
        rows('media').remove(m);
      }
      rows('rounds').removeWhere((r) => r['user'] == uid);
      for (final key in [
        'sessions',
        'comments',
        'scores',
        'verification',
        'reports',
      ]) {
        rows(key).removeWhere((r) => r['user'] == uid);
      }
      for (final a in rows('announcements')) {
        (a['views'] as List).remove(uid);
        (a['viewTimes'] as Map?)?.remove(uid);
      }
      rows('announcements').removeWhere((a) => a['user'] == uid);
      rows('activity').removeWhere((a) => a['user'] == uid);
      for (final section in rows('sections')) {
        (section['teachers'] as List).remove(uid);
        (section['students'] as List).remove(uid);
      }
      for (final key in ['direct', 'blocks', 'notifications']) {
        rows(key).removeWhere(
          (r) =>
              r['user'] == uid ||
              r['target'] == uid ||
              r['actor'] == uid ||
              r['from'] == uid ||
              r['to'] == uid,
        );
      }
      rows('messages').removeWhere((r) => r['user'] == uid);
      for (final post in rows('posts')) {
        (post['likes'] as List).remove(uid);
      }
      for (final g in rows('groups')) {
        (g['members'] as List).remove(uid);
      }
      for (final doc in List<Map<String, dynamic>>.from(
        rows('documents').where((r) => r['user'] == uid),
      )) {
        final disk = File('${file.parent.path}/documents/${doc['id']}.bin');
        if (disk.existsSync()) disk.deleteSync();
      }
      for (final poll in rows('polls')) {
        (poll['votes'] as Map).remove(uid);
      }
      final ownedTournaments = rows('tournaments')
          .where((t) => t['user'] == uid)
          .map((t) => t['id'])
          .toSet();
      rows('duels')
          .removeWhere((g) => ownedTournaments.contains(g['tournament']));
      rows('tournaments').removeWhere((t) => t['user'] == uid);
      for (final tournament in rows('tournaments')) {
        (tournament['players'] as List).remove(uid);
      }
      for (final key in [
        'documents',
        'polls',
        'memoryRounds',
        'mailCodes',
        'devices',
      ]) {
        rows(key).removeWhere((r) => r['user'] == uid);
      }
      for (final key in ['friends', 'duels']) {
        rows(key).removeWhere((r) => r['from'] == uid || r['to'] == uid);
      }
      deleteProductData(uid);
      rows('users').remove(user);
      save();
      return {'ok': true};
    }
    if (path == '/people' && method == 'GET') {
      final q = (req.uri.queryParameters['q'] ?? '').trim().toLowerCase();
      return {
        'items': rows('users')
            .where(
              (u) =>
                  u['id'] != uid &&
                  u['university'] == user['university'] &&
                  u['disabled'] != true &&
                  !blocked(uid, u['id']) &&
                  (!school(user) || schoolSocial(user, u)) &&
                  (q.isEmpty ||
                      (u['name'] as String).toLowerCase().contains(q)),
            )
            .take(100)
            .map((u) => {...author(u['id']), 'bio': u['bio']})
            .toList(),
      };
    }
    if (path == '/blocks' && method == 'GET') {
      return {
        'items': rows('blocks')
            .where((b) => b['user'] == uid)
            .map((b) => author(b['target']))
            .toList(),
      };
    }
    if (p.length == 2 &&
        p[0] == 'blocks' &&
        ['POST', 'DELETE'].contains(method)) {
      final other = find('users', p[1]);
      sameUniversity(other, user);
      if (p[1] == uid) throw ApiError(400, 'لا يمكنك حظر نفسك');
      rows('blocks')
          .removeWhere((b) => b['user'] == uid && b['target'] == p[1]);
      if (method == 'POST') {
        rows('blocks').add({'id': id(), 'user': uid, 'target': p[1]});
        clearRelationship(uid, p[1]);
      }
      save();
      return {'ok': true};
    }
    if (p.length == 3 && p[0] == 'posts' && p[2] == 'comments') {
      final post = find('posts', p[1]);
      sameUniversity(post, user);
      if (blocked(uid, post!['user'])) throw ApiError(404, 'المحتوى غير موجود');
      if (method == 'GET') {
        return {
          'items': rows('comments')
              .where(
                (c) =>
                    c['post'] == p[1] &&
                    !blocked(uid, c['user']) &&
                    (!school(user) ||
                        schoolSocial(user, find('users', c['user']) ?? user)),
              )
              .take(200)
              .map(
                (c) => {
                  ...c as Map<String, dynamic>,
                  'author': author(c['user']),
                },
              )
              .toList(),
        };
      }
      if (method == 'POST') {
        final b = await body(req), cid = id();
        rows('comments').add({
          'id': cid,
          'post': p[1],
          'user': uid,
          'text': field(b, 'text', max: 1000),
          'created': now(),
        });
        notify(
          post['user'],
          uid,
          'comment',
          'تعليق جديد على منشورك',
          target: p[1],
        );
        save();
        return {'id': cid};
      }
    }
    if (p.length == 2 && p[0] == 'comments' && method == 'DELETE') {
      final comment = find('comments', p[1]);
      if (comment == null) throw ApiError(404, 'التعليق غير موجود');
      final post = find('posts', comment['post']);
      sameUniversity(post, user);
      if (comment['user'] != uid && post!['user'] != uid) {
        throw ApiError(403, 'لا يمكنك حذف هذا التعليق');
      }
      rows('comments').remove(comment);
      save();
      return {'ok': true};
    }
    if (path == '/inbox' && method == 'GET') {
      final peers = <String, dynamic>{};
      for (final msg in rows(
        'direct',
      ).where((m) => m['from'] == uid || m['to'] == uid)) {
        final peer = msg['from'] == uid ? msg['to'] : msg['from'];
        if (!blocked(uid, peer) &&
            find('users', peer) != null &&
            schoolSocial(user, find('users', peer)!)) {
          peers[peer] = {
            'person': author(peer),
            'text': msg['text'],
            'created': msg['created'],
          };
        }
      }
      return {'items': peers.values.toList().reversed.toList()};
    }
    if (p.length == 2 && p[0] == 'direct') {
      final peer = find('users', p[1]);
      sameUniversity(peer, user);
      if (peer!['disabled'] == true ||
          blocked(uid, p[1]) ||
          p[1] == uid ||
          !schoolSocial(user, peer)) {
        throw ApiError(403, 'المحادثة غير متاحة');
      }
      if (method == 'GET') {
        return {
          'items': rows('direct')
              .where(
                (m) =>
                    (m['from'] == uid && m['to'] == p[1]) ||
                    (m['to'] == uid && m['from'] == p[1]),
              )
              .toList()
              .reversed
              .take(100)
              .toList()
              .reversed
              .map(
                (m) => {
                  ...m as Map<String, dynamic>,
                  'author': author(m['from']),
                },
              )
              .toList(),
        };
      }
      if (method == 'POST') {
        final b = await body(req);
        rows('direct').add({
          'id': id(),
          'from': uid,
          'to': p[1],
          'text': field(b, 'text', max: 1000),
          'created': now(),
        });
        notify(p[1], uid, 'message', 'رسالة خاصة جديدة', target: uid);
        save();
        return {'ok': true};
      }
    }
    if (path == '/notifications' && method == 'GET') {
      return {
        'items': rows('notifications')
            .where(
              (n) =>
                  n['user'] == uid &&
                  !blocked(uid, n['actor']) &&
                  (!school(user) ||
                      schoolSocial(user, find('users', n['actor']) ?? user)),
            )
            .toList()
            .reversed
            .take(100)
            .map(
              (n) => {
                ...n as Map<String, dynamic>,
                'author': author(n['actor']),
              },
            )
            .toList(),
      };
    }
    if (path == '/notifications/read' && method == 'POST') {
      for (final n in rows('notifications').where((n) => n['user'] == uid)) {
        n['read'] = true;
      }
      save();
      return {'ok': true};
    }
    if (path == '/verification') {
      if (method == 'GET') {
        return {
          'items': rows('verification')
              .where((v) => v['user'] == uid)
              .toList()
              .reversed
              .toList(),
        };
      }
      if (method == 'POST') {
        final b = await body(req), role = field(b, 'role');
        if (!['student', 'doctor'].contains(role)) {
          throw ApiError(400, 'نوع حساب غير صحيح');
        }
        if (rows('verification')
            .any((v) => v['user'] == uid && v['status'] == 'pending')) {
          throw ApiError(409, 'يوجد طلب قيد المراجعة');
        }
        rows('verification').add({
          'id': id(),
          'user': uid,
          'role': role,
          'reference': field(b, 'reference', min: 2, max: 150),
          'note': field(b, 'note', min: 0, max: 500),
          'status': 'pending',
          'created': now(),
        });
        save();
        return {'ok': true};
      }
    }
    if (path == '/media' && method == 'POST') {
      final b = await body(req, limit: 28 * 1024 * 1024);
      final encoded = field(b, 'data', max: 28 * 1024 * 1024);
      List<int> bytes;
      try {
        bytes = base64.decode(encoded);
      } catch (_) {
        throw ApiError(400, 'ملف غير صالح');
      }
      if (bytes.length > 20 * 1024 * 1024 || bytes.length < 12) {
        throw ApiError(400, 'الحد الأقصى للملف ٢٠ ميجابايت');
      }
      String? mime, kind;
      if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
        mime = 'image/jpeg';
        kind = 'image';
      }
      if (bytes.take(8).join(',') == '137,80,78,71,13,10,26,10') {
        mime = 'image/png';
        kind = 'image';
      }
      if (ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
          ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
        mime = 'image/webp';
        kind = 'image';
      }
      if (ascii.decode(bytes.sublist(4, 8), allowInvalid: true) == 'ftyp') {
        mime = 'video/mp4';
        kind = 'video';
      }
      if (mime == null) {
        throw ApiError(400, 'الصيغ المدعومة: JPG وPNG وWEBP وMP4');
      }
      final total =
          [...rows('media'), ...rows('documents'), ...rows('voiceAttachments')]
              .where((m) => m['user'] == uid)
              .fold<int>(0, (s, m) => s + (m['size'] as int));
      if (total + bytes.length > 150 * 1024 * 1024) {
        throw ApiError(413, 'وصلت لحد التخزين المحلي للحساب');
      }
      final mid = id(), disk = mediaFile(mid);
      disk.parent.createSync(recursive: true);
      disk.writeAsBytesSync(bytes, flush: true);
      rows('media').add({
        'id': mid,
        'user': uid,
        'university': user['university'],
        'mime': mime,
        'kind': kind,
        'size': bytes.length,
        'attached': null,
        'created': now(),
      });
      save();
      return {'id': mid, 'kind': kind};
    }
    if (p.isNotEmpty && p[0] == 'admin') {
      if (user['role'] != 'admin') throw ApiError(403, 'للمشرف فقط');
      if (path == '/admin/overview' && method == 'GET') {
        return {
          'reports': rows('reports')
              .where(
                (r) =>
                    manages(user, 'reports') &&
                    (owner(user) ||
                        find('users', r['user'])?['university'] ==
                            user['university']),
              )
              .toList()
              .reversed
              .take(200)
              .map(
                (r) => {
                  ...r as Map<String, dynamic>,
                  'reporter': author(r['user']),
                  'content':
                      find(r['type'], r['target'])?['text'] ?? 'المحتوى محذوف',
                },
              )
              .toList(),
          'verification': rows('verification')
              .where(
                (v) =>
                    v['status'] == 'pending' &&
                    manages(user, 'verification') &&
                    (owner(user) ||
                        find('users', v['user'])?['university'] ==
                            user['university']),
              )
              .map(
                (v) => {
                  ...v as Map<String, dynamic>,
                  'person': author(v['user']),
                  'university': find('users', v['user'])?['university'],
                },
              )
              .toList(),
          'users': rows('users')
              .where(
                (v) =>
                    manages(user, 'users') &&
                    (owner(user) || v['university'] == user['university']),
              )
              .map((u) => publicUser(u as Map<String, dynamic>))
              .toList(),
        };
      }
      if (p.length == 3 && p[1] == 'verification' && method == 'POST') {
        final v = find('verification', p[2]);
        if (v == null || v['status'] != 'pending') {
          throw ApiError(404, 'الطلب غير موجود');
        }
        final b = await body(req);
        if (b['approve'] is! bool) throw ApiError(400, 'قرار غير صالح');
        final target = find('users', v['user']);
        if (target == null || target['role'] == 'admin') {
          throw ApiError(400, 'الحساب غير متاح');
        }
        v['status'] = b['approve'] == true ? 'approved' : 'rejected';
        v['reviewer'] = uid;
        if (b['approve'] == true) {
          target['verified'] = true;
          target['role'] = v['role'];
        }
        notify(
          target['id'],
          uid,
          'verification',
          b['approve'] == true ? 'تم اعتماد طلب توثيقك' : 'تم رفض طلب التوثيق',
        );
        rows('audit').add({
          'id': id(),
          'actor': uid,
          'action': 'verification',
          'target': v['id'],
          'created': now(),
        });
        save();
        return {'ok': true};
      }
      if (p.length == 3 && p[1] == 'reports' && method == 'POST') {
        final r = find('reports', p[2]);
        if (r == null) throw ApiError(404, 'البلاغ غير موجود');
        final b = await body(req);
        if (!['dismiss', 'remove'].contains(b['action'])) {
          throw ApiError(400, 'قرار غير صالح');
        }
        if (b['action'] == 'remove') {
          final target = find(r['type'], r['target']);
          if (target != null) {
            r['contentOwner'] = target['user'] ?? target['from'];
            r['decisionReason'] = b['reason'] is String
                ? (b['reason'] as String).substring(
                    0,
                    min(500, (b['reason'] as String).length),
                  )
                : r['reason'];
            removeContent(r['type'], target);
            notify(
              r['contentOwner'],
              uid,
              'moderation',
              'تمت إزالة محتوى بعد مراجعة بلاغ',
              target: r['id'],
            );
          }
        }
        r['status'] = b['action'];
        r['reviewer'] = uid;
        auditAction(user, 'report-decision', r['id']);
        save();
        return {'ok': true};
      }
      if (p.length == 3 && p[1] == 'users' && method == 'POST') {
        final target = find('users', p[2]);
        if (target == null) throw ApiError(404, 'الحساب غير موجود');
        if (target['role'] == 'admin') {
          throw ApiError(400, 'لا يمكن إيقاف حساب مشرف');
        }
        final b = await body(req);
        if (b['disabled'] is! bool) throw ApiError(400, 'قرار غير صالح');
        target['disabled'] = b['disabled'];
        if (b['disabled'] == true) {
          rows('sessions').removeWhere((s) => s['user'] == target['id']);
        }
        rows('audit').add({
          'id': id(),
          'actor': uid,
          'action': b['disabled'] == true ? 'disable' : 'enable',
          'target': target['id'],
          'created': now(),
        });
        save();
        return {'ok': true};
      }
    }
    return null;
  }
}
