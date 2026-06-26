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
                  ? _Tile(data: items[i], rank: i)
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
  final int rank; // 0 = 1º (ouro), 1 = 2º (prata), 2 = 3º (bronze)
  const _Tile({required this.data, required this.rank});

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
      child: AspectRatio(
        aspectRatio: 4 / 5,
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            Positioned(top: 6, left: 6, child: _RankBadge(rank: rank)),
          ],
        ),
      ),
    );
  }
}

// ─── Medalha de posição (ouro / prata / bronze) ──────────────────────────────

class _RankBadge extends StatelessWidget {
  final int rank;
  const _RankBadge({required this.rank});

  @override
  Widget build(BuildContext context) {
    const medals = [Color(0xFFF5B301), Color(0xFF9AA7B4), Color(0xFFC07A33)];
    const labels = ['Vencendo', '2º', '3º'];
    if (rank < 0 || rank > 2) return const SizedBox.shrink();
    final color = medals[rank];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.emoji_events, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            labels[rank],
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}
