import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stu_club/main.dart';
import 'package:stu_club/api.dart';
import 'package:stu_club/play_hub.dart';

class PreviewApi extends Api {
  @override
  Future<void> restore() async {
    token = 'preview';
  }

  @override
  Future<Map<String, dynamic>> call(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    if (path == '/me') {
      return {
        'user': {
          'id': 'preview',
          'name': 'أحمد',
          'email': 'preview@example.test',
          'university': 'cairo',
          'role': 'student',
          'verified': true,
          'bio': '',
        },
      };
    }
    if (path == '/feed') return {'posts': [], 'stories': []};
    if (path == '/quiz') return {'done': true};
    if (path == '/announcements') {
      return {
        'canPublish': false,
        'items': [
          {
            'id': 'sample',
            'text': 'محاضرة اليوم انتقلت إلى القاعة ٢٠٤. نلتقي الساعة العاشرة.',
            'author': {'name': 'د. مريم أحمد'},
            'pinned': true,
            'seen': false,
          },
        ],
      };
    }
    if (path == '/streak') {
      return {
        'count': 7,
        'today': true,
        'days': List.generate(
          7,
          (i) => DateTime.now()
              .toUtc()
              .subtract(Duration(days: i))
              .toIso8601String()
              .substring(0, 10),
        ),
      };
    }
    return {'items': []};
  }
}

class GuestPreviewApi extends PreviewApi {
  @override
  Future<void> restore() async {
    token = null;
  }
}

void main() {
  testWidgets('brand previews and local XO win; small screen layout', (
    tester,
  ) async {
    final font = FontLoader('Cairo')
      ..addFont(rootBundle.load('assets/fonts/Cairo.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(414, 896);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: StuClub(api: PreviewApi()),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory(
          Platform.environment['STU_PREVIEW_DIR'] ?? 'build/previews',
        );
        await directory.create(recursive: true);
        await File(
          '${Platform.environment['STU_PREVIEW_DIR'] ?? 'build/previews'}/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/brand/stuclub.png'),
        key.currentContext!,
      );
    });
    await tester.pumpAndSettle();
    expect(find.text('مايفوتكش إعلان'), findsOneWidget);
    await capture('StuClub-1.4-home');
    await tester.tap(find.text('الألعاب'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await capture('StuClub-1.4-games');
    await tester.tap(find.text('7 يوم متواصل'));
    await tester.pumpAndSettle();
    await capture('StuClub-1.4-streak');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('XO'));
    await tester.pumpAndSettle();
    final tiles = find.byType(LocalXO).evaluate();
    expect(tiles, isNotEmpty);
    for (final i in [0, 3, 1, 4, 2]) {
      await tester.tap(find.bySemanticsLabel(RegExp('خانة ${i + 1}:.*')));
      await tester.pump();
    }
    expect(find.text('الفائز X'), findsOneWidget);
    await capture('StuClub-1.4-XO');
    await tester.pageBack();
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(320, 740);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    tester.view.physicalSize = const Size(414, 896);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: StuClub(api: GuestPreviewApi()),
      ),
    );
    await tester.pumpAndSettle();
    await capture('StuClub-1.4-login');
  });
}
