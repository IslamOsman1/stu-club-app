import 'package:flutter/material.dart';

import 'dart:convert';

import 'api.dart';
import 'design.dart';
import 'course_page.dart';

class AcademicPanel extends StatefulWidget {
  final Api api;
  const AcademicPanel({super.key, required this.api});
  @override
  State<AcademicPanel> createState() => _AcademicPanelState();
}

class _AcademicPanelState extends State<AcademicPanel> {
  List<dynamic> items = [];
  bool publish = false, loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await widget.api.call('/announcements');
      if (mounted) {
        setState(() {
          items = r['items'] as List;
          publish = r['canPublish'] == true;
          error = null;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'تعذر تحميل الإعلانات';
          loading = false;
        });
      }
    }
  }

  Future<void> create() async {
    try {
      final academic = await widget.api.call('/courses');
      final isAdmin = academic['isAdmin'] == true;
      final sections = (academic['sections'] as List)
          .where((s) => s['active'] == true && s['canPublish'] == true)
          .toList();
      final targets = <Map<String, dynamic>>[
        if (isAdmin) {'value': 'all', 'name': 'كل المؤسسة'},
        ...sections.map(
          (s) => {
            'value': 'section:${s['id']}',
            'name': '${s['courseName']} · ${s['name']}',
          },
        ),
      ];
      if (targets.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لم يتم تكليفك بشعبة بعد. تواصل مع المشرف.'),
            ),
          );
        }
        return;
      }
      if (!mounted) return;
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => AnnouncementComposer(groups: targets, api: widget.api),
      );
      if (result == null) return;
      await widget.api.call('/announcements', method: 'POST', body: result);
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> open(Map<String, dynamic> a) async {
    try {
      await widget.api.call('/announcements/${a['id']}/view', method: 'POST');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${a['author']['name']} · إعلان رسمي'),
          content: SingleChildScrollView(
            child: Text('${a['audience'] ?? 'إعلان المؤسسة'}\n\n${a['text']}'),
          ),
          actions: [
            if (a['document'] != null)
              TextButton.icon(
                icon: const Icon(Icons.download),
                label: const Text('تحميل المرفق'),
                onPressed: () async {
                  try {
                    final docs =
                        (await widget.api.call('/documents'))['items'] as List;
                    final doc = docs
                        .where((d) => d['id'] == a['document'])
                        .firstOrNull;
                    if (doc == null) throw ApiException('المرفق لم يعد متاحًا');
                    final bytes = await widget.api.binary(
                      '/documents/${doc['id']}/content',
                    );
                    await Api.storage.invokeMethod('saveDocument', {
                      'name': doc['name'],
                      'mime': doc['mime'],
                      'data': base64Encode(bytes),
                    });
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx)
                          .showSnackBar(SnackBar(content: Text('$e')));
                    }
                  }
                },
              ),
            if (a.containsKey('viewCount'))
              TextButton(
                onPressed: () async {
                  try {
                    await widget.api.call(
                      '/announcements/${a['id']}',
                      method: 'PATCH',
                      body: {'pinned': a['pinned'] != true},
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('$e')));
                    }
                  }
                },
                child: Text(a['pinned'] == true ? 'إلغاء التثبيت' : 'تثبيت'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('تم'),
            ),
          ],
        ),
      );
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF28105C), Color(0xFF101C46)],
      ),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: ClubStyle.green),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.campaign_rounded, color: ClubStyle.cyan),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'مايفوتكش إعلان',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
            ),
            IconButton(
              tooltip: 'المواد والشُعب',
              onPressed: () async {
                await Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Directionality(
                      textDirection: TextDirection.rtl,
                      child: CoursePage(api: widget.api),
                    ),
                  ),
                );
                await load();
              },
              icon: const Icon(Icons.class_outlined, size: 20),
            ),
            IconButton(
              tooltip: 'تحديث الإعلانات',
              onPressed: load,
              icon: const Icon(Icons.refresh, size: 20),
            ),
            if (publish)
              IconButton(
                tooltip: 'نشر إعلان رسمي',
                onPressed: create,
                icon: const Icon(Icons.add_circle, color: ClubStyle.cyan),
              ),
          ],
        ),
        const Text(
          'إعلانات معتمدة من مدرسيك ودكاترتك',
          style: TextStyle(color: ClubStyle.muted, fontSize: 12),
        ),
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          TextButton(onPressed: load, child: Text('$error · إعادة المحاولة')),
        if (!loading && error == null && items.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text('لما ينزل إعلان يخصك، هتلاقيه هنا.'),
          ),
        if (items.isNotEmpty)
          SizedBox(
            height: 174,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, index) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final a = items[i] as Map<String, dynamic>;
                return SizedBox(
                  width: 220,
                  child: InkWell(
                    onTap: () => open(a),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      margin: const EdgeInsets.only(top: 14),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: ClubStyle.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: a['seen'] == true
                              ? ClubStyle.line
                              : ClubStyle.cyan,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.verified,
                                size: 16,
                                color: ClubStyle.cyan,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  a['author']['name'] as String,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (a['pinned'] == true)
                                const Icon(Icons.push_pin, size: 15),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: Text(
                              a['text'] as String,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            a.containsKey('viewCount')
                                ? '${a['viewCount']} مشاهدة'
                                : a['seen'] == true
                                ? 'تمت المشاهدة'
                                : 'إعلان جديد',
                            style: const TextStyle(
                              color: ClubStyle.cyan,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    ),
  );
}

class AnnouncementComposer extends StatefulWidget {
  final List<dynamic> groups;
  final Api? api;
  const AnnouncementComposer({super.key, required this.groups, this.api});
  @override
  State<AnnouncementComposer> createState() => _AnnouncementComposerState();
}

class _AnnouncementComposerState extends State<AnnouncementComposer> {
  final text = TextEditingController();
  late String group;
  @override
  void initState() {
    super.initState();
    group = widget.groups.first['value'] as String;
    widget.api
        ?.call('/documents')
        .then((r) {
          if (mounted) setState(() => documents = r['items']);
        })
        .catchError((Object e) {
          if (mounted) setState(() => attachmentError = '$e');
        });
  }

  bool pinned = false;
  DateTime? publishAt, expiresAt;
  String importance = 'normal';
  List documents = [];
  String? document, attachmentError;
  Future<void> chooseDate(bool expiry) async {
    final current = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: (expiry ? expiresAt : publishAt) ?? current,
      firstDate: current,
      lastDate: current.add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null || !mounted) return;
    final value = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (expiry) {
        expiresAt = value;
      } else {
        publishAt = value;
      }
    });
  }

  String dateLabel(DateTime? value, String fallback) => value == null
      ? fallback
      : '${value.year}/${value.month}/${value.day} ${value.hour}:${value.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: AlertDialog(
      title: const Text('إعلان أكاديمي رسمي'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: text,
              maxLines: 5,
              maxLength: 3000,
              decoration: const InputDecoration(labelText: 'نص الإعلان'),
            ),
            DropdownButtonFormField<String>(
              initialValue: group,
              isExpanded: true,
              items: [
                ...widget.groups.map(
                  (g) => DropdownMenuItem(
                    value: g['value'] as String,
                    child: Text(g['name'] as String),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => group = v!),
              decoration: const InputDecoration(labelText: 'الجمهور'),
            ),
            DropdownButtonFormField<String>(
              initialValue: importance,
              decoration: const InputDecoration(labelText: 'أهمية الإعلان'),
              items: const [
                DropdownMenuItem(value: 'normal', child: Text('عادي')),
                DropdownMenuItem(value: 'important', child: Text('مهم')),
                DropdownMenuItem(value: 'urgent', child: Text('عاجل')),
              ],
              onChanged: (v) => setState(() => importance = v!),
            ),
            ListTile(
              title: const Text('موعد النشر'),
              subtitle: Text(dateLabel(publishAt, 'النشر فورًا')),
              onTap: () => chooseDate(false),
              trailing: publishAt == null
                  ? const Icon(Icons.schedule)
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => publishAt = null),
                    ),
            ),
            ListTile(
              title: const Text('انتهاء الإعلان'),
              subtitle: Text(dateLabel(expiresAt, 'بدون انتهاء')),
              onTap: () => chooseDate(true),
              trailing: expiresAt == null
                  ? const Icon(Icons.event)
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => expiresAt = null),
                    ),
            ),
            if (attachmentError != null)
              Text(
                attachmentError!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            DropdownButtonFormField<String>(
              initialValue: document,
              decoration: const InputDecoration(
                labelText: 'مستند مرفق (اختياري)',
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('بدون مرفق'),
                ),
                for (final d in documents)
                  DropdownMenuItem(
                    value: d['id'] as String,
                    child: Text(d['name']),
                  ),
              ],
              onChanged: (v) => document = v,
            ),
            SwitchListTile(
              title: const Text('تثبيت الإعلان'),
              value: pinned,
              onChanged: (v) => setState(() => pinned = v),
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
          onPressed: () {
            if (text.text.trim().isNotEmpty) {
              if (expiresAt != null &&
                  !expiresAt!.isAfter(publishAt ?? DateTime.now())) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('الانتهاء يجب أن يكون بعد النشر'),
                  ),
                );
                return;
              }
              Navigator.pop(context, {
                'text': text.text.trim(),
                'section': group.startsWith('section:')
                    ? group.substring(8)
                    : null,
                'pinned': pinned,
                'importance': importance,
                'document': document,
                'publishAt': publishAt?.toUtc().toIso8601String(),
                'expiresAt': expiresAt?.toUtc().toIso8601String(),
              });
            }
          },
          child: const Text('نشر'),
        ),
      ],
    ),
  );
}
