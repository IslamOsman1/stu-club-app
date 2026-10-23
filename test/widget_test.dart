import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stu_club/main.dart';
import 'package:stu_club/api.dart';

class FakeApi extends Api {
  bool restored = false;
  @override
  Future<void> restore() async {
    restored = true;
  }

  @override
  Future<void> saveToken(String value) async {
    token = value;
  }

  @override
  Future<void> clear() async {
    token = null;
  }

  @override
  Future<Map<String, dynamic>> call(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    if (path == '/auth/login') {
      return {
        'token': 'test',
        'user': {
          'id': 'a',
          'name': 'أحمد',
          'email': 'a@example.test',
          'university': 'cairo',
          'role': 'student',
          'bio': '',
        },
      };
    }
    if (path == '/announcements') return {'items': [], 'canPublish': false};
    if (path == '/streak') return {'count': 0, 'days': [], 'today': false};
    if (path == '/feed') return {'posts': [], 'stories': []};
    if (path == '/groups') return {'items': []};
    if (path == '/quiz') {
      return {
        'id': 'stack-1',
        'question': 'سؤال اليوم',
        'choices': ['Queue', 'Stack', 'Array'],
      };
    }
    if (path == '/quiz/answer') {
      return {
        'correct': true,
        'points': 10,
        'explanation': 'شرح الإجابة',
        'alreadyAnswered': false,
      };
    }
    if (path == '/leaderboard') return {'items': []};
    return {'ok': true};
  }
}

class SchoolApi extends FakeApi {
  @override
  Future<Map<String, dynamic>> call(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    final result = await super.call(path, method: method, body: body);
    if (path == '/auth/login') {
      result['user'] = Map<String, dynamic>.from(result['user'] as Map);
      result['user']['university'] = 'school_demo';
      result['user']['institutionKind'] = 'school';
      result['user']['verified'] = false;
    }
    return result;
  }
}

void main() {
  testWidgets('unverified school account sees approval instead of content', (
    tester,
  ) async {
    await tester.pumpWidget(StuClub(api: SchoolApi()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'school@example.test');
    await tester.enterText(find.byType(TextField).at(1), 'StrongPass123!');
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'تسجيل الدخول'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'تسجيل الدخول'));
    await tester.pumpAndSettle();
    expect(find.text('بانتظار اعتماد المؤسسة'), findsOneWidget);
    expect(find.text('مايفوتكش إعلان'), findsNothing);
    await tester.tap(find.text('الألعاب'));
    await tester.pumpAndSettle();
    expect(find.text('بانتظار اعتماد المؤسسة'), findsOneWidget);
    expect(find.text('العب. اتواصل. اتعلم.'), findsNothing);
  });

  testWidgets('sign in, quiz feedback and sign out', (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(StuClub(api: api));
    await tester.pumpAndSettle();
    expect(api.restored, true);
    await tester.enterText(find.byType(TextField).at(0), 'a@example.test');
    await tester.enterText(find.byType(TextField).at(1), 'StrongPass123!');
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'تسجيل الدخول'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'تسجيل الدخول'));
    await tester.pumpAndSettle();
    expect(find.text('أهلًا، أحمد 👋'), findsOneWidget);
    expect(api.token, 'test');
    await tester.tap(find.text('الألعاب'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Stack'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stack'));
    await tester.pumpAndSettle();
    expect(find.text('إجابة صحيحة! 🎉'), findsOneWidget);
    await tester.tap(find.text('حسابي'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('تسجيل الخروج'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تسجيل الخروج'));
    await tester.pumpAndSettle();
    expect(api.token, isNull);
    expect(find.text('أهلًا برجوعك'), findsOneWidget);
  });
}
