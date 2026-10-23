import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stu_club/api.dart';
import 'package:stu_club/community.dart';

class CommunityApi extends Api {
  final comments = <Map<String, dynamic>>[];
  String? lastMutation;
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
    if (method != 'GET') lastMutation = path;
    if (path == '/blocks') return {'items': []};
    if (path == '/account/recovery') return {'code': 'ONLY-SHOW-ONCE'};
    if (path == '/account/password') return {'ok': true};
    if (path == '/posts/p/comments') {
      if (method == 'POST') {
        comments.add({
          'id': 'c',
          'user': 'me',
          'text': body!['text'],
          'author': {'name': 'أحمد', 'verified': false},
        });
      }
      return {'items': List<Map<String, dynamic>>.from(comments)};
    }
    if (path == '/comments/c') {
      comments.clear();
      return {'ok': true};
    }
    return {'items': []};
  }
}

void main() {
  testWidgets('comments can be added and deleted through the UI', (
    tester,
  ) async {
    final api = CommunityApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: commentsPage(api, {
            'id': 'p',
            'user': 'owner',
            'text': 'منشور',
          }, 'me'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('أضف تعليقًا'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'تعليق جديد');
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();
    expect(find.text('تعليق جديد'), findsOneWidget);
    expect(api.comments.length, 1);
    await tester.tap(find.byTooltip('حذف'));
    await tester.pumpAndSettle();
    expect(api.comments, isEmpty);
  });
  testWidgets('recovery code is shown after password confirmation', (
    tester,
  ) async {
    final api = CommunityApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: AccountTools(api: api, onSignedOut: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('إنشاء كود استعادة الحساب'));
    await tester.pumpAndSettle();
    expect(find.text('ONLY-SHOW-ONCE'), findsNothing);
    await tester.enterText(find.byType(TextField), 'StrongPass123!');
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();
    expect(api.lastMutation, '/account/recovery');
    expect(find.text('ONLY-SHOW-ONCE'), findsOneWidget);
    await tester.tap(find.text('حفظته'));
    await tester.pumpAndSettle();
    expect(find.text('ONLY-SHOW-ONCE'), findsNothing);
  });
}
