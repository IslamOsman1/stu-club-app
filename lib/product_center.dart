import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'community.dart';
import 'design.dart';
import 'release_hub.dart';
import 'product_chat.dart';
import 'voice_rooms.dart';

class ProductCenter extends StatelessWidget {
  final Api api;
  const ProductCenter({super.key, required this.api});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('مجتمعي وخدماتي')),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text(
          'كل ما يخص مجتمعك',
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 18),
        for (final item in <(IconData, String, String, Widget)>[
          (
            Icons.event,
            'الفعاليات والحضور',
            'سجّل وتابع أنشطة مؤسستك',
            EventsPage(api: api),
          ),
          (
            Icons.headset_mic,
            'الغرف الصوتية',
            'ادخل غرفة أو أنشئ حوارًا',
            VoiceRoomsPage(api: api),
          ),
          (
            Icons.search,
            'البحث والمنشورات المحفوظة',
            'ابحث واحفظ وراجع منشوراتك',
            ProductSearchPage(api: api),
          ),
          (
            Icons.group_add_outlined,
            'دعوات المجموعات',
            'اقبل الدعوات أو ارفضها',
            groupInvitesPage(api),
          ),
          (
            Icons.history,
            'سجل المباريات',
            'نتائج مبارياتك مع أصدقائك',
            gameHistoryPage(api),
          ),
          (
            Icons.manage_accounts,
            'المؤسسة والدعوات',
            'تابع انضمامك وانتقالك',
            membershipPage(api),
          ),
          (
            Icons.devices,
            'الأجهزة والجلسات',
            'راجع وألغِ جلسات الدخول',
            sessionsPage(api),
          ),
          (
            Icons.notifications_active,
            'تفضيلات التنبيهات',
            'اختار التنبيهات المناسبة لك',
            preferencesPage(api),
          ),
          (
            Icons.support_agent,
            'المساعدة والدعم',
            'تذاكر الدعم والقرارات والاستئناف',
            supportPage(api),
          ),
          (
            Icons.file_download,
            'بياناتي وخصوصيتي',
            'اطلع على نسخة من بيانات حسابك',
            exportPage(api),
          ),
        ])
          Card(
            child: ListTile(
              leading: Icon(item.$1, color: ClubStyle.green),
              title: Text(item.$2),
              subtitle: Text(item.$3),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => openPage(context, item.$4),
            ),
          ),
      ],
    ),
  );
}

Widget membershipPage(Api api) => RemotePanel(
  api: api,
  path: '/product/account',
  title: 'مؤسستي والانضمام',
  content: (s) {
    final me = s.data!['user'] as Json,
        requests = s.data!['membership'] as List;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: ListTile(
            title: Text(me['institutionName'] ?? ''),
            subtitle: Text(
              me['membershipStatus'] == 'pending'
                  ? 'طلبك ينتظر اعتماد المؤسسة'
                  : 'عضوية معتمدة',
            ),
          ),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.mail_outline),
          label: const Text('استخدام رمز دعوة'),
          onPressed: () => s.action(() async {
            final f = await askFields(s.context, 'رمز الدعوة', {
              'code': 'رمز الدعوة',
            });
            if (f != null) {
              await api.call(
                '/product/invitation/claim',
                method: 'POST',
                body: f,
              );
            }
          }),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.domain_add),
          label: const Text('طلب انضمام أو انتقال'),
          onPressed: () => s.action(() async {
            final institutions = (s.data!['institutions'] as List).cast<Json>();
            String? target = await showDialog<String>(
              context: s.context,
              builder: (c) => SimpleDialog(
                title: const Text('اختر المؤسسة'),
                children: institutions
                    .where(
                      (i) => i['active'] != false && i['kind'] != 'platform',
                    )
                    .map(
                      (i) => SimpleDialogOption(
                        onPressed: () => Navigator.pop(c, i['id']),
                        child: Text(i['name']),
                      ),
                    )
                    .toList(),
              ),
            );
            if (target == null || !s.mounted) return;
            final f = await askFields(s.context, 'معلومات طلب الانضمام', {
              'note': 'سبب الطلب أو بيانات القيد',
              if (institutions.firstWhere((i) => i['id'] == target)['kind'] ==
                  'school')
                'birthYear': 'سنة الميلاد',
              if (institutions.firstWhere((i) => i['id'] == target)['kind'] ==
                  'school')
                'grade': 'الصف الدراسي',
            });
            if (f != null) {
              await api.call(
                '/product/membership',
                method: 'POST',
                body: {
                  ...f,
                  'institution': target,
                  if (f['birthYear'] != null)
                    'birthYear': int.tryParse(f['birthYear']!),
                  if (f['grade'] != null) 'grade': int.tryParse(f['grade']!),
                },
              );
            }
          }),
        ),
        const SizedBox(height: 20),
        const Text(
          'طلباتك',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        ...requests.map(
          (r) => Card(
            child: ListTile(
              title: Text(
                (s.data!['institutions'] as List)
                        .cast<Json>()
                        .where((i) => i['id'] == r['university'])
                        .firstOrNull?['name'] ??
                    r['university'],
              ),
              subtitle: Text(
                '${r['status']}\n${r['reason'] ?? r['note'] ?? ''}',
              ),
            ),
          ),
        ),
        if (requests.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('لا توجد طلبات سابقة.'),
          ),
      ],
    );
  },
);
Widget sessionsPage(Api api) => RemotePanel(
  api: api,
  path: '/product/sessions',
  title: 'الأجهزة والجلسات',
  content: (s) => Column(
    children: [
      const Text(
        'إنهاء الجلسة يلغي دخولها وتنبيهاتها. قد تحتاج إعادة تسجيل الدخول إذا أنهيت جلستك الحالية.',
      ),
      ...(s.data!['items'] as List).map(
        (r) => Card(
          child: ListTile(
            leading: const Icon(Icons.devices),
            title: Text(
              r['current'] == true ? 'هذا الجهاز' : r['device'] ?? 'جلسة تطبيق',
            ),
            subtitle: Text('تنتهي: ${r['expires']}'),
            trailing: IconButton(
              tooltip: 'إنهاء الجلسة',
              icon: const Icon(Icons.logout),
              onPressed: () => s.action(() async {
                if (await confirm(s.context, 'إنهاء جلسة الدخول؟')) {
                  await api.call(
                    '/product/sessions/${r['id']}',
                    method: 'DELETE',
                  );
                }
              }),
            ),
          ),
        ),
      ),
    ],
  ),
);
Widget preferencesPage(Api api) => RemotePanel(
  api: api,
  path: '/product/account',
  title: 'تفضيلات التنبيهات',
  content: (s) {
    final prefs = Map<String, dynamic>.from(s.data!['preferences']);
    return Column(
      children: [
        for (final e in {
          'push': 'تنبيهات الهاتف عند تفعيل الخدمة',
          'academic': 'الإعلانات والفعاليات',
          'messages': 'الرسائل',
          'social': 'الإعجابات والتفاعل',
        }.entries)
          SwitchListTile(
            title: Text(e.value),
            value: prefs[e.key] != false,
            onChanged: (v) => s.action(() async {
              prefs[e.key] = v;
              await api.call(
                '/product/preferences',
                method: 'PATCH',
                body: {
                  for (final k in ['push', 'academic', 'messages', 'social'])
                    k: prefs[k] != false,
                },
              );
            }),
          ),
      ],
    );
  },
);
Widget exportPage(Api api) => RemotePanel(
  api: api,
  path: '/product/export',
  title: 'بيانات حسابي',
  content: (s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'نسخة من بيانات حسابك ومحتواك. لا تتضمن كلمات المرور أو رموز الدخول، ولا ملفات المرفقات نفسها.',
      ),
      const SizedBox(height: 18),
      SelectableText(
        'المنشورات: ${(s.data!['posts'] as List).length}\nالتعليقات: ${(s.data!['comments'] as List).length}\nالرسائل المرسلة: ${(s.data!['messages'] as List).length}',
      ),
      const SizedBox(height: 18),
      FilledButton.icon(
        icon: const Icon(Icons.download),
        label: const Text('حفظ ملف بياناتي'),
        onPressed: () => s.action(() async {
          await Api.storage.invokeMethod('saveDocument', {
            'name': 'stuclub-account.json',
            'mime': 'application/json',
            'data': base64Encode(
              utf8.encode(const JsonEncoder.withIndent('  ').convert(s.data)),
            ),
          });
        }),
      ),
      FilledButton.icon(
        icon: const Icon(Icons.copy),
        label: const Text('نسخ بياناتي بصيغة JSON'),
        onPressed: () async {
          await Clipboard.setData(
            ClipboardData(
              text: const JsonEncoder.withIndent('  ').convert(s.data),
            ),
          );
          s.toast('نُسخت البيانات. احتفظ بها في مكان خاص.');
        },
      ),
    ],
  ),
);
Widget supportPage(Api api) => RemotePanel(
  api: api,
  path: '/product/support',
  title: 'الدعم والمساعدة',
  content: (s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('تذكرة دعم جديدة'),
        onPressed: () => s.action(() async {
          final f = await releaseForm(s.context, api, 'تواصل مع الدعم', {
            'subject': 'الموضوع',
            'text': 'تفاصيل المشكلة',
          });
          if (f != null) {
            await api.call('/product/support', method: 'POST', body: f);
          }
        }),
      ),
      OutlinedButton(
        onPressed: () => openPage(s.context, decisionsPage(api)),
        child: const Text('قرارات الإشراف والاستئناف'),
      ),
      ...(s.data!['items'] as List).map(
        (r) => Card(
          child: ExpansionTile(
            title: Text(r['subject']),
            subtitle: Text(r['status'] == 'closed' ? 'مغلقة' : 'مفتوحة'),
            children: [
              Padding(
                padding: const EdgeInsets.all(15),
                child: SelectableText(r['text']),
              ),
              ...(r['replies'] as List).map(
                (a) => ListTile(
                  title: Text(a['text']),
                  subtitle: Text(a['created']),
                ),
              ),
              TextButton(
                onPressed: () => s.action(() async {
                  final f = await askFields(s.context, 'إضافة رد', {
                    'text': 'الرد',
                  });
                  if (f != null) {
                    await api.call(
                      '/product/support/${r['id']}/reply',
                      method: 'POST',
                      body: f,
                    );
                  }
                }),
                child: const Text('إضافة رد'),
              ),
            ],
          ),
        ),
      ),
    ],
  ),
);
Widget decisionsPage(Api api) => RemotePanel(
  api: api,
  path: '/product/moderation-decisions',
  title: 'قرارات الإشراف',
  content: (s) => Column(
    children: [
      const Text(
        'يمكنك الاعتراض على قرار إزالة محتواك. قبول الاستئناف لا يعيد الملف المحذوف تلقائيًا؛ يتواصل معك فريق الإشراف.',
      ),
      ...(s.data!['items'] as List).map(
        (r) => Card(
          child: ListTile(
            title: Text(r['reason'] ?? ''),
            subtitle: Text(r['created'] ?? ''),
            trailing: TextButton(
              child: const Text('استئناف'),
              onPressed: () => s.action(() async {
                final f = await askFields(s.context, 'استئناف القرار', {
                  'text': 'سبب الاعتراض',
                });
                if (f != null) {
                  await api.call(
                    '/product/appeals',
                    method: 'POST',
                    body: {...f, 'report': r['id']},
                  );
                }
              }),
            ),
          ),
        ),
      ),
      TextButton(
        onPressed: () => openPage(
          s.context,
          RemotePanel(
            api: api,
            path: '/product/appeals',
            title: 'استئنافات حسابي',
            content: (s) => Column(
              children: [
                ...(s.data!['items'] as List).map(
                  (r) => Card(
                    child: ListTile(
                      title: Text(r['text']),
                      subtitle: Text('${r['status']}\n${r['response'] ?? ''}'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        child: const Text('متابعة الاستئنافات'),
      ),
    ],
  ),
);

class ProductSearchPage extends StatefulWidget {
  final Api api;
  const ProductSearchPage({super.key, required this.api});
  @override
  State<ProductSearchPage> createState() => _SearchState();
}

class _SearchState extends State<ProductSearchPage> {
  final search = TextEditingController();
  List posts = [], people = [];
  bool saved = false, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final r = await widget.api.call(
        saved
            ? '/product/saved'
            : '/product/search?q=${Uri.encodeQueryComponent(search.text)}',
      );
      if (mounted) {
        setState(() {
          posts = r[saved ? 'items' : 'posts'];
          people = r['people'] ?? [];
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('البحث والمنشورات')),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        TextField(
          controller: search,
          onSubmitted: (_) => load(),
          decoration: InputDecoration(
            labelText: 'ابحث عن منشور أو زميل',
            suffixIcon: IconButton(
              onPressed: load,
              icon: const Icon(Icons.search),
            ),
          ),
        ),
        SwitchListTile(
          title: const Text('المنشورات المحفوظة فقط'),
          value: saved,
          onChanged: (v) {
            setState(() => saved = v);
            load();
          },
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.redAccent)),
        ...people.map(
          (p) => Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(p['name']),
              onTap: () => openPage(
                context,
                ProductChat(
                  api: widget.api,
                  kind: 'direct',
                  target: p['id'],
                  title: p['name'],
                ),
              ),
            ),
          ),
        ),
        ...posts.map(
          (p) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p['author']['name'],
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SelectableText(p['text']),
                  Wrap(
                    children: [
                      TextButton.icon(
                        icon: Icon(
                          p['saved'] == true
                              ? Icons.bookmark
                              : Icons.bookmark_border,
                        ),
                        label: const Text('حفظ'),
                        onPressed: () async {
                          try {
                            await widget.api.call(
                              '/product/posts/${p['id']}/save',
                              method: 'POST',
                              body: {},
                            );
                            await load();
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(content: Text('$e')));
                            }
                          }
                        },
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.copy),
                        label: const Text('نسخ النص والروابط'),
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: p['text'])),
                      ),
                      if (p['canEdit'] == true)
                        TextButton.icon(
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('تعديل منشوري'),
                          onPressed: () async {
                            final f = await askFields(
                              context,
                              'تعديل منشورك',
                              {'text': 'النص'},
                              initial: {'text': p['text']},
                            );
                            if (f != null) {
                              try {
                                await widget.api.call(
                                  '/product/posts/${p['id']}',
                                  method: 'PATCH',
                                  body: f,
                                );
                                await load();
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(
                                    context,
                                  ).showSnackBar(SnackBar(content: Text('$e')));
                                }
                              }
                            }
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (posts.isEmpty && !busy)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('لا توجد منشورات مطابقة.'),
          ),
      ],
    ),
  );
}

class EventsPage extends StatelessWidget {
  final Api api;
  const EventsPage({super.key, required this.api});
  @override
  Widget build(BuildContext context) => RemotePanel(
    api: api,
    path: '/product/events',
    title: 'الفعاليات والأنشطة',
    content: (s) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s.data!['canCreate'] == true)
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('تنظيم فعالية'),
            onPressed: () => s.action(() async {
              final data = await showDialog<Json>(
                context: s.context,
                builder: (_) => EventEditor(api: api),
              );
              if (data != null) {
                await api.call('/product/events', method: 'POST', body: data);
              }
            }),
          ),
        ...(s.data!['items'] as List).map(
          (e) => Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e['title'],
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(e['text']),
                  Text('المكان: ${e['location']}'),
                  Text('تبدأ: ${DateTime.parse(e['starts']).toLocal()}'),
                  Text('المسجلون: ${e['registered']} / ${e['capacity']}'),
                  if (e['cancelled'] == true)
                    const Text(
                      'الفعالية ملغاة',
                      style: TextStyle(color: Colors.redAccent),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(
                          onPressed: () => s.action(() async {
                            await api.call(
                              '/product/events/${e['id']}/${e['mine'] == null ? 'register' : 'unregister'}',
                              method: 'POST',
                              body: {},
                            );
                          }),
                          child: Text(
                            e['mine'] == null
                                ? 'التسجيل في الفعالية'
                                : 'إلغاء تسجيلي',
                          ),
                        ),
                        if (e['mine'] != null && e['mine']['attended'] != true)
                          OutlinedButton(
                            onPressed: () => s.action(() async {
                              final f = await askFields(
                                s.context,
                                'تسجيل الحضور',
                                {'code': 'رمز الحضور من المنظم'},
                              );
                              if (f != null) {
                                await api.call(
                                  '/product/events/${e['id']}/checkin',
                                  method: 'POST',
                                  body: f,
                                );
                              }
                            }),
                            child: const Text('تأكيد الحضور'),
                          ),
                        if (e['mine']?['attended'] == true)
                          const Chip(label: Text('تم تسجيل حضورك')),
                      ],
                    ),
                  if (e['canManage'] == true) ...[
                    const Divider(),
                    SelectableText('رمز الحضور: ${e['checkinCode']}'),
                    Wrap(
                      children: [
                        TextButton(
                          onPressed: () => openPage(
                            s.context,
                            RemotePanel(
                              api: api,
                              path: '/product/events/${e['id']}/registrations',
                              title: 'قائمة الحضور',
                              content: (s) => Column(
                                children: [
                                  ...(s.data!['items'] as List).map(
                                    (r) => ListTile(
                                      title: Text(r['person']['name']),
                                      subtitle: Text(
                                        r['attended'] == true
                                            ? 'حضر'
                                            : r['status'],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          child: const Text('قائمة المسجلين'),
                        ),
                        TextButton(
                          onPressed: () => s.action(() async {
                            final data = await showDialog<Json>(
                              context: s.context,
                              builder: (_) => EventEditor(api: api, initial: e),
                            );
                            if (data != null) {
                              await api.call(
                                '/product/events/${e['id']}',
                                method: 'PATCH',
                                body: data,
                              );
                            }
                          }),
                          child: const Text('تعديل'),
                        ),
                        TextButton(
                          onPressed: () => s.action(() async {
                            if (await confirm(
                              s.context,
                              'إلغاء الفعالية وإبلاغ المسجلين؟',
                            )) {
                              await api.call(
                                '/product/events/${e['id']}/cancel',
                                method: 'POST',
                                body: {},
                              );
                            }
                          }),
                          child: const Text('إلغاء الفعالية'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class EventEditor extends StatefulWidget {
  final Api api;
  final Json? initial;
  const EventEditor({super.key, required this.api, this.initial});
  @override
  State<EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<EventEditor> {
  late final name = TextEditingController(text: widget.initial?['title']),
      text = TextEditingController(text: widget.initial?['text']),
      location = TextEditingController(text: widget.initial?['location']),
      capacity = TextEditingController(
        text: '${widget.initial?['capacity'] ?? 30}',
      );
  late DateTime start = widget.initial?['starts'] == null
          ? DateTime.now().add(const Duration(days: 1))
          : DateTime.parse(widget.initial!['starts']).toLocal(),
      end = widget.initial?['ends'] == null
          ? DateTime.now().add(const Duration(days: 1, hours: 2))
          : DateTime.parse(widget.initial!['ends']).toLocal();
  List sections = [];
  String? section;
  String? error;
  @override
  void initState() {
    super.initState();
    section = widget.initial?['section'];
    widget.api
        .call('/courses')
        .then((r) {
          if (mounted) setState(() => sections = r['sections']);
        })
        .catchError((Object e) {
          if (mounted) setState(() => error = '$e');
        });
  }

  @override
  void dispose() {
    for (final c in [name, text, location, capacity]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<DateTime?> pick(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    return time == null
        ? null
        : DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? 'تنظيم فعالية' : 'تعديل الفعالية'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.redAccent)),
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'اسم الفعالية'),
          ),
          TextField(
            controller: text,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'تفاصيل الفعالية'),
          ),
          TextField(
            controller: location,
            decoration: const InputDecoration(labelText: 'المكان'),
          ),
          TextField(
            controller: capacity,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'عدد الأماكن'),
          ),
          TextButton(
            onPressed: () async {
              final d = await pick(start);
              if (d != null) setState(() => start = d);
            },
            child: Text('البداية: $start'),
          ),
          TextButton(
            onPressed: () async {
              final d = await pick(end);
              if (d != null) setState(() => end = d);
            },
            child: Text('النهاية: $end'),
          ),
          DropdownButtonFormField<String>(
            initialValue: section,
            decoration: const InputDecoration(labelText: 'الجمهور'),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('كل المؤسسة'),
              ),
              ...sections.map(
                (s) => DropdownMenuItem<String>(
                  value: s['id'],
                  child: Text('${s['courseName']} / ${s['name']}'),
                ),
              ),
            ],
            onChanged: (v) => section = v,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, {
          'title': name.text,
          'text': text.text,
          'location': location.text,
          'capacity': int.tryParse(capacity.text),
          'starts': start.toUtc().toIso8601String(),
          'ends': end.toUtc().toIso8601String(),
          'section': section,
        }),
        child: const Text('حفظ'),
      ),
    ],
  );
}

Widget groupInvitesPage(Api api) => RemotePanel(
  api: api,
  path: '/product/group-invites',
  title: 'دعوات المجموعات',
  content: (s) => Column(
    children: [
      if ((s.data!['items'] as List).isEmpty) const Text('لا توجد دعوات معلقة'),
      for (final item in s.data!['items'])
        Card(
          child: ListTile(
            title: Text(item['groupName']),
            subtitle: Text('دعوة من ${item['person']['name']}'),
            trailing: Wrap(
              children: [
                for (final accept in [true, false])
                  TextButton(
                    onPressed: () => s.action(() async {
                      await api.call(
                        '/product/group-invites/${item['id']}',
                        method: 'POST',
                        body: {'accept': accept},
                      );
                    }),
                    child: Text(accept ? 'قبول' : 'رفض'),
                  ),
              ],
            ),
          ),
        ),
    ],
  ),
);
Widget gameHistoryPage(Api api) => RemotePanel(
  api: api,
  path: '/product/games/history',
  title: 'سجل المباريات',
  content: (s) => Column(
    children: [
      if ((s.data!['items'] as List).isEmpty)
        const Text('لم تنتهِ مباريات بعد'),
      for (final game in s.data!['items'])
        Card(
          child: ListTile(
            leading: const Icon(Icons.sports_esports),
            title: Text(
              game['state'] == 'finished'
                  ? (game['winner'] == 'draw' ? 'تعادل' : 'انتهت المباراة')
                  : ({
                          'declined': 'الدعوة مرفوضة',
                          'expired': 'انتهت المهلة',
                          'cancelled': 'ملغاة',
                        }[game['state']] ??
                        game['state']),
            ),
            subtitle: Text(game['created'] ?? ''),
          ),
        ),
    ],
  ),
);
