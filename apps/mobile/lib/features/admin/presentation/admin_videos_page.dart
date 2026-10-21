import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/open_url_stub.dart'
    if (dart.library.js_interop) '../../../core/utils/open_url_web.dart';
import '../../../core/widgets/video_link_view.dart';
import '../../../core/widgets/web_frame.dart';

/// Admin → Vídeos para verificar.
///
/// O YouTube é conferido sozinho no envio (título com o código, vertical e
/// público). O Instagram não tem consulta pública: o vídeo chega aqui como
/// 'pending', o admin abre o embed COM LEGENDA, confere o código e aprova ou
/// recusa (`adminReviewVideoEntry`). Só vídeo aprovado concorre ao prêmio —
/// por isso vale conferir antes do fim do prazo do desafio.
class AdminVideosPage extends StatelessWidget {
  const AdminVideosPage({super.key});

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('entries')
        .where('videoCheck', isEqualTo: 'pending')
        .limit(100)
        .snapshots();
    return Scaffold(
      appBar: AppBar(title: const Text('Vídeos para verificar')),
      body: WebFrame(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: stream,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(child: Text('Erro ao carregar: ${snap.error}'));
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            // Mais antigos primeiro (prazo mais perto de vencer).
            final docs = [...snap.data!.docs]..sort((a, b) =>
                (a.data()['createdAt'] as String? ?? '')
                    .compareTo(b.data()['createdAt'] as String? ?? ''));
            if (docs.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nenhum vídeo aguardando verificação. 🎉',
                      textAlign: TextAlign.center),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
              itemCount: docs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _VideoCard(
                key: ValueKey(docs[i].id),
                entryId: docs[i].id,
                data: docs[i].data(),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _VideoCard extends StatefulWidget {
  const _VideoCard({super.key, required this.entryId, required this.data});
  final String entryId;
  final Map<String, dynamic> data;

  @override
  State<_VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<_VideoCard> {
  bool _busy = false;
  late final Future<(String, String, DateTime?)> _info = _loadInfo();

  /// (autor, título do desafio, prazo do desafio)
  Future<(String, String, DateTime?)> _loadInfo() async {
    final db = FirebaseFirestore.instance;
    final uid = widget.data['userId'] as String? ?? '';
    final cid = widget.data['challengeId'] as String? ?? '';
    var author = uid;
    var title = cid;
    DateTime? expires;
    try {
      final p = await db.collection('publicProfiles').doc(uid).get();
      final d = p.data();
      if (d != null) {
        author = '${d['name'] ?? ''} @${d['username'] ?? ''}'.trim();
      }
    } catch (_) {}
    try {
      final c = await db.collection('challenges').doc(cid).get();
      final d = c.data();
      if (d != null) {
        title = d['title'] as String? ?? cid;
        expires = DateTime.tryParse(d['expiresAt'] as String? ?? '');
      }
    } catch (_) {}
    return (author, title, expires);
  }

  Future<void> _review(bool approve) async {
    if (!approve) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Recusar vídeo?'),
          content: const Text(
              'A participação some do desafio e o participante é avisado. '
              'Ele pode participar de novo com outro link.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Recusar')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('adminReviewVideoEntry')
          .call({'entryId': widget.entryId, 'approve': approve});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(approve ? 'Vídeo aprovado ✅' : 'Vídeo recusado')));
      // O card sai sozinho da lista (o stream só traz os 'pending').
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final provider = d['videoProvider'] as String? ?? 'instagram';
    final url = d['contentUrl'] as String? ?? '';
    final embed = d['videoEmbed'] as String? ?? '';
    final code = d['videoCode'] as String? ?? '—';
    // Embed com LEGENDA: é onde o código aparece no Instagram.
    final captioned = provider == 'instagram' && embed.endsWith('/embed/')
        ? '${embed}captioned/'
        : embed;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 84,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: VideoLinkCover(
                    provider: provider,
                    thumbUrl: d['videoThumb'] as String?,
                    compact: true,
                    onTap: embed.isEmpty
                        ? null
                        : () => showVideoLinkPlayer(context,
                            provider: provider, embedUrl: captioned, url: url),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FutureBuilder<(String, String, DateTime?)>(
                future: _info,
                builder: (context, snap) {
                  final info = snap.data;
                  final expires = info?.$3;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(info?.$2 ?? '…',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(info?.$1 ?? '…',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54)),
                      if (expires != null)
                        Text(
                          'Prazo do desafio: '
                          '${expires.toLocal().toString().substring(0, 16)}',
                          style: TextStyle(
                              fontSize: 12,
                              color: expires.isBefore(DateTime.now()
                                      .add(const Duration(hours: 24)))
                                  ? Colors.red
                                  : Colors.black54),
                        ),
                      const SizedBox(height: 8),
                      const Text('Código esperado na legenda:',
                          style:
                              TextStyle(fontSize: 11, color: Colors.black54)),
                      SelectableText(code,
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                              fontFamily: 'monospace')),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact),
                        onPressed: url.isEmpty ? null : () => openExternalUrl(url),
                        icon: const Icon(Icons.open_in_new, size: 14),
                        label: const Text('Abrir no Instagram',
                            style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          FilledButton.icon(
                            onPressed: _busy ? null : () => _review(true),
                            style: FilledButton.styleFrom(
                                backgroundColor: Colors.green),
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('Aprovar'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : () => _review(false),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red),
                            icon: const Icon(Icons.close, size: 18),
                            label: const Text('Recusar'),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
