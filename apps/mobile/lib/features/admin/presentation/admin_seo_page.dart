import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/open_url_stub.dart'
    if (dart.library.js_interop) '../../../core/utils/open_url_web.dart';
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

  // Consultor de SEO por IA
  final _gscCtrl = TextEditingController();
  bool _advising = false;
  Map<String, dynamic>? _advice;
  bool _addingTopics = false;

  static const _serviceAccount =
      'desafio-app-b8665@appspot.gserviceaccount.com';
  static const _sitemapBr = 'https://desafiopago.com.br/sitemap.xml';
  static const _sitemapIntl = 'https://trialspaid.web.app/sitemap.xml';

  @override
  void dispose() {
    _topicCtrl.dispose();
    _gscCtrl.dispose();
    super.dispose();
  }

  void _copy(String text, [String? label]) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${label ?? 'Copiado'}: $text')));
  }

  Future<void> _runAdvisor() async {
    setState(() {
      _advising = true;
      _advice = null;
    });
    try {
      final res = await _functions.httpsCallable('adminSeoAdvisor').call({
        'pastedResults': _gscCtrl.text.trim(),
      });
      setState(() => _advice = Map<String, dynamic>.from(res.data as Map));
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message ?? 'Erro'),
                duration: const Duration(seconds: 6)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _advising = false);
    }
  }

  Future<void> _addSuggestedTopics(List topics) async {
    setState(() => _addingTopics = true);
    try {
      final res = await _functions
          .httpsCallable('adminAddSeoTopics')
          .call({'topics': topics});
      final added = (res.data as Map)['added'] ?? 0;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$added tema(s) adicionado(s) à fila ✅')));
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message ?? 'Erro')));
      }
    } finally {
      if (mounted) setState(() => _addingTopics = false);
    }
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
            _gscGuideCard(),
            const SizedBox(height: 8),
            _advisorCard(),
            const SizedBox(height: 16),
            const Text('CONTEÚDO',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Colors.black45)),
            const SizedBox(height: 8),
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

  // ── Guia: submeter o sitemap no Google Search Console ─────────────────────
  Widget _gscGuideCard() {
    Widget urlRow(String label, String url) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.black54)),
                    SelectableText(url,
                        style: const TextStyle(
                            fontSize: 12.5, color: Color(0xFF1565C0))),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 16),
                tooltip: 'Copiar',
                visualDensity: VisualDensity.compact,
                onPressed: () => _copy(url, 'Sitemap'),
              ),
            ],
          ),
        );

    const steps = [
      'Acesse search.google.com/search-console e entre com sua conta Google.',
      'Clique em "Adicionar propriedade" → escolha "Prefixo do URL" e cole o '
          'endereço do site (um por vez: desafiopago.com.br e depois '
          'trialspaid.web.app).',
      'Confirme a posse (o método mais fácil costuma ser "Registro de DNS" '
          'ou a "tag HTML"; para o .web.app, use a tag HTML).',
      'No menu lateral, abra "Sitemaps", cole a URL do sitemap (abaixo) e '
          'clique em "Enviar". Faça isso para cada site com o sitemap dele.',
      'Opcional (loop de demanda automático): em "Configurações → Usuários e '
          'permissões", adicione o e-mail de serviço abaixo como usuário — '
          'assim o sistema lê as buscas reais e alimenta a fila de conteúdo.',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.travel_explore, color: Color(0xFF1565C0)),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Enviar o sitemap ao Google Search Console',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'É isso que faz o Google descobrir e indexar suas páginas. '
              'Passo a passo:',
              style: TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () =>
                    openExternalUrl('https://search.google.com/search-console'),
                icon: const Icon(Icons.open_in_new, size: 15),
                label: const Text('Abrir o Google Search Console',
                    style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1565C0),
                  side: const BorderSide(color: Color(0xFF90B4E8)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${i + 1}. ',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1565C0),
                            fontSize: 13)),
                    Expanded(
                      child: Text(steps[i],
                          style: const TextStyle(fontSize: 13, height: 1.4)),
                    ),
                  ],
                ),
              ),
            const Divider(height: 20),
            urlRow('Sitemap — Brasil', _sitemapBr),
            urlRow('Sitemap — Internacional', _sitemapIntl),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('E-mail de serviço (loop de demanda)',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.black54)),
                      SelectableText(_serviceAccount,
                          style: const TextStyle(fontSize: 12.5)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: 'Copiar',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _copy(_serviceAccount, 'E-mail'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Consultor de SEO por IA (tempo real) ──────────────────────────────────
  Widget _advisorCard() {
    final advice = _advice;
    final topics =
        (advice?['suggestedTopics'] as List?)?.cast<dynamic>() ?? const [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome, color: Color(0xFF6A1B9A)),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Consultor de SEO (IA em tempo real)',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'A IA analisa a situação atual e te dá o plano mais eficaz para '
              'ganhar acessos. Cole aqui os resultados do Search Console '
              '(queries, cliques, impressões, posição) para uma análise sob '
              'medida — ou deixe vazio para recomendações gerais.',
              style: TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _gscCtrl,
              maxLines: 5,
              minLines: 3,
              decoration: const InputDecoration(
                labelText: 'Resultados do Search Console (colar aqui)',
                hintText: 'ex.: "renda extra com fotos — 1.200 impressões, '
                    '8 cliques, posição 18"...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF6A1B9A)),
                onPressed: _advising ? null : _runAdvisor,
                icon: _advising
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.insights),
                label: Text(_advising
                    ? 'Analisando...'
                    : 'Analisar e recomendar'),
              ),
            ),
            if (advice != null) ...[
              const SizedBox(height: 16),
              if ((advice['summary'] as String?)?.isNotEmpty ?? false)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3EAFB),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(advice['summary'] as String,
                      style: const TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: FontWeight.w600)),
                ),
              _adviceSection('Prioridades',
                  (advice['priorities'] as List?) ?? const [],
                  isPriority: true),
              _adviceSection('Ganhos rápidos',
                  (advice['quickWins'] as List?) ?? const []),
              if (topics.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text('Temas sugeridos (com demanda)',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13.5)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: topics
                      .map((t) => Chip(
                            label: Text(t.toString(),
                                style: const TextStyle(fontSize: 11.5)),
                            backgroundColor: const Color(0xFFF0F1F8),
                            visualDensity: VisualDensity.compact,
                          ))
                      .toList(),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _addingTopics
                        ? null
                        : () => _addSuggestedTopics(topics),
                    icon: _addingTopics
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.playlist_add, size: 18),
                    label: const Text('Adicionar esses temas à fila'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _adviceSection(String title, List items, {bool isPriority = false}) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
        const SizedBox(height: 6),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: isPriority
                ? _priorityTile(Map<String, dynamic>.from(item as Map))
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('✓ ',
                          style: TextStyle(color: Color(0xFF00875A))),
                      Expanded(
                        child: Text(item.toString(),
                            style: const TextStyle(fontSize: 13, height: 1.4)),
                      ),
                    ],
                  ),
          ),
      ],
    );
  }

  Widget _priorityTile(Map<String, dynamic> p) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE6E9F2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p['title']?.toString() ?? '',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13)),
          if ((p['why']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(p['why'].toString(),
                style:
                    const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
          if ((p['how']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.arrow_right, size: 16, color: Color(0xFF6A1B9A)),
                Expanded(
                  child: Text(p['how'].toString(),
                      style: const TextStyle(
                          fontSize: 12.5, height: 1.35)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
