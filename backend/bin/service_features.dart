part of 'server.dart';

extension ServiceFeatures on ClubServer {
  String get mailMode => Platform.environment['STU_MAIL_MODE'] ?? 'outbox';
  bool get pushReady =>
      (Platform.environment['STU_FCM_PROJECT'] ?? '').isNotEmpty &&
      (Platform.environment['GOOGLE_APPLICATION_CREDENTIALS'] ?? '').isNotEmpty;
  void mailRate(String key) {
    final times = attempts.putIfAbsent('email:$key', () => []);
    times.removeWhere(
      (t) => t.isBefore(DateTime.now().subtract(const Duration(minutes: 15))),
    );
    if (times.length >= 5) throw ApiError(429, 'انتظر قبل طلب كود آخر');
    times.add(DateTime.now());
  }

  Future<void> deliverMail(String email, String subject, String text) async {
    if (mailTransport != null) {
      await mailTransport!(email, subject, text);
      return;
    }
    if (mailMode == 'outbox') {
      final out = File('${file.parent.path}/outbox/${id()}.json');
      out.parent.createSync(recursive: true);
      out.writeAsStringSync(
        jsonEncode({
          'to': email,
          'subject': subject,
          'text': text,
          'created': now(),
        }),
        flush: true,
      );
      return;
    }
    if (mailMode != 'smtp') throw ApiError(503, 'خدمة البريد غير مفعلة');
    final env = Platform.environment,
        host = env['STU_SMTP_HOST'],
        from = env['STU_MAIL_FROM'];
    if (host == null || from == null) {
      throw ApiError(503, 'خدمة البريد غير مجهزة');
    }
    final message = mail.Message()
      ..from = mail.Address(from, 'StuClub')
      ..recipients.add(email)
      ..subject = subject
      ..text = text;
    final smtpServer = smtp.SmtpServer(
      host,
      port: int.tryParse(env['STU_SMTP_PORT'] ?? '') ?? 587,
      username: env['STU_SMTP_USER'],
      password: env['STU_SMTP_PASSWORD'],
      ssl: env['STU_SMTP_SSL'] == 'true',
      allowInsecure: false,
    );
    try {
      await mail.send(
        message,
        smtpServer,
        timeout: const Duration(seconds: 20),
      );
    } catch (_) {
      throw ApiError(503, 'تعذر إرسال البريد؛ حاول لاحقًا');
    }
  }

  Future<void> issueMailCode(Map<String, dynamic> user, String purpose) async {
    final code = (100000 + random.nextInt(900000)).toString();
    rows('mailCodes')
        .removeWhere((r) => r['user'] == user['id'] && r['purpose'] == purpose);
    rows('mailCodes').add({
      'id': id(),
      'user': user['id'],
      'purpose': purpose,
      'hash': await digest(code),
      'expires': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 10))
          .toIso8601String(),
      'attempts': 0,
    });
    save();
    await deliverMail(
      user['email'],
      purpose == 'verify' ? 'تأكيد بريد StuClub' : 'استعادة حساب StuClub',
      'كودك: $code\nصالح لعشر دقائق. لا تشاركه مع أي شخص.',
    );
  }

  Future<void> confirmMailCode(
    Map<String, dynamic> user,
    String purpose,
    String code,
  ) async {
    final candidates = rows('mailCodes')
        .where((r) => r['user'] == user['id'] && r['purpose'] == purpose);
    if (candidates.isEmpty) {
      throw ApiError(400, 'الكود غير صحيح أو انتهت صلاحيته');
    }
    final r = candidates.first;
    if (r['attempts'] >= 8 ||
        DateTime.parse(r['expires']).isBefore(DateTime.now().toUtc())) {
      throw ApiError(400, 'الكود غير صحيح أو انتهت صلاحيته');
    }
    r['attempts']++;
    final expected = r['hash'];
    save();
    final actual = await digest(code);
    if (actual != expected || !rows('mailCodes').contains(r)) {
      throw ApiError(400, 'الكود غير صحيح أو انتهت صلاحيته');
    }
    rows('mailCodes').remove(r);
  }

  Future<Map<String, dynamic>?> publicService(HttpRequest req) async {
    if (req.uri.path == '/auth/email-reset/request' && req.method == 'POST') {
      final b = await body(req),
          email = field(b, 'email', max: 180).toLowerCase();
      mailRate('reset:${req.connectionInfo?.remoteAddress.address}');
      mailRate(email);
      final users = rows('users')
          .where((r) => r['email'] == email && r['disabled'] != true);
      if (users.isNotEmpty) await issueMailCode(users.first, 'reset');
      return {
        'ok': true,
        'delivery': mailMode,
        'message': 'إذا كان البريد مسجلًا ستصلك تعليمات الاستعادة',
      };
    }
    if (req.uri.path == '/auth/email-reset/confirm' && req.method == 'POST') {
      final b = await body(req),
          email = field(b, 'email', max: 180).toLowerCase(),
          code = field(b, 'code', max: 20),
          password = field(b, 'password', min: 10, max: 128);
      final users = rows('users')
          .where((r) => r['email'] == email && r['disabled'] != true);
      if (users.isEmpty) throw ApiError(400, 'الكود غير صحيح أو انتهت صلاحيته');
      final user = users.first;
      await confirmMailCode(user, 'reset', code);
      final salt = List.generate(24, (_) => random.nextInt(256));
      final key = await kdf.deriveKeyFromPassword(
        password: password,
        nonce: salt,
      );
      user['salt'] = base64.encode(salt);
      user['password'] = base64.encode(await key.extractBytes());
      rows('sessions').removeWhere((r) => r['user'] == user['id']);
      rows('devices').removeWhere((r) => r['user'] == user['id']);
      rows('mailCodes').removeWhere((r) => r['user'] == user['id']);
      save();
      return {'ok': true};
    }
    return null;
  }

  Future<Map<String, dynamic>?> serviceFeatures(
    HttpRequest req,
    Map<String, dynamic> u,
  ) async {
    final path = req.uri.path, method = req.method, uid = u['id'];
    if (path == '/services' && method == 'GET') {
      return {
        'mail': mailMode,
        'pushConfigured': pushReady,
        'emailVerified': u['emailVerified'] == true,
      };
    }
    if (path == '/email/verify/request' && method == 'POST') {
      mailRate(uid);
      await issueMailCode(u, 'verify');
      return {'ok': true, 'delivery': mailMode};
    }
    if (path == '/email/verify/confirm' && method == 'POST') {
      final b = await body(req);
      await confirmMailCode(u, 'verify', field(b, 'code', max: 20));
      u['emailVerified'] = true;
      save();
      return {'ok': true};
    }
    if (path == '/devices' && method == 'POST') {
      final b = await body(req),
          token = field(b, 'token', min: 10, max: 4096),
          session = await digest(
            req.headers.value('authorization')!.substring(7),
          );
      rows('devices').removeWhere(
        (r) =>
            r['token'] == token ||
            (r['user'] == uid && r['session'] == session),
      );
      rows('devices')
          .add({'id': id(), 'user': uid, 'session': session, 'token': token});
      save();
      return {'ok': true};
    }
    if (path == '/devices' && method == 'DELETE') {
      final session = await digest(
        req.headers.value('authorization')!.substring(7),
      );
      rows('devices').removeWhere((r) => r['session'] == session);
      save();
      return {'ok': true};
    }
    return null;
  }

  Future<void> sendPush(String recipient) async {
    if (!pushReady) return;
    try {
      final env = Platform.environment,
          credentials = auth.ServiceAccountCredentials.fromJson(
            jsonDecode(
              File(env['GOOGLE_APPLICATION_CREDENTIALS']!).readAsStringSync(),
            ),
          );
      final client = await auth.clientViaServiceAccount(credentials, [
        'https://www.googleapis.com/auth/firebase.messaging',
      ]);
      try {
        for (final device in List<Map<String, dynamic>>.from(
          rows('devices').where((r) => r['user'] == recipient),
        )) {
          final session = find('sessions', device['session']);
          if (session == null ||
              DateTime.parse(session['expires'])
                  .isBefore(DateTime.now().toUtc())) {
            continue;
          }
          final response = await client
              .post(
                Uri.parse(
                  'https://fcm.googleapis.com/v1/projects/${env['STU_FCM_PROJECT']}/messages:send',
                ),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'message': {
                    'token': device['token'],
                    'notification': {
                      'title': 'StuClub',
                      'body': 'لديك تحديث جديد داخل التطبيق',
                    },
                    'android': {
                      'notification': {'channel_id': 'stuclub_updates'},
                    },
                  },
                }),
              )
              .timeout(const Duration(seconds: 15));
          if (response.statusCode == 404) rows('devices').remove(device);
        }
      } finally {
        client.close();
      }
    } catch (_) {
      stderr.writeln(
        'Push delivery unavailable; in-app notifications remain available.',
      );
    }
  }
}
