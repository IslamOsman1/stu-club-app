import 'stickers.dart';

import 'package:flutter/material.dart';

class ClubStyle {
  static const ink = Color(0xFFF4F2FF),
      green = Color(0xFF9855FF),
      cream = Color(0xFF090C24),
      muted = Color(0xFFB0ACCF),
      line = Color(0xFF383254),
      mint = Color(0xFF252047),
      gold = Color(0xFF42E8F5),
      coral = Color(0xFFFF4CDF);
  static const surface = Color(0xFF18152F),
      cyan = Color(0xFF42E8F5),
      pink = Color(0xFFFF4CDF);
  static ThemeData theme() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: green,
          brightness: Brightness.dark,
        ).copyWith(
          primary: green,
          secondary: const Color(0xFF42E8F5),
          surface: surface,
          onSurface: ink,
          outline: line,
          surfaceContainerHighest: mint,
        );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Cairo',
      fontFamilyFallback: const ['Noto Color Emoji'],
      scaffoldBackgroundColor: cream,
    );
    return base.copyWith(
      textTheme: base.textTheme
          .apply(bodyColor: ink, displayColor: ink)
          .copyWith(
            bodyLarge: const TextStyle(
              fontFamily: 'Cairo',
              fontFamilyFallback: ['Noto Color Emoji'],
              fontSize: 15,
              height: 1.65,
              color: ink,
            ),
            bodyMedium: const TextStyle(
              fontFamily: 'Cairo',
              fontFamilyFallback: ['Noto Color Emoji'],
              fontSize: 13,
              height: 1.65,
              color: ink,
            ),
            titleLarge: const TextStyle(
              fontFamily: 'Cairo',
              fontFamilyFallback: ['Noto Color Emoji'],
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
            titleMedium: const TextStyle(
              fontFamily: 'Cairo',
              fontFamilyFallback: ['Noto Color Emoji'],
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
      appBarTheme: const AppBarTheme(
        backgroundColor: cream,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: ink,
        titleTextStyle: TextStyle(
          fontFamily: 'Cairo',
          fontFamilyFallback: ['Noto Color Emoji'],
          fontSize: 19,
          fontWeight: FontWeight.w800,
          color: ink,
        ),
        toolbarHeight: 68,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF19172F),
        labelStyle: const TextStyle(color: muted, fontSize: 13),
        hintStyle: const TextStyle(color: muted, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: green, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 50),
          textStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontFamilyFallback: ['Noto Color Emoji'],
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 46),
          side: const BorderSide(color: line),
          textStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontFamilyFallback: ['Noto Color Emoji'],
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontFamilyFallback: ['Noto Color Emoji'],
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: ink),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: line),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        iconColor: green,
        titleTextStyle: TextStyle(
          fontFamily: 'Cairo',
          fontFamilyFallback: ['Noto Color Emoji'],
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: 'Cairo',
          fontFamilyFallback: ['Noto Color Emoji'],
          fontSize: 12,
          color: muted,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 74,
        indicatorColor: mint,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontFamily: 'Cairo',
            fontFamilyFallback: const ['Noto Color Emoji'],
            fontSize: 11,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? green : muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 23,
            color: s.contains(WidgetState.selected) ? green : muted,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: green,
        linearTrackColor: mint,
      ),
    );
  }
}

class BrandMark extends StatelessWidget {
  final double size;
  final bool light;
  const BrandMark({super.key, this.size = 42, this.light = false});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * .25),
    child: Image.asset(
      'assets/brand/stuclub.png',
      width: size,
      height: size,
      fit: BoxFit.cover,
    ),
  );
}

class ClubAvatar extends StatelessWidget {
  final String name;
  final double size;
  final bool doctor;
  const ClubAvatar({
    super.key,
    required this.name,
    this.size = 42,
    this.doctor = false,
  });
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: doctor ? const Color(0xFF302046) : ClubStyle.mint,
      borderRadius: BorderRadius.circular(size * .36),
    ),
    child: doctor
        ? Icon(
            Icons.school_outlined,
            color: const Color(0xFF42E8F5),
            size: size * .5,
          )
        : Text(
            name.isEmpty ? '؟' : name.characters.first,
            style: TextStyle(
              fontSize: size * .4,
              fontWeight: FontWeight.w800,
              color: ClubStyle.green,
            ),
          ),
  );
}

class ClubEmpty extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final VoidCallback? action;
  final String? actionLabel;
  const ClubEmpty({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.forum_outlined,
    this.action,
    this.actionLabel,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: ClubStyle.mint,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Icon(icon, color: ClubStyle.green, size: 32),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: ClubStyle.muted,
            fontSize: 12,
            height: 1.7,
          ),
        ),
        if (action != null) ...[
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: action,
            child: Text(actionLabel ?? 'ابدأ الآن'),
          ),
        ],
      ],
    ),
  );
}

class CampusArt extends StatelessWidget {
  const CampusArt({super.key});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [
          ClubStyle.cyan.withValues(alpha: .18),
          ClubStyle.pink.withValues(alpha: .08),
          Colors.transparent,
        ],
      ),
    ),
    child: Icon(
      Icons.auto_awesome_rounded,
      size: 78,
      color: ClubStyle.cyan.withValues(alpha: .18),
    ),
  );
}

class MessageBubble extends StatelessWidget {
  final String name, text;
  final bool mine;
  final String? created;
  final VoidCallback? report;
  const MessageBubble({
    super.key,
    required this.name,
    required this.text,
    required this.mine,
    this.created,
    this.report,
  });
  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(created ?? '')?.toLocal();
    final clock = date == null
        ? ''
        : '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .82,
        ),
        margin: const EdgeInsets.only(bottom: 13),
        padding: const EdgeInsets.fromLTRB(15, 11, 15, 8),
        decoration: BoxDecoration(
          color: mine ? ClubStyle.green : ClubStyle.surface,
          border: mine ? null : Border.all(color: ClubStyle.line),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(19),
            topRight: const Radius.circular(19),
            bottomLeft: Radius.circular(mine ? 19 : 5),
            bottomRight: Radius.circular(mine ? 5 : 19),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!mine) ...[
              Text(
                name,
                style: const TextStyle(
                  color: ClubStyle.green,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
            ],
            if (text.startsWith(':sticker:') &&
                ClubSticker.ids.contains(text.substring(9)))
              ClubSticker(id: text.substring(9))
            else
              SelectableText(
                text,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.8,
                  color: mine ? Colors.white : ClubStyle.ink,
                ),
              ),
            const SizedBox(height: 5),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  clock,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 8,
                    color: mine ? const Color(0xFFBFDBCB) : ClubStyle.muted,
                  ),
                ),
                if (report != null) ...[
                  const SizedBox(width: 9),
                  InkWell(
                    onTap: report,
                    child: const Padding(
                      padding: EdgeInsets.all(5),
                      child: Icon(
                        Icons.more_horiz,
                        size: 14,
                        color: ClubStyle.muted,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class MessageComposer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback send;
  const MessageComposer({
    super.key,
    required this.controller,
    required this.sending,
    required this.send,
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: ClubStyle.surface,
      border: Border(top: BorderSide(color: ClubStyle.line)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              tooltip: 'ستيكرز',
              onPressed: sending
                  ? null
                  : () async {
                      final value = await showModalBottomSheet<String>(
                        context: context,
                        builder: (ctx) => SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              children:
                                  [...ClubSticker.ids.map((v) => ':sticker:$v')]
                                      .map(
                                        (e) => InkWell(
                                          onTap: () => Navigator.pop(ctx, e),
                                          child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: ClubSticker(
                                              id: e.substring(9),
                                              size: 86,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                            ),
                          ),
                        ),
                      );
                      if (value != null && context.mounted) {
                        controller.text = value;
                        send();
                      }
                    },
              icon: const Icon(
                Icons.emoji_emotions_outlined,
                color: ClubStyle.cyan,
              ),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                maxLength: 1000,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'اكتب رسالة...',
                  counterText: '',
                  contentPadding: EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 15,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              onPressed: sending ? null : send,
              tooltip: 'إرسال',
              style: IconButton.styleFrom(
                backgroundColor: ClubStyle.green,
                foregroundColor: Colors.white,
                minimumSize: const Size(48, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              icon: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.arrow_upward_rounded, size: 22),
            ),
          ],
        ),
      ),
    ),
  );
}
