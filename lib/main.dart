import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'community.dart';
import 'media_widgets.dart';
import 'design.dart';
import 'connection_settings.dart';
import 'academic_panel.dart';
import 'course_page.dart';
import 'friends_page.dart';
import 'release_hub.dart';
import 'product_center.dart';
import 'product_chat.dart';
import 'play_hub.dart';

void main() => runApp(const StuClub());
const purple = ClubStyle.green;
const navy = ClubStyle.ink;
final universities = <String, String>{};
final institutionKinds = <String, String>{};

typedef Json = Map<String, dynamic>;

class StuClub extends StatelessWidget {
  final Api? api;
  const StuClub({super.key, this.api});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'STU Club',
    theme: ClubStyle.theme(),

    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Club(api: api ?? Api()),
    ),
  );
}

class Club extends StatefulWidget {
  final Api api;
  const Club({super.key, required this.api});
  @override
  State<Club> createState() => _ClubState();
}

class _ClubState extends State<Club> {
  Api get api => widget.api;
  Json? me;
  Json? quiz;
  Json? result;
  List<dynamic> posts = [], stories = [], groups = [], leaders = [];
  bool busy = true;
  bool register = false;
  bool showPassword = false, doctorsOnly = false, searchOpen = false;
  String feedQuery = '', groupQuery = '';
  String? error;
  int page = 0;
  String university = 'cairo';
  final birthYear = TextEditingController(), grade = TextEditingController();
  final name = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController();
  @override
  void initState() {
    super.initState();
    bootstrap();
  }

  @override
  void dispose() {
    birthYear.dispose();
    grade.dispose();
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> bootstrap() async {
    await run(() async {
      await api.restore();
      await loadInstitutions();
      if (api.token != null) {
        me = (await api.call('/me'))['user'] as Json;
        await loadInstitutions();
        await refresh();
      }
    });
  }

  Future<void> run(Future<void> Function() action) async {
    if (mounted) {
      setState(() {
        busy = true;
        error = null;
      });
    }
    try {
      await action();
    } catch (e) {
      if (e is ApiException && e.status == 401) {
        await api.clear();
        me = null;
      }
      if (mounted) {
        setState(
          () => error = e is ApiException
              ? e.message
              : 'تعذر إكمال العملية. حاول مرة أخرى.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  bool get needsApproval =>
      me != null &&
      (me!['membershipStatus'] == 'pending' ||
          ((me!['institutionKind'] == 'school' ||
                  institutionKinds[me!['university']] == 'school') &&
              me!['verified'] != true)) &&
      me!['role'] != 'admin';

  Widget approval() => card(
    Column(
      children: [
        const Icon(Icons.shield_outlined, size: 52, color: ClubStyle.cyan),
        const SizedBox(height: 16),
        const Text(
          'بانتظار اعتماد المؤسسة',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        const Text(
          'مجتمع المدرسة التجريبي يحتاج اعتماد المشرف قبل عرض المحتوى أو التواصل. أرسل طلب توثيق من هنا.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => openTool(verificationPage(api)),
          child: const Text('طلب توثيق الحساب'),
        ),
      ],
    ),
  );

  Future<void> loadInstitutions() async {
    final r = await api.call('/universities');
    if (r['items'] is List) {
      universities.clear();
      institutionKinds.clear();
      for (final i in r['items'] as List) {
        universities[i['id']] = i['name'];
        institutionKinds[i['id']] = i['kind'] ?? 'university';
      }
    }
    if (!universities.containsKey(university)) {
      university = universities.keys.firstOrNull ?? '';
    }
  }

  Future<void> refresh() async {
    if (needsApproval) {
      if (mounted) {
        setState(() {
          posts = [];
          stories = [];
          groups = [];
          leaders = [];
          quiz = null;
          result = null;
        });
      }
      return;
    }
    final data = await Future.wait([
      api.call('/feed'),
      api.call('/groups'),
      api.call('/quiz'),
      api.call('/leaderboard'),
    ]);
    if (!mounted) return;
    setState(() {
      posts = data[0]['posts'] as List;
      stories = data[0]['stories'] as List;
      groups = data[1]['items'] as List;
      if (quiz?['id'] != data[2]['id']) result = null;
      quiz = data[2];
      leaders = data[3]['items'] as List;
    });
  }

  Future<void> authenticate() async {
    if (email.text.trim().isEmpty ||
        password.text.length < 10 ||
        (register && name.text.trim().length < 2)) {
      setState(() => error = 'أدخل بياناتك، وكلمة مرور لا تقل عن ١٠ أحرف.');
      return;
    }
    await run(() async {
      final response = await api.call(
        register ? '/auth/register' : '/auth/login',
        method: 'POST',
        body: {
          'email': email.text.trim(),
          'password': password.text,
          if (register) 'name': name.text.trim(),
          if (register) 'university': university,
          if (register && institutionKinds[university] == 'school')
            'birthYear': int.tryParse(birthYear.text),
          if (register && institutionKinds[university] == 'school')
            'grade': int.tryParse(grade.text),
        },
      );
      await api.saveToken(response['token'] as String);
      me = response['user'] as Json;
      posts = [];
      stories = [];
      groups = [];
      leaders = [];
      quiz = null;
      password.clear();
      result = null;
      page = 0;
      await refresh();
    });
  }

  Future<String?> prompt(
    String title, {
    String initial = '',
    int max = 2000,
    int lines = 5,
  }) => showDialog<String>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: TextPrompt(title: title, initial: initial, max: max, lines: lines),
    ),
  );
  void toast(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text, textDirection: TextDirection.rtl)),
      );
    }
  }

  Future<void> compose(String type) async {
    final published = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: ComposeDialog(api: api, type: type),
      ),
    );
    if (published == true && mounted) await run(refresh);
  }

  Future<void> openTool(Widget tool) async {
    await openPage(context, tool);
    if (mounted && api.token != null) {
      await run(() async {
        me = (await api.call('/me'))['user'] as Json;
        await loadInstitutions();
        await refresh();
      });
    }
  }

  Future<void> delete(String type, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف المحتوى؟'),
          content: const Text('سيتم حذف هذا المحتوى من التطبيق.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    await run(() async {
      await api.call('/$type/$id', method: 'DELETE');
      await refresh();
    });
  }

  Future<void> report(String type, String id) async {
    final reason = await prompt('سبب الإبلاغ', max: 500);
    if (reason == null || reason.trim().isEmpty || !mounted) return;
    await run(() async {
      await api.call(
        '/reports',
        method: 'POST',
        body: {'type': type, 'target': id, 'reason': reason},
      );
      toast('تم حفظ البلاغ للمراجعة');
    });
  }

  Future<void> settings() async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: ConnectionSettings(api: api),
      ),
    );
    if (value == null || !mounted) return;
    await run(() async {
      if (value != api.base) {
        await api.configure(value);
        me = null;
      }
      await api.checkConnection(force: true);
      toast('الاتصال بالخادم شغال');
    });
  }

  Widget card(Widget child, {Color color = ClubStyle.surface}) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: color == ClubStyle.surface ? ClubStyle.line : color,
      ),
    ),
    child: Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    ),
  );
  Widget heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 14),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: navy,
      ),
    ),
  );
  Widget tag(
    String label, {
    Color color = ClubStyle.green,
    Color background = ClubStyle.mint,
    IconData? icon,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
        ],
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
  Widget errorNotice() => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF1E9),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFF6D8C9)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 19, color: Color(0xFFB45F36)),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                error!,
                style: const TextStyle(
                  color: Color(0xFF9C512F),
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: settings,
            icon: const Icon(Icons.network_check, size: 16),
            label: const Text('فحص الاتصال'),
          ),
        ),
      ],
    ),
  );
  Widget input(
    TextEditingController controller,
    String label, {
    bool secret = false,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 15),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          obscureText: secret && !showPassword,
          textDirection: secret || keyboard == TextInputType.emailAddress
              ? TextDirection.ltr
              : TextDirection.rtl,
          textAlign: secret || keyboard == TextInputType.emailAddress
              ? TextAlign.left
              : TextAlign.right,
          keyboardType: keyboard,
          autocorrect: !secret,
          enableSuggestions: !secret,
          decoration: InputDecoration(
            hintText: secret
                ? '••••••••••'
                : keyboard == TextInputType.emailAddress
                ? 'name@university.edu'
                : 'اكتب اسمك',
            prefixIcon: Icon(
              secret
                  ? Icons.lock_outline
                  : keyboard == TextInputType.emailAddress
                  ? Icons.alternate_email
                  : Icons.person_outline,
              size: 19,
            ),
            suffixIcon: secret
                ? IconButton(
                    tooltip: showPassword
                        ? 'إخفاء كلمة المرور'
                        : 'إظهار كلمة المرور',
                    onPressed: () =>
                        setState(() => showPassword = !showPassword),
                    icon: Icon(
                      showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 19,
                    ),
                  )
                : null,
          ),
        ),
      ],
    ),
  );
  Future<void> recoverAccount() async {
    final v = await askFields(
      context,
      'استعادة بكود احتياطي',
      {
        'email': 'البريد الإلكتروني',
        'code': 'كود الاستعادة المحفوظ',
        'newPassword': 'كلمة مرور جديدة · ١٠ أحرف على الأقل',
      },
      secrets: {'code', 'newPassword'},
      initial: {'email': email.text},
    );
    if (v == null || !mounted) return;
    await run(() async {
      await api.call('/auth/recover', method: 'POST', body: v);
      toast('تم تغيير كلمة المرور. سجّل الدخول بالكلمة الجديدة.');
    });
  }

  Widget login() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const BrandMark(size: 38),
          const SizedBox(width: 10),
          const Text(
            'STU CLUB',
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'إعداد اتصال الخادم',
            onPressed: settings,
            icon: const Icon(Icons.tune_rounded, size: 21),
          ),
        ],
      ),
      const SizedBox(height: 22),
      Container(
        height: 222 * MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.5),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF42168C), Color(0xFF172B54)],
          ),
          borderRadius: BorderRadius.circular(26),
        ),
        child: Stack(
          children: [
            const Positioned(
              left: -15,
              bottom: -5,
              width: 205,
              height: 190,
              child: CampusArt(),
            ),
            Positioned(
              top: 23,
              right: 22,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  tag(
                    'مجتمعك الطلابي',
                    color: ClubStyle.gold,
                    background: const Color(0xFF35205C),
                    icon: Icons.auto_awesome_outlined,
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    'اتواصل. العب.\nواتعلم كل يوم.',
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      height: 1.55,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const SizedBox(
                    width: 160,
                    child: Text(
                      'صحبة، معرفة، ولحظات تستاهل تتشارك.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.7,
                        color: Color(0xFFE4D9FF),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              register ? 'ابدأ حكايتك معانا' : 'أهلًا برجوعك',
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              register
                  ? 'حساب جديد، ومجتمع كامل مستنيك.'
                  : 'سجّل دخولك وارجع لمجتمعك.',
              style: const TextStyle(fontSize: 12, color: ClubStyle.muted),
            ),
            const SizedBox(height: 22),
            if (error != null) errorNotice(),
            if (register) input(name, 'اسمك'),
            input(
              email,
              'البريد الإلكتروني',
              keyboard: TextInputType.emailAddress,
            ),
            input(password, 'كلمة المرور', secret: true),
            if (register) ...[
              const Text(
                '١٠ أحرف على الأقل',
                style: TextStyle(fontSize: 10, color: ClubStyle.muted),
              ),
              const SizedBox(height: 14),
              const Text(
                'المؤسسة التعليمية',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 7),
              if (universities.isEmpty)
                const Text(
                  'لم تُضف مؤسسات متاحة بعد. تواصل مع إدارة StuClub.',
                  style: TextStyle(color: ClubStyle.muted),
                ),
              DropdownButtonFormField<String>(
                initialValue: universities.containsKey(university)
                    ? university
                    : null,
                isExpanded: true,
                items: universities.entries
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(
                          e.value,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => university = v!),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.school_outlined, size: 19),
                ),
              ),
              if (institutionKinds[university] == 'school') ...[
                input(birthYear, 'سنة الميلاد', keyboard: TextInputType.number),
                input(
                  grade,
                  'الصف من ١ إلى ١٢',
                  keyboard: TextInputType.number,
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'اختيار المؤسسة لا يساوي توثيق الحساب؛ يمكنك طلب التوثيق بعد التسجيل.',
                style: TextStyle(
                  fontSize: 10,
                  color: ClubStyle.muted,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 16),
            ] else
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: recoverAccount,
                  child: const Text('نسيت كلمة المرور؟'),
                ),
              ),
            FilledButton(
              onPressed: register && universities.isEmpty ? null : authenticate,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(register ? 'إنشاء الحساب' : 'تسجيل الدخول'),
                  const SizedBox(width: 10),
                  const Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
            if (!register)
              TextButton(
                onPressed: () async {
                  final b = await releaseForm(context, api, 'استعادة بالبريد', {
                    'email': 'البريد الإلكتروني',
                  });
                  if (b == null) return;
                  await run(() async {
                    final response = await api.call(
                      '/auth/email-reset/request',
                      method: 'POST',
                      body: b,
                    );
                    toast(
                      response['delivery'] == 'outbox'
                          ? 'وضع محلي: الكود في صندوق بريد الكمبيوتر'
                          : 'إذا كان البريد مسجلًا سيصلك كود',
                    );
                  });
                  if (!mounted) return;
                  final confirm = await releaseForm(
                    context,
                    api,
                    'كود الاستعادة',
                    {'code': 'الكود', 'password': 'كلمة المرور الجديدة'},
                  );
                  if (confirm == null) return;
                  await run(() async {
                    await api.call(
                      '/auth/email-reset/confirm',
                      method: 'POST',
                      body: {...confirm, 'email': b['email']},
                    );
                    toast('تم تغيير كلمة المرور؛ سجل الدخول من جديد');
                  });
                },
                child: const Text('استعادة عن طريق البريد'),
              ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  register ? 'عندك حساب بالفعل؟' : 'لسه جديد هنا؟',
                  style: const TextStyle(fontSize: 12, color: ClubStyle.muted),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    register = !register;
                    error = null;
                  }),
                  child: Text(register ? 'سجّل الدخول' : 'أنشئ حسابك'),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 7),
      const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.school_outlined, size: 15, color: ClubStyle.muted),
          SizedBox(width: 6),
          Text(
            'مدرستك. جامعتك. مجتمعك.',
            style: TextStyle(fontSize: 11, color: ClubStyle.muted),
          ),
        ],
      ),
      const SizedBox(height: 20),
    ],
  );

  Widget person(Json author) => InkWell(
    onTap: author['id'] == me!['id']
        ? null
        : () => openTool(DirectChat(api: api, person: author)),
    borderRadius: BorderRadius.circular(12),
    child: Row(
      children: [
        ClubAvatar(
          name: author['name'] as String,
          doctor: author['role'] == 'doctor',
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      author['name'] as String,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (author['verified'] == true) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.verified, size: 14, color: purple),
                  ],
                ],
              ),
              Text(
                author['role'] == 'doctor'
                    ? 'مدرس / دكتور'
                    : universities[me!['university']] ?? '',
                style: const TextStyle(color: ClubStyle.muted, fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> openStory(Json story) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: person(story['author'] as Json),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    story['text'] as String,
                    style: const TextStyle(fontSize: 20, height: 1.8),
                  ),
                  if (story['media'] != null)
                    MediaTile(
                      api: api,
                      id: story['media'] as String,
                      kind: story['mediaKind'] as String,
                    ),
                ],
              ),
            ),
          ),
          actions: [
            if (story['user'] == me!['id'])
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'delete'),
                child: const Text('حذف'),
              )
            else
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'report'),
                child: const Text('إبلاغ'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'delete') await delete('stories', story['id'] as String);
    if (action == 'report') await report('stories', story['id'] as String);
  }

  String when(String? value) {
    final date = DateTime.tryParse(value ?? '');
    if (date == null) return 'الآن';
    final d = DateTime.now().difference(date.toLocal());
    if (d.inMinutes < 1) return 'الآن';
    if (d.inHours < 1) return 'منذ ${d.inMinutes} دقيقة';
    if (d.inDays < 1) return 'منذ ${d.inHours} ساعة';
    return 'منذ ${d.inDays} يوم';
  }

  Widget home() {
    final visible = posts.where((raw) {
      final p = raw as Json;
      return (!doctorsOnly || p['author']['role'] == 'doctor') &&
          ('${p['text']} ${p['author']['name']}').toLowerCase().contains(
            feedQuery.toLowerCase(),
          );
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AcademicPanel(api: api),
        const SizedBox(height: 4),
        Text(
          'أهلًا، ${me!['name']} 👋',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'صحابك، ألعابك، وكل أخبار دراستك.',
          style: TextStyle(fontSize: 12, color: ClubStyle.muted),
        ),
        const SizedBox(height: 20),
        Container(
          height: 163 * MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.5),
          margin: const EdgeInsets.only(bottom: 20),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF42168C), Color(0xFF172B54)],
            ),
            borderRadius: BorderRadius.circular(23),
          ),
          child: Stack(
            children: [
              const Positioned(
                left: -12,
                bottom: -13,
                width: 170,
                height: 157,
                child: CampusArt(),
              ),
              Positioned(
                right: 20,
                top: 17,
                bottom: 15,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'تحدّي النهارده',
                      style: TextStyle(
                        color: ClubStyle.gold,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'استراحة صغيرة،\nفكرة كبيرة.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        height: 1.5,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      height: 32,
                      child: FilledButton.tonal(
                        onPressed: () => setState(() => page = 2),
                        style: FilledButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(horizontal: 13),
                          backgroundColor: const Color(0xFF252047),
                          foregroundColor: purple,
                          textStyle: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('ابدأ التحدي'),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward, size: 14),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            const Expanded(
              child: Text(
                'لحظات مجتمعك',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
            tag(
              '٢٤ ساعة',
              color: ClubStyle.muted,
              background: const Color(0xFF18152F),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 97,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 13),
                child: InkWell(
                  onTap: () => compose('stories'),
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 65,
                    child: Column(
                      children: [
                        Container(
                          height: 62,
                          width: 62,
                          decoration: BoxDecoration(
                            color: ClubStyle.surface,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: ClubStyle.line),
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            color: purple,
                            size: 25,
                          ),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'لحظتك',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (stories.isEmpty)
                const SizedBox(
                  width: 180,
                  child: Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'فيه لحظة حلوة النهارده؟\nخلي زملاءك يشوفوها.',
                      style: TextStyle(
                        color: ClubStyle.muted,
                        fontSize: 11,
                        height: 1.8,
                      ),
                    ),
                  ),
                ),
              ...stories.map((raw) {
                final s = raw as Json, a = s['author'] as Json;
                return Padding(
                  padding: const EdgeInsets.only(left: 13),
                  child: InkWell(
                    onTap: () => openStory(s),
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      width: 65,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(23),
                              border: Border.all(
                                color: a['role'] == 'doctor'
                                    ? ClubStyle.gold
                                    : purple,
                                width: 1.5,
                              ),
                            ),
                            child: ClubAvatar(
                              name: a['name'] as String,
                              doctor: a['role'] == 'doctor',
                              size: 54,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            a['name'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        card(
          InkWell(
            onTap: () => compose('posts'),
            child: Row(
              children: [
                ClubAvatar(name: me!['name'] as String, size: 37),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'عندك فكرة أو لحظة؟',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'شاركها مع مجتمعك',
                        style: TextStyle(fontSize: 10, color: ClubStyle.muted),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: ClubStyle.mint,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.add_photo_alternate_outlined,
                    color: purple,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
        Row(
          children: [
            const Expanded(
              child: Text(
                'من مجتمعك',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: 'بحث في المنشورات',
              onPressed: () => setState(() => searchOpen = !searchOpen),
              icon: const Icon(Icons.search_rounded, size: 21),
            ),
            _filter(
              'الكل',
              !doctorsOnly,
              () => setState(() => doctorsOnly = false),
            ),
            const SizedBox(width: 6),
            _filter(
              'الدكاترة',
              doctorsOnly,
              () => setState(() => doctorsOnly = true),
            ),
          ],
        ),
        if (searchOpen)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: TextField(
              key: const ValueKey('feed-search'),
              onChanged: (v) => setState(() => feedQuery = v),
              decoration: const InputDecoration(
                hintText: 'ابحث في المنشورات المعروضة',
                prefixIcon: Icon(Icons.search, size: 20),
              ),
            ),
          ),
        const SizedBox(height: 10),
        if (visible.isEmpty)
          card(
            ClubEmpty(
              title: posts.isEmpty
                  ? 'أول حكاية ممكن تبدأ منك'
                  : 'مفيش منشورات مطابقة',
              subtitle: posts.isEmpty
                  ? 'شارك سؤال، فكرة، أو لحظة من يومك الجامعي.'
                  : 'جرّب بحثًا مختلفًا أو اعرض كل المنشورات.',
              action: posts.isEmpty
                  ? () => compose('posts')
                  : () => setState(() {
                      doctorsOnly = false;
                      feedQuery = '';
                      searchOpen = false;
                    }),
              actionLabel: posts.isEmpty ? 'اكتب أول منشور' : 'عرض الكل',
            ),
          ),
        ...visible.map((raw) {
          final p = raw as Json;
          return card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: person(p['author'] as Json)),
                    PopupMenuButton<String>(
                      tooltip: 'خيارات المنشور',
                      icon: const Icon(
                        Icons.more_horiz,
                        size: 21,
                        color: ClubStyle.muted,
                      ),
                      onSelected: (v) {
                        if (v == 'delete') {
                          delete('posts', p['id'] as String);
                        } else {
                          report('posts', p['id'] as String);
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: p['user'] == me!['id'] ? 'delete' : 'report',
                          child: Text(
                            p['user'] == me!['id']
                                ? 'حذف المنشور'
                                : 'إبلاغ عن المنشور',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if ((p['text'] as String).isNotEmpty)
                  Text(
                    p['text'] as String,
                    style: const TextStyle(fontSize: 14, height: 1.9),
                  ),
                if (p['media'] != null)
                  MediaTile(
                    key: ValueKey(p['media']),
                    api: api,
                    id: p['media'] as String,
                    kind: p['mediaKind'] as String,
                  ),
                const SizedBox(height: 12),
                Text(
                  when(p['created'] as String?),
                  style: const TextStyle(fontSize: 9, color: ClubStyle.muted),
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    _postAction(
                      p['liked'] == true
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      '${p['likeCount']} إعجاب',
                      () => run(() async {
                        await api.call(
                          '/posts/${p['id']}/like',
                          method: 'POST',
                        );
                        await refresh();
                      }),
                      active: p['liked'] == true,
                    ),
                    const SizedBox(width: 16),
                    _postAction(
                      Icons.mode_comment_outlined,
                      '${p['commentCount'] ?? 0} تعليق',
                      () => openTool(commentsPage(api, p, me!['id'] as String)),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'حفظ المنشور',
                      icon: Icon(
                        p['saved'] == true
                            ? Icons.bookmark
                            : Icons.bookmark_border,
                      ),
                      onPressed: () => run(() async {
                        await api.call(
                          '/product/posts/${p['id']}/save',
                          method: 'POST',
                          body: {},
                        );
                        await refresh();
                      }),
                    ),
                    if (p['user'] == me!['id'])
                      IconButton(
                        tooltip: 'تعديل المنشور',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => run(() async {
                          final f = await askFields(
                            context,
                            'تعديل المنشور',
                            {'text': 'النص'},
                            initial: {'text': p['text']},
                          );
                          if (f != null) {
                            await api.call(
                              '/product/posts/${p['id']}',
                              method: 'PATCH',
                              body: f,
                            );
                            await refresh();
                          }
                        }),
                      ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _filter(String text, bool selected, VoidCallback tap) => InkWell(
    onTap: tap,
    borderRadius: BorderRadius.circular(9),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? ClubStyle.mint : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: selected ? purple : ClubStyle.muted,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
  Widget _postAction(
    IconData icon,
    String text,
    VoidCallback tap, {
    bool active = false,
  }) => InkWell(
    onTap: tap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
      child: Row(
        children: [
          Icon(
            icon,
            size: 19,
            color: active ? const Color(0xFFC77360) : ClubStyle.muted,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              color: ClubStyle.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );

  Widget groupPage() {
    final filtered = groups
        .where((g) => (g['name'] as String).contains(groupQuery))
        .toList();
    const icons = [
      Icons.code_rounded,
      Icons.menu_book_rounded,
      Icons.celebration_outlined,
    ];
    const tones = [ClubStyle.mint, Color(0xFF252047), Color(0xFF302046)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading('مكانك وسط ناس شبهك'),
        TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('إنشاء مجموعة'),
          onPressed: () => run(() async {
            final f = await askFields(context, 'مجموعة جديدة', {
              'name': 'اسم المجموعة',
              'description': 'وصف المجموعة',
            });
            if (f != null) {
              await api.call('/product/groups', method: 'POST', body: f);
              await refresh();
            }
          }),
        ),
        const Text(
          'اتعلّموا سوا، شاركوا اهتماماتكم، واعملوا ذكريات.',
          style: TextStyle(fontSize: 12, color: ClubStyle.muted),
        ),
        const SizedBox(height: 20),
        TextField(
          key: const ValueKey('group-search'),
          onChanged: (v) => setState(() => groupQuery = v),
          decoration: const InputDecoration(
            hintText: 'دور على مجموعتك',
            prefixIcon: Icon(Icons.search, size: 20),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Expanded(
              child: Text(
                'مجموعات الجامعة',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            tag(
              '${groups.where((g) => g['joined'] == true).length} انضممت لها',
              icon: Icons.check_circle_outline,
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (filtered.isEmpty)
          const ClubEmpty(
            title: 'مفيش مجموعة بالاسم ده',
            subtitle: 'جرّب كلمة تانية في البحث.',
            icon: Icons.groups_outlined,
          ),
        ...List.generate(filtered.length, (i) {
          final g = filtered[i] as Json;
          final joined = g['joined'] == true;
          return card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 62,
                      height: 65,
                      decoration: BoxDecoration(
                        color: tones[i % 3],
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(icons[i % 3], color: purple, size: 29),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            g['name'] as String,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${g['count']} عضو · ${universities[me!['university']]}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: ClubStyle.muted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          tag(
                            joined ? 'أنت عضو هنا' : 'مجتمع جامعتك',
                            background: joined
                                ? ClubStyle.mint
                                : const Color(0xFF18152F),
                            color: joined ? purple : ClubStyle.muted,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: joined
                          ? FilledButton.icon(
                              onPressed: () async {
                                await openPage(
                                  context,
                                  GroupChat(
                                    api: api,
                                    group: g,
                                    currentUserId: me!['id'] as String,
                                  ),
                                );
                                if (mounted) await run(refresh);
                              },
                              icon: const Icon(
                                Icons.chat_bubble_outline,
                                size: 17,
                              ),
                              label: const Text('افتح الشات'),
                            )
                          : FilledButton.icon(
                              onPressed: () => run(() async {
                                await api.call(
                                  '/groups/${g['id']}/membership',
                                  method: 'POST',
                                );
                                await refresh();
                              }),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('انضم للمجموعة'),
                            ),
                    ),
                    if (joined && g['managed'] != true) ...[
                      const SizedBox(width: 10),
                      IconButton(
                        tooltip: 'مغادرة المجموعة',
                        onPressed: () => run(() async {
                          await api.call(
                            '/groups/${g['id']}/membership',
                            method: 'POST',
                          );
                          await refresh();
                        }),
                        icon: const Icon(
                          Icons.logout,
                          size: 19,
                          color: ClubStyle.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget games() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'اختبر معلوماتك',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          tag('١٠ نقاط للسؤال', icon: Icons.bolt_outlined),
        ],
      ),
      const SizedBox(height: 14),
      if (quiz != null && quiz!['done'] == true)
        card(
          const ClubEmpty(
            title: 'أنهيت جميع التحديات!',
            subtitle: 'معرفة جديدة ونقاط تستاهلها. جرّب سباق الحساب.',
            icon: Icons.emoji_events_outlined,
          ),
        )
      else if (quiz != null)
        card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.lightbulb_outline, size: 18, color: purple),
                  SizedBox(width: 7),
                  Text(
                    'سؤال جديد لفكرة جديدة',
                    style: TextStyle(fontSize: 10, color: ClubStyle.muted),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                quiz!['question'] as String,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 20),
              ...List.generate(
                (quiz!['choices'] as List).length,
                (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: OutlinedButton(
                    onPressed: result != null
                        ? null
                        : () => run(() async {
                            result = await api.call(
                              '/quiz/answer',
                              method: 'POST',
                              body: {'id': quiz!['id'], 'answer': i},
                            );
                            leaders =
                                (await api.call('/leaderboard'))['items']
                                    as List;
                          }),
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(
                        vertical: 13,
                        horizontal: 13,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 27,
                          height: 27,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: ClubStyle.cream,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            ['أ', 'ب', 'ج', 'د'][i % 4],
                            style: const TextStyle(
                              fontSize: 12,
                              color: ClubStyle.muted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            quiz!['choices'][i] as String,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (result != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: result!['correct'] == true
                        ? ClubStyle.mint
                        : const Color(0xFF252047),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result!['correct'] == true
                            ? 'إجابة صحيحة! 🎉'
                            : 'إجابة غير صحيحة',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: purple,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        result!['explanation'] as String,
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${result!['points']} نقطة',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => run(() async {
                    quiz = await api.call('/quiz');
                    result = null;
                  }),
                  child: const Text('السؤال التالي'),
                ),
              ],
            ],
          ),
        ),
      heading('لوحة المتصدرين'),
      if (leaders.isEmpty)
        const ClubEmpty(
          title: 'الصدارة مستنياك',
          subtitle: 'ابدأ أول تحدٍّ وشوف اسمك هنا.',
          icon: Icons.leaderboard_outlined,
        )
      else
        card(
          Column(
            children: List.generate(
              leaders.length,
              (i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(
                        '${i + 1}'.padLeft(2, '0'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: i == 0
                              ? const Color(0xFFAA7A2D)
                              : ClubStyle.muted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ClubAvatar(name: leaders[i]['name'] as String, size: 35),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        leaders[i]['name'] as String,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    tag(
                      '${leaders[i]['points']} نقطة',
                      background: i == 0
                          ? const Color(0xFF252047)
                          : ClubStyle.cream,
                      color: i == 0 ? const Color(0xFFAA7A2D) : ClubStyle.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );

  Future<void> editProfile() async {
    final newName = await prompt(
      'تعديل الاسم',
      initial: me!['name'] as String,
      max: 60,
      lines: 1,
    );
    if (newName == null || !mounted) return;
    final bio = await prompt(
      'نبذة عنك',
      initial: me!['bio'] as String? ?? '',
      max: 250,
      lines: 3,
    );
    if (bio == null || !mounted) return;
    await run(() async {
      me =
          (await api.call(
                '/me',
                method: 'PATCH',
                body: {'name': newName, 'bio': bio},
              ))['user']
              as Json;
      await refresh();
    });
  }

  Widget menuTile(
    IconData icon,
    String title,
    VoidCallback tap, {
    String? subtitle,
  }) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Container(
      width: 37,
      height: 37,
      decoration: BoxDecoration(
        color: ClubStyle.mint,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, color: purple, size: 19),
    ),
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle),
    trailing: const Icon(Icons.chevron_left, size: 20, color: ClubStyle.muted),
    onTap: tap,
  );
  Widget profile() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading('مساحتك الشخصية'),
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ClubAvatar(
                  name: me!['name'] as String,
                  size: 64,
                  doctor: me!['role'] == 'doctor',
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        me!['name'] as String,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        me!['email'] as String,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: ClubStyle.muted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      tag(
                        me!['verified'] == true ? 'حساب موثّق' : 'طالب جامعي',
                        icon: me!['verified'] == true
                            ? Icons.verified_outlined
                            : Icons.school_outlined,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'تعديل الملف الشخصي',
                  onPressed: editProfile,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                ),
              ],
            ),
            if ((me!['bio'] as String? ?? '').isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                me!['bio'] as String,
                style: const TextStyle(fontSize: 12, height: 1.8),
              ),
            ],
            const Divider(height: 30),
            Row(
              children: [
                const Icon(
                  Icons.account_balance_outlined,
                  size: 17,
                  color: ClubStyle.muted,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    universities[me!['university']] ?? '',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Text(
                  '${groups.where((g) => g['joined'] == true).length} مجموعات',
                  style: const TextStyle(
                    color: purple,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 6),
      const Padding(
        padding: EdgeInsets.only(bottom: 10, right: 4),
        child: Text(
          'مجتمعك',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: ClubStyle.muted,
          ),
        ),
      ),
      card(
        Column(
          children: [
            menuTile(
              Icons.description_outlined,
              'المستندات',
              () => openTool(documentPage(api)),
            ),
            menuTile(
              Icons.poll_outlined,
              'الاستطلاعات',
              () => openTool(pollsPage(api)),
            ),
            menuTile(
              Icons.hub_outlined,
              'مجتمعي وخدماتي',
              () => openTool(ProductCenter(api: api)),
            ),
            menuTile(
              Icons.notifications_active_outlined,
              'البريد وإشعارات الهاتف',
              () => openTool(servicePage(api)),
            ),
            if (me!['role'] == 'doctor' || me!['role'] == 'admin')
              menuTile(
                Icons.bar_chart,
                'تقارير الإعلانات',
                () => openTool(reportsPage(api)),
              ),
            if (me!['role'] == 'admin')
              menuTile(
                Icons.location_city,
                'المؤسسات والمدارس',
                () => openTool(institutionsPage(api)),
              ),
            const Divider(height: 1),
            menuTile(
              Icons.people_alt_outlined,
              'الأصدقاء واللعب',
              () => openTool(FriendsPage(api: api)),
            ),
            const Divider(height: 1),
            menuTile(
              Icons.class_outlined,
              'المواد والشُعب',
              () => openTool(CoursePage(api: api)),
            ),
            const Divider(height: 1),
            menuTile(
              Icons.chat_bubble_outline,
              'الرسائل الخاصة',
              () => openTool(inboxPage(api)),
            ),
            const Divider(height: 1),
            menuTile(
              Icons.people_outline,
              'زملاء الجامعة',
              () => openTool(peoplePage(api, me!['id'] as String)),
            ),
          ],
        ),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 6, bottom: 10, right: 4),
        child: Text(
          'الحساب',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: ClubStyle.muted,
          ),
        ),
      ),
      card(
        Column(
          children: [
            menuTile(
              Icons.verified_outlined,
              me!['verified'] == true
                  ? 'الحساب موثق · طلباتي'
                  : 'طلب توثيق الحساب',
              () => openTool(verificationPage(api)),
              subtitle: 'مراجعة يدوية من مشرف مجتمعك',
            ),
            const Divider(height: 1),
            menuTile(
              Icons.shield_outlined,
              'الحساب والخصوصية',
              () => openTool(
                AccountTools(
                  api: api,
                  onSignedOut: () {
                    if (mounted) {
                      setState(() {
                        me = null;
                        posts = [];
                        stories = [];
                        groups = [];
                        leaders = [];
                        result = null;
                        page = 0;
                      });
                    }
                  },
                ),
              ),
              subtitle: 'كلمة المرور، الحظر، وكود الاستعادة',
            ),
            if (me!['role'] == 'admin') ...[
              const Divider(height: 1),
              menuTile(
                Icons.admin_panel_settings_outlined,
                'لوحة المشرف',
                () => openTool(adminPage(api)),
              ),
            ],
          ],
        ),
      ),
      Card(
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          title: const Text(
            'عن STU Club',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          leading: const Icon(Icons.info_outline, size: 20),
          children: const [
            Padding(
              padding: EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Text(
                'مجتمعك مرتبط بالمؤسسة التي تنتمي إليها. راجع الجلسات والخصوصية والدعم من مجتمعي وخدماتي.',
                style: TextStyle(
                  fontSize: 11,
                  color: ClubStyle.muted,
                  height: 1.8,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: () => run(() async {
          await api.call('/auth/logout', method: 'POST');
          await api.clear();
          me = null;
          posts = [];
          stories = [];
          groups = [];
          leaders = [];
          result = null;
        }),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFAC6354),
          side: const BorderSide(color: Color(0xFFEEDDD5)),
        ),
        icon: const Icon(Icons.logout, size: 18),
        label: const Text('تسجيل الخروج'),
      ),
      const SizedBox(height: 22),
      const Center(
        child: Text(
          'STU CLUB  /  CONNECT · PLAY · LEARN',
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: 10,
            color: ClubStyle.muted,
            letterSpacing: 1.5,
          ),
        ),
      ),
      const SizedBox(height: 12),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: me == null
        ? null
        : AppBar(
            title: Row(
              children: [
                const BrandMark(size: 37),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'STU Club',
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                          letterSpacing: -.7,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        universities[me!['university']] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9,
                          color: ClubStyle.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: IconButton.filledTonal(
                  tooltip: 'الرسائل الخاصة',
                  onPressed: busy ? null : () => openTool(inboxPage(api)),
                  style: IconButton.styleFrom(
                    backgroundColor: ClubStyle.surface,
                    side: const BorderSide(color: ClubStyle.line),
                  ),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 14),
                child: IconButton.filledTonal(
                  tooltip: 'التنبيهات',
                  onPressed: busy
                      ? null
                      : () => openTool(notificationsPage(api)),
                  style: IconButton.styleFrom(
                    backgroundColor: ClubStyle.surface,
                    side: const BorderSide(color: ClubStyle.line),
                  ),
                  icon: const Icon(Icons.notifications_none_rounded, size: 21),
                ),
              ),
            ],
          ),
    body: SafeArea(
      top: me == null,
      bottom: false,
      child: Stack(
        children: [
          AbsorbPointer(
            absorbing: busy,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: RefreshIndicator(
                  onRefresh: () =>
                      me == null ? Future<void>.value() : run(refresh),
                  child: ListView(
                    key: PageStorageKey('club-${me == null ? 'auth' : page}'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      20,
                      me == null ? 12 : 8,
                      20,
                      24,
                    ),
                    children: [
                      if (me != null && error != null) errorNotice(),
                      if (me == null)
                        login()
                      else if (needsApproval && page != 3)
                        approval()
                      else
                        [
                          home,
                          groupPage,
                          () => Column(
                            children: [
                              PlayHub(api: api),
                              games(),
                            ],
                          ),
                          profile,
                        ][page](),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (busy)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    ),
    bottomNavigationBar: me == null
        ? null
        : Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: ClubStyle.line)),
            ),
            child: NavigationBar(
              selectedIndex: page,
              onDestinationSelected: busy
                  ? null
                  : (i) => setState(() => page = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'الرئيسية',
                ),
                NavigationDestination(
                  icon: Icon(Icons.groups_outlined),
                  selectedIcon: Icon(Icons.groups_rounded),
                  label: 'المجموعات',
                ),
                NavigationDestination(
                  icon: Icon(Icons.sports_esports_outlined),
                  selectedIcon: Icon(Icons.sports_esports_rounded),
                  label: 'الألعاب',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: 'حسابي',
                ),
              ],
            ),
          ),
  );
}

class TextPrompt extends StatefulWidget {
  final String title, initial;
  final int max, lines;
  const TextPrompt({
    super.key,
    required this.title,
    required this.initial,
    required this.max,
    required this.lines,
  });
  @override
  State<TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<TextPrompt> {
  late final controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: controller,
      maxLength: widget.max,
      minLines: widget.lines,
      maxLines: widget.lines + 2,
      autofocus: true,
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text),
        child: const Text('حفظ'),
      ),
    ],
  );
}

class GroupChat extends StatelessWidget {
  final Api api;
  final Json group;
  final String currentUserId;
  const GroupChat({
    super.key,
    required this.api,
    required this.group,
    this.currentUserId = '',
  });
  @override
  Widget build(BuildContext context) => ProductChat(
    api: api,
    kind: 'group',
    target: group['id'],
    title: group['name'],
  );
}
