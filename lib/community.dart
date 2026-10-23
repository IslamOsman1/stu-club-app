import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'design.dart';
import 'product_chat.dart';

typedef Json = Map<String, dynamic>;
Future<T?> openPage<T>(BuildContext context, Widget page) => Navigator.push<T>(
  context,
  MaterialPageRoute(
    builder: (_) =>
        Directionality(textDirection: TextDirection.rtl, child: page),
  ),
);
Future<Map<String, String>?> askFields(
  BuildContext context,
  String title,
  Map<String, String> fields, {
  Set<String> secrets = const {},
  Map<String, String> initial = const {},
}) => showDialog<Map<String, String>>(
  context: context,
  builder: (_) => Directionality(
    textDirection: TextDirection.rtl,
    child: _Fields(
      title: title,
      fields: fields,
      secrets: secrets,
      initial: initial,
    ),
  ),
);

class _Fields extends StatefulWidget {
  final String title;
  final Map<String, String> fields, initial;
  final Set<String> secrets;
  const _Fields({
    required this.title,
    required this.fields,
    required this.secrets,
    required this.initial,
  });
  @override
  State<_Fields> createState() => _FieldsState();
}

class _FieldsState extends State<_Fields> {
  late final controls = {
    for (final k in widget.fields.keys)
      k: TextEditingController(text: widget.initial[k] ?? ''),
  };
  @override
  void dispose() {
    for (final c in controls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: widget.fields.entries
            .map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: controls[e.key],
                  obscureText: widget.secrets.contains(e.key),
                  maxLength: widget.secrets.contains(e.key) ? 128 : 500,
                  maxLines: 1,
                  decoration: InputDecoration(labelText: e.value),
                ),
              ),
            )
            .toList(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, {
          for (final e in controls.entries) e.key: e.value.text,
        }),
        child: const Text('تأكيد'),
      ),
    ],
  );
}

Future<bool> confirm(
  BuildContext context,
  String title, [
  String text = 'راجع الإجراء قبل التأكيد.',
]) async =>
    (await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تأكيد'),
            ),
          ],
        ),
      ),
    )) ??
    false;

class RemotePanel extends StatefulWidget {
  final Api api;
  final String path, title;
  final Widget Function(PanelState) content;
  const RemotePanel({
    super.key,
    required this.api,
    required this.path,
    required this.title,
    required this.content,
  });
  @override
  PanelState createState() => PanelState();
}

class PanelState extends State<RemotePanel> {
  String query = '';
  Widget search(String hint) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      onChanged: (v) => setState(() => query = v),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 20),
      ),
    ),
  );
  void stopLoading() {
    if (mounted) setState(() => busy = false);
  }

  Json? data;
  String? error;
  bool busy = false;
  Api get api => widget.api;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async => action(() async {
    final res = await api.call(widget.path);
    if (mounted) setState(() => data = res);
  }, reload: false);
  Future<void> action(
    Future<void> Function() task, {
    bool reload = true,
  }) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await task();
      if (reload) {
        final res = await api.call(widget.path);
        if (mounted) setState(() => data = res);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void toast(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        IconButton(
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              error!,
              style: const TextStyle(color: Colors.deepOrange),
            ),
          ),
        Expanded(
          child: AbsorbPointer(
            absorbing: busy,
            child: data == null
                ? Center(
                    child: Text(
                      busy ? 'جارٍ التحميل...' : 'تعذر تحميل البيانات',
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: widget.content(this),
                  ),
          ),
        ),
      ],
    ),
  );
}

Widget personLabel(Json p) => Row(
  children: [
    const CircleAvatar(child: Icon(Icons.person_outline)),
    const SizedBox(width: 10),
    Expanded(
      child: Text(
        p['name'] as String? ?? 'مستخدم',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    ),
    if (p['verified'] == true)
      const Icon(Icons.verified, size: 18, color: ClubStyle.green),
  ],
);
Future<void> reportContent(PanelState panel, String type, String id) async {
  final values = await askFields(panel.context, 'إبلاغ عن محتوى', {
    'reason': 'سبب الإبلاغ',
  });
  if (values == null || !panel.mounted) return;
  await panel.action(() async {
    await panel.api.call(
      '/reports',
      method: 'POST',
      body: {'type': type, 'target': id, 'reason': values['reason']},
    );
    panel.toast('تم حفظ البلاغ للمراجعة');
  });
}

Widget commentsPage(Api api, Json post, String uid) => RemotePanel(
  api: api,
  path: '/posts/${post['id']}/comments',
  title: 'التعليقات',
  content: (s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(post['text'] as String),
        ),
      ),
      FilledButton.icon(
        onPressed: () async {
          final v = await askFields(s.context, 'تعليق جديد', {
            'text': 'اكتب تعليقك',
          });
          if (v == null || !s.mounted) return;
          await s.action(() async {
            await api.call(
              '/posts/${post['id']}/comments',
              method: 'POST',
              body: {'text': v['text']},
            );
          });
        },
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('أضف تعليقًا'),
      ),
      if ((s.data!['items'] as List).isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('ابدأ أول تعليق.'),
        ),
      ...(s.data!['items'] as List).map((raw) {
        final c = raw as Json;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                personLabel(c['author'] as Json),
                const SizedBox(height: 10),
                Text(c['text'] as String),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (c['user'] == uid || post['user'] == uid)
                      IconButton(
                        tooltip: 'حذف',
                        onPressed: () => s.action(() async {
                          await api.call(
                            '/comments/${c['id']}',
                            method: 'DELETE',
                          );
                        }),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    if (c['user'] != uid)
                      IconButton(
                        tooltip: 'إبلاغ',
                        onPressed: () =>
                            reportContent(s, 'comments', c['id'] as String),
                        icon: const Icon(Icons.flag_outlined),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      }),
    ],
  ),
);

Widget peoplePage(Api api, String uid) => RemotePanel(
  api: api,
  path: '/people',
  title: 'زملاء الجامعة',
  content: (s) => Column(
    children: [
      const Text(
        'ابحث عن زملائك وابدأ محادثة خاصة. البريد الإلكتروني لا يظهر هنا.',
      ),
      const SizedBox(height: 16),
      if ((s.data!['items'] as List).isEmpty)
        const Text('لا يوجد زملاء متاحون حاليًا.'),
      s.search('ابحث باسم زميلك'),
      ...(s.data!['items'] as List)
          .where(
            (p) => (p['name'] as String).toLowerCase().contains(
              s.query.toLowerCase(),
            ),
          )
          .map((raw) {
            final p = raw as Json;
            return Card(
              child: Column(
                children: [
                  ListTile(
                    title: personLabel(p),
                    subtitle: Text(p['bio'] as String? ?? ''),
                    onTap: () =>
                        openPage(s.context, DirectChat(api: api, person: p)),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => openPage(
                          s.context,
                          DirectChat(api: api, person: p),
                        ),
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('مراسلة'),
                      ),
                      TextButton(
                        onPressed: () async {
                          if (!await confirm(
                            s.context,
                            'حظر المستخدم؟',
                            'سيتم إخفاء المحتوى ومنع المحادثات بينكما.',
                          )) {
                            return;
                          }
                          if (!s.mounted) return;
                          await s.action(() async {
                            await api.call(
                              '/blocks/${p['id']}',
                              method: 'POST',
                            );
                          });
                        },
                        child: const Text('حظر'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
    ],
  ),
);
Widget inboxPage(Api api) => RemotePanel(
  api: api,
  path: '/inbox',
  title: 'الرسائل الخاصة',
  content: (s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton.icon(
        onPressed: () => openPage(s.context, peoplePage(api, '')),
        icon: const Icon(Icons.person_search_outlined),
        label: const Text('ابدأ محادثة مع زميل'),
      ),
      ...(s.data!['items'] as List).map((raw) {
        final row = raw as Json;
        return Card(
          child: ListTile(
            title: Text(row['person']['name'] as String),
            subtitle: Text(
              row['text'] as String,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_left),
            onTap: () async {
              await openPage(
                s.context,
                DirectChat(api: api, person: row['person'] as Json),
              );
              if (s.mounted) await s.load();
            },
          ),
        );
      }),
      if ((s.data!['items'] as List).isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('لا توجد محادثات بعد.'),
        ),
    ],
  ),
);

class DirectChat extends StatelessWidget {
  final Api api;
  final Json person;
  const DirectChat({super.key, required this.api, required this.person});
  @override
  Widget build(BuildContext context) => ProductChat(
    api: api,
    kind: 'direct',
    target: person['id'],
    title: person['name'],
  );
}

Widget notificationsPage(Api api) => RemotePanel(
  api: api,
  path: '/notifications',
  title: 'التنبيهات',
  content: (s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'تنبيهات داخل التطبيق. إشعارات الهاتف خارج التطبيق ليست مفعلة.',
      ),
      TextButton(
        onPressed: () => s.action(() async {
          await api.call('/notifications/read', method: 'POST');
        }),
        child: const Text('تعليم الكل كمقروء'),
      ),
      ...(s.data!['items'] as List).map((raw) {
        final n = raw as Json;
        return Card(
          child: ListTile(
            leading: Icon(
              n['read'] == true
                  ? Icons.notifications_none
                  : Icons.notifications_active,
              color: ClubStyle.green,
            ),
            title: Text(n['text'] as String),
            subtitle: Text(n['author']['name'] as String),
            onTap: n['type'] == 'message'
                ? () => openPage(
                    s.context,
                    DirectChat(api: api, person: n['author'] as Json),
                  )
                : null,
          ),
        );
      }),
      if ((s.data!['items'] as List).isEmpty)
        const Text('لا توجد تنبيهات بعد.'),
    ],
  ),
);

class AccountTools extends StatelessWidget {
  final Api api;
  final VoidCallback onSignedOut;
  const AccountTools({super.key, required this.api, required this.onSignedOut});
  void done(BuildContext context) {
    onSignedOut();
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => RemotePanel(
    api: api,
    path: '/blocks',
    title: 'إدارة الحساب والخصوصية',
    content: (s) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: () async {
            final v = await askFields(
              s.context,
              'تغيير كلمة المرور',
              {
                'password': 'كلمة المرور الحالية',
                'newPassword': 'الجديدة · ١٠ أحرف على الأقل',
              },
              secrets: {'password', 'newPassword'},
            );
            if (v == null || !s.mounted) return;
            await s.action(() async {
              await api.call('/account/password', method: 'POST', body: v);
              await api.clear();
              if (s.mounted) done(s.context);
            }, reload: false);
          },
          icon: const Icon(Icons.password),
          label: const Text('تغيير كلمة المرور وتسجيل الخروج من الأجهزة'),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final v = await askFields(
              s.context,
              'إنشاء كود استعادة جديد',
              {'password': 'كلمة المرور الحالية'},
              secrets: {'password'},
            );
            if (v == null || !s.mounted) return;
            await s.action(() async {
              final res = await api.call(
                '/account/recovery',
                method: 'POST',
                body: v,
              );
              if (!s.mounted) return;
              s.stopLoading();
              await showDialog<void>(
                context: s.context,
                builder: (ctx) => Directionality(
                  textDirection: TextDirection.rtl,
                  child: AlertDialog(
                    title: const Text('احفظ كود الاستعادة'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'الكود يظهر مرة واحدة، ويصلح للاستخدام مرة واحدة. إنشاء كود جديد يلغي السابق. احتفظ به في مكان آمن ولا تشاركه.',
                        ),
                        const SizedBox(height: 16),
                        SelectableText(
                          res['code'] as String,
                          textDirection: TextDirection.ltr,
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('حفظته'),
                      ),
                    ],
                  ),
                ),
              );
            }, reload: false);
          },
          icon: const Icon(Icons.key_outlined),
          label: const Text('إنشاء كود استعادة الحساب'),
        ),
        const SizedBox(height: 16),
        const Text(
          'الحسابات المحظورة',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        ...(s.data!['items'] as List).map(
          (p) => ListTile(
            title: Text(p['name'] as String),
            trailing: TextButton(
              onPressed: () => s.action(() async {
                await api.call('/blocks/${p['id']}', method: 'DELETE');
              }),
              child: const Text('إلغاء الحظر'),
            ),
          ),
        ),
        const Divider(),
        OutlinedButton.icon(
          onPressed: () async {
            if (!await confirm(
              s.context,
              'حذف الحساب نهائيًا؟',
              'سيتم حذف حسابك ومنشوراتك ورسائلك وملفاتك من الخادم المحلي. لا يمكن التراجع.',
            )) {
              return;
            }
            if (!s.mounted) return;
            final v = await askFields(
              s.context,
              'تأكيد حذف الحساب',
              {'password': 'كلمة المرور الحالية'},
              secrets: {'password'},
            );
            if (v == null || !s.mounted) return;
            await s.action(() async {
              await api.call('/account/delete', method: 'POST', body: v);
              await api.clear();
              if (s.mounted) done(s.context);
            }, reload: false);
          },
          icon: const Icon(Icons.delete_forever, color: Colors.red),
          label: const Text(
            'حذف الحساب نهائيًا',
            style: TextStyle(color: Colors.red),
          ),
        ),
      ],
    ),
  );
}

Widget verificationPage(Api api) => RemotePanel(
  api: api,
  path: '/verification',
  title: 'طلب توثيق الحساب',
  content: (s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'أرسل مرجعًا جامعيًا للمراجعة اليدوية. لا ترسل كلمة مرور أو رقم هوية حكومية. الاعتماد يتم بعد تحقق المشرف خارج التطبيق.',
      ),
      const SizedBox(height: 12),
      ...['student', 'doctor'].map(
        (role) => OutlinedButton(
          onPressed: () async {
            final v = await askFields(
              s.context,
              role == 'doctor' ? 'طلب توثيق مدرس / دكتور' : 'طلب توثيق طالب',
              {
                'reference': 'مرجع جامعي / بريد جامعي',
                'note': 'ملاحظات للمشرف',
              },
            );
            if (v == null || !s.mounted) return;
            await s.action(() async {
              await api.call(
                '/verification',
                method: 'POST',
                body: {...v, 'role': role},
              );
            });
          },
          child: Text(
            role == 'doctor' ? 'طلب توثيق مدرس / دكتور' : 'طلب توثيق طالب',
          ),
        ),
      ),
      ...(s.data!['items'] as List).map(
        (v) => Card(
          child: ListTile(
            title: Text(v['role'] == 'doctor' ? 'دكتور' : 'طالب'),
            subtitle: Text(
              {
                    'pending': 'قيد المراجعة',
                    'approved': 'تم الاعتماد',
                    'rejected': 'مرفوض',
                  }[v['status']] ??
                  v['status'] as String,
            ),
          ),
        ),
      ),
    ],
  ),
);

Widget adminPage(Api api) => RemotePanel(
  api: api,
  path: '/admin/overview',
  title: 'لوحة المشرف',
  content: (s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'طلبات التوثيق',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
      ...(s.data!['verification'] as List).map(
        (v) => Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${v['person']['name']} · ${v['role']}'),
                Text('${v['reference']}\n${v['note']}'),
                Row(
                  children: [
                    TextButton(
                      onPressed: () async {
                        if (!await confirm(
                          s.context,
                          'اعتماد الحساب؟',
                          'أكد أنك تحققت من الانتماء الجامعي والصفة خارج التطبيق.',
                        )) {
                          return;
                        }
                        if (!s.mounted) return;
                        await s.action(() async {
                          await api.call(
                            '/admin/verification/${v['id']}',
                            method: 'POST',
                            body: {'approve': true},
                          );
                        });
                      },
                      child: const Text('اعتماد'),
                    ),
                    TextButton(
                      onPressed: () => s.action(() async {
                        await api.call(
                          '/admin/verification/${v['id']}',
                          method: 'POST',
                          body: {'approve': false},
                        );
                      }),
                      child: const Text('رفض'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      const Divider(),
      const Text(
        'البلاغات',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
      ...(s.data!['reports'] as List).map(
        (r) => Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r['reason'] as String,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(r['content'] as String),
                Text('الحالة: ${r['status'] ?? 'جديد'}'),
                if (r['status'] == null)
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => s.action(() async {
                          await api.call(
                            '/admin/reports/${r['id']}',
                            method: 'POST',
                            body: {'action': 'dismiss'},
                          );
                        }),
                        child: const Text('إغلاق البلاغ'),
                      ),
                      TextButton(
                        onPressed: () async {
                          if (!await confirm(
                            s.context,
                            'حذف المحتوى؟',
                            'سيتم حذف المحتوى المبلغ عنه من الخادم.',
                          )) {
                            return;
                          }
                          if (!s.mounted) return;
                          await s.action(() async {
                            await api.call(
                              '/admin/reports/${r['id']}',
                              method: 'POST',
                              body: {'action': 'remove'},
                            );
                          });
                        },
                        child: const Text('حذف المحتوى'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
      const Divider(),
      const Text(
        'الحسابات',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
      ...(s.data!['users'] as List).map(
        (u) => Card(
          child: ListTile(
            title: Text(u['name'] as String),
            subtitle: Text('${u['email']} · ${u['role']}'),
            trailing: u['role'] == 'admin'
                ? const Icon(Icons.admin_panel_settings)
                : TextButton(
                    onPressed: () async {
                      final disable = u['disabled'] != true;
                      if (!await confirm(
                        s.context,
                        disable ? 'إيقاف الحساب؟' : 'إعادة تفعيل الحساب؟',
                        u['name'] as String,
                      )) {
                        return;
                      }
                      if (!s.mounted) return;
                      await s.action(() async {
                        await api.call(
                          '/admin/users/${u['id']}',
                          method: 'POST',
                          body: {'disabled': disable},
                        );
                      });
                    },
                    child: Text(u['disabled'] == true ? 'تفعيل' : 'إيقاف'),
                  ),
          ),
        ),
      ),
    ],
  ),
);
