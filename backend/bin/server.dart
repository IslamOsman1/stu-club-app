import 'dart:async';

import 'package:archive/archive.dart' as archive;
import 'package:mailer/mailer.dart' as mail;
import 'package:mailer/smtp_server.dart' as smtp;
import 'package:googleapis_auth/auth_io.dart' as auth;

import 'sqlite_store.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

part 'features.dart';
part 'academic.dart';
part 'owner_setup.dart';
part 'courses.dart';
part 'friends_play.dart';
part 'institutions.dart';
part 'content_features.dart';
part 'competition.dart';
part 'service_features.dart';

const universities = [
  {'id': 'cairo', 'name': 'جامعة القاهرة'},
  {'id': 'ain_shams', 'name': 'جامعة عين شمس'},
  {'id': 'alex', 'name': 'جامعة الإسكندرية'},
  {'id': 'school_demo', 'name': 'مدرسة تجريبية · تجربة محلية'},
];
final random = Random.secure();
String id() => base64Url
    .encode(List.generate(24, (_) => random.nextInt(256)))
    .replaceAll('=', '');
String now() => DateTime.now().toUtc().toIso8601String();

class ApiError implements Exception {
  final int status;
  final String message;
  ApiError(this.status, this.message);
}

class ClubServer {
  final File file;
  SqliteStore? store;
  Future<void> Function(String, String, String)? mailTransport;
  final Set<String> pendingPush = {};
  bool requireVerification = false;
  late Map<String, dynamic> data;
  final attempts = <String, List<DateTime>>{};
  final kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 210000,
    bits: 256,
  );
  ClubServer(String path, {bool sqlite = false}) : file = File(path) {
    if (sqlite) {
      file.parent.createSync(recursive: true);
      store = SqliteStore("$path.sqlite");
    }
    data =
        store?.load() ??
        (file.existsSync()
            ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic>
            : {
                for (final key in [
                  'users',
                  'sessions',
                  'posts',
                  'stories',
                  'messages',
                  'reports',
                  'scores',
                ])
                  key: <dynamic>[],
                'groups': <dynamic>[],
              });
    for (final key in [
      'users',
      'sessions',
      'posts',
      'stories',
      'messages',
      'reports',
      'scores',
      'groups',
    ]) {
      data.putIfAbsent(key, () => <dynamic>[]);
    }
    data.putIfAbsent('rounds', () => <dynamic>[]);
    for (final key in [
      'institutions',
      'documents',
      'polls',
      'memoryRounds',
      'tournaments',
      'mailCodes',
      'devices',
      'friends',
      'duels',
      'courses',
      'sections',
      'announcements',
      'activity',
      'comments',
      'direct',
      'blocks',
      'notifications',
      'verification',
      'media',
      'audit',
    ]) {
      data.putIfAbsent(key, () => <dynamic>[]);
    }
    if (!rows('groups').any((g) => g['university'] == 'school_demo')) {
      for (final title in ['الصف التجريبي', 'الأنشطة المدرسية']) {
        rows('groups').add({
          'id': id(),
          'university': 'school_demo',
          'name': title,
          'members': <dynamic>[],
        });
      }
    }
    for (final user in rows('users')) {
      user.putIfAbsent('verified', () => false);
      user.putIfAbsent('disabled', () => false);
    }
    {
      for (final u in universities) {
        if (rows('groups').any((g) => g['university'] == u['id'])) continue;
        for (final name in [
          'نادي البرمجة',
          'مذاكرة ومراجعة',
          'الأنشطة والفعاليات',
        ]) {
          rows('groups').add({
            'id': id(),
            'university': u['id'],
            'name': name,
            'members': <dynamic>[],
          });
        }
      }
      save();
    }
  }
  List<dynamic> rows(String key) => data[key] as List<dynamic>;
  Map<String, dynamic>? find(String key, String value) {
    for (final row in rows(key)) {
      if (row['id'] == value) return row as Map<String, dynamic>;
    }
    return null;
  }

  void save() {
    if (store != null) {
      store!.save(data);
      return;
    }
    file.parent.createSync(recursive: true);
    final temp = File('${file.path}.tmp');
    temp.writeAsStringSync(jsonEncode(data), flush: true);
    temp.renameSync(file.path);
  }

  String field(
    Map<String, dynamic> body,
    String key, {
    int min = 1,
    int max = 500,
  }) {
    final value = body[key];
    if (value is! String || value.trim().length < min || value.length > max) {
      throw ApiError(400, 'تحقق من الحقل: $key');
    }
    return key == 'password' ? value : value.trim();
  }

  Map<String, dynamic> publicUser(Map<String, dynamic> user) => {
    for (final k in [
      'id',
      'name',
      'email',
      'university',
      'role',
      'bio',
      'verified',
      'disabled',
    ])
      k: user[k],
    'institutionKind': institution(user['university'])?['kind'],
    'institutionName': institution(user['university'])?['name'],
    'birthYear': user['birthYear'],
    'grade': user['grade'],
    'emailVerified': user['emailVerified'] == true,
  };
  Map<String, dynamic> author(String uid) {
    final user = find('users', uid);
    return {
      'id': uid,
      'name': user?['name'] ?? 'مستخدم',
      'role': user?['role'] ?? 'student',
      'verified': user?['verified'] ?? false,
    };
  }

  Future<String> digest(String value) async =>
      base64.encode((await Sha256().hash(utf8.encode(value))).bytes);
  Future<Map<String, dynamic>> login(Map<String, dynamic> user) async {
    final token = id();
    rows('sessions').removeWhere(
      (s) => DateTime.parse(s['expires']).isBefore(DateTime.now().toUtc()),
    );
    rows('sessions').add({
      'id': await digest(token),
      'user': user['id'],
      'expires': DateTime.now()
          .toUtc()
          .add(const Duration(days: 7))
          .toIso8601String(),
    });
    save();
    return {'token': token, 'user': publicUser(user)};
  }

  Future<Map<String, dynamic>> authenticated(HttpRequest request) async {
    final header = request.headers.value('authorization') ?? '';
    if (!header.startsWith('Bearer ')) throw ApiError(401, 'سجّل الدخول أولًا');
    final session = find('sessions', await digest(header.substring(7)));
    if (session == null ||
        DateTime.parse(session['expires']).isBefore(DateTime.now().toUtc())) {
      throw ApiError(401, 'انتهت الجلسة، سجّل الدخول مرة أخرى');
    }
    final user = find('users', session['user']);
    if (user == null) throw ApiError(401, 'الحساب غير موجود');
    if (user['disabled'] == true) {
      throw ApiError(403, 'الحساب موقوف، تواصل مع المشرف');
    }
    return user;
  }

  void sameUniversity(
    Map<String, dynamic>? resource,
    Map<String, dynamic> user,
  ) {
    if (resource == null ||
        resource['university'] != user['university'] ||
        (resource.containsKey('members') && !schoolGroup(resource, user)) ||
        (school(user) &&
            user['role'] != 'admin' &&
            resource['user'] != null &&
            find('users', resource['user']) != null &&
            !schoolSocial(user, find('users', resource['user'])!))) {
      throw ApiError(404, 'المحتوى غير موجود');
    }
  }

  Future<Map<String, dynamic>> body(
    HttpRequest request, {
    int limit = 16384,
  }) async {
    final bytes = <int>[];
    await for (final part in request) {
      bytes.addAll(part);
      if (bytes.length > limit) throw ApiError(413, 'الطلب أكبر من المسموح');
    }
    try {
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiError(400, 'بيانات الطلب غير صالحة');
    }
  }

  Future<void> handle(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set('Cache-Control', 'no-store');
    try {
      if (request.uri.pathSegments.length == 3 &&
          request.uri.pathSegments.first == 'documents' &&
          request.uri.pathSegments.last == 'content' &&
          request.method == 'GET') {
        await serveDocument(request);
        return;
      }
      if (request.uri.pathSegments.length == 2 &&
          request.uri.pathSegments.first == 'media' &&
          request.method == 'GET') {
        await serveMedia(request);
        return;
      }
      final result = await route(request);
      request.response.write(jsonEncode(result));
    } on ApiError catch (e) {
      request.response.statusCode = e.status;
      request.response.write(jsonEncode({'error': e.message}));
    } catch (e, stack) {
      stderr.writeln('Request failed: ${e.runtimeType}\n$stack');
      request.response.statusCode = 500;
      request.response.write(
        jsonEncode({'error': 'تعذر تنفيذ الطلب، حاول مرة أخرى'}),
      );
    } finally {
      await request.response.close();
    }
  }

  Future<Map<String, dynamic>> route(HttpRequest request) async {
    final p = request.uri.pathSegments;
    final method = request.method;
    final publicResult = await publicService(request);
    if (publicResult != null) return publicResult;
    if (request.uri.path == '/auth/recover' && method == 'POST') {
      return recover(request);
    }
    if (request.uri.path == '/health') {
      return {
        'ok': true,
        'service': 'stuclub',
        'version': '2.0.0',
        'storage': store == null ? 'json' : 'sqlite',
      };
    }
    if (request.uri.path == '/universities' && method == 'GET') {
      return {'items': institutionList()};
    }
    if (p.length == 2 &&
        p[0] == 'auth' &&
        ['login', 'register'].contains(p[1]) &&
        method == 'POST') {
      final ip = Platform.environment['STU_TRUST_PROXY'] == 'true'
          ? (request.headers.value('x-forwarded-for')?.split(',').last.trim() ??
                request.connectionInfo?.remoteAddress.address ??
                'unknown')
          : request.connectionInfo?.remoteAddress.address ?? 'unknown';
      final times = attempts.putIfAbsent(ip, () => []);
      times.removeWhere(
        (t) => t.isBefore(DateTime.now().subtract(const Duration(minutes: 1))),
      );
      if (times.length >= 12) throw ApiError(429, 'محاولات كثيرة، انتظر دقيقة');
      times.add(DateTime.now());
      final b = await body(request);
      final email = field(b, 'email', max: 180).toLowerCase();
      final password = field(b, 'password', min: 10, max: 128);
      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
        throw ApiError(400, 'البريد الإلكتروني غير صحيح');
      }
      Map<String, dynamic>? existing;
      for (final u in rows('users')) {
        if (u['email'] == email) existing = u as Map<String, dynamic>;
      }
      if (p[1] == 'register') {
        final university = field(b, 'university');
        final name = field(b, 'name', min: 2, max: 60);
        if (institution(university) == null) {
          throw ApiError(400, 'اختر مؤسسة صحيحة');
        }
        if (institution(university)?['kind'] == 'school') {
          final year = b['birthYear'], grade = b['grade'];
          if (year is! int ||
              year < DateTime.now().year - 100 ||
              year > DateTime.now().year - 5 ||
              grade is! int ||
              grade < 1 ||
              grade > 12) {
            throw ApiError(400, 'أدخل سنة الميلاد والصف الدراسي الصحيحين');
          }
        }
        if (existing != null) throw ApiError(409, 'البريد مستخدم بالفعل');
        final salt = List.generate(24, (_) => random.nextInt(256));
        final hash = await kdf.deriveKeyFromPassword(
          password: password,
          nonce: salt,
        );
        if (rows('users').any((u) => u['email'] == email)) {
          throw ApiError(409, 'البريد مستخدم بالفعل');
        }
        final user = <String, dynamic>{
          'id': id(),
          'email': email,
          'name': name,
          'university': university,
          if (institution(university)?['kind'] == 'school')
            'birthYear': b['birthYear'],
          if (institution(university)?['kind'] == 'school') 'grade': b['grade'],
          'role': 'student',
          'bio': '',
          'verified': false,
          'disabled': false,
          'salt': base64.encode(salt),
          'password': base64.encode(await hash.extractBytes()),
        };
        rows('users').add(user);
        return login(user);
      }
      // Run the KDF even for unknown accounts to reduce account timing leaks.
      final hash = await kdf.deriveKeyFromPassword(
        password: password,
        nonce: existing == null
            ? List.filled(24, 0)
            : base64.decode(existing['salt']),
      );
      final actual = await hash.extractBytes();
      final expected = existing == null
          ? List.filled(32, 0)
          : base64.decode(existing['password']);
      var difference = 0;
      for (var i = 0; i < 32; i++) {
        difference |= actual[i] ^ expected[i];
      }
      if (existing == null || difference != 0) {
        throw ApiError(401, 'البريد أو كلمة المرور غير صحيح');
      }
      if (existing['disabled'] == true) throw ApiError(403, 'الحساب موقوف');
      return login(existing);
    }
    final user = await authenticated(request);
    final uid = user['id'] as String;
    if ((requireVerification || school(user)) &&
        user['verified'] != true &&
        user['role'] != 'admin' &&
        !request.uri.path.startsWith('/account/') &&
        ![
          '/me',
          '/verification',
          '/auth/logout',
          '/blocks',
          '/notifications',
          '/notifications/read',
          '/devices',
          '/services',
          '/email/verify/request',
          '/email/verify/confirm',
        ].contains(request.uri.path)) {
      throw ApiError(
        403,
        'أرسل طلب توثيق من حسابي وانتظر اعتماد المشرف للوصول لمحتوى الجامعة',
      );
    }
    final institutionResult = await institutions(request, user);
    if (institutionResult != null) return institutionResult;
    final contentResult = await contentFeatures(request, user);
    if (contentResult != null) return contentResult;
    final competitionResult = await competitions(request, user);
    if (competitionResult != null) return competitionResult;
    final serviceResult = await serviceFeatures(request, user);
    if (serviceResult != null) return serviceResult;
    final socialResult = await friendsPlay(request, user);
    if (socialResult != null) return socialResult;
    final courseResult = await courses(request, user);
    if (courseResult != null) return courseResult;
    final academicResult = await academic(request, user);
    if (academicResult != null) return academicResult;
    final extraResult = await features(request, user);
    if (extraResult != null) return extraResult;
    if (request.uri.path == '/auth/logout' && method == 'POST') {
      final hash = await digest(
        request.headers.value('authorization')!.substring(7),
      );
      rows('sessions').removeWhere((s) => s['id'] == hash);
      rows('devices').removeWhere((d) => d['session'] == hash);
      save();
      return {'ok': true};
    }
    if (request.uri.path == '/me') {
      if (method == 'PATCH') {
        final b = await body(request);
        user['name'] = field(b, 'name', min: 2, max: 60);
        user['bio'] = field(b, 'bio', min: 0, max: 250);
        save();
      } else if (method != 'GET') {
        throw ApiError(405, 'طريقة غير مدعومة');
      }
      return {'user': publicUser(user)};
    }
    if (request.uri.path == '/feed' && method == 'GET') {
      final items = rows('posts')
          .where(
            (r) =>
                r['university'] == user['university'] &&
                !blocked(uid, r['user']) &&
                (!school(user) ||
                    schoolSocial(user, find('users', r['user']) ?? user)),
          )
          .toList()
          .reversed
          .take(100)
          .map(
            (r) => {
              ...r as Map<String, dynamic>,
              'author': author(r['user']),
              'liked': (r['likes'] as List).contains(uid),
              'likeCount': (r['likes'] as List).length,
              'commentCount': rows('comments')
                  .where(
                    (c) => c['post'] == r['id'] && !blocked(uid, c['user']),
                  )
                  .length,
            }..remove('likes'),
          )
          .toList();
      final stories = rows('stories')
          .where(
            (r) =>
                r['university'] == user['university'] &&
                !blocked(uid, r['user']) &&
                DateTime.parse(r['expires']).isAfter(DateTime.now().toUtc()),
          )
          .toList()
          .reversed
          .take(100)
          .map(
            (r) => {...r as Map<String, dynamic>, 'author': author(r['user'])},
          )
          .toList();
      return {'posts': items, 'stories': stories};
    }
    if (p.length == 1 &&
        ['posts', 'stories'].contains(p[0]) &&
        method == 'POST') {
      final b = await body(request);
      final media = b['media'];
      if (media != null) {
        final m = find('media', media is String ? media : '');
        if (m == null || m['user'] != uid || m['attached'] != null) {
          throw ApiError(400, 'ملف مرفق غير صالح');
        }
      }
      final row = {
        'id': id(),
        'user': uid,
        'university': user['university'],
        'text': field(
          b,
          'text',
          min: media == null ? 1 : 0,
          max: p[0] == 'posts' ? 2000 : 500,
        ),
        'media': ?media,
        if (media != null) 'mediaKind': find('media', media as String)!['kind'],
        'created': now(),
        if (p[0] == 'posts') 'likes': <dynamic>[],
        if (p[0] == 'stories')
          'expires': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 24))
              .toIso8601String(),
      };
      rows(p[0]).add(row);
      if (media != null) {
        find('media', media as String)!['attached'] = {
          'type': p[0],
          'id': row['id'],
        };
      }
      save();
      return {'id': row['id']};
    }
    if (p.length >= 2 && ['posts', 'stories'].contains(p[0])) {
      final row = find(p[0], p[1]);
      sameUniversity(row, user);
      if (blocked(uid, row!['user'])) throw ApiError(404, 'المحتوى غير موجود');
      if (p.length == 2 && method == 'DELETE') {
        if (row['user'] != uid) throw ApiError(403, 'يمكنك حذف محتواك فقط');
        removeContent(p[0], row);
        save();
        return {'ok': true};
      }
      if (p.length == 3 &&
          p[0] == 'posts' &&
          p[2] == 'like' &&
          method == 'POST') {
        final likes = row['likes'] as List;
        if (likes.contains(uid)) {
          likes.remove(uid);
        } else {
          likes.add(uid);
          notify(row['user'], uid, 'like', 'أعجب بمنشورك', target: row['id']);
        }
        save();
        return {'ok': true};
      }
    }
    if (request.uri.path == '/groups' && method == 'GET') {
      return {
        'items': rows('groups')
            .where(
              (g) =>
                  g['university'] == user['university'] && schoolGroup(g, user),
            )
            .map(
              (g) => {
                'id': g['id'],
                'name': g['name'],
                'joined':
                    (g['members'] as List).contains(uid) ||
                    user['role'] == 'admin',
                'managed': g['section'] != null,
                'count': (g['members'] as List).length,
              },
            )
            .toList(),
      };
    }
    if (p.length == 3 && p[0] == 'groups') {
      final g = find('groups', p[1]);
      sameUniversity(g, user);
      final members = g!['members'] as List;
      if (p[2] == 'membership' && method == 'POST') {
        if (g['section'] != null) {
          throw ApiError(403, 'عضوية مجموعة الشعبة يحددها التسجيل الرسمي');
        }
        members.contains(uid) ? members.remove(uid) : members.add(uid);
        save();
        return {'ok': true};
      }
      if (p[2] == 'messages') {
        if (!members.contains(uid) && user['role'] != 'admin') {
          throw ApiError(403, 'انضم للمجموعة لعرض رسائلها');
        }
        if (method == 'POST') {
          final b = await body(request);
          rows('messages').add({
            'id': id(),
            'group': g['id'],
            'user': uid,
            'text': field(b, 'text', max: 1000),
            'created': now(),
          });
          save();
          return {'ok': true};
        }
        if (method == 'GET') {
          return {
            'items': rows('messages')
                .where(
                  (m) =>
                      m['group'] == g['id'] &&
                      !blocked(uid, m['user']) &&
                      (!school(user) ||
                          schoolSocial(user, find('users', m['user']) ?? user)),
                )
                .toList()
                .reversed
                .take(100)
                .toList()
                .reversed
                .map(
                  (m) => {
                    ...m as Map<String, dynamic>,
                    'author': author(m['user']),
                  },
                )
                .toList(),
          };
        }
      }
    }
    if (request.uri.path == '/reports' && method == 'POST') {
      final b = await body(request);
      final type = field(b, 'type');
      if (![
        'posts',
        'stories',
        'comments',
        'direct',
        'messages',
      ].contains(type)) {
        throw ApiError(400, 'نوع محتوى غير صحيح');
      }
      final row = find(type, field(b, 'target'));
      if (row == null) throw ApiError(404, 'المحتوى غير موجود');
      if (type == 'comments') {
        sameUniversity(find('posts', row['post']), user);
      } else if (type == 'direct') {
        if (row['from'] != uid && row['to'] != uid) {
          throw ApiError(404, 'المحتوى غير موجود');
        }
      } else if (type == 'messages') {
        final g = find('groups', row['group']);
        sameUniversity(g, user);
        if (!(g!['members'] as List).contains(uid)) {
          throw ApiError(403, 'انضم للمجموعة أولًا');
        }
      } else {
        sameUniversity(row, user);
      }
      rows('reports').add({
        'id': id(),
        'user': uid,
        'type': type,
        'target': row['id'],
        'reason': field(b, 'reason', max: 500),
        'created': now(),
      });
      save();
      return {'ok': true};
    }
    if (request.uri.path == '/quiz' && method == 'GET') {
      final remaining = questions
          .where(
            (q) =>
                !rows('scores')
                    .any((s) => s['user'] == uid && s['quiz'] == q['id']),
          )
          .toList();
      return remaining.isEmpty
            ? {'done': true, 'total': questions.length}
            : Map<String, dynamic>.from(remaining.first)
        ..remove('answer');
    }
    if (request.uri.path == '/quiz/answer' && method == 'POST') {
      final b = await body(request);
      final matches = questions.where((q) => q['id'] == b['id']);
      if (matches.isEmpty ||
          b['answer'] is! int ||
          b['answer'] < 0 ||
          b['answer'] >= (matches.first['choices'] as List).length) {
        throw ApiError(400, 'إجابة غير صالحة');
      }
      final previous = rows('scores')
          .where((s) => s['user'] == uid && s['quiz'] == b['id']);
      if (previous.isNotEmpty) {
        return {
          'correct': previous.first['correct'],
          'points': previous.first['points'],
          'alreadyAnswered': true,
          'explanation': matches.first['explanation'],
        };
      }
      final correct = b['answer'] == matches.first['answer'];
      if (correct) recordActivity(uid);
      rows('scores').add({
        'id': id(),
        'user': uid,
        'quiz': b['id'],
        'correct': correct,
        'points': correct ? 10 : 0,
      });
      save();
      return {
        'correct': correct,
        'points': correct ? 10 : 0,
        'alreadyAnswered': false,
        'explanation': matches.first['explanation'],
      };
    }
    if (request.uri.path == '/leaderboard' && method == 'GET') {
      final items = rows('users')
          .where((u) => u['university'] == user['university'])
          .map(
            (u) => {
              'name': u['name'],
              'points': rows('scores')
                  .where((s) => s['user'] == u['id'])
                  .fold<int>(0, (sum, s) => sum + (s['points'] as int)),
            },
          )
          .toList();
      items.sort((a, b) => (b['points'] as int).compareTo(a['points'] as int));
      return {'items': items.take(20).toList()};
    }
    throw ApiError(404, 'المسار غير موجود');
  }

  Future<HttpServer> start({int port = 8080, String host = '127.0.0.1'}) async {
    final server = await HttpServer.bind(host, port);
    server.listen(handle);
    return server;
  }
}

Future<void> main() async {
  final env = Platform.environment;
  final app = ClubServer(
    env['STU_DATA'] ?? 'data/club.json',
    sqlite: env['STU_STORAGE'] != 'json',
  );
  await app.bootstrapOwner(env);
  final operatorFile = File('${app.file.parent.path}/operator.json');
  final operator = operatorFile.existsSync()
      ? jsonDecode(operatorFile.readAsStringSync()) as Map<String, dynamic>
      : <String, dynamic>{};
  app.requireVerification =
      operator['requireVerification'] == true ||
      env['STU_REQUIRE_VERIFICATION'] == 'true';
  final adminEmails = {
    ...(operator['admins'] as List? ?? []).map(
      (e) => e.toString().toLowerCase(),
    ),
    ...(env['STU_ADMIN_EMAILS'] ?? '')
        .split(',')
        .map((e) => e.trim().toLowerCase()),
  };
  // Roles are assigned by the local operator, never by a registration request.
  final doctors = (env['STU_DOCTOR_EMAILS'] ?? '')
      .split(',')
      .map((e) => e.trim().toLowerCase())
      .where((e) => e.isNotEmpty)
      .toSet();
  for (final u in app.rows('users')) {
    if (doctors.contains(u['email'])) {
      u['role'] = 'doctor';
      u['verified'] = true;
    }
    if (adminEmails.contains(u['email'])) {
      u['role'] = 'admin';
      u['verified'] = true;
    }
  }
  app.save();
  if (app.store != null && app.file.existsSync()) {
    final backup = Directory('${app.file.parent.parent.path}/backups')
      ..createSync(recursive: true);
    app.file.renameSync(
      '${backup.path}/migration-${DateTime.now().toUtc().millisecondsSinceEpoch}.json',
    );
  }
  var delivering = false;
  Timer.periodic(const Duration(seconds: 5), (_) async {
    if (delivering || app.pendingPush.isEmpty) return;
    delivering = true;
    final ids = app.pendingPush.toList();
    app.pendingPush.clear();
    try {
      for (final id in ids) {
        await app.sendPush(id);
      }
    } finally {
      delivering = false;
    }
  });
  final server = await app.start(
    port: int.parse(env['PORT'] ?? '8080'),
    host: env['STU_HOST'] ?? '127.0.0.1',
  );
  stdout.writeln(
    'STU Club API: http://${server.address.address}:${server.port}',
  );
}
