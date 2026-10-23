import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'api.dart';
import 'community.dart';
import 'design.dart';
import 'release_hub.dart';

class VoiceRoomsPage extends StatelessWidget {
  final Api api;
  const VoiceRoomsPage({super.key, required this.api});
  @override
  Widget build(BuildContext context) => RemotePanel(
    api: api,
    path: '/product/rooms',
    title: 'الغرف الصوتية',
    content: (s) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'حوار صوتي مباشر حتى 6 مشاركين. تبدأ بالميكروفون مغلقًا؛ اطلب التحدث من المضيف. الغرفة تعمل أثناء فتحها في التطبيق.',
        ),
        const SizedBox(height: 15),
        if (s.data!['canCreate'] == true)
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('إنشاء غرفة صوتية'),
            onPressed: () => s.action(() async {
              final f = await releaseForm(s.context, api, 'غرفة جديدة', {
                'title': 'عنوان الحوار',
              }, audience: true);
              if (f != null) {
                await api.call('/product/rooms', method: 'POST', body: f);
              }
            }),
          ),
        ...(s.data!['items'] as List).map(
          (r) => Card(
            child: ListTile(
              leading: const Icon(Icons.headset_mic, color: ClubStyle.green),
              title: Text(r['title']),
              subtitle: Text('${r['host']['name']} · ${r['count']} / 6'),
              onTap: () async {
                await openPage(
                  s.context,
                  VoiceRoomPage(api: api, room: r['id'], title: r['title']),
                );
                if (s.mounted) await s.load();
              },
            ),
          ),
        ),
        if ((s.data!['items'] as List).isEmpty)
          const Padding(
            padding: EdgeInsets.all(30),
            child: Text('لا توجد غرف مفتوحة. أنشئ غرفة وادعُ زملاءك.'),
          ),
      ],
    ),
  );
}

class VoiceRoomPage extends StatefulWidget {
  final Api api;
  final String room, title;
  const VoiceRoomPage({
    super.key,
    required this.api,
    required this.room,
    required this.title,
  });
  @override
  State<VoiceRoomPage> createState() => _VoiceRoomState();
}

class _VoiceRoomState extends State<VoiceRoomPage> with WidgetsBindingObserver {
  MediaStream? local;
  Timer? timer;
  Json? self;
  List participants = [], servers = [];
  final Map<String, RTCPeerConnection> peers = {};
  final Map<String, RTCVideoRenderer> renderers = {};
  final Map<String, List<RTCIceCandidate>> candidates = {};
  final Set<String> offered = {};
  final Map<String, String> connection = {};
  int cursor = 0;
  bool polling = false, joining = false, canManage = false;
  String? error;
  bool leaving = false;
  String get base => '/product/rooms/${widget.room}';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    join();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && self != null) {
      leave();
    }
  }

  Future<void> join() async {
    if (joining) return;
    setState(() {
      joining = true;
      error = null;
    });
    try {
      local = await navigator.mediaDevices.getUserMedia({
        'audio': {'echoCancellation': true, 'noiseSuppression': true},
        'video': false,
      });
      for (final t in local!.getAudioTracks()) {
        t.enabled = false;
      }
      final r = await widget.api.call('$base/join', method: 'POST', body: {});
      if (!mounted) {
        await leave();
        return;
      }
      setState(() {
        self = r['self'];
        participants = r['participants'];
        servers = r['iceServers'];
        canManage = r['room']['canManage'] == true;
      });
      await Helper.setSpeakerphoneOn(true);
      timer = Timer.periodic(const Duration(seconds: 3), (_) => poll());
      await poll();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
      await leave();
    } finally {
      if (mounted) setState(() => joining = false);
    }
  }

  Future<RTCPeerConnection> peer(String id) async {
    if (peers[id] != null) return peers[id]!;
    final pc = await createPeerConnection({
      'iceServers': servers,
      'sdpSemantics': 'unified-plan',
    });
    peers[id] = pc;
    candidates[id] = [];
    for (final track in local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      await pc.addTrack(track, local!);
    }
    pc.onIceCandidate = (c) {
      if (c.candidate != null && self != null) {
        sendSignal(id, 'candidate', {
          'candidate': c.candidate,
          'sdpMid': c.sdpMid ?? '',
          'sdpMLineIndex': c.sdpMLineIndex ?? 0,
        });
      }
    };
    pc.onTrack = (event) async {
      if (event.streams.isEmpty) return;
      final renderer = RTCVideoRenderer();
      await renderer.initialize();
      if (!mounted || self == null) {
        await renderer.dispose();
        return;
      }
      renderer.srcObject = event.streams.first;
      renderer.muted = true;
      await renderers[id]?.dispose();
      renderers[id] = renderer;
      syncAudio();
      if (mounted) setState(() {});
    };
    pc.onConnectionState = (state) {
      connection[id] = state.name;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        if (mounted) {
          setState(
            () => error =
                'تعذر اتصال الصوت بأحد المشاركين. قد تحتاج الشبكة خادم TURN.',
          );
        }
      } else if (mounted) {
        setState(() {});
      }
    };
    return pc;
  }

  Future<void> sendSignal(String to, String type, Json payload) async {
    try {
      await widget.api.call(
        '$base/signal',
        method: 'POST',
        body: {'to': to, 'type': type, ...payload},
      );
    } catch (e) {
      if (mounted && self != null) setState(() => error = '$e');
    }
  }

  Future<void> applySignal(Json s) async {
    final id = s['from'] as String;
    if (!participants.any((p) => p['id'] == id)) return;
    final pc = await peer(id), payload = s['payload'] as Json;
    if (s['type'] == 'candidate') {
      final c = RTCIceCandidate(
        payload['candidate'],
        payload['sdpMid'],
        payload['sdpMLineIndex'],
      );
      if (await pc.getRemoteDescription() == null) {
        candidates[id]!.add(c);
      } else {
        await pc.addCandidate(c);
      }
      return;
    }
    await pc.setRemoteDescription(
      RTCSessionDescription(payload['sdp'], s['type']),
    );
    for (final c in candidates[id] ?? <RTCIceCandidate>[]) {
      await pc.addCandidate(c);
    }
    candidates[id]?.clear();
    if (s['type'] == 'offer') {
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      await sendSignal(id, 'answer', {'sdp': answer.sdp});
    }
  }

  void syncAudio() {
    final enabled =
        self != null &&
        self!['role'] == 'speaker' &&
        self!['muted'] == false &&
        self!['forcedMuted'] != true;
    for (final t in local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = enabled;
    }
    for (final e in renderers.entries) {
      final p = participants
          .cast<Json>()
          .where((p) => p['id'] == e.key)
          .firstOrNull;
      e.value.muted =
          p == null ||
          p['role'] != 'speaker' ||
          p['muted'] != false ||
          p['forcedMuted'] == true;
    }
  }

  Future<void> poll() async {
    if (polling || self == null || leaving) return;
    polling = true;
    try {
      final r = await widget.api.call('$base/state?after=$cursor');
      if (!mounted) return;
      self = r['self'];
      participants = r['participants'];
      canManage = r['room']['canManage'] == true;
      for (final id in peers.keys.toList()) {
        if (!participants.any((p) => p['id'] == id)) {
          await peers.remove(id)?.close();
          await renderers.remove(id)?.dispose();
          offered.remove(id);
          candidates.remove(id);
          connection.remove(id);
        }
      }
      for (final s in r['signals'] as List) {
        await applySignal(s as Json);
      }
      cursor = r['cursor'];
      for (final p in participants) {
        final id = p['id'] as String;
        if (id == self!['id']) continue;
        if ((self!['id'] as String).compareTo(id) < 0 &&
            !offered.contains(id)) {
          offered.add(id);
          final pc = await peer(id);
          final offer = await pc.createOffer();
          await pc.setLocalDescription(offer);
          await sendSignal(id, 'offer', {'sdp': offer.sdp});
        }
      }
      syncAudio();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => error = '$e');
      if (e is ApiException && [403, 404].contains(e.status)) {
        await leave();
      }
    } finally {
      polling = false;
    }
  }

  Future<void> closeMedia() async {
    timer?.cancel();
    for (final p in peers.values) {
      await p.close();
    }
    peers.clear();
    for (final r in renderers.values) {
      await r.dispose();
    }
    renderers.clear();
    for (final t in local?.getTracks() ?? <MediaStreamTrack>[]) {
      await t.stop();
    }
    await local?.dispose();
    local = null;
    offered.clear();
    candidates.clear();
    cursor = 0;
  }

  Future<void> leave() async {
    if (leaving) return;
    leaving = true;
    timer?.cancel();
    final joined = self != null;
    self = null;
    await closeMedia();
    if (joined) {
      try {
        await widget.api.call('$base/leave', method: 'POST', body: {});
      } catch (_) {}
    }
    if (mounted) setState(() {});
    leaving = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    unawaited(leave());
    super.dispose();
  }

  Future<void> control(Json participant, String action) async {
    try {
      await widget.api.call(
        '$base/control',
        method: 'POST',
        body: {'participant': participant['id'], 'action': action},
      );
      await poll();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        if (canManage && self != null)
          IconButton(
            tooltip: 'إغلاق الغرفة',
            icon: const Icon(Icons.close),
            onPressed: () async {
              if (await confirm(context, 'إنهاء الغرفة لكل المشاركين؟')) {
                await widget.api.call('$base/close', method: 'POST', body: {});
                await leave();
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
      ],
    ),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          if (joining) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                error!,
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            ),
          const Text(
            'الصوت لا يُسجّل داخل الغرفة. ارفع يدك لطلب التحدث.',
            style: TextStyle(color: ClubStyle.muted),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              childAspectRatio: 1.1,
              children: participants.map((raw) {
                final p = raw as Json;
                return Card(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: ClubStyle.green,
                        child: Icon(
                          p['muted'] == true || p['role'] != 'speaker'
                              ? Icons.mic_off
                              : Icons.mic,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(p['person']?['name'] ?? '', maxLines: 1),
                      Text(
                        p['role'] == 'speaker' ? 'متحدث' : 'مستمع',
                        style: const TextStyle(
                          color: ClubStyle.muted,
                          fontSize: 11,
                        ),
                      ),
                      if (p['hand'] == true)
                        const Icon(
                          Icons.front_hand_outlined,
                          color: Colors.amber,
                        ),
                      if (p['id'] != self?['id'])
                        Text(
                          connection[p['id']]?.contains('Connected') == true
                              ? 'متصل'
                              : 'جاري اتصال الصوت',
                          style: const TextStyle(fontSize: 9),
                        ),
                      if (canManage && p['id'] != self?['id'])
                        PopupMenuButton<String>(
                          onSelected: (a) => control(p, a),
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'speaker',
                              child: Text('السماح بالتحدث'),
                            ),
                            const PopupMenuItem(
                              value: 'listener',
                              child: Text('تحويل إلى مستمع'),
                            ),
                            const PopupMenuItem(
                              value: 'mute',
                              child: Text('كتم'),
                            ),
                            const PopupMenuItem(
                              value: 'allow',
                              child: Text('رفع الكتم الإجباري'),
                            ),
                            const PopupMenuItem(
                              value: 'remove',
                              child: Text('إزالة من الغرفة'),
                            ),
                          ],
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          for (final r in renderers.values)
            SizedBox(width: 1, height: 1, child: RTCVideoView(r)),
          if (self == null)
            FilledButton.icon(
              onPressed: joining ? null : join,
              icon: const Icon(Icons.login),
              label: const Text('الانضمام للغرفة'),
            )
          else
            Wrap(
              spacing: 12,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed:
                      self!['role'] != 'speaker' || self!['forcedMuted'] == true
                      ? null
                      : () async {
                          try {
                            await widget.api.call(
                              '$base/mute',
                              method: 'POST',
                              body: {'muted': self!['muted'] != true},
                            );
                            await poll();
                          } catch (e) {
                            if (mounted) setState(() => error = '$e');
                          }
                        },
                  icon: Icon(
                    self!['muted'] == true ? Icons.mic_off : Icons.mic,
                  ),
                  label: Text(
                    self!['muted'] == true ? 'فتح الميكروفون' : 'كتم',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await widget.api.call(
                      '$base/hand',
                      method: 'POST',
                      body: {},
                    );
                    await poll();
                  },
                  icon: const Icon(Icons.front_hand_outlined),
                  label: const Text('طلب التحدث'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await leave();
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.call_end, color: Colors.redAccent),
                  label: const Text('مغادرة'),
                ),
              ],
            ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
}
