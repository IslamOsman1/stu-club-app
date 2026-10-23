import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stu_club/api.dart';
import 'package:stu_club/course_page.dart';
import 'package:stu_club/academic_panel.dart';
import 'package:stu_club/design.dart';

class CourseApi extends Api {
  final bool admin;
  CourseApi({this.admin = true});
  List<dynamic> courses = [], sections = [];
  Map<String, dynamic>? published;
  @override
  Future<Map<String, dynamic>> call(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    if (path == '/courses' && method == 'POST') {
      courses.add({'id': 'c1', 'name': body!['name'], 'code': body['code']});
      return {'id': 'c1'};
    }
    if (path == '/courses') {
      return {'items': courses, 'sections': sections, 'isAdmin': admin};
    }
    if (path == '/courses/people') {
      return {
        'items': [
          {
            'id': 'teacher',
            'name': 'المدرس المعتمد',
            'role': 'doctor',
            'verified': true,
            'email': 'teacher@example.test',
          },
          {
            'id': 'student',
            'name': 'الطالب المسجل',
            'role': 'student',
            'verified': false,
            'email': 'student@example.test',
          },
        ],
      };
    }
    if (path == '/courses/c1/sections') {
      sections.add({
        'id': 's1',
        'name': body!['name'],
        'course': 'c1',
        'courseName': 'البرمجة',
        'teachers': [
          {'id': 'teacher', 'name': 'المدرس المعتمد'},
        ],
        'students': [
          {'id': 'student', 'name': 'الطالب المسجل'},
        ],
        'studentCount': 1,
        'active': true,
        'canPublish': true,
      });
      return {'id': 's1'};
    }
    if (path == '/announcements' && method == 'POST') {
      published = body;
      return {'id': 'a1'};
    }
    if (path == '/announcements') return {'items': [], 'canPublish': true};
    return {'items': []};
  }
}

final captureKey = GlobalKey();
Widget frame(Widget child) => RepaintBoundary(
  key: captureKey,
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
      captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$directory/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  testWidgets(
    'admin creates a course then assigns teacher and student through section editor',
    (tester) async {
      await prepare(tester);
      final api = CourseApi();
      await tester.pumpWidget(frame(CoursePage(api: api)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إنشاء مادة'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'البرمجة');
      await tester.enterText(find.byType(TextField).at(1), 'CS101');
      await tester.tap(find.text('إنشاء'));
      await tester.pumpAndSettle();
      expect(find.text('CS101 · البرمجة'), findsOneWidget);
      await tester.tap(find.text('إضافة شعبة'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'الشعبة أ');
      await tester.tap(find.text('المدرس المعتمد'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('الطالب المسجل'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('الطالب المسجل'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('حفظ التسجيل'));
      await tester.pumpAndSettle();
      expect(api.sections.length, 1);
      expect(find.text('الشعبة أ'), findsOneWidget);
      await capture(tester, 'StuClub-1.5-courses');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'teacher announcement composer targets assigned section instead of entire institution',
    (tester) async {
      await prepare(tester);
      final api = CourseApi(admin: false);
      api.sections = [
        {
          'id': 's1',
          'name': 'الشعبة أ',
          'course': 'c1',
          'courseName': 'البرمجة',
          'active': true,
          'canPublish': true,
        },
      ];
      await tester.pumpWidget(
        frame(
          Scaffold(
            body: SingleChildScrollView(child: AcademicPanel(api: api)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('نشر إعلان رسمي'));
      await tester.pumpAndSettle();
      expect(find.text('البرمجة · الشعبة أ'), findsOneWidget);
      expect(find.text('كل المؤسسة'), findsNothing);
      await capture(tester, 'StuClub-1.5-announcement-target');
      await tester.enterText(find.byType(TextField), 'تغيير موعد المحاضرة');
      await tester.tap(find.text('نشر'));
      await tester.pumpAndSettle();
      expect(api.published!['section'], 's1');
      expect(api.published!.containsKey('group'), false);
    },
  );
}
