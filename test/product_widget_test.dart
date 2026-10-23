import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stu_club/api.dart';
import 'package:stu_club/design.dart';
import 'package:stu_club/product_center.dart';

class ProductApi extends Api {
  final calls = <String>[];
  bool registered = false, accepted = false;
  @override
  Future<Map<String, dynamic>> call(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    calls.add('$method $path');
    if (path == '/product/events/e/register') {
      registered = true;
      return {'ok': true};
    }
    if (path == '/product/events') {
      return {
        'canCreate': false,
        'items': [
          {
            'id': 'e',
            'title': 'لقاء نادي العلوم',
            'text': 'نشاط حقيقي',
            'location': 'القاعة الرئيسية',
            'starts': '2026-11-01T10:00:00Z',
            'ends': '2026-11-01T12:00:00Z',
            'capacity': 20,
            'registered': registered ? 1 : 0,
            'mine': registered
                ? {'status': 'registered', 'attended': false}
                : null,
            'canManage': false,
            'cancelled': false,
          },
        ],
      };
    }
    if (path == '/product/group-invites/i') {
      accepted = true;
      return {'ok': true};
    }
    if (path == '/product/group-invites') {
      return {
        'items': accepted
            ? []
            : [
                {
                  'id': 'i',
                  'groupName': 'نادي العلوم',
                  'person': {'id': 'a', 'name': 'أحمد'},
                },
              ],
      };
    }
    return {'items': []};
  }
}

Widget host(Widget child) => MaterialApp(
  theme: ClubStyle.theme(),
  home: Directionality(textDirection: TextDirection.rtl, child: child),
);
void main() {
  testWidgets(
    'product center exposes working services on a narrow Android screen',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ProductApi();
      await tester.pumpWidget(host(ProductCenter(api: api)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('الفعاليات والحضور'));
      await tester.pumpAndSettle();
      expect(find.text('لقاء نادي العلوم'), findsOneWidget);
      await tester.tap(find.text('التسجيل في الفعالية'));
      await tester.pumpAndSettle();
      expect(api.registered, isTrue);
      expect(find.text('إلغاء تسجيلي'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('group invitation acceptance reloads its real response', (
    tester,
  ) async {
    final api = ProductApi();
    await tester.pumpWidget(host(groupInvitesPage(api)));
    await tester.pumpAndSettle();
    expect(find.text('نادي العلوم'), findsOneWidget);
    await tester.tap(find.text('قبول'));
    await tester.pumpAndSettle();
    expect(api.accepted, isTrue);
    expect(find.text('لا توجد دعوات معلقة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
