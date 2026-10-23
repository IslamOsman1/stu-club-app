import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stu_club/api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(Api.storage, null));
  test('emulator gets its host alias when no address was saved', () async {
    messenger.setMockMethodCallHandler(
      Api.storage,
      (MethodCall call) async => call.method == 'isEmulator' ? true : null,
    );
    final api = Api();
    await api.restore();
    expect(api.base, 'http://10.0.2.2:8080');
  });
  test('a saved server address is respected', () async {
    messenger.setMockMethodCallHandler(
      Api.storage,
      (MethodCall call) async =>
          call.method == 'read' && call.arguments == 'base'
          ? 'https://example.test'
          : null,
    );
    final api = Api();
    await api.restore();
    expect(api.base, 'https://example.test');
  });
}
