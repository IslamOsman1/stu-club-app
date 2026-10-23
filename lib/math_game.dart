import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'design.dart';

class MathGame extends StatefulWidget {
  final Api api;
  const MathGame({super.key, required this.api});
  @override
  State<MathGame> createState() => _MathGameState();
}

class _MathGameState extends State<MathGame> {
  Map<String, dynamic>? round, result;
  String? error;
  bool busy = false;
  int remaining = 90, index = 0;
  final answers = <int>[];
  final input = TextEditingController();
  Timer? timer;
  @override
  void dispose() {
    timer?.cancel();
    input.dispose();
    super.dispose();
  }

  Future<void> start() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await widget.api.call('/games/math/start', method: 'POST');
      if (!mounted) return;
      setState(() {
        round = data;
        result = data['done'] == true ? data : null;
        index = 0;
        answers.clear();
        input.clear();
      });
      timer?.cancel();
      if (result == null) {
        tick();
        timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void tick() {
    if (!mounted || round == null || result != null) return;
    final seconds = DateTime.parse(round!['expires'])
        .difference(DateTime.now().toUtc())
        .inSeconds;
    setState(() => remaining = seconds.clamp(0, 90));
    if (remaining == 0) timer?.cancel();
  }

  Future<void> next() async {
    final value = int.tryParse(input.text);
    if (value == null || busy || remaining == 0) return;
    if (index < 9) {
      setState(() {
        answers.add(value);
        index++;
        input.clear();
      });
      return;
    }
    setState(() => busy = true);
    try {
      final data = await widget.api.call(
        '/games/math/submit',
        method: 'POST',
        body: {
          'id': round!['id'],
          'answers': [...answers, value],
        },
      );
      if (mounted) setState(() => result = data);
      timer?.cancel();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('سباق الحساب')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.timer_outlined, size: 64, color: ClubStyle.green),
        const SizedBox(height: 16),
        const Text(
          '١٠ أسئلة في ٩٠ ثانية',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
        ),
        const Text(
          '٥ نقاط لكل إجابة صحيحة. تُحتسب جولة واحدة فقط يوميًا بتوقيت UTC.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.deepOrange)),
        if (busy) const LinearProgressIndicator(),
        if (result != null) ...[
          const Icon(Icons.emoji_events, size: 64, color: Colors.amber),
          Text(
            'النتيجة: ${result!['correctCount']} من ١٠\n${result!['points']} نقطة',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24),
          ),
          const Text('ارجع بكرة لتحدٍ جديد.', textAlign: TextAlign.center),
        ] else if (round == null)
          FilledButton(
            onPressed: busy ? null : start,
            child: const Text('ابدأ السباق'),
          )
        else if (remaining == 0) ...[
          const Text('انتهى الوقت. يمكنك المحاولة من جديد.'),
          FilledButton(
            onPressed: busy ? null : start,
            child: const Text('جولة جديدة'),
          ),
        ] else ...[
          Text(
            'متبقي $remaining ثانية · السؤال ${index + 1}/١٠',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Text(
            round!['questions'][index] as String,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: input,
            keyboardType: TextInputType.number,
            enabled: !busy,
            maxLength: 5,
            textAlign: TextAlign.center,
            onSubmitted: (_) => next(),
            decoration: const InputDecoration(
              labelText: 'إجابتك',
              border: OutlineInputBorder(),
            ),
          ),
          FilledButton(
            onPressed: busy ? null : next,
            child: Text(index == 9 ? 'إنهاء وإظهار النتيجة' : 'التالي'),
          ),
        ],
      ],
    ),
  );
}
