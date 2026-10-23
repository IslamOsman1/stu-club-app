import 'package:flutter/material.dart';

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
        builder: (_) => AnnouncementComposer(groups: targets),
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
  const AnnouncementComposer({super.key, required this.groups});
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
  }

  bool pinned = false;
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
              Navigator.pop(context, {
                'text': text.text.trim(),
                'section': group.startsWith('section:')
                    ? group.substring(8)
                    : null,
                'pinned': pinned,
              });
            }
          },
          child: const Text('نشر'),
        ),
      ],
    ),
  );
}
