import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'api.dart';

class ComposeDialog extends StatefulWidget {
  final Api api;
  final String type;
  const ComposeDialog({super.key, required this.api, required this.type});
  @override
  State<ComposeDialog> createState() => _ComposeDialogState();
}

class _ComposeDialogState extends State<ComposeDialog> {
  final text = TextEditingController();
  XFile? attachment;
  String? uploaded, error;
  bool busy = false;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    try {
      final selected = await ImagePicker().pickMedia(
        requestFullMetadata: false,
      );
      if (selected == null) return;
      if (await selected.length() > 20 * 1024 * 1024) {
        throw ApiException('الحد الأقصى ٢٠ ميجابايت');
      }
      if (mounted) {
        setState(() {
          attachment = selected;
          uploaded = null;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ApiException ? e.message : 'تعذر اختيار الملف',
        );
      }
    }
  }

  Future<void> publish() async {
    if (busy || (text.text.trim().isEmpty && attachment == null)) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (attachment != null && uploaded == null) {
        final data = await attachment!.readAsBytes();
        final res = await widget.api.call(
          '/media',
          method: 'POST',
          body: {'data': base64Encode(data)},
        );
        uploaded = res['id'] as String;
      }
      await widget.api.call(
        '/${widget.type}',
        method: 'POST',
        body: {
          'text': text.text.trim(),
          if (uploaded != null) 'media': uploaded,
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(widget.type == 'posts' ? 'منشور جديد' : 'استوري · ٢٤ ساعة'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: text,
              maxLength: widget.type == 'posts' ? 2000 : 500,
              minLines: 3,
              maxLines: 6,
              enabled: !busy,
              decoration: const InputDecoration(hintText: 'شارك لحظتك...'),
            ),
            if (attachment != null)
              Text(
                attachment!.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            OutlinedButton.icon(
              onPressed: busy ? null : pick,
              icon: const Icon(Icons.perm_media_outlined),
              label: const Text('أضف صورة أو فيديو · حتى ٢٠ ميجابايت'),
            ),
            if (attachment != null)
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        attachment = null;
                        uploaded = null;
                      }),
                child: const Text('إزالة المرفق'),
              ),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.deepOrange)),
            if (busy) const LinearProgressIndicator(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: busy ? null : publish,
          child: const Text('نشر'),
        ),
      ],
    ),
  );
}

class MediaTile extends StatefulWidget {
  final Api api;
  final String id, kind;
  const MediaTile({
    super.key,
    required this.api,
    required this.id,
    required this.kind,
  });
  @override
  State<MediaTile> createState() => _MediaTileState();
}

class _MediaTileState extends State<MediaTile> {
  late Future<Uint8List> data = widget.api.media(widget.id);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: FutureBuilder<Uint8List>(
      future: data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return TextButton.icon(
            onPressed: () => setState(() => data = widget.api.media(widget.id)),
            icon: const Icon(Icons.refresh),
            label: const Text('تعذر تحميل المرفق · أعد المحاولة'),
          );
        }
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 60,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (widget.kind == 'video') {
          return FilledButton.tonalIcon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => Directionality(
                  textDirection: TextDirection.rtl,
                  child: ClipPlayer(bytes: snapshot.data!),
                ),
              ),
            ),
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('تشغيل الفيديو'),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.memory(
            snapshot.data!,
            fit: BoxFit.contain,
            height: 240,
            errorBuilder: (_, e, s) => const Text('تعذر عرض الصورة'),
          ),
        );
      },
    ),
  );
}

class ClipPlayer extends StatefulWidget {
  final Uint8List bytes;
  const ClipPlayer({super.key, required this.bytes});
  @override
  State<ClipPlayer> createState() => _ClipPlayerState();
}

class _ClipPlayerState extends State<ClipPlayer> {
  VideoPlayerController? player;
  File? file;
  String? error;
  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    VideoPlayerController? pending;
    try {
      final dir = await getTemporaryDirectory();
      final f = File(
        '${dir.path}/stu-${DateTime.now().microsecondsSinceEpoch}.mp4',
      );
      await f.writeAsBytes(widget.bytes);
      file = f;
      pending = VideoPlayerController.file(f);
      await pending.initialize();
      if (!mounted) {
        await pending.dispose();
        if (await f.exists()) await f.delete();
        return;
      }
      player = pending;
      await player!.play();
      setState(() {});
    } catch (_) {
      await pending?.dispose();
      if (mounted) setState(() => error = 'تعذر تشغيل هذا الفيديو');
    }
  }

  @override
  void dispose() {
    final p = player, f = file;
    Future<void>(() async {
      await p?.dispose();
      if (f != null && await f.exists()) await f.delete();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('فيديو')),
    body: Center(
      child: error != null
          ? Text(error!)
          : player == null
          ? const CircularProgressIndicator()
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AspectRatio(
                  aspectRatio: player!.value.aspectRatio,
                  child: VideoPlayer(player!),
                ),
                VideoProgressIndicator(player!, allowScrubbing: true),
                IconButton(
                  onPressed: () {
                    setState(() {
                      player!.value.isPlaying
                          ? player!.pause()
                          : player!.play();
                    });
                  },
                  icon: Icon(
                    player!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  ),
                ),
              ],
            ),
    ),
  );
}
