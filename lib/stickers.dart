import 'package:flutter/material.dart';

class ClubSticker extends StatelessWidget {
  final String id;
  final double size;
  const ClubSticker({super.key, required this.id, this.size = 110});
  static const ids = ['cheer', 'love', 'win', 'study', 'fire', 'laugh'];
  @override
  Widget build(BuildContext context) {
    final index = ids.indexOf(id);
    final i = index < 0 ? 0 : index;
    const icons = [
      Icons.celebration_rounded,
      Icons.favorite_rounded,
      Icons.emoji_events_rounded,
      Icons.auto_stories_rounded,
      Icons.local_fire_department_rounded,
      Icons.sentiment_very_satisfied_rounded,
    ];
    const labels = ['عاش!', 'معاك', 'بطل!', 'يلا نذاكر', 'حماس!', 'ضحكتني'];
    return Semantics(
      label: 'ملصق ${labels[i]}',
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * .1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * .3),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.cyanAccent.withValues(alpha: .25),
              Colors.deepPurpleAccent.withValues(alpha: .7),
            ],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: .4),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icons[i],
              size: size * .46,
              color: i == 1
                  ? Colors.pinkAccent
                  : i == 2
                  ? Colors.amberAccent
                  : Colors.cyanAccent,
            ),
            Text(
              labels[i],
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: size * .16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
