import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stu_club/api.dart';
import 'package:stu_club/design.dart';
import 'package:stu_club/friends_page.dart';

class SocialApi extends Api {
  bool accepted = false, invited = false, cancelled = false;
  int moves = 0;
  bool hold = false;
  Completer<Map<String, dynamic>>? gate;
  final board = List.filled(9, '');
  String turn = 'me';
  final person = <String, dynamic>{
    'id': 'friend',
    'name': 'يوسف أحمد',
    'verified': true,
    'role': 'student',
  };
  Map<String, dynamic> game() => {
    'id': 'g',
    'from': 'me',
    'to': 'friend',
    'person': person,
    'board': List<String>.from(board),
    'state': 'playing',
    'turn': turn,
    'winner': null,
    'yourMark': 'X',
    'incoming': false,
  };
  @override
  Future<Map<String, dynamic>> call(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    if (path == '/friends') {
      return {
        'items': accepted
            ? [
                {'id': 'r', 'person': person},
              ]
            : [],
        'incoming': accepted || cancelled
            ? []
            : [
                {'id': 'r', 'person': person},
              ],
        'outgoing': [],
      };
    }
    if (path == '/friend-requests/r/accept') {
      accepted = true;
      return {'ok': true};
    }
    if (path == '/friend-people') return {'items': []};
    if (path == '/friends/friend' && method == 'DELETE') {
      accepted = false;
      cancelled = true;
      return {'ok': true};
    }
    if (path == '/duels' && method == 'POST') {
      invited = true;
      return {'id': 'g'};
    }
    if (path == '/duels') {
      return {
        'items': invited ? [game()] : [],
      };
    }
    if (path == '/duels/g/move') {
      moves++;
      board[body!['cell'] as int] = 'X';
      turn = 'friend';
      return game();
    }
    if (path == '/duels/g') {
      if (hold) {
        hold = false;
        gate = Completer<Map<String, dynamic>>();
        return gate!.future;
      }
      return game();
    }
    return {'ok': true};
  }
}

final previewKey = GlobalKey();
Widget frame(Widget child) => RepaintBoundary(
  key: previewKey,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ClubStyle.theme(),
    home: Directionality(textDirection: TextDirection.rtl, child: child),
  ),
);
Future<void> prepare(WidgetTester tester) async {
  tester.view.physicalSize = const Size(414, 896);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final font = FontLoader('Cairo')
    ..addFont(rootBundle.load('assets/fonts/Cairo.ttf'));
  await font.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

Future<void> capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['STU_PREVIEW_DIR'];
  if (directory == null) return;
  final boundary =
      previewKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$directory/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  testWidgets('accept friendship, invite friend and open online game', (
    tester,
  ) async {
    await prepare(tester);
    final api = SocialApi();
    await tester.pumpWidget(frame(FriendsPage(api: api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الطلبات'));
    await tester.pumpAndSettle();
    expect(find.text('يوسف أحمد'), findsOneWidget);
    await tester.tap(find.text('قبول'));
    await tester.pumpAndSettle();
    expect(api.accepted, true);
    await tester.tap(find.text('أصدقائي'));
    await tester.pumpAndSettle();
    await capture(tester, 'StuClub-1.6-friends');
    await tester.tap(find.text('دعوة XO'));
    await tester.pumpAndSettle();
    expect(api.invited, true);
    await tester.tap(find.text('افتح المباراة'));
    await tester.pumpAndSettle();
    expect(find.text('دورك الآن'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('خانة أونلاين 1'));
    await tester.pumpAndSettle();
    expect(find.text('بانتظار صديقك'), findsOneWidget);
    expect(api.moves, 1);
    await capture(tester, 'StuClub-1.6-online-XO');
    await tester.tap(find.bySemanticsLabel('خانة أونلاين 2'));
    await tester.pumpAndSettle();
    expect(api.moves, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets(
    'late poll cannot overwrite a newer move and small screens remain usable',
    (tester) async {
      await prepare(tester);
      final api = SocialApi();
      await tester.pumpWidget(frame(OnlineXO(api: api, id: 'g')));
      await tester.pumpAndSettle();
      final stale = api.game();
      api.hold = true;
      await tester.pump(const Duration(seconds: 2));
      expect(api.gate, isNotNull);
      await tester.tap(find.bySemanticsLabel('خانة أونلاين 1'));
      await tester.pumpAndSettle();
      expect(find.text('X'), findsOneWidget);
      api.gate!.complete(stale);
      await tester.pumpAndSettle();
      expect(find.text('X'), findsOneWidget);
      expect(find.text('بانتظار صديقك'), findsOneWidget);
      tester.view.physicalSize = const Size(320, 740);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
