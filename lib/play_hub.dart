import 'package:flutter/material.dart';

import 'api.dart';
import 'design.dart';
import 'math_game.dart';
import 'friends_page.dart';
import 'memory_game.dart';
import 'release_hub.dart';

class PlayHub extends StatefulWidget {
  final Api api;
  const PlayHub({super.key, required this.api});
  @override
  State<PlayHub> createState() => _PlayHubState();
}

class _PlayHubState extends State<PlayHub> {
  String query = '';
  Map<String, dynamic>? streak;
  bool failed = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await widget.api.call('/streak');
      if (mounted) {
        setState(() {
          streak = r;
          failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  Future<void> launch(Widget child) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            Directionality(textDirection: TextDirection.rtl, child: child),
      ),
    );
    await load();
  }

  @override
  Widget build(BuildContext context) {
    final games = [
      (
        'XO',
        'لاعبان على نفس الجهاز',
        Icons.grid_3x3_rounded,
        const Color(0xFF6533E8),
        () => launch(const LocalXO()),
      ),
      (
        'XO مع صديق',
        'دعوة · جهازان',
        Icons.people_alt_rounded,
        const Color(0xFF7D1BC6),
        () => launch(FriendsPage(api: widget.api, showGames: true)),
      ),
      (
        'تحدّي الذاكرة',
        'مطابقة · نقاط يومية',
        Icons.psychology_alt,
        const Color(0xFF176A85),
        () => launch(MemoryGame(api: widget.api)),
      ),
      (
        'سباق الحساب',
        '١٠ أسئلة · ٩٠ ثانية',
        Icons.bolt_rounded,
        const Color(0xFF0065D8),
        () => launch(MathGame(api: widget.api)),
      ),
    ].where((g) => g.$1.toLowerCase().contains(query.toLowerCase())).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'العب. اتواصل. اتعلم.',
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        const Text(
          'اختار تحدّيك وكمّل سلسلة نشاطك',
          style: TextStyle(color: ClubStyle.muted),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => launch(tournamentsPage(widget.api)),
          icon: const Icon(Icons.emoji_events_outlined),
          label: const Text('البطولات والترتيب'),
        ),
        InkWell(
          onTap: streak == null
              ? load
              : () => launch(StreakCalendar(data: streak!)),
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                colors: [Color(0xFF3B176F), Color(0xFF192C52)],
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.local_fire_department_rounded,
                  color: Color(0xFFFFAD56),
                  size: 46,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        streak == null
                            ? failed
                                  ? 'تعذر تحميل النشاط · حاول مجددًا'
                                  : 'جاري تحميل النشاط…'
                            : '${streak!['count']} يوم متواصل',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 19,
                        ),
                      ),
                      const Text(
                        'نشاط يومي · التقويم بتوقيت UTC',
                        style: TextStyle(color: ClubStyle.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_left),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (streak != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  'رصيد التجميد: ${streak!['freezes'] ?? 0} · يوم لكل ٧ أيام نشاط',
                  style: const TextStyle(color: ClubStyle.muted, fontSize: 11),
                ),
              ),
              if (streak!['canFreeze'] == true)
                TextButton.icon(
                  onPressed: () async {
                    try {
                      await widget.api.call('/streak/freeze', method: 'POST');
                      await load();
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('$e')));
                      }
                    }
                  },
                  icon: const Icon(Icons.ac_unit, color: ClubStyle.cyan),
                  label: const Text('احمِ السلسلة'),
                ),
            ],
          ),
        const SizedBox(height: 10),
        TextField(
          onChanged: (v) => setState(() => query = v),
          decoration: const InputDecoration(
            hintText: 'ابحث عن لعبة',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, c) => GridView.count(
            crossAxisCount: c.maxWidth < 560 ? 2 : 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: MediaQuery.textScalerOf(context).scale(1) > 1.1
                ? .60
                : .82,
            children: games
                .map(
                  (g) => InkWell(
                    onTap: g.$5,
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: ClubStyle.line),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [g.$4, ClubStyle.surface],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Align(
                            alignment: Alignment.topLeft,
                            child: Icon(
                              Icons.play_circle_fill,
                              color: ClubStyle.cyan,
                              size: 30,
                            ),
                          ),
                          Expanded(
                            child: Center(
                              child: Icon(g.$3, size: 56, color: Colors.white),
                            ),
                          ),
                          Text(
                            g.$1,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                          Text(
                            g.$2,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        if (games.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('لا توجد لعبة بهذا الاسم'),
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class LocalXO extends StatefulWidget {
  const LocalXO({super.key});
  @override
  State<LocalXO> createState() => _LocalXOState();
}

class _LocalXOState extends State<LocalXO> {
  List<String> board = List.filled(9, '');
  String turn = 'X', winner = '';
  void tap(int i) {
    if (board[i].isNotEmpty || winner.isNotEmpty) return;
    setState(() {
      board[i] = turn;
      for (final line in [
        [0, 1, 2],
        [3, 4, 5],
        [6, 7, 8],
        [0, 3, 6],
        [1, 4, 7],
        [2, 5, 8],
        [0, 4, 8],
        [2, 4, 6],
      ]) {
        if (board[line[0]].isNotEmpty &&
            board[line[0]] == board[line[1]] &&
            board[line[1]] == board[line[2]]) {
          winner = turn;
        }
      }
      if (winner.isEmpty && !board.contains('')) winner = 'draw';
      turn = turn == 'X' ? 'O' : 'X';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('XO · لاعبان محليًا')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                winner == 'draw'
                    ? 'تعادل!'
                    : winner.isNotEmpty
                    ? 'الفائز $winner'
                    : 'دور $turn',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 24),
              GridView.builder(
                shrinkWrap: true,
                itemCount: 9,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemBuilder: (_, i) => Semantics(
                  label:
                      'خانة ${i + 1}: ${board[i].isEmpty ? 'فارغة' : board[i]}',
                  button: true,
                  child: InkWell(
                    onTap: () => tap(i),
                    child: Container(
                      decoration: BoxDecoration(
                        color: ClubStyle.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: ClubStyle.line),
                      ),
                      child: Center(
                        child: Text(
                          board[i],
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                            color: board[i] == 'X'
                                ? ClubStyle.cyan
                                : ClubStyle.pink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => setState(() {
                  board = List.filled(9, '');
                  turn = 'X';
                  winner = '';
                }),
                child: const Text('جولة جديدة'),
              ),
              const SizedBox(height: 12),
              const Text(
                'بدون نقاط ترتيب · العب مع صديق على نفس الهاتف',
                textAlign: TextAlign.center,
                style: TextStyle(color: ClubStyle.muted),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class StreakCalendar extends StatelessWidget {
  final Map<String, dynamic> data;
  const StreakCalendar({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final first = DateTime.utc(now.year, now.month);
    final count = DateTime.utc(now.year, now.month + 1, 0).day;
    final days = (data['days'] as List).toSet();
    final frozen = (data['frozenDays'] as List? ?? []).toSet();
    return Scaffold(
      appBar: AppBar(title: const Text('سلسلة النشاط')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(
            Icons.local_fire_department,
            size: 80,
            color: Color(0xFFFFAD56),
          ),
          Text(
            '${data['count']} يوم متواصل',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Text(
            data['today'] == true
                ? 'نشاطك اليوم اتحسب 🎉'
                : 'حل سؤالًا أو أكمل سباق الحساب لتسجيل نشاط اليوم',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          Text(
            '${now.year} / ${now.month}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22),
          ),
          const SizedBox(height: 16),
          Directionality(
            textDirection: TextDirection.ltr,
            child: GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                ...[
                  'M',
                  'T',
                  'W',
                  'T',
                  'F',
                  'S',
                  'S',
                ].map((d) => Center(child: Text(d))),
                ...List.generate(first.weekday - 1, (_) => const SizedBox()),
                ...List.generate(count, (i) {
                  final key = DateTime.utc(
                    now.year,
                    now.month,
                    i + 1,
                  ).toIso8601String().substring(0, 10);
                  return Container(
                    margin: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: frozen.contains(key)
                          ? const Color(0xFF176D95)
                          : days.contains(key)
                          ? ClubStyle.green
                          : ClubStyle.surface,
                    ),
                    child: Center(child: Text('${i + 1}')),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'يُحسب النشاط من إجابة تعليمية صحيحة أو إكمال سباق الحساب. اليوم بتوقيت UTC. يوم تجميد لكل ٧ أيام نشاط، لحماية يوم أمس الفائت. لا توجد إعلانات تجارية.',
            textAlign: TextAlign.center,
            style: TextStyle(color: ClubStyle.muted),
          ),
        ],
      ),
    );
  }
}
