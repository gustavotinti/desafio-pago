import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/safe_image.dart';
import 'auto_video.dart';

/// Faixa com as 3 participações mais votadas de um desafio, em 4:5.
/// Foto/vídeo aparecem cortados (cover); vídeo toca ao passar o mouse.
class EntryPreviewStrip extends StatefulWidget {
  final String challengeId;
  final VoidCallback onOpen;

  const EntryPreviewStrip({
    super.key,
    required this.challengeId,
    required this.onOpen,
  });

  @override
  State<EntryPreviewStrip> createState() => _EntryPreviewStripState();
}

class _EntryPreviewStripState extends State<EntryPreviewStrip> {
  late final Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('entries')
          .where('challengeId', isEqualTo: widget.challengeId)
          .where('isActive', isEqualTo: true)
          .orderBy('voteCount', descending: true)
          .limit(3)
          .get();
      return snap.docs.map((d) => d.data()).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        final items = snap.data!;
        final tiles = <Widget>[];
        for (var i = 0; i < 3; i++) {
          tiles.add(Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < 2 ? 6 : 0),
              child: i < items.length
                  ? _Tile(data: items[i])
                  : const SizedBox.shrink(),
            ),
          ));
        }
        return GestureDetector(
          onTap: widget.onOpen,
          behavior: HitTestBehavior.opaque,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text(
                  'Mais votados',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.black45),
                ),
              ),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: tiles),
            ],
          ),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  final Map<String, dynamic> data;
  const _Tile({required this.data});

  @override
  Widget build(BuildContext context) {
    final type = data['contentType'] as String? ?? 'text';
    final url = data['contentUrl'] as String?;
    final text = data['contentText'] as String? ?? '';

    Widget child;
    if (type == 'image' && url != null && url.isNotEmpty) {
      child = SafeImage(url: url);
    } else if (type == 'video' && url != null && url.isNotEmpty) {
      child = AutoVideo(url: url, hoverToPlay: true);
    } else {
      child = Container(
        color: const Color(0xFFEDF1F8),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(8),
        child: Text(
          text,
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: Colors.black87),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: AspectRatio(aspectRatio: 4 / 5, child: child),
    );
  }
}
