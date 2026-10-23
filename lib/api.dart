import 'package:flutter/foundation.dart';

import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

class ApiException implements Exception {
  final String message;
  final int status;
  ApiException(this.message, [this.status = 0]);
  @override
  String toString() => message;
}

class Api {
  bool _emulator = false;
  bool get onEmulator => _emulator;
  DateTime? _lastCheck;
  String? _checkedBase;
  Future<Map<String, dynamic>> probe(String address) async {
    if (kReleaseMode && Uri.tryParse(address)?.scheme != 'https') {
      throw ApiException('نسخة النشر تحتاج عنوان خادم HTTPS');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final req = await client
          .getUrl(Uri.parse('$address/health'))
          .timeout(const Duration(seconds: 5));
      final res = await req.close().timeout(const Duration(seconds: 5));
      final text = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) {
        throw ApiException('الخادم لا يستجيب لفحص الاتصال');
      }
      final data = jsonDecode(text) as Map<String, dynamic>;
      if (data['ok'] != true || data['service'] != 'stuclub') {
        throw ApiException('العنوان ليس خادم STU Club');
      }
      return data;
    } finally {
      client.close(force: true);
    }
  }

  Future<String> checkConnection({bool force = false}) async {
    if (!force &&
        _checkedBase == base &&
        _lastCheck != null &&
        DateTime.now().difference(_lastCheck!).inSeconds < 30) {
      return base;
    }
    final uri = Uri.parse(base);
    final local =
        uri.scheme == 'http' &&
        uri.port == 8080 &&
        ['127.0.0.1', 'localhost', '10.0.2.2'].contains(uri.host);
    final addresses = <String>{
      base,
      if (local && onEmulator) 'http://10.0.2.2:8080',
      if (local && onEmulator) 'http://127.0.0.1:8080',
    };
    Object? failure;
    for (final address in addresses) {
      try {
        await probe(address);
        base = address;
        _checkedBase = address;
        _lastCheck = DateTime.now();
        return base;
      } catch (e) {
        failure = e;
      }
    }
    _lastCheck = null;
    if (failure is ApiException) throw failure;
    throw ApiException(
      'لم نصل إلى خادم STU Club. شغّل Start-Local على الكمبيوتر، ثم اضغط فحص الاتصال. العنوان الحالي: $base',
    );
  }

  Future<Uint8List> media(String id) => binary('/media/$id');
  Future<Uint8List> binary(String path) async {
    if (kReleaseMode && Uri.tryParse(base)?.scheme != 'https') {
      throw ApiException('نسخة النشر تحتاج عنوان خادم HTTPS');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client
          .getUrl(Uri.parse('$base$path'))
          .timeout(const Duration(seconds: 15));
      if (token != null) req.headers.set('Authorization', 'Bearer $token');
      final response = await req.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw ApiException('تعذر تحميل الملف', response.statusCode);
      }
      final bytes = BytesBuilder();
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        bytes.add(chunk);
        if (bytes.length > 21 * 1024 * 1024) {
          throw ApiException('الملف أكبر من المسموح');
        }
      }
      return bytes.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  static const storage = MethodChannel('stuclub/secure');
  String base = const String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://127.0.0.1:8080',
  );
  String? token;
  Future<void> restore() async {
    token = await storage.invokeMethod<String>('read', 'token');
    final saved = await storage.invokeMethod<String>('read', 'base');
    _emulator = await storage.invokeMethod<bool>('isEmulator') == true;
    if (saved != null) {
      base = saved;
    } else if (const String.fromEnvironment('API_URL').isEmpty && onEmulator) {
      base = 'http://10.0.2.2:8080';
    }
  }

  Future<void> configure(String value) async {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw ApiException('أدخل عنوان خادم صحيحًا مثل http://127.0.0.1:8080');
    }
    base = value.trim().replaceFirst(RegExp(r'/$'), '');
    _lastCheck = null;
    token = null;
    await storage.invokeMethod('delete', 'token');
    await storage.invokeMethod('write', {'key': 'base', 'value': base});
  }

  Future<void> saveToken(String value) async {
    await storage.invokeMethod('write', {'key': 'token', 'value': value});
    token = value;
  }

  Future<void> clear() async {
    token = null;
    await storage.invokeMethod('delete', 'token');
  }

  Future<Map<String, dynamic>> call(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    if (path.startsWith('/auth/') &&
            method == 'POST' &&
            path != '/auth/logout' ||
        path == '/me' && token != null) {
      await checkConnection();
    }
    if (kReleaseMode && Uri.tryParse(base)?.scheme != 'https') {
      throw ApiException('نسخة النشر تحتاج عنوان خادم HTTPS');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client
          .openUrl(method, Uri.parse('$base$path'))
          .timeout(const Duration(seconds: 12));
      req.headers.contentType = ContentType.json;
      if (token != null) req.headers.set('Authorization', 'Bearer $token');
      if (body != null) req.write(jsonEncode(body));
      final response = await req.close().timeout(
        Duration(
          seconds: path.startsWith('/auth/') || path.startsWith('/account/')
              ? 60
              : 30,
        ),
      );
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 20));
      final parsed = jsonDecode(text) as Map<String, dynamic>;
      if (response.statusCode >= 400) {
        throw ApiException(
          parsed['error'] as String? ?? 'تعذر تنفيذ الطلب',
          response.statusCode,
        );
      }
      return parsed;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      _lastCheck = null;
      throw ApiException(
        'الخادم لم يستجب في الوقت المحدد. انتظر لحظة ثم حاول مرة أخرى.',
      );
    } on SocketException {
      _lastCheck = null;
      throw ApiException(
        'تعذر الوصول إلى $base. افتح إعداد الاتصال واضغط فحص الاتصال.',
      );
    } on HandshakeException {
      throw ApiException(
        'تعذر تأمين الاتصال بالخادم. تحقق من العنوان وشهادة HTTPS.',
      );
    } on FormatException {
      throw ApiException(
        'الخادم أعاد استجابة غير صالحة. تحقق من أن العنوان يخص STU Club.',
      );
    } on HttpException {
      _lastCheck = null;
      throw ApiException(
        'انقطع الاتصال بالخادم. افحص الاتصال ثم حاول مرة أخرى.',
      );
    } finally {
      client.close(force: true);
    }
  }
}
