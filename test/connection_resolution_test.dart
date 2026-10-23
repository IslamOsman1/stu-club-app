import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stu_club/api.dart';

class ProbeApi extends Api {
  final bool emulator;
  final String works;
  final requests = <String>[];
  ProbeApi({required this.emulator, required this.works});
  @override
  bool get onEmulator => emulator;
  @override
  Future<Map<String, dynamic>> probe(String address) async {
    requests.add(address);
    if (address != works) throw const SocketException('unreachable');
    return {'ok': true, 'service': 'stuclub'};
  }
}

void main() {
  test(
    'emulator falls back between the two local aliases before authentication',
    () async {
      final api = ProbeApi(emulator: true, works: 'http://10.0.2.2:8080')
        ..base = 'http://127.0.0.1:8080';
      expect(await api.checkConnection(), 'http://10.0.2.2:8080');
      expect(api.requests, ['http://127.0.0.1:8080', 'http://10.0.2.2:8080']);
      await api.checkConnection();
      expect(api.requests.length, 2);
    },
  );
  test('physical devices and custom addresses are never redirected to another host', () async {
    for (final api in [
      ProbeApi(emulator: false, works: 'none')..base = 'http://127.0.0.1:8080',
      ProbeApi(emulator: true, works: 'none')..base = 'https://example.test',
    ]) {
      final original = api.base;
      await expectLater(api.checkConnection(), throwsA(isA<ApiException>()));
      expect(api.requests, [original]);
      expect(api.base, original);
    }
  });
}
