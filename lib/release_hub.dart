import 'dart:convert';

import 'package:flutter/material.dart';

import 'api.dart';
import 'community.dart';
import 'design.dart';
import 'friends_page.dart';
import 'push_service.dart';

Future<Map<String, dynamic>?> releaseForm(
  BuildContext context,
  Api api,
  String title,
  Map<String, String> fields, {
  bool audience = false,
  Map<String, List<String>> choices = const {},
}) async {
  final sections = audience
      ? ((await api.call('/courses'))['sections'] as List)
      : <dynamic>[];
  if (!context.mounted) return null;
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => ReleaseForm(
      title: title,
      fields: fields,
      choices: choices,
      sections: sections,
      audience: audience,
    ),
  );
}

class ReleaseForm extends StatefulWidget {
  final String title;
  final Map<String, String> fields;
  final Map<String, List<String>> choices;
  final List<dynamic> sections;
  final bool audience;
  const ReleaseForm({
    super.key,
    required this.title,
    required this.fields,
    required this.choices,
    this.sections = const [],
    this.audience = false,
  });
  @override
  State<ReleaseForm> createState() => _ReleaseFormState();
}

class _ReleaseFormState extends State<ReleaseForm> {
  late final Map<String, TextEditingController> controls;
  final Map<String, String> selected = {};
  String section = 'all';
  String? error;
  @override
  void initState() {
    super.initState();
    controls = {for (final k in widget.fields.keys) k: TextEditingController()};
    for (final e in widget.choices.entries) {
      selected[e.key] = e.value.first;
    }
  }

  @override
  void dispose() {
    for (final c in controls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...widget.fields.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: TextField(
                    controller: controls[e.key],
                    maxLength: e.key == 'data' ? 3000 : 250,
                    maxLines: e.key == 'options' ? 5 : 1,
                    obscureText: e.key == 'password',
                    decoration: InputDecoration(labelText: e.value),
                  ),
                ),
              ),
              ...widget.choices.entries.map(
                (e) => DropdownButtonFormField<String>(
                  initialValue: selected[e.key],
                  isExpanded: true,
                  items: e.value
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => setState(() => selected[e.key] = v!),
                  decoration: InputDecoration(
                    labelText: e.key == 'kind' ? 'نوع المؤسسة' : 'اختيار',
                  ),
                ),
              ),
              if (widget.audience)
                DropdownButtonFormField<String>(
                  initialValue: section,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'الجمهور'),
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('كل المؤسسة · المدارس تتطلب شعبة'),
                    ),
                    ...widget.sections
                        .where((s) => s['active'] == true)
                        .map(
                          (s) => DropdownMenuItem(
                            value: s['id'] as String,
                            child: Text('${s['courseName']} · ${s['name']}'),
                          ),
                        ),
                  ],
                  onChanged: (v) => setState(() => section = v!),
                ),
              if (error != null) Text(error!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () {
            if (controls.values.any((c) => c.text.trim().isEmpty)) {
              setState(() => error = 'أكمل البيانات المطلوبة');
              return;
            }
            Navigator.pop(context, {
              for (final e in controls.entries) e.key: e.value.text.trim(),
              ...selected,
              if (widget.audience) 'section': section == 'all' ? null : section,
            });
          },
          child: const Text('تأكيد'),
        ),
      ],
    ),
  );
}

Widget documentPage(Api api) => RemotePanel(
  api: api,
  path: '/documents',
  title: 'المستندات',
  content: (s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'شارك PDF أو Word أو نصًا حتى ١٠ ميجابايت. ملفات الشُعب للمسجلين فيها فقط.',
        style: TextStyle(color: ClubStyle.muted),
      ),
      FilledButton.icon(
        onPressed: () async {
          try {
            final target = await releaseForm(
              s.context,
              api,
              'مشاركة مستند',
              {},
              audience: true,
            );
            if (target == null) return;
            final file = await Api.storage.invokeMapMethod<String, dynamic>(
              'pickDocument',
            );
            if (file == null || !s.mounted) return;
            await s.action(() async {
              await api.call(
                '/documents',
                method: 'POST',
                body: {
                  'name': file['name'],
                  'data': file['data'],
                  'section': target['section'],
                },
              );
            });
          } catch (e) {
            if (s.mounted) {
              ScaffoldMessenger.of(s.context)
                  .showSnackBar(SnackBar(content: Text('$e')));
            }
          }
        },
        icon: const Icon(Icons.upload_file),
        label: const Text('إضافة مستند'),
      ),
      if ((s.data!['items'] as List).isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('لا توجد مستندات بعد'),
        ),
      ...(s.data!['items'] as List).map(
        (d) => Card(
          child: ListTile(
            leading: const Icon(
              Icons.description_outlined,
              color: ClubStyle.cyan,
            ),
            title: Text(d['name'] as String),
            subtitle: Text(
              '${d['author']['name']} · ${(d['size'] / 1024).round()} كيلوبايت',
            ),
            trailing: Wrap(
              children: [
                IconButton(
                  tooltip: 'حفظ المستند',
                  icon: const Icon(Icons.download),
                  onPressed: () => s.action(() async {
                    final bytes = await api.binary(
                      '/documents/${d['id']}/content',
                    );
                    await Api.storage.invokeMethod('saveDocument', {
                      'name': d['name'],
                      'mime': d['mime'],
                      'data': base64Encode(bytes),
                    });
                  }),
                ),
                if (d['canDelete'] == true)
                  IconButton(
                    tooltip: 'حذف المستند',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await confirm(
                        s.context,
                        'حذف المستند؟',
                        'سيتم حذفه من التخزين النشط.',
                      )) {
                        await s.action(() async {
                          await api.call(
                            '/documents/${d['id']}',
                            method: 'DELETE',
                          );
                        });
                      }
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    ],
  ),
);

Widget pollsPage(Api api) => RemotePanel(
  api: api,
  path: '/polls',
  title: 'الاستطلاعات',
  content: (s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton.icon(
        onPressed: () async {
          final b = await releaseForm(s.context, api, 'استطلاع جديد', {
            'question': 'السؤال',
            'options': 'كل خيار في سطر مستقل',
          }, audience: true);
          if (b == null) return;
          await s.action(() async {
            await api.call(
              '/polls',
              method: 'POST',
              body: {
                ...b,
                'options': (b['options'] as String)
                    .split('\n')
                    .where((v) => v.trim().isNotEmpty)
                    .toList(),
              },
            );
          });
        },
        icon: const Icon(Icons.poll_outlined),
        label: const Text('إنشاء استطلاع'),
      ),
      if ((s.data!['items'] as List).isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('لا توجد استطلاعات بعد'),
        ),
      ...(s.data!['items'] as List).map(
        (p) => Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  p['question'] as String,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${p['author']['name']} · ${p['total']} صوت${p['closed'] == true ? ' · مغلق' : ''}',
                  style: const TextStyle(color: ClubStyle.muted),
                ),
                ...List.generate(
                  (p['options'] as List).length,
                  (i) => Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: OutlinedButton(
                      onPressed: p['closed'] == true
                          ? null
                          : () => s.action(() async {
                              await api.call(
                                '/polls/${p['id']}/vote',
                                method: 'POST',
                                body: {'choice': i},
                              );
                            }),
                      child: Row(
                        children: [
                          if (p['myVote'] == i)
                            const Icon(
                              Icons.check_circle,
                              color: ClubStyle.cyan,
                            ),
                          Expanded(child: Text(p['options'][i] as String)),
                          Text('${p['counts'][i]}'),
                        ],
                      ),
                    ),
                  ),
                ),
                if (p['canClose'] == true && p['closed'] != true)
                  TextButton(
                    onPressed: () => s.action(() async {
                      await api.call('/polls/${p['id']}/close', method: 'POST');
                    }),
                    child: const Text('إغلاق الاستطلاع'),
                  ),
              ],
            ),
          ),
        ),
      ),
    ],
  ),
);

Widget reportsPage(Api api) => RemotePanel(
  api: api,
  path: '/announcement-reports',
  title: 'تقارير وصول الإعلانات',
  content: (s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'النسب للطلاب الحاليين المؤهلين لرؤية الإعلان. زمن المشاهدة يُسجّل من هذا الإصدار؛ لا تُختلق أزمنة للإعلانات القديمة.',
        style: TextStyle(color: ClubStyle.muted),
      ),
      if ((s.data!['items'] as List).isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('انشر إعلانًا لتظهر نتائجه هنا'),
        ),
      ...(s.data!['items'] as List).map(
        (a) => Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  a['text'] as String,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                Text(
                  '${a['seen']} من ${a['eligible']} طالب · ${a['percent']}٪',
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: ClubStyle.cyan,
                  ),
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(value: (a['percent'] as num) / 100),
                const SizedBox(height: 12),
                Text(
                  a['averageSeconds'] == null
                      ? 'لم تُسجّل أزمنة مشاهدة بعد'
                      : 'متوسط زمن الفتح: ${a['averageSeconds']} ثانية',
                  style: const TextStyle(color: ClubStyle.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  ),
);

Widget institutionsPage(Api api) => RemotePanel(
  api: api,
  path: '/institutions/manage',
  title: 'المؤسسات والمدارس',
  content: (s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton.icon(
        onPressed: () async {
          final b = await releaseForm(
            s.context,
            api,
            'إضافة مؤسسة',
            {'name': 'اسم المؤسسة'},
            choices: {
              'kind': ['مدرسة', 'جامعة'],
            },
          );
          if (b == null) return;
          await s.action(() async {
            await api.call(
              '/institutions',
              method: 'POST',
              body: {
                ...b,
                'kind': b['kind'] == 'مدرسة' ? 'school' : 'university',
              },
            );
          });
        },
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('إضافة مدرسة أو جامعة'),
      ),
      ...(s.data!['items'] as List).map(
        (i) => Card(
          child: ListTile(
            title: Text(i['name'] as String),
            subtitle: Text(i['kind'] == 'school' ? 'مدرسة' : 'جامعة'),
            trailing: TextButton(
              onPressed: () async {
                if (await confirm(
                  s.context,
                  'تبديل نطاق الإدارة؟',
                  'ستعرض محتوى هذه المؤسسة بحساب المشرف.',
                )) {
                  try {
                    await api.call(
                      '/institutions/select',
                      method: 'POST',
                      body: {'institution': i['id']},
                    );
                    if (s.mounted) Navigator.pop(s.context);
                  } catch (e) {
                    if (s.mounted) {
                      ScaffoldMessenger.of(s.context)
                          .showSnackBar(SnackBar(content: Text('$e')));
                    }
                  }
                }
              },
              child: const Text('إدارة'),
            ),
          ),
        ),
      ),
      const SizedBox(height: 18),
      const Text(
        'بيانات طلاب المدرسة في النطاق الحالي',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      ...(s.data!['people'] as List)
          .where(
            (p) => p['role'] == 'student' && p['institutionKind'] == 'school',
          )
          .map(
            (p) => Card(
              child: ListTile(
                title: Text(p['name'] as String),
                subtitle: Text(
                  'سنة الميلاد: ${p['birthYear'] ?? 'غير مسجلة'} · الصف: ${p['grade'] ?? 'غير مسجل'}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    final b = await releaseForm(
                      s.context,
                      api,
                      'بيانات الطالب',
                      {'birthYear': 'سنة الميلاد', 'grade': 'الصف من ١ إلى ١٢'},
                    );
                    if (b == null) return;
                    await s.action(() async {
                      await api.call(
                        '/institutions/students/${p['id']}',
                        method: 'PATCH',
                        body: {
                          'birthYear': int.tryParse(b['birthYear']),
                          'grade': int.tryParse(b['grade']),
                        },
                      );
                    });
                  },
                ),
              ),
            ),
          ),
    ],
  ),
);

Widget servicePage(Api api) => RemotePanel(
  api: api,
  path: '/services',
  title: 'البريد وإشعارات الهاتف',
  content: (s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Card(
        child: ListTile(
          leading: const Icon(Icons.mark_email_read_outlined),
          title: Text(
            s.data!['emailVerified'] == true ? 'البريد مؤكد' : 'تأكيد بريدك',
          ),
          subtitle: Text(
            s.data!['mail'] == 'outbox'
                ? 'وضع تجربة: الرسائل محفوظة في صندوق البريد المحلي على الكمبيوتر، ولا تصل لبريدك الحقيقي.'
                : 'إرسال عبر خدمة البريد المجهزة',
          ),
        ),
      ),
      FilledButton(
        onPressed: () => s.action(() async {
          final response = await api.call(
            '/email/verify/request',
            method: 'POST',
          );
          if (s.mounted) {
            ScaffoldMessenger.of(s.context).showSnackBar(
              SnackBar(
                content: Text(
                  response['delivery'] == 'outbox'
                      ? 'الكود جاهز في صندوق البريد المحلي على الكمبيوتر'
                      : 'تم طلب إرسال كود التأكيد',
                ),
              ),
            );
          }
        }),
        child: const Text('طلب كود التأكيد'),
      ),
      OutlinedButton(
        onPressed: () async {
          final b = await releaseForm(s.context, api, 'تأكيد البريد', {
            'code': 'كود التأكيد',
          });
          if (b != null) {
            await s.action(() async {
              await api.call('/email/verify/confirm', method: 'POST', body: b);
            });
          }
        },
        child: const Text('إدخال كود التأكيد'),
      ),
      const SizedBox(height: 24),
      Text(
        s.data!['pushConfigured'] == true
            ? 'إشعارات الهاتف جاهزة للربط'
            : 'إشعارات الهاتف غير مفعّلة بعد',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      FilledButton.icon(
        onPressed: () async {
          try {
            await PushService.enable(api);
            if (s.mounted) {
              ScaffoldMessenger.of(s.context).showSnackBar(
                const SnackBar(content: Text('تم تسجيل الجهاز للإشعارات')),
              );
            }
          } catch (e) {
            if (s.mounted) {
              ScaffoldMessenger.of(s.context)
                  .showSnackBar(SnackBar(content: Text('$e')));
            }
          }
        },
        icon: const Icon(Icons.notifications_active_outlined),
        label: const Text('تفعيل إشعارات الهاتف'),
      ),
    ],
  ),
);

Widget tournamentsPage(Api api) => RemotePanel(
  api: api,
  path: '/tournaments',
  title: 'البطولات',
  content: (s) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'بطولة XO بنظام كل لاعب ضد الآخرين، من لاعبين إلى ٨. الفوز ٣ نقاط والتعادل نقطة.',
        style: TextStyle(color: ClubStyle.muted),
      ),
      if (s.data!['canCreate'] == true)
        FilledButton.icon(
          onPressed: () async {
            final b = await releaseForm(s.context, api, 'إنشاء بطولة', {
              'title': 'اسم البطولة',
            }, audience: true);
            if (b != null) {
              await s.action(() async {
                await api.call('/tournaments', method: 'POST', body: b);
              });
            }
          },
          icon: const Icon(Icons.emoji_events_outlined),
          label: const Text('بطولة جديدة'),
        ),
      OutlinedButton(
        onPressed: () =>
            openPage(s.context, FriendsPage(api: api, showGames: true)),
        child: const Text('افتح مبارياتي'),
      ),
      if ((s.data!['items'] as List).isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('لا توجد بطولات بعد'),
        ),
      ...(s.data!['items'] as List).map(
        (t) => Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t['title'] as String,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  t['state'] == 'open'
                      ? 'التسجيل مفتوح'
                      : t['finished'] == true
                      ? 'انتهت المباريات'
                      : 'البطولة جارية',
                  style: const TextStyle(color: ClubStyle.cyan),
                ),
                ...(t['players'] as List).map(
                  (p) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(p['person']['name'] as String),
                    trailing: Text(
                      '${p['points']} نقطة · ${p['played']} مباراة',
                    ),
                  ),
                ),
                if (t['state'] == 'open')
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => s.action(() async {
                          await api.call(
                            '/tournaments/${t['id']}/join',
                            method: 'POST',
                          );
                        }),
                        child: Text(t['joined'] == true ? 'انسحاب' : 'انضمام'),
                      ),
                      if (t['canManage'] == true)
                        FilledButton(
                          onPressed: () => s.action(() async {
                            await api.call(
                              '/tournaments/${t['id']}/start',
                              method: 'POST',
                            );
                          }),
                          child: const Text('بدء البطولة'),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    ],
  ),
);
