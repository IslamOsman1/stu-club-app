import 'package:flutter/material.dart';

import 'api.dart';
import 'design.dart';

class MemoryGame extends StatefulWidget {
  final Api api;
  const MemoryGame({super.key, required this.api});
  @override
  State<MemoryGame> createState() => _MemoryGameState();
}

class _MemoryGameState extends State<MemoryGame> {
  Map<String, dynamic>? round;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    start();
  }

  Future<void> start() async {
    setState(() => busy = true);
    try {
      final r = await widget.api.call('/games/memory/start', method: 'POST');
      if (mounted) {
        setState(() {
          round = r;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> flip(int i) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final r = await widget.api.call(
        '/memory/${round!['id']}/flip',
        method: 'POST',
        body: {'cell': i},
      );
      if (mounted) setState(() => round = r);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const icons = [
      Icons.school,
      Icons.favorite,
      Icons.bolt,
      Icons.rocket_launch,
      Icons.pets,
      Icons.star,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('تحدّي الذاكرة')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'اجمع كل زوجين متطابقين خلال ٣ دقائق. مكافأة نقاط واحدة كل يوم.',
            textAlign: TextAlign.center,
            style: TextStyle(color: ClubStyle.muted),
          ),
          if (error != null) Text(error!),
          if (busy) const LinearProgressIndicator(),
          if (round != null) ...[
            const SizedBox(height: 20),
            Text(
              round!['finished'] == true
                  ? 'أحسنت! اكتملت الجولة'
                  : 'المحاولات: ${round!['attempts']}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 18),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 12,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemBuilder: (_, i) {
                final value = round!['cards'][i];
                return Semantics(
                  label: 'بطاقة ذاكرة ${i + 1}',
                  button: true,
                  child: InkWell(
                    onTap:
                        busy ||
                            round!['finished'] == true ||
                            (round!['matched'] as List).contains(i)
                        ? null
                        : () => flip(i),
                    child: Container(
                      decoration: BoxDecoration(
                        color: value == null
                            ? ClubStyle.surface
                            : ClubStyle.mint,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: value == null
                              ? ClubStyle.line
                              : ClubStyle.cyan,
                        ),
                      ),
                      child: Icon(
                        value == null
                            ? Icons.question_mark
                            : icons[value as int],
                        size: 40,
                        color: ClubStyle.cyan,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
          ],
          OutlinedButton(
            onPressed: busy ? null : start,
            child: const Text('جولة جديدة'),
          ),
        ],
      ),
    );
  }
}
