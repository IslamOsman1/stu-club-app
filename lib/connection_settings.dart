import 'package:flutter/material.dart';

import 'api.dart';
import 'design.dart';

class _ProbeApi extends Api {
  final Api source;
  _ProbeApi(this.source);
  @override
  bool get onEmulator => source.onEmulator;
}

class ConnectionSettings extends StatefulWidget {
  final Api api;
  const ConnectionSettings({super.key, required this.api});
  @override
  State<ConnectionSettings> createState() => _ConnectionSettingsState();
}

class _ConnectionSettingsState extends State<ConnectionSettings> {
  late final address = TextEditingController(text: widget.api.base);
  bool busy = false, success = false;
  String? result;
  @override
  void dispose() {
    address.dispose();
    super.dispose();
  }

  Future<void> check() async {
    setState(() {
      busy = true;
      success = false;
      result = null;
    });
    try {
      final uri = Uri.tryParse(address.text.trim());
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          (uri.path.isNotEmpty && uri.path != '/')) {
        throw ApiException('أدخل عنوانًا صحيحًا مثل http://10.0.2.2:8080');
      }
      final test = _ProbeApi(widget.api)
        ..base = address.text.trim().replaceFirst(RegExp(r'/$'), '');
      final working = await test.checkConnection(force: true);
      if (mounted) {
        setState(() {
          address.text = working;
          success = true;
          result = 'الاتصال شغال. تم التأكد من خادم STU Club.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => result = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('إعداد اتصال الخادم'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'شغّل Start-Local على الكمبيوتر. الفحص لا يرسل بريدك أو كلمة مرورك.',
            style: TextStyle(fontSize: 12, color: ClubStyle.muted),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: address,
            textDirection: TextDirection.ltr,
            enabled: !busy,
            keyboardType: TextInputType.url,
            onChanged: (_) => setState(() {
              success = false;
              result = null;
            }),
            decoration: const InputDecoration(labelText: 'عنوان الخادم'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy ? null : check,
            icon: const Icon(Icons.network_check),
            label: const Text('فحص الاتصال'),
          ),
          if (busy) const LinearProgressIndicator(),
          if (result != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                result!,
                style: TextStyle(
                  fontSize: 12,
                  color: success ? ClubStyle.green : Colors.deepOrange,
                ),
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'المحاكي: 10.0.2.2:8080\nالهاتف عبر USB: 127.0.0.1:8080',
            textDirection: TextDirection.rtl,
            style: TextStyle(fontSize: 10, color: ClubStyle.muted),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('إغلاق'),
      ),
      FilledButton(
        onPressed: !success || busy
            ? null
            : () => Navigator.pop(context, address.text),
        child: const Text('استخدام الاتصال'),
      ),
    ],
  );
}
