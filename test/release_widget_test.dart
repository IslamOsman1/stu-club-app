import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stu_club/api.dart';
import 'package:stu_club/release_hub.dart';
import 'package:stu_club/memory_game.dart';
import 'package:stu_club/design.dart';
import 'package:stu_club/stickers.dart';

import 'courses_widget_test.dart' show prepare, frame, capture;

class ReleaseApi extends Api {
  final documents = <Map<String, dynamic>>[];
  final polls = <Map<String, dynamic>>[];
  bool verified = false;
  Map<String, dynamic>? createdInstitution;
  final cards = List<dynamic>.filled(12, null);
  final matched = <int>[];
  @override
  Future<Uint8List> binary(String path) async =>
      Uint8List.fromList(utf8.encode('%PDF-1.4\nlesson\n%%EOF'));
  @override
  Future<Map<String, dynamic>> call(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    if (path == '/courses') {
      return {'items': [], 'sections': [], 'isAdmin': true};
    }
    if (path == '/documents' && method == 'POST') {
      documents.add({
        'id': 'd',
        'name': body!['name'],
        'size': 28,
        'author': {'name': 'د. مريم'},
        'canDelete': true,
        'mime': 'application/pdf',
      });
      return {'id': 'd'};
    }
    if (path == '/documents') return {'items': documents};
    if (path == '/polls' && method == 'POST') {
      polls.add({
        'id': 'p',
        'question': body!['question'],
        'options': body['options'],
        'counts': [0, 0],
        'total': 0,
        'myVote': null,
        'closed': false,
        'author': {'name': 'د. مريم'},
        'canClose': true,
      });
      return {'id': 'p'};
    }
    if (path == '/polls/p/vote') {
      final p = polls.single;
      p['myVote'] = body!['choice'];
      p['counts'] = [body['choice'] == 0 ? 1 : 0, body['choice'] == 1 ? 1 : 0];
      p['total'] = 1;
      return {'ok': true};
    }
    if (path == '/polls/p/close') {
      polls.single['closed'] = true;
      return {'ok': true};
    }
    if (path == '/polls') return {'items': polls};
    if (path == '/announcement-reports') {
      return {
        'items': [
          {
            'id': 'a',
            'text': 'تحديث موعد محاضرة البرمجة',
            'eligible': 12,
            'seen': 9,
            'percent': 75,
            'averageSeconds': 90,
          },
        ],
      };
    }
    if (path == '/institutions/manage') {
      return {
        'items': [
          {'id': 'school', 'name': 'مدرسة المستقبل', 'kind': 'school'},
        ],
        'people': [],
      };
    }
    if (path == '/institutions' && method == 'POST') {
      createdInstitution = body;
      return {'id': 's'};
    }
    if (path == '/services') {
      return {
        'mail': 'outbox',
        'pushConfigured': false,
        'emailVerified': verified,
      };
    }
    if (path == '/email/verify/request') {
      return {'delivery': 'outbox', 'ok': true};
    }
    if (path == '/email/verify/confirm') {
      verified = true;
      return {'ok': true};
    }
    if (path == '/games/memory/start') {
      return {
        'id': 'm',
        'cards': List<dynamic>.from(cards),
        'matched': matched,
        'finished': false,
        'attempts': 0,
      };
    }
    if (path == '/memory/m/flip') {
      final i = body!['cell'] as int;
      cards[i] = i ~/ 2;
      if (i.isOdd) {
        matched.addAll([i - 1, i]);
      }
      return {
        'id': 'm',
        'cards': List<dynamic>.from(cards),
        'matched': List<int>.from(matched),
        'finished': matched.length == 12,
        'attempts': matched.length ~/ 2,
      };
    }
    return {'ok': true};
  }
}

void main() {
  testWidgets('upload and save a PDF through the native document contract', (
    tester,
  ) async {
    await prepare(tester);
    final api = ReleaseApi();
    Map<dynamic, dynamic>? saved;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Api.storage, (call) async {
          if (call.method == 'pickDocument') {
            return {
              'name': 'lecture.pdf',
              'data': base64Encode(utf8.encode('%PDF-1.4\nlesson\n%%EOF')),
            };
          }
          if (call.method == 'saveDocument') {
            saved = call.arguments as Map;
            return true;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(Api.storage, null),
    );
    await tester.pumpWidget(frame(documentPage(api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إضافة مستند'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();
    expect(find.text('lecture.pdf'), findsOneWidget);
    await tester.tap(find.byTooltip('حفظ المستند'));
    await tester.pumpAndSettle();
    expect(saved!['name'], 'lecture.pdf');
    await capture(tester, 'StuClub-2.0-documents');
  });
  testWidgets(
    'create a poll, vote, close it and render announcement analytics',
    (tester) async {
      await prepare(tester);
      final api = ReleaseApi();
      await tester.pumpWidget(frame(pollsPage(api)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إنشاء استطلاع'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'أي موعد يناسبكم؟');
      await tester.enterText(find.byType(TextField).at(1), 'الأحد\nالاثنين');
      await tester.tap(find.text('تأكيد'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('الأحد'));
      await tester.pumpAndSettle();
      expect(api.polls.single['total'], 1);
      await capture(tester, 'StuClub-2.0-polls');
      await tester.tap(find.text('إغلاق الاستطلاع'));
      await tester.pumpAndSettle();
      expect(api.polls.single['closed'], true);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(frame(reportsPage(api)));
      await tester.pumpAndSettle();
      expect(find.text('9 من 12 طالب · 75٪'), findsOneWidget);
      await capture(tester, 'StuClub-2.0-reports');
    },
  );
  testWidgets(
    'school creation, email confirmation and illustrated stickers are usable',
    (tester) async {
      await prepare(tester);
      final api = ReleaseApi();
      await tester.pumpWidget(frame(institutionsPage(api)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إضافة مدرسة أو جامعة'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'مدرسة جديدة');
      await tester.tap(find.text('تأكيد'));
      await tester.pumpAndSettle();
      expect(api.createdInstitution!['kind'], 'school');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(frame(servicePage(api)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إدخال كود التأكيد'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('تأكيد'));
      await tester.pumpAndSettle();
      expect(find.text('البريد مؤكد'), findsOneWidget);
      final controller = TextEditingController();
      String? sent;
      await tester.pumpWidget(
        frame(
          Scaffold(
            body: MessageComposer(
              controller: controller,
              sending: false,
              send: () => sent = controller.text,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('ستيكرز'));
      await tester.pumpAndSettle();
      expect(find.byType(ClubSticker), findsNWidgets(6));
      await capture(tester, 'StuClub-2.0-stickers');
      await tester.tap(find.bySemanticsLabel('ملصق عاش!'));
      await tester.pumpAndSettle();
      expect(sent, ':sticker:cheer');
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets('memory game completes through all matched pairs', (
    tester,
  ) async {
    await prepare(tester);
    final api = ReleaseApi();
    await tester.pumpWidget(frame(MemoryGame(api: api)));
    await tester.pumpAndSettle();
    for (var i = 0; i < 12; i++) {
      await tester.ensureVisible(find.bySemanticsLabel('بطاقة ذاكرة ${i + 1}'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('بطاقة ذاكرة ${i + 1}'));
      await tester.pumpAndSettle();
    }
    expect(find.text('أحسنت! اكتملت الجولة'), findsOneWidget);
    await capture(tester, 'StuClub-2.0-memory');
  });
}
