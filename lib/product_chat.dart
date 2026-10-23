import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'community.dart';
import 'design.dart';
import 'stickers.dart';

class ProductChat extends StatefulWidget {
  final Api api;
  final String kind, target, title;
  const ProductChat({
    super.key,
    required this.api,
    required this.kind,
    required this.target,
    required this.title,
  });
  @override
  State<ProductChat> createState() => _ProductChatState();
}

class _ProductChatState extends State<ProductChat> {
  final text = TextEditingController(), recorder = AudioRecorder();
  AudioPlayer? player;
  Timer? timer, recordTimer;
  List items = [], typing = [];
  Json? reply;
  String? error, playing;
  final Set<String> playbackFiles = {};
  StreamSubscription<void>? playbackSubscription;
  bool sending = false, fetching = false, recording = false, canManage = false;
  DateTime? lastTyping;
  String get path => '/product/chat/${widget.kind}/${widget.target}';
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 3), (_) => load());
  }

  @override
  void dispose() {
    timer?.cancel();
    recordTimer?.cancel();
    recorder.dispose();
    playbackSubscription?.cancel();
    player?.dispose();
    for (final path in playbackFiles) {
      unawaited(
        File(path)
            .exists()
            .then((exists) async {
              if (exists) await File(path).delete();
            })
            .catchError((Object _) {}),
      );
    }
    text.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (fetching) return;
    fetching = true;
    try {
      final r = await widget.api.call(path);
      if (mounted) {
        setState(() {
          items = r['items'];
          typing = r['typing'];
          canManage = r['canManage'] == true;
          error = null;
        });
      }
      await widget.api.call('$path/read', method: 'POST', body: {});
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      fetching = false;
    }
  }

  Future<void> send({String? voice}) async {
    if (sending || (text.text.trim().isEmpty && voice == null)) return;
    setState(() => sending = true);
    try {
      await widget.api.call(
        path,
        method: 'POST',
        body: {
          'text': text.text.trim(),
          'voice': voice,
          'replyTo': reply?['id'],
        },
      );
      text.clear();
      reply = null;
      await widget.api.call(
        '$path/presence',
        method: 'POST',
        body: {'typing': false},
      );
      await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> typingChanged() async {
    if (lastTyping != null &&
        DateTime.now().difference(lastTyping!) < const Duration(seconds: 3)) {
      return;
    }
    lastTyping = DateTime.now();
    try {
      await widget.api.call(
        '$path/presence',
        method: 'POST',
        body: {'typing': text.text.isNotEmpty},
      );
    } catch (_) {}
  }

  Future<void> toggleRecord() async {
    try {
      if (recording) {
        recordTimer?.cancel();
        final path = await recorder.stop();
        if (mounted) setState(() => recording = false);
        if (path == null) return;
        final file = File(path);
        try {
          if (file.lengthSync() > 5 * 1024 * 1024) {
            throw ApiException('التسجيل أكبر من الحد المسموح');
          }
          final upload = await widget.api.call(
            '/product/voice-files',
            method: 'POST',
            body: {'data': base64Encode(await file.readAsBytes())},
          );
          await send(voice: upload['id']);
        } finally {
          if (await file.exists()) await file.delete();
        }
      } else {
        if (!await recorder.hasPermission()) {
          throw ApiException('اسمح بالميكروفون لتسجيل رسالة صوتية');
        }
        final dir = await getTemporaryDirectory();
        await recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 64000,
            sampleRate: 44100,
          ),
          path:
              '${dir.path}/voice-${DateTime.now().millisecondsSinceEpoch}.m4a',
        );
        if (mounted) setState(() => recording = true);
        recordTimer = Timer(const Duration(minutes: 2), () {
          if (mounted && recording) toggleRecord();
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> play(Json m) async {
    try {
      if (playing == m['id']) {
        await player?.stop();
        if (mounted) setState(() => playing = null);
        return;
      }
      await player?.stop();
      final bytes = await widget.api.binary(
        '/product/voice-files/${m['voice']}',
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/received-${m['voice']}.m4a');
      await file.writeAsBytes(bytes, flush: true);
      playbackFiles.add(file.path);
      if (player == null) {
        player = AudioPlayer();
        playbackSubscription = player!.onPlayerComplete.listen((_) {
          if (mounted) setState(() => playing = null);
        });
      }
      await player!.play(DeviceFileSource(file.path));
      if (mounted) setState(() => playing = m['id']);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> messageAction(String action, Json m) async {
    try {
      if (action == 'reply') {
        setState(() => reply = m);
        return;
      }
      if (action == 'edit') {
        final f = await askFields(
          context,
          'تعديل الرسالة',
          {'text': 'النص'},
          initial: {'text': m['text']},
        );
        if (f != null) {
          await widget.api.call(
            '/product/messages/${widget.kind}/${m['id']}',
            method: 'PATCH',
            body: f,
          );
        }
      }
      if (!mounted) return;
      if (action == 'delete' && await confirm(context, 'حذف الرسالة للجميع؟')) {
        await widget.api.call(
          '/product/messages/${widget.kind}/${m['id']}',
          method: 'DELETE',
        );
      }
      if (!mounted) return;
      if (action == 'report') {
        final f = await askFields(context, 'إبلاغ عن الرسالة', {
          'reason': 'سبب الإبلاغ',
        });
        if (f != null) {
          await widget.api.call(
            '/reports',
            method: 'POST',
            body: {
              ...f,
              'type': widget.kind == 'direct' ? 'direct' : 'messages',
              'target': m['id'],
            },
          );
        }
      }
      await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Widget messageTile(Json m) => Align(
    alignment: m['mine'] == true ? Alignment.centerRight : Alignment.centerLeft,
    child: Card(
      color: m['mine'] == true ? const Color(0xff243361) : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 330),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                m['author']['name'],
                style: const TextStyle(fontSize: 11, color: ClubStyle.green),
              ),
              if (m['reply'] != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  color: Colors.white10,
                  child: Text(
                    'رد على: ${m['reply']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (m['voice'] != null)
                TextButton.icon(
                  onPressed: () => play(m),
                  icon: Icon(
                    playing == m['id']
                        ? Icons.stop_circle_outlined
                        : Icons.play_circle_outline,
                  ),
                  label: const Text('رسالة صوتية'),
                ),
              if ((m['text'] as String).startsWith(':sticker:'))
                ClubSticker(id: (m['text'] as String).substring(9))
              else if ((m['text'] as String).isNotEmpty)
                SelectableText(m['text']),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${m['created'].toString().substring(11, 16)}${m['edited'] != null ? ' · معدّلة' : ''}',
                    style: const TextStyle(fontSize: 9, color: ClubStyle.muted),
                  ),
                  if (m['mine'] == true)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        (m['readCount'] as int) > 0
                            ? Icons.done_all
                            : Icons.done,
                        size: 14,
                        color: (m['readCount'] as int) > 0
                            ? Colors.cyan
                            : ClubStyle.muted,
                      ),
                    ),
                  PopupMenuButton<String>(
                    onSelected: (a) => messageAction(a, m),
                    itemBuilder: (_) => [
                      if (m['deleted'] != true)
                        const PopupMenuItem(
                          value: 'reply',
                          child: Text('رد على الرسالة'),
                        ),
                      if (m['mine'] == true && m['deleted'] != true)
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('تعديل'),
                        ),
                      if ((m['mine'] == true || canManage) &&
                          m['deleted'] != true)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('حذف'),
                        ),
                      if (m['mine'] != true)
                        const PopupMenuItem(
                          value: 'report',
                          child: Text('إبلاغ'),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        if (widget.kind == 'group')
          IconButton(
            tooltip: 'معلومات المجموعة',
            icon: const Icon(Icons.group_outlined),
            onPressed: () =>
                openPage(context, groupSettings(widget.api, widget.target)),
          ),
      ],
    ),
    body: Column(
      children: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              error!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        if (typing.isNotEmpty)
          Text(
            '${typing.map((p) => p['name']).join('، ')} يكتب الآن…',
            style: const TextStyle(color: ClubStyle.muted),
          ),
        Expanded(
          child: ListView.builder(
            reverse: true,
            padding: const EdgeInsets.all(15),
            itemCount: items.length,
            itemBuilder: (c, i) =>
                messageTile(items[items.length - 1 - i] as Json),
          ),
        ),
        if (reply != null)
          ListTile(
            dense: true,
            title: Text('رد على: ${reply!['text']}', maxLines: 1),
            trailing: IconButton(
              onPressed: () => setState(() => reply = null),
              icon: const Icon(Icons.close),
            ),
          ),
        if (recording)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'جارٍ التسجيل… اضغط إيقاف للإرسال (حتى دقيقتين)',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                PopupMenuButton<String>(
                  tooltip: 'الملصقات',
                  icon: const Icon(Icons.emoji_emotions_outlined),
                  onSelected: (sticker) {
                    text.text = ':sticker:$sticker';
                    send();
                  },
                  itemBuilder: (_) => [
                    for (final st in ClubSticker.ids)
                      PopupMenuItem(
                        value: st,
                        child: ClubSticker(id: st, size: 64),
                      ),
                  ],
                ),
                IconButton(
                  tooltip: recording
                      ? 'إيقاف وإرسال التسجيل'
                      : 'تسجيل رسالة صوتية',
                  onPressed: sending ? null : toggleRecord,
                  icon: Icon(
                    recording ? Icons.stop_circle : Icons.mic_none,
                    color: recording ? Colors.redAccent : null,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: text,
                    onChanged: (_) => typingChanged(),
                    maxLines: 3,
                    minLines: 1,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      hintText: 'رسالتك…',
                      counterText: '',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'إرسال',
                  onPressed: sending ? null : () => send(),
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

Widget groupSettings(Api api, String group) => RemotePanel(
  api: api,
  path: '/product/groups/$group',
  title: 'معلومات وإدارة المجموعة',
  content: (s) {
    final g = s.data!['group'] as Json, members = g['members'] as List;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          g['name'],
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
        ),
        Text(g['description'] ?? ''),
        if (g['section'] == null)
          OutlinedButton.icon(
            icon: const Icon(Icons.person_add_alt),
            label: const Text('دعوة عضو للمجموعة'),
            onPressed: () => s.action(() async {
              final people = (await api.call('/people'))['items'] as List;
              if (!s.mounted) return;
              final selected = await showDialog<String>(
                context: s.context,
                builder: (c) => SimpleDialog(
                  title: const Text('اختر صاحب الدعوة'),
                  children: [
                    for (final peer in people.where(
                      (p) => !members.any((m) => m['id'] == p['id']),
                    ))
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(c, peer['id'] as String),
                        child: Text(peer['name']),
                      ),
                  ],
                ),
              );
              if (selected != null) {
                await api.call(
                  '/product/groups/$group/invite',
                  method: 'POST',
                  body: {'user': selected},
                );
              }
            }),
          ),
        if (g['section'] != null)
          const Text('مجموعة شعبة رسمية؛ العضوية من تسجيل المادة.'),
        if (s.data!['canManage'] == true && g['section'] == null)
          FilledButton(
            onPressed: () => s.action(() async {
              final f = await askFields(
                s.context,
                'تعديل المجموعة',
                {'name': 'الاسم', 'description': 'الوصف'},
                initial: {
                  'name': g['name'],
                  'description': g['description'] ?? '',
                },
              );
              if (f != null) {
                await api.call(
                  '/product/groups/$group',
                  method: 'PATCH',
                  body: {...f, 'moderators': g['moderators'] ?? []},
                );
              }
            }),
            child: const Text('تعديل المجموعة'),
          ),
        ...members.map(
          (m) => Card(
            child: ListTile(
              title: Text(m['name']),
              subtitle: Text(
                (g['moderators'] as List? ?? []).contains(m['id'])
                    ? 'مشرف مجموعة'
                    : 'عضو',
              ),
              trailing: s.data!['canManage'] == true && g['section'] == null
                  ? PopupMenuButton<String>(
                      onSelected: (a) => s.action(() async {
                        if (a == 'remove') {
                          if (await confirm(
                            s.context,
                            'إزالة العضو من المجموعة؟',
                          )) {
                            await api.call(
                              '/product/groups/$group/remove',
                              method: 'POST',
                              body: {'user': m['id']},
                            );
                          }
                        } else {
                          final moderators = List<dynamic>.from(
                            g['moderators'] ?? [],
                          );
                          moderators.contains(m['id'])
                              ? moderators.remove(m['id'])
                              : moderators.add(m['id']);
                          await api.call(
                            '/product/groups/$group',
                            method: 'PATCH',
                            body: {
                              'name': g['name'],
                              'description': g['description'] ?? '',
                              'moderators': moderators,
                            },
                          );
                        }
                      }),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'moderator',
                          child: Text('تبديل إشراف المجموعة'),
                        ),
                        const PopupMenuItem(
                          value: 'remove',
                          child: Text('إزالة العضو'),
                        ),
                      ],
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  },
);
