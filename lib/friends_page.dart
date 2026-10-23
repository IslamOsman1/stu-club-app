import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'design.dart';
import 'community.dart';

class FriendsPage extends StatefulWidget {
  final Api api;
  final bool showGames;
  const FriendsPage({super.key, required this.api, this.showGames = false});
  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  Map<String, dynamic>? friends;
  List<dynamic> people = [], games = [];
  String? error;
  String query = '';
  bool busy = false, fetching = false;
  late int tab;
  int revision = 0;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    tab = widget.showGames ? 2 : 0;
    load();
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true && !busy) load();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load({bool force = false}) async {
    if (fetching && !force) return;
    fetching = true;
    final version = ++revision;
    try {
      final results = await Future.wait([
        widget.api.call('/friends'),
        widget.api.call('/friend-people'),
        widget.api.call('/duels'),
      ]);
      if (mounted && version == revision) {
        setState(() {
          friends = results[0];
          people = results[1]['items'] as List;
          games = results[2]['items'] as List;
          error = null;
        });
      }
    } catch (e) {
      if (mounted && version == revision) setState(() => error = '$e');
    } finally {
      if (version == revision) fetching = false;
    }
  }

  Future<void> action(Future<void> Function() work) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      revision++;
      await work();
      await load(force: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) {
        fetching = false;
        setState(() => busy = false);
      }
    }
  }

  Future<void> remove(Map<String, dynamic> person, String label) async {
    if (await confirm(
      context,
      label,
      'هل تريد المتابعة؟ ستُلغى أيضًا الدعوات والمباريات المفتوحة بينكما.',
    )) {
      await action(() async {
        await widget.api.call('/friends/${person['id']}', method: 'DELETE');
      });
    }
  }

  Future<void> invite(Map<String, dynamic> person) async {
    await action(() async {
      await widget.api.call(
        '/duels',
        method: 'POST',
        body: {'target': person['id']},
      );
      if (mounted) {
        setState(() => tab = 2);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تم إرسال دعوة XO')));
      }
    });
  }

  Widget personRow(Map<String, dynamic> p, List<Widget> buttons) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClubAvatar(name: p['name'] as String, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  p['name'] as String,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (p['verified'] == true)
                const Icon(Icons.verified, color: ClubStyle.cyan, size: 18),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(alignment: WrapAlignment.end, spacing: 8, children: buttons),
        ],
      ),
    ),
  );
  List<Widget> requests() {
    final incoming = friends!['incoming'] as List,
        outgoing = friends!['outgoing'] as List;
    return [
      const Text(
        'طلبات واردة',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
      ),
      if (incoming.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('لا توجد طلبات واردة'),
        ),
      ...incoming.map((r) {
        final p = r['person'] as Map<String, dynamic>;
        return personRow(p, [
          TextButton(
            onPressed: () => remove(p, 'رفض طلب الصداقة؟'),
            child: const Text('رفض'),
          ),
          FilledButton(
            onPressed: () => action(() async {
              await widget.api.call(
                '/friend-requests/${r['id']}/accept',
                method: 'POST',
              );
            }),
            child: const Text('قبول'),
          ),
        ]);
      }),
      const SizedBox(height: 18),
      const Text(
        'طلبات أرسلتها',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
      ),
      if (outgoing.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('لا توجد طلبات مرسلة'),
        ),
      ...outgoing.map((r) {
        final p = r['person'] as Map<String, dynamic>;
        return personRow(p, [
          TextButton(
            onPressed: () => remove(p, 'إلغاء طلب الصداقة؟'),
            child: const Text('إلغاء الطلب'),
          ),
        ]);
      }),
    ];
  }

  List<Widget> friendList() {
    final list = (friends!['items'] as List)
        .where(
          (r) => '${r['person']['name']}'.toLowerCase().contains(
            query.toLowerCase(),
          ),
        )
        .toList();
    return [
      TextField(
        key: ValueKey('friends-search-$tab'),
        onChanged: (v) => setState(() => query = v),
        decoration: const InputDecoration(
          hintText: 'ابحث في أصدقائك',
          prefixIcon: Icon(Icons.search),
        ),
      ),
      const SizedBox(height: 12),
      if (list.isEmpty)
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text('أضف زميلًا من تبويب اكتشاف وابدأوا اللعب معًا.'),
        ),
      ...list.map((r) {
        final p = r['person'] as Map<String, dynamic>;
        return personRow(p, [
          TextButton(
            onPressed: () => remove(p, 'حذف الصداقة؟'),
            child: const Text('حذف الصداقة'),
          ),
          TextButton.icon(
            onPressed: () async {
              await openPage(context, DirectChat(api: widget.api, person: p));
              await load();
            },
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('مراسلة'),
          ),
          FilledButton.icon(
            onPressed: () => invite(p),
            icon: const Icon(Icons.sports_esports_outlined),
            label: const Text('دعوة XO'),
          ),
        ]);
      }),
    ];
  }

  List<Widget> discover() {
    final known = <String>{
      for (final k in ['items', 'incoming', 'outgoing'])
        ...(friends![k] as List).map((r) => r['person']['id'] as String),
    };
    final list = people
        .where(
          (p) =>
              !known.contains(p['id']) &&
              '${p['name']}'.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    return [
      TextField(
        key: ValueKey('friends-search-$tab'),
        onChanged: (v) => setState(() => query = v),
        decoration: const InputDecoration(
          hintText: 'ابحث باسم زميلك',
          prefixIcon: Icon(Icons.search),
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'طلبات الصداقة واللعب داخل مؤسستك وبين الفئة نفسها: طلاب مع طلاب، وحسابات تعليمية مع بعضها.',
        style: TextStyle(color: ClubStyle.muted, fontSize: 12),
      ),
      if (list.isEmpty)
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text('لا توجد حسابات جديدة مطابقة'),
        ),
      ...list.map((raw) {
        final p = raw as Map<String, dynamic>;
        return personRow(p, [
          FilledButton.icon(
            onPressed: () => action(() async {
              await widget.api.call('/friends/${p['id']}', method: 'POST');
            }),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('إضافة صديق'),
          ),
        ]);
      }),
    ];
  }

  List<Widget> gameList() => [
    const Text(
      'مباريات XO مع الأصدقاء',
      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
    ),
    const Text(
      'الدعوة صالحة ١٠ دقائق. المباراة ساعة كحد أقصى. تحديث تلقائي أثناء فتح الشاشة.',
      style: TextStyle(color: ClubStyle.muted, fontSize: 12),
    ),
    if (games.isEmpty)
      const Padding(
        padding: EdgeInsets.all(20),
        child: Text('اختار صديقًا واضغط دعوة XO.'),
      ),
    ...games.map((raw) {
      final g = raw as Map<String, dynamic>;
      final pending = g['state'] == 'pending';
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                g['person']['name'] as String,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                {
                      'pending': g['incoming'] == true
                          ? 'دعوة واردة'
                          : 'بانتظار صديقك',
                      'playing': 'مباراة جارية',
                      'finished': 'مباراة انتهت',
                      'cancelled': 'تم الإلغاء',
                      'expired': 'انتهت المهلة',
                    }[g['state']] ??
                    '',
              ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  if (pending)
                    TextButton(
                      onPressed: () => action(() async {
                        await widget.api.call(
                          '/duels/${g['id']}/cancel',
                          method: 'POST',
                        );
                      }),
                      child: Text(
                        g['incoming'] == true ? 'رفض' : 'إلغاء الدعوة',
                      ),
                    ),
                  if (pending && g['incoming'] == true)
                    FilledButton(
                      onPressed: () => action(() async {
                        await widget.api.call(
                          '/duels/${g['id']}/accept',
                          method: 'POST',
                        );
                      }),
                      child: const Text('قبول اللعب'),
                    ),
                  if (['playing', 'finished'].contains(g['state']))
                    FilledButton(
                      onPressed: () async {
                        await openPage(
                          context,
                          OnlineXO(api: widget.api, id: g['id'] as String),
                        );
                        await load();
                      },
                      child: Text(
                        g['state'] == 'playing' ? 'افتح المباراة' : 'النتيجة',
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }),
  ];
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('الأصدقاء واللعب'),
      actions: [
        IconButton(
          tooltip: 'تحديث الأصدقاء',
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
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(
                  4,
                  (i) => Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text(
                        ['أصدقائي', 'الطلبات', 'المباريات', 'اكتشاف'][i],
                      ),
                      selected: tab == i,
                      onSelected: (_) => setState(() {
                        tab = i;
                        query = '';
                      }),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (error != null)
              TextButton(
                onPressed: load,
                child: Text('$error · إعادة المحاولة'),
              ),
            if (friends == null && error == null)
              const Center(child: CircularProgressIndicator()),
            if (friends != null)
              ...[friendList, requests, gameList, discover][tab](),
          ],
        ),
      ),
    ),
  );
}

class OnlineXO extends StatefulWidget {
  final Api api;
  final String id;
  const OnlineXO({super.key, required this.api, required this.id});
  @override
  State<OnlineXO> createState() => _OnlineXOState();
}

class _OnlineXOState extends State<OnlineXO> {
  Map<String, dynamic>? game;
  String? error;
  bool moving = false, fetching = false;
  int revision = 0;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true && !moving) {
        load();
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load({bool force = false}) async {
    if (fetching && !force) return;
    fetching = true;
    final version = ++revision;
    try {
      final g = await widget.api.call('/duels/${widget.id}');
      if (mounted && version == revision) {
        setState(() {
          game = g;
          error = null;
        });
      }
    } catch (e) {
      if (mounted && version == revision) setState(() => error = '$e');
    } finally {
      if (version == revision) fetching = false;
    }
  }

  Future<void> command(String operation, {Map<String, dynamic>? body}) async {
    if (moving) return;
    revision++;
    fetching = false;
    setState(() => moving = true);
    try {
      final g = await widget.api.call(
        '/duels/${widget.id}/$operation',
        method: 'POST',
        body: body,
      );
      if (mounted) {
        setState(() {
          game = g;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
      await load(force: true);
    } finally {
      if (mounted) setState(() => moving = false);
    }
  }

  Future<void> move(int cell) => command('move', body: {'cell': cell});

  @override
  Widget build(BuildContext context) {
    final g = game;
    final ownId = g == null
        ? ''
        : g['yourMark'] == 'X'
        ? g['from']
        : g['to'];
    final turn = g != null && g['turn'] == ownId;
    final status = g == null
        ? 'جاري الاتصال…'
        : g['state'] == 'finished'
        ? (g['winner'] == 'draw'
              ? 'تعادل!'
              : g['winner'] == ownId
              ? 'فزت بالمباراة 🎉'
              : 'فاز صديقك بالمباراة')
        : g['state'] == 'playing'
        ? (turn ? 'دورك الآن' : 'بانتظار صديقك')
        : g['state'] == 'expired'
        ? 'انتهت مهلة المباراة'
        : 'تم إلغاء المباراة';
    return Scaffold(
      appBar: AppBar(title: const Text('XO مع صديق')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (error != null)
            TextButton(onPressed: load, child: Text('$error · إعادة الاتصال')),
          Text(
            status,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
          if (g != null) ...[
            Text(
              '${g['person']['name']} · أنت ${g['yourMark']}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: ClubStyle.muted),
            ),
            const SizedBox(height: 28),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 9,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemBuilder: (_, i) => Semantics(
                    label: 'خانة أونلاين ${i + 1}',
                    button: true,
                    child: InkWell(
                      onTap:
                          error == null &&
                              !moving &&
                              turn &&
                              g['state'] == 'playing' &&
                              g['board'][i] == ''
                          ? () => move(i)
                          : null,
                      child: Container(
                        decoration: BoxDecoration(
                          color: ClubStyle.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: ClubStyle.line),
                        ),
                        child: Center(
                          child: Text(
                            g['board'][i] as String,
                            style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.w900,
                              color: g['board'][i] == 'X'
                                  ? ClubStyle.cyan
                                  : ClubStyle.pink,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (g['state'] == 'playing')
              OutlinedButton(
                onPressed: moving
                    ? null
                    : () async {
                        if (await confirm(
                          context,
                          'إنهاء المباراة؟',
                          'ستُلغى المباراة عند الطرفين.',
                        )) {
                          await command('cancel');
                        }
                      },
                child: const Text('إنهاء المباراة'),
              ),
            const Text(
              'تزامن عبر الخادم المحلي كل ثانيتين. اللعب بدون نقاط ترتيب حاليًا.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ClubStyle.muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
