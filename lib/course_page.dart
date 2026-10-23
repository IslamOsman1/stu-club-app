import 'package:flutter/material.dart';

import 'api.dart';
import 'design.dart';

class CoursePage extends StatefulWidget {
  final Api api;
  const CoursePage({super.key, required this.api});
  @override
  State<CoursePage> createState() => _CoursePageState();
}

class _CoursePageState extends State<CoursePage> {
  Map<String, dynamic>? data;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await widget.api.call('/courses');
      if (mounted) {
        setState(() {
          data = r;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> act(Future<void> Function() f) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await f();
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> createCourse() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const CourseComposer(),
    );
    if (result != null) {
      await act(() async {
        await widget.api.call('/courses', method: 'POST', body: result);
      });
    }
  }

  Future<void> editSection(
    Map<String, dynamic> course, [
    Map<String, dynamic>? section,
  ]) async {
    await act(() async {
      final people =
          (await widget.api.call('/courses/people'))['items'] as List;
      if (!mounted) return;
      setState(() => busy = false);
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => SectionComposer(
          people: people,
          section: section,
          courseName: course['name'] as String,
        ),
      );
      if (result == null || !mounted) return;
      setState(() => busy = true);
      await widget.api.call(
        section == null
            ? '/courses/${course['id']}/sections'
            : '/sections/${section['id']}',
        method: section == null ? 'POST' : 'PATCH',
        body: result,
      );
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('المواد والشُعب'),
      actions: [
        IconButton(
          tooltip: 'تحديث المواد',
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: AbsorbPointer(
      absorbing: busy,
      child: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              TextButton(
                onPressed: load,
                child: Text('$error · إعادة المحاولة'),
              ),
            if (data == null && error == null)
              const Center(child: CircularProgressIndicator()),
            if (data != null) ...[
              Text(
                data!['isAdmin'] == true
                    ? 'إدارة التسجيل الأكاديمي'
                    : 'موادّي وشُعبي',
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'التسجيل وتعيين المدرسين بواسطة المشرف. عضوية المجموعة الاجتماعية لا تسجلك في مادة.',
                style: TextStyle(color: ClubStyle.muted),
              ),
              const SizedBox(height: 18),
              if (data!['isAdmin'] == true)
                FilledButton.icon(
                  onPressed: createCourse,
                  icon: const Icon(Icons.add),
                  label: const Text('إنشاء مادة'),
                ),
              if ((data!['items'] as List).isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Text('لا توجد مواد مسجّلة بعد. تواصل مع مشرف مؤسستك.'),
                ),
              ...(data!['items'] as List).map((raw) {
                final c = raw as Map<String, dynamic>;
                final sections = (data!['sections'] as List)
                    .where((s) => s['course'] == c['id'])
                    .toList();
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${c['code']} · ${c['name']}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (data!['isAdmin'] == true)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => editSection(c),
                              icon: const Icon(Icons.add),
                              label: const Text('إضافة شعبة'),
                            ),
                          ),
                        if (sections.isEmpty)
                          const Text(
                            'لم تُنشأ شعب لهذه المادة بعد',
                            style: TextStyle(color: ClubStyle.muted),
                          ),
                        ...sections.map(
                          (s) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              s['active'] == true
                                  ? Icons.class_outlined
                                  : Icons.archive_outlined,
                              color: ClubStyle.cyan,
                            ),
                            title: Text(
                              '${s['name']}${s['active'] == true ? '' : ' · مؤرشفة'}',
                            ),
                            subtitle: Text(
                              '${(s['teachers'] as List).map((t) => t['name']).join('، ')}\n${s['studentCount']} طالب',
                            ),
                            isThreeLine: true,
                            trailing: data!['isAdmin'] == true
                                ? IconButton(
                                    tooltip: 'تعديل الشعبة والتسجيل',
                                    onPressed: () => editSection(
                                      c,
                                      s as Map<String, dynamic>,
                                    ),
                                    icon: const Icon(Icons.edit_outlined),
                                  )
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    ),
  );
}

class CourseComposer extends StatefulWidget {
  const CourseComposer({super.key});
  @override
  State<CourseComposer> createState() => _CourseComposerState();
}

class _CourseComposerState extends State<CourseComposer> {
  final name = TextEditingController(), code = TextEditingController();
  String? error;
  @override
  void dispose() {
    name.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: AlertDialog(
      title: const Text('إنشاء مادة'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'اسم المادة'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: code,
              maxLength: 30,
              decoration: const InputDecoration(
                labelText: 'رمز المادة · CS101',
              ),
            ),
            if (error != null) Text(error!),
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
            if (name.text.trim().isEmpty || code.text.trim().isEmpty) {
              setState(() => error = 'أدخل الاسم والرمز');
              return;
            }
            Navigator.pop(context, {
              'name': name.text.trim(),
              'code': code.text.trim(),
            });
          },
          child: const Text('إنشاء'),
        ),
      ],
    ),
  );
}

class SectionComposer extends StatefulWidget {
  final List<dynamic> people;
  final Map<String, dynamic>? section;
  final String courseName;
  const SectionComposer({
    super.key,
    required this.people,
    this.section,
    required this.courseName,
  });
  @override
  State<SectionComposer> createState() => _SectionComposerState();
}

class _SectionComposerState extends State<SectionComposer> {
  late final TextEditingController name;
  late Set<String> teachers, students;
  bool active = true;
  String query = '';
  String? error;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(
      text: widget.section?['name'] as String? ?? '',
    );
    teachers = (widget.section?['teachers'] as List? ?? [])
        .map((p) => p['id'] as String)
        .toSet();
    students = (widget.section?['students'] as List? ?? [])
        .map((p) => p['id'] as String)
        .toSet();
    active = widget.section?['active'] != false;
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Widget choices(bool teaching) {
    final selected = teaching ? teachers : students;
    final people = widget.people
        .where(
          (p) =>
              ((teaching
                      ? p['role'] == 'doctor' && p['verified'] == true
                      : p['role'] == 'student') ||
                  selected.contains(p['id'])) &&
              '${p['name']} ${p['email']}'.toLowerCase().contains(
                query.toLowerCase(),
              ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          teaching
              ? 'المدرسون المعتمدون (${teachers.length})'
              : 'الطلاب المسجّلون (${students.length})',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        if (people.isEmpty)
          const Text(
            'لا توجد حسابات مطابقة',
            style: TextStyle(color: ClubStyle.muted),
          ),
        ...people.map(
          (p) => CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(p['name'] as String),
            subtitle: Text(
              '${p['email']}${p['disabled'] == true ? ' · موقوف' : ''}',
            ),
            value: selected.contains(p['id']),
            onChanged: (v) => setState(() {
              if (v == true && p['disabled'] != true) {
                selected.add(p['id'] as String);
              } else {
                selected.remove(p['id']);
              }
            }),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: AlertDialog(
      title: Text(
        '${widget.section == null ? 'إضافة' : 'تعديل'} شعبة · ${widget.courseName}',
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'اسم الشعبة'),
              ),
              if (widget.section != null)
                SwitchListTile(
                  title: const Text('شعبة نشطة'),
                  subtitle: const Text(
                    'إيقافها يخفي محتواها عن الطلاب والمدرسين',
                  ),
                  value: active,
                  onChanged: (v) => setState(() => active = v),
                ),
              TextField(
                onChanged: (v) => setState(() => query = v),
                decoration: const InputDecoration(
                  labelText: 'بحث بالاسم أو البريد',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 16),
              choices(true),
              const Divider(),
              choices(false),
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
            if (name.text.trim().isEmpty) {
              setState(() => error = 'أدخل اسم الشعبة');
              return;
            }
            Navigator.pop(context, {
              'name': name.text.trim(),
              'teachers': teachers.toList(),
              'students': students.toList(),
              'active': active,
            });
          },
          child: const Text('حفظ التسجيل'),
        ),
      ],
    ),
  );
}
