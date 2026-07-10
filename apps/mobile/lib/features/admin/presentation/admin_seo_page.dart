import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/web_frame.dart';

final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

/// Painel "SEO / Novidades": lista os artigos publicados em /novidades,
/// gera artigo novo por IA (tema livre ou próximo da fila), controla a
/// publicação automática diária e mostra a fila de tópicos (inclui os
/// vindos do Google Search Console).
class AdminSeoPage extends StatefulWidget {
  const AdminSeoPage({super.key});

  @override
  State<AdminSeoPage> createState() => _AdminSeoPageState();
}

class _AdminSeoPageState extends State<AdminSeoPage> {
  final _topicCtrl = TextEditingController();
  bool _generating = false;

  @override
  void dispose() {
    _topicCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      final res = await _functions
          .httpsCallable('adminGenerateSeoArticle')
          .call({'topic': _topicCtrl.text.trim()});
      final data = Map<String, dynamic>.from(res.data as Map);
      _topicCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Publicado: ${data['title']} ✅'),
          duration: const Duration(seconds: 5),
        ));
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('[${e.code}] ${e.message ?? 'Erro'}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _setAutoPublish(bool v) async {
    try {
      await _functions
          .httpsCallable('adminSetSeoConfig')
          .call({'autoPublish': v});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(v
                ? 'Publicação automática LIGADA (1 artigo/dia às 9h) ✅'
                : 'Publicação automática desligada')));
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('[${e.code}] ${e.message ?? 'Erro'}')));
      }
    }
  }

  void _copyUrl(String slug) {
    final url = 'https://desafiopago.com.br/novidades/$slug';
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Link copiado: $url')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin — SEO / Novidades')),
      body: WebFrame(
        maxWidth: 760,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Gerar artigo ────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.auto_awesome, color: Color(0xFF0cc0df)),
                        SizedBox(width: 8),
                        Text('Gerar artigo por IA',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Deixe vazio para usar o próximo tema da fila '
                      '(inclui a demanda real vinda do Google). '
                      'A geração leva ~30 segundos.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _topicCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tema (opcional)',
                        hintText:
                            'ex.: como ganhar dinheiro com fotos no celular',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _generating ? null : _generate,
                        icon: _generating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.publish),
                        label: Text(_generating
                            ? 'Gerando (aguarde ~30s)...'
                            : 'Gerar e publicar agora'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // ── Publicação automática ───────────────────────────────
            Card(
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('config')
                    .doc('seo')
                    .snapshots(),
                builder: (context, snap) {
                  final enabled = snap.data?.data()?['autoPublish'] != false;
                  return SwitchListTile(
                    secondary:
                        const Icon(Icons.schedule, color: Color(0xFF003b8a)),
                    title: const Text('Publicação automática diária',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: const Text(
                      '1 artigo por dia às 9h (BRT), usando a fila de '
                      'tópicos. Toda segunda o sistema puxa a demanda do '
                      'Google Search Console e alimenta a fila.',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: enabled,
                    onChanged: snap.hasData ? _setAutoPublish : null,
                  );
                },
              ),
            ),
            const SizedBox(height: 8),

            // ── Fila de tópicos ─────────────────────────────────────
            Card(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('seo_topics')
                      .where('used', isEqualTo: false)
                      .snapshots(),
                  builder: (context, snap) {
                    final n = snap.data?.docs.length;
                    final fromGsc = snap.data?.docs
                            .where((d) => d.data()['source'] == 'gsc')
                            .length ??
                        0;
                    return Row(
                      children: [
                        const Icon(Icons.format_list_bulleted,
                            color: Color(0xFF00875A)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            n == null
                                ? 'Fila de tópicos: carregando…'
                                : 'Fila de tópicos: $n pendente'
                                    '${n == 1 ? '' : 's'}'
                                    '${fromGsc > 0 ? ' ($fromGsc vindos do Google)' : ''}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Artigos publicados ──────────────────────────────────
            const Padding(
              padding: EdgeInsets.only(left: 2, bottom: 8),
              child: Text('ARTIGOS PUBLICADOS',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: Colors.black45)),
            ),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('seo_articles')
                  .orderBy('publishedAt', descending: true)
                  .limit(100)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(
                      child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator()));
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Nenhum artigo ainda — gere o primeiro! 👆',
                        style: TextStyle(color: Colors.black54)),
                  );
                }
                return Column(
                  children: docs.map((d) {
                    final a = d.data();
                    final date =
                        (a['publishedAt'] as String? ?? '').split('T').first;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.article_outlined,
                            color: Color(0xFF003b8a)),
                        title: Text(a['title'] as String? ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13.5)),
                        subtitle: Text(
                          '/novidades/${a['slug']} · $date',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.link, size: 18),
                          tooltip: 'Copiar link',
                          onPressed: () => _copyUrl(a['slug'] as String? ?? ''),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
