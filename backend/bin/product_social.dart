part of 'server.dart';

extension ProductSocial on ClubServer {
  bool postVisible(Map<String, dynamic> r, Map<String, dynamic> u) =>
      r['university'] == u['university'] &&
      !blocked(u['id'], r['user']) &&
      (!school(u) || schoolSocial(u, find('users', r['user']) ?? u));
  Map<String, dynamic> productPost(
    Map<String, dynamic> r,
    Map<String, dynamic> u,
  ) => {
    ...r,
    'author': author(r['user']),
    'canEdit': r['user'] == u['id'],
    'liked': (r['likes'] as List).contains(u['id']),
    'likeCount': (r['likes'] as List).length,
    'saved': rows('savedPosts')
        .any((s) => s['user'] == u['id'] && s['post'] == r['id']),
  }..remove('likes');
  Map<String, dynamic> chatTarget(
    String kind,
    String target,
    Map<String, dynamic> u,
  ) {
    if (kind == 'direct') {
      final peer = find('users', target);
      sameUniversity(peer, u);
      if (peer!['disabled'] == true ||
          peer['id'] == u['id'] ||
          blocked(u['id'], target) ||
          !schoolSocial(u, peer)) {
        throw ApiError(403, 'المحادثة غير متاحة');
      }
      return peer;
    }
    if (kind != 'group') throw ApiError(400, 'نوع محادثة غير صحيح');
    final g = find('groups', target);
    sameUniversity(g, u);
    if (!schoolGroup(g!, u) ||
        (!(g['members'] as List).contains(u['id']) && u['role'] != 'admin')) {
      throw ApiError(403, 'المجموعة غير متاحة');
    }
    return g;
  }

  bool sameThread(
    Map<String, dynamic> m,
    String kind,
    String target,
    String uid,
  ) => kind == 'group'
      ? m['group'] == target
      : ((m['from'] == uid && m['to'] == target) ||
            (m['to'] == uid && m['from'] == target));
  String chatKey(String kind, String target, String uid) {
    if (kind == 'group') return 'group:$target';
    final pair = [uid, target]..sort();
    return 'direct:${pair.join(':')}';
  }

  void socialRate(Map<String, dynamic> u, String category, {int limit = 30}) {
    final key = 'product:${u['id']}:$category',
        current = DateTime.now().toUtc(),
        list = attempts.putIfAbsent(key, () => []);
    list.removeWhere((t) => current.difference(t) > const Duration(minutes: 1));
    if (list.length >= limit) throw ApiError(429, 'طلبات متكررة، انتظر قليلًا');
    list.add(current);
  }

  Future<void> serveVoiceAttachment(HttpRequest req) async {
    final u = await authenticated(req);
    if ((requireVerification || school(u)) &&
        u['verified'] != true &&
        u['role'] != 'admin') {
      throw ApiError(403, 'يجب اعتماد الحساب');
    }
    if (u['role'] != 'admin' &&
        (u['membershipStatus'] == 'pending' ||
            institutionConfig(u['university'])['active'] == false)) {
      throw ApiError(403, 'المؤسسة غير متاحة');
    }
    final row = find('voiceAttachments', req.uri.pathSegments.last);
    sameUniversity(row, u);
    final attached = row!['attached'];
    if (attached == null) {
      if (row['user'] != u['id']) throw ApiError(404, 'الملف غير موجود');
    } else {
      if (attached['kind'] == 'direct') {
        if (u['id'] != attached['sender'] && u['id'] != attached['target']) {
          throw ApiError(404, 'الملف غير موجود');
        }
        chatTarget(
          'direct',
          u['id'] == attached['sender']
              ? attached['target']
              : attached['sender'],
          u,
        );
      } else {
        chatTarget('group', attached['target'], u);
      }
    }
    final disk = File('${file.parent.path}/voice/${row['id']}.m4a');
    if (!disk.existsSync()) throw ApiError(404, 'الملف غير موجود');
    req.response.headers.contentType = ContentType('audio', 'mp4');
    req.response.headers.set('X-Content-Type-Options', 'nosniff');
    req.response.contentLength = disk.lengthSync();
    await req.response.addStream(disk.openRead());
  }

  Future<Map<String, dynamic>?> productSocial(
    HttpRequest req,
    Map<String, dynamic> u,
  ) async {
    final path = req.uri.path,
        p = req.uri.pathSegments,
        method = req.method,
        uid = u['id'] as String;
    if (path == '/product/search' && method == 'GET') {
      final q = (req.uri.queryParameters['q'] ?? '').trim().toLowerCase();
      if (q.length > 100) throw ApiError(400, 'عبارة البحث طويلة');
      return {
        'posts': rows('posts')
            .where(
              (r) =>
                  postVisible(r as Map<String, dynamic>, u) &&
                  (q.isEmpty ||
                      (r['text'] as String).toLowerCase().contains(q)),
            )
            .toList()
            .reversed
            .take(100)
            .map((r) => productPost(r as Map<String, dynamic>, u))
            .toList(),
        'people': rows('users')
            .where(
              (r) =>
                  r['university'] == u['university'] &&
                  r['disabled'] != true &&
                  r['id'] != uid &&
                  !blocked(uid, r['id']) &&
                  schoolSocial(u, r as Map<String, dynamic>) &&
                  (q.isEmpty ||
                      (r['name'] as String).toLowerCase().contains(q)),
            )
            .take(50)
            .map((r) => author(r['id']))
            .toList(),
      };
    }
    if (path == '/product/saved' && method == 'GET') {
      return {
        'items': rows('savedPosts')
            .where((s) => s['user'] == uid)
            .map((s) => find('posts', s['post']))
            .whereType<Map<String, dynamic>>()
            .where((r) => postVisible(r, u))
            .map((r) => productPost(r, u))
            .toList(),
      };
    }
    if (p.length == 4 &&
        p[1] == 'posts' &&
        p[3] == 'save' &&
        method == 'POST') {
      final post = find('posts', p[2]);
      if (post == null || !postVisible(post, u)) {
        throw ApiError(404, 'المنشور غير موجود');
      }
      final existing = rows('savedPosts')
          .where((s) => s['user'] == uid && s['post'] == p[2])
          .firstOrNull;
      if (existing == null) {
        rows('savedPosts')
            .add({'id': id(), 'user': uid, 'post': p[2], 'created': now()});
      } else {
        rows('savedPosts').remove(existing);
      }
      save();
      return {'saved': existing == null};
    }
    if (p.length == 3 && p[1] == 'posts' && method == 'PATCH') {
      final post = find('posts', p[2]);
      if (post == null || post['user'] != uid) {
        throw ApiError(403, 'يمكنك تعديل منشوراتك فقط');
      }
      final b = await body(req);
      post['text'] = field(
        b,
        'text',
        min: post['media'] == null ? 1 : 0,
        max: 2000,
      );
      post['edited'] = now();
      save();
      return {'ok': true};
    }
    if (path == '/product/voice-files' && method == 'POST') {
      socialRate(u, 'voice', limit: 10);
      final b = await body(req, limit: 7 * 1024 * 1024);
      List<int> bytes;
      try {
        bytes = base64.decode(field(b, 'data', max: 7 * 1024 * 1024));
      } catch (_) {
        throw ApiError(400, 'ملف صوتي غير صالح');
      }
      if (bytes.length < 16 ||
          bytes.length > 5 * 1024 * 1024 ||
          ascii.decode(bytes.sublist(4, 8), allowInvalid: true) != 'ftyp') {
        throw ApiError(400, 'اختر تسجيل M4A حتى 5 ميجابايت');
      }
      final total =
          [...rows('media'), ...rows('documents'), ...rows('voiceAttachments')]
              .where((r) => r['user'] == uid)
              .fold<int>(0, (a, r) => a + (r['size'] as int));
      if (total + bytes.length > 150 * 1024 * 1024) {
        throw ApiError(413, 'وصلت لحد تخزين الحساب');
      }
      final mid = id(), disk = File('${file.parent.path}/voice/$mid.m4a');
      disk.parent.createSync(recursive: true);
      disk.writeAsBytesSync(bytes, flush: true);
      rows('voiceAttachments').add({
        'id': mid,
        'user': uid,
        'university': u['university'],
        'size': bytes.length,
        'created': now(),
        'attached': null,
      });
      save();
      return {'id': mid};
    }
    if (p.length >= 4 && p[1] == 'chat') {
      final kind = p[2], target = p[3];
      chatTarget(kind, target, u);
      final collection = kind == 'direct' ? 'direct' : 'messages',
          key = chatKey(kind, target, uid);
      if (p.length == 4 && method == 'GET') {
        final items = rows(collection)
            .where(
              (m) =>
                  sameThread(m as Map<String, dynamic>, kind, target, uid) &&
                  (kind == 'direct' ||
                      (!blocked(uid, m['user']) &&
                          schoolSocial(u, find('users', m['user']) ?? u))),
            )
            .toList()
            .reversed
            .take(100)
            .toList()
            .reversed;
        final receipts = rows('messageReceipts')
                .where((r) => r['thread'] == key)
                .toList(),
            current = DateTime.now().toUtc();
        return {
          'items': items
              .map(
                (m) => {
                  ...m as Map<String, dynamic>,
                  'author': author(m['from'] ?? m['user']),
                  'mine': (m['from'] ?? m['user']) == uid,
                  'readCount': receipts
                      .where(
                        (r) =>
                            r['user'] != (m['from'] ?? m['user']) &&
                            (r['readAt'] as String).compareTo(m['created']) >=
                                0,
                      )
                      .length,
                  'reply': m['replyTo'] == null
                      ? null
                      : find(collection, m['replyTo'])?['deleted'] == true
                      ? 'رسالة محذوفة'
                      : find(collection, m['replyTo'])?['text'] ??
                            'رسالة غير متاحة',
                },
              )
              .toList(),
          'typing': rows('chatPresence')
              .where(
                (r) =>
                    r['thread'] == key &&
                    r['user'] != uid &&
                    r['typing'] == true &&
                    current.difference(DateTime.parse(r['updated'])) <
                        const Duration(seconds: 8),
              )
              .map((r) => author(r['user']))
              .toList(),
          'canManage':
              kind == 'group' &&
              ((find('groups', target)?['moderators'] as List? ?? []).contains(
                    uid,
                  ) ||
                  find('groups', target)?['owner'] == uid ||
                  manages(u, 'content')),
        };
      }
      if (p.length == 4 && method == 'POST') {
        socialRate(u, 'chat', limit: 60);
        final b = await body(req), voice = b['voice'], reply = b['replyTo'];
        if (reply != null) {
          final original = find(collection, reply);
          if (original == null || !sameThread(original, kind, target, uid)) {
            throw ApiError(400, 'الرد خارج المحادثة');
          }
        }
        Map<String, dynamic>? attachment;
        if (voice != null) {
          attachment = find('voiceAttachments', voice);
          if (attachment == null ||
              attachment['user'] != uid ||
              attachment['attached'] != null) {
            throw ApiError(400, 'تسجيل صوتي غير صالح');
          }
        }
        final m = {
          'id': id(),
          if (kind == 'direct') 'from': uid,
          if (kind == 'direct') 'to': target,
          if (kind == 'group') 'user': uid,
          if (kind == 'group') 'group': target,
          'text': field(b, 'text', min: voice == null ? 1 : 0, max: 1000),
          'voice': voice,
          'replyTo': reply,
          'created': now(),
        };
        rows(collection).add(m);
        if (attachment != null) {
          attachment['attached'] = {
            'kind': kind,
            'target': kind == 'direct' ? target : target,
            'sender': uid,
            'message': m['id'],
          };
        }
        if (kind == 'direct') {
          notify(target, uid, 'message', 'رسالة خاصة جديدة', target: uid);
        } else {
          for (final member in find('groups', target)!['members'] as List) {
            notify(
              member,
              uid,
              'message',
              'رسالة جديدة في المجموعة',
              target: target,
            );
          }
        }
        save();
        return {'id': m['id']};
      }
      if (p.length == 5 && p[4] == 'presence' && method == 'POST') {
        socialRate(u, 'presence', limit: 90);
        final b = await body(req);
        if (b['typing'] is! bool) throw ApiError(400, 'حالة كتابة غير صحيحة');
        rows('chatPresence')
            .removeWhere((r) => r['user'] == uid && r['thread'] == key);
        rows('chatPresence').add({
          'id': id(),
          'user': uid,
          'thread': key,
          'typing': b['typing'],
          'updated': now(),
        });
        save();
        return {'ok': true};
      }
      if (p.length == 5 && p[4] == 'read' && method == 'POST') {
        rows('messageReceipts')
            .removeWhere((r) => r['user'] == uid && r['thread'] == key);
        rows('messageReceipts')
            .add({'id': id(), 'user': uid, 'thread': key, 'readAt': now()});
        save();
        return {'ok': true};
      }
    }
    if (p.length == 4 &&
        p[1] == 'messages' &&
        ['direct', 'group'].contains(p[2]) &&
        ['PATCH', 'DELETE'].contains(method)) {
      final collection = p[2] == 'direct' ? 'direct' : 'messages',
          m = find(collection, p[3]);
      if (m == null) throw ApiError(404, 'الرسالة غير موجودة');
      final authorId = m['from'] ?? m['user'],
          target = p[2] == 'direct'
              ? (m['from'] == uid ? m['to'] : m['from'])
              : m['group'];
      chatTarget(p[2], target, u);
      if (authorId != uid && !(p[2] == 'group' && manages(u, 'content'))) {
        throw ApiError(403, 'تعديل رسائلك فقط');
      }
      if (method == 'PATCH') {
        if (m['deleted'] == true) throw ApiError(409, 'الرسالة محذوفة');
        final b = await body(req);
        m['text'] = field(
          b,
          'text',
          min: m['voice'] == null ? 1 : 0,
          max: 1000,
        );
        m['edited'] = now();
      } else {
        if (m['voice'] != null) {
          final disk = File('${file.parent.path}/voice/${m['voice']}.m4a');
          if (disk.existsSync()) disk.deleteSync();
          rows('voiceAttachments').removeWhere((v) => v['id'] == m['voice']);
        }
        m['text'] = 'رسالة محذوفة';
        m['voice'] = null;
        m['replyTo'] = null;
        m['deleted'] = true;
      }
      save();
      return {'ok': true};
    }
    if (path == '/product/groups' && method == 'POST') {
      if (school(u)) {
        throw ApiError(403, 'مجموعات المدرسة تُنشأ من الشعب الرسمية');
      }
      final b = await body(req),
          g = {
            'id': id(),
            'name': field(b, 'name', max: 80),
            'description': field(b, 'description', min: 0, max: 500),
            'university': u['university'],
            'owner': uid,
            'moderators': [uid],
            'members': [uid],
          };
      rows('groups').add(g);
      auditAction(u, 'group-create', g['id'] as String);
      save();
      return {'id': g['id']};
    }
    if (p.length >= 3 && p[1] == 'groups') {
      final g = find('groups', p[2]);
      sameUniversity(g, u);
      chatTarget('group', p[2], u);
      final canManage =
          g!['owner'] == uid ||
          (g['moderators'] as List? ?? []).contains(uid) ||
          manages(u, 'content');
      if (p.length == 3 && method == 'GET') {
        return {
          'group': {
            ...g,
            'members': (g['members'] as List).map((m) => author(m)).toList(),
          },
          'canManage': canManage,
        };
      }
      if (p.length == 3 && method == 'PATCH') {
        if (!canManage) throw ApiError(403, 'للمشرف على المجموعة فقط');
        if (g['section'] != null) {
          throw ApiError(403, 'إدارة الشعبة من المواد والتسجيل');
        }
        final b = await body(req);
        final name = field(b, 'name', max: 80);
        final description = field(b, 'description', min: 0, max: 500);
        final moderators = b['moderators'];
        if (moderators is! List ||
            moderators.any((m) => !(g['members'] as List).contains(m))) {
          throw ApiError(400, 'اختر مشرفين من الأعضاء');
        }
        g['name'] = name;
        g['description'] = description;
        g['moderators'] = {
          g['owner'],
          ...moderators,
        }.whereType<String>().toList();
        auditAction(u, 'group-update', g['id']);
        save();
        return {'ok': true};
      }
      if (p.length == 4 && p[3] == 'remove' && method == 'POST') {
        if (!canManage || g['section'] != null) {
          throw ApiError(403, 'غير مسموح');
        }
        final b = await body(req), member = field(b, 'user');
        if (member == g['owner'] || member == uid) {
          throw ApiError(400, 'لا يمكن إزالة مالك المجموعة بهذه الطريقة');
        }
        (g['members'] as List).remove(member);
        (g['moderators'] as List? ?? []).remove(member);
        auditAction(u, 'group-remove-member', member);
        save();
        return {'ok': true};
      }
    }
    if (path == '/product/group-invites' && method == 'GET') {
      return {
        'items': rows('groupInvites')
            .where((r) => r['to'] == uid && r['status'] == 'pending')
            .map(
              (r) => {
                ...r as Map<String, dynamic>,
                'groupName': find('groups', r['group'])?['name'] ?? 'مجموعة',
                'person': author(r['from']),
              },
            )
            .toList(),
      };
    }
    if (p.length == 3 && p[1] == 'group-invites' && method == 'POST') {
      final invite = find('groupInvites', p[2]);
      if (invite == null || invite['to'] != uid) {
        throw ApiError(404, 'الدعوة غير موجودة');
      }
      if (invite['status'] != 'pending') {
        throw ApiError(409, 'تم الرد على الدعوة');
      }
      final b = await body(req);
      if (b['accept'] is! bool) throw ApiError(400, 'اختر قبولًا أو رفضًا');
      final group = find('groups', invite['group']);
      sameUniversity(group, u);
      if (group!['section'] != null ||
          school(u) ||
          blocked(uid, invite['from'])) {
        throw ApiError(403, 'الدعوة غير متاحة');
      }
      invite['status'] = b['accept'] == true ? 'accepted' : 'declined';
      if (b['accept'] == true && !(group['members'] as List).contains(uid)) {
        (group['members'] as List).add(uid);
      }
      save();
      return {'ok': true};
    }
    if (p.length == 4 &&
        p[1] == 'groups' &&
        p[3] == 'invite' &&
        method == 'POST') {
      final group = chatTarget('group', p[2], u);
      if (group['section'] != null || school(u)) {
        throw ApiError(403, 'عضوية الشعب الرسمية من المؤسسة');
      }
      final b = await body(req), target = field(b, 'user');
      final peer = chatTarget('direct', target, u);
      if ((group['members'] as List).contains(target)) {
        throw ApiError(409, 'الحساب عضو بالفعل');
      }
      if (rows('groupInvites').any(
        (r) =>
            r['to'] == target && r['group'] == p[2] && r['status'] == 'pending',
      )) {
        throw ApiError(409, 'توجد دعوة معلقة');
      }
      socialRate(u, 'group-invite', limit: 15);
      rows('groupInvites').add({
        'id': id(),
        'from': uid,
        'to': peer['id'],
        'group': p[2],
        'university': u['university'],
        'status': 'pending',
        'created': now(),
      });
      notify(
        target,
        uid,
        'group_invite',
        'دعوة للانضمام إلى ${group['name']}',
        target: p[2],
      );
      save();
      return {'ok': true};
    }
    if (path == '/product/games/history' && method == 'GET') {
      return {
        'items': rows('duels')
            .where(
              (g) =>
                  (g['from'] == uid || g['to'] == uid) &&
                  [
                    'finished',
                    'declined',
                    'expired',
                    'cancelled',
                  ].contains(g['state']),
            )
            .toList()
            .reversed
            .take(100)
            .toList(),
      };
    }
    return null;
  }
}
