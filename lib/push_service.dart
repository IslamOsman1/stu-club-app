import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'api.dart';

class PushService {
  static bool listening = false;
  static Future<void> enable(Api api) async {
    const key = String.fromEnvironment('FIREBASE_API_KEY'),
        app = String.fromEnvironment('FIREBASE_APP_ID'),
        project = String.fromEnvironment('FIREBASE_PROJECT_ID'),
        sender = String.fromEnvironment('FIREBASE_SENDER_ID');
    if ([key, app, project, sender].any((v) => v.isEmpty)) {
      throw ApiException('خدمة إشعارات الهاتف غير مجهزة في هذه النسخة بعد');
    }
    final status = await api.call('/services');
    if (status['pushConfigured'] != true) {
      throw ApiException('خادم الإشعارات لم يُجهز بعد');
    }
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: key,
          appId: app,
          projectId: project,
          messagingSenderId: sender,
        ),
      );
    }
    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      throw ApiException('اسمح بالإشعارات من إعدادات الهاتف');
    }
    // HTTP v1 adapter uses registration tokens, which remain supported by this SDK.
    // ignore: deprecated_member_use
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) throw ApiException('تعذر تسجيل جهازك للإشعارات');
    await api.call('/devices', method: 'POST', body: {'token': token});
    if (!listening) {
      listening = true;
      // ignore: deprecated_member_use
      FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
        if (api.token != null) {
          try {
            await api.call('/devices', method: 'POST', body: {'token': token});
          } catch (_) {}
        }
      });
      FirebaseMessaging.onMessage.listen((message) {
        Api.storage
            .invokeMethod('notify', {
              'title': 'StuClub',
              'text': 'لديك تحديث جديد داخل التطبيق',
            })
            .catchError((_) {
              return null;
            });
      });
    }
  }
}
