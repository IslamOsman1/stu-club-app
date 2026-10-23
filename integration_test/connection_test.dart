import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:stu_club/api.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android app reaches local API and completes register and login', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('STU Club — connection verification')),
        ),
      ),
    );
    final api = Api()..base = 'http://10.0.2.2:18083';
    final watch = Stopwatch()..start();
    expect((await api.probe(api.base))['service'], 'stuclub');
    final email =
        'device-${DateTime.now().microsecondsSinceEpoch}@example.test';
    final registered = await api.call(
      '/auth/register',
      method: 'POST',
      body: {
        'name': 'Device Test',
        'email': email,
        'password': 'DeviceTestPass123!',
        'university': 'cairo',
      },
    );
    expect(registered['token'], isA<String>());
    final loggedIn = await api.call(
      '/auth/login',
      method: 'POST',
      body: {'email': email, 'password': 'DeviceTestPass123!'},
    );
    api.token = loggedIn['token'] as String;
    expect((await api.call('/me'))['user']['email'], email);
    expect((await api.call('/feed'))['posts'], isA<List>());
    await api.call(
      '/account/delete',
      method: 'POST',
      body: {'password': 'DeviceTestPass123!'},
    );
    watch.stop();
    debugPrint(
      'Device API register/login verification passed in ${watch.elapsed.inSeconds}s',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
