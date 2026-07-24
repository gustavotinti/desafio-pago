import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/safe_avatar.dart';
import '../../../core/widgets/safe_image.dart';
import '../../../core/widgets/web_frame.dart';

final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

/// Painel de denúncias: agrupa as denúncias pendentes por participação, mostra
/// o conteúdo denunciado + autor + motivos, e permite descartar, ocultar,
/// reativar ou banir o autor. Uma ação resolve todas as denúncias da
/// participação de uma vez.
class AdminReportsPage extends StatelessWidget {
  const AdminReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin — Denúncias')),
      body: WebFrame(
        maxWidth: 760,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('reports')
              .where('status', isEqualTo: 'pending')
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              return const _EmptyState();
            }
            // Agrupa por participação denunciada.
            final groups = <String, _Group>{};
            for (final d in docs) {
              final data = d.data();
              final entryId = data['entryId'] as String? ?? '';
              if (entryId.isEmpty) continue;
              final g = groups.putIfAbsent(entryId, () => _Group(entryId));
              g.count++;
              final reason = (data['reason'] as String? ?? '').trim();
              if (reason.isNotEmpty) g.reasons.add(reason);
              g.reportedUserId ??= data['reportedUserId'] as String?;
              g.challengeId ??= data['challengeId'] as String?;
            }
            final list = groups.values.toList()
              ..sort((a, b) => b.count.compareTo(a.count));
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 10, left: 2),
                  child: Text(
                    '${list.length} participação(ões) denunciada(s) · '
                    '${docs.length} denúncia(s)',
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54),
                  ),
                ),
                ...list.map((g) => _ReportCard(group: g)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Group {
  final String entryId;
  String? reportedUserId;
  String? challengeId;
  final Set<String> reasons = {};
  int count = 0;
  _Group(this.entryId);
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_user_outlined,
              size: 48, color: Color(0xFF00875A)),
          SizedBox(height: 12),
          Text('Nenhuma denúncia pendente 🎉',
              style: TextStyle(fontWeight: FontWeight.w600)),
          SizedBox(height: 4),
          Text('Tudo tranquilo na moderação.',
              style: TextStyle(color: Colors.black54, fontSize: 13)),
        ],
      ),
    );
  }
}

class _ReportCard extends StatefulWidget {
  final _Group group;
  const _ReportCard({required this.group});

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  bool _busy = false;
  late Future<_EntryInfo> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_EntryInfo> _load() async {
    final db = FirebaseFirestore.instance;
    final entry =
        await db.collection('entries').doc(widget.group.entryId).get();
    final e = entry.data() ?? {};
    Map<String, dynamic>? author;
    final uid = widget.group.reportedUserId ?? e['userId'] as String?;
    if (uid != null) {
      author = (await db.collection('publicProfiles').doc(uid).get()).data();
    }
    String? challengeTitle;
    final cid = widget.group.challengeId ?? e['challengeId'] as String?;
    if (cid != null) {
      challengeTitle =
          (await db.collection('challenges').doc(cid).get()).data()?['title']
              as String?;
    }
    return _EntryInfo(
      exists: entry.exists,
      isActive: e['isActive'] != false,
      contentType: e['contentType'] as String? ?? 'image',
      contentUrl: e['contentUrl'] as String?,
      contentText: e['contentText'] as String?,
      authorName: author?['name'] as String? ?? '—',
      authorUsername: author?['username'] as String? ?? '',
      authorPhoto: author?['photoUrl'] as String?,
      challengeTitle: challengeTitle ?? '',
    );
  }

  Future<void> _resolve(String action, {String? reason}) async {
    setState(() => _busy = true);
    try {
      final payload = <String, dynamic>{
        'entryId': widget.group.entryId,
        'action': action,
      };
      if (reason != null) payload['reason'] = reason;
      await _functions.httpsCallable('adminResolveReport').call(payload);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(switch (action) {
          'hide' => 'Participação ocultada.',
          'restore' => 'Participação reativada.',
          'ban' => 'Autor banido e conteúdo ocultado.',
          _ => 'Denúncias descartadas.',
        })));
      }
      // O stream remove o card sozinho ao resolver as denúncias.
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message ?? 'Erro')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmBan() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Banir autor?'),
        content: const Text(
            'O autor não poderá mais acessar a plataforma e a participação '
            'será ocultada. Você pode reverter o banimento em Usuários.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Banir'),
          ),
        ],
      ),
    );
    if (ok == true) await _resolve('ban', reason: 'Conteúdo denunciado');
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: FutureBuilder<_EntryInfo>(
          future: _future,
          builder: (context, snap) {
            final info = snap.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDECEC),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFF3B4B4)),
                      ),
                      child: Text('${g.count} denúncia(s)',
                          style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFC62828))),
                    ),
                    const Spacer(),
                    if (info != null && !info.isActive)
                      const Text('Já oculto',
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange)),
                  ],
                ),
                const SizedBox(height: 10),
                if (info == null)
                  const Center(
                      child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ))
                else if (!info.exists)
                  const Text('Participação removida do banco.',
                      style: TextStyle(color: Colors.black54))
                else ...[
                  // Autor + desafio
                  Row(
                    children: [
                      SafeAvatar(photoUrl: info.authorPhoto, radius: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(info.authorName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5)),
                            if (info.challengeTitle.isNotEmpty)
                              Text('em "${info.challengeTitle}"',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 11.5, color: Colors.black45)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Conteúdo denunciado
                  if (info.contentType == 'image' && info.contentUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 260),
                        child: SafeImage(
                          url: info.contentUrl!,
                          width: double.infinity,
                          fit: BoxFit.contain,
                        ),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6F8FC),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(info.contentText ?? '(sem texto)'),
                    ),
                  const SizedBox(height: 10),
                  // Motivos
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: g.reasons
                        .map((r) => Chip(
                              label: Text(r,
                                  style: const TextStyle(fontSize: 11)),
                              backgroundColor: const Color(0xFFF0F1F8),
                              visualDensity: VisualDensity.compact,
                            ))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 12),
                // Ações
                _busy
                    ? const Center(
                        child: Padding(
                        padding: EdgeInsets.all(6),
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2)),
                      ))
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _resolve('dismiss'),
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text('Descartar'),
                          ),
                          if (info != null && info.isActive)
                            OutlinedButton.icon(
                              onPressed: () => _resolve('hide'),
                              icon: const Icon(Icons.visibility_off,
                                  size: 16, color: Colors.orange),
                              label: const Text('Ocultar',
                                  style: TextStyle(color: Colors.orange)),
                              style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                      color: Colors.orange)),
                            ),
                          if (info != null && !info.isActive)
                            OutlinedButton.icon(
                              onPressed: () => _resolve('restore'),
                              icon: const Icon(Icons.visibility,
                                  size: 16, color: Color(0xFF00875A)),
                              label: const Text('Reativar',
                                  style:
                                      TextStyle(color: Color(0xFF00875A))),
                              style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                      color: Color(0xFF00875A))),
                            ),
                          FilledButton.icon(
                            onPressed: _confirmBan,
                            icon: const Icon(Icons.block, size: 16),
                            label: const Text('Banir autor'),
                            style: FilledButton.styleFrom(
                                backgroundColor: Colors.red),
                          ),
                        ],
                      ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EntryInfo {
  final bool exists;
  final bool isActive;
  final String contentType;
  final String? contentUrl;
  final String? contentText;
  final String authorName;
  final String authorUsername;
  final String? authorPhoto;
  final String challengeTitle;
  _EntryInfo({
    required this.exists,
    required this.isActive,
    required this.contentType,
    required this.contentUrl,
    required this.contentText,
    required this.authorName,
    required this.authorUsername,
    required this.authorPhoto,
    required this.challengeTitle,
  });
}
