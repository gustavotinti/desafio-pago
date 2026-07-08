import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/web_frame.dart';

/// Ticker de vitórias no topo do feed: mostra, em rotação aleatória, quem
/// GANHOU quais desafios ("🏆 @fulano ganhou R$X · '...'"), usando desafios
/// reais já encerrados + seus vencedores. Reforça a sensação de que dá pra
/// ganhar dinheiro de verdade (prova social).
class ActivityTicker extends StatefulWidget {
  const ActivityTicker({super.key});

  @override
  State<ActivityTicker> createState() => _ActivityTickerState();
}

class _WinItem {
  final String who; // @username ou nome
  final double amount;
  final String challengeTitle;
  final int template; // qual variação de frase usar
  const _WinItem({
    required this.who,
    required this.amount,
    required this.challengeTitle,
    required this.template,
  });
}

// Variações da frase de vitória — tokens: {who}, {amt}, {t}.
const _winTemplates = [
  '{who} ganhou {amt} · "{t}"',
  '{who} levou {amt} no desafio "{t}"',
  '{who} faturou {amt} com "{t}" 💰',
  '{who} venceu "{t}" e ganhou {amt}',
  '{amt} pagos para {who} · "{t}"',
  '{who} acabou de ganhar {amt} em "{t}" 🎉',
  'prêmio de {amt} foi para {who} · "{t}"',
  '{who} conquistou {amt} vencendo "{t}" 🏆',
];

class _ActivityTickerState extends State<ActivityTicker> {
  List<_WinItem> _items = [];
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final db = FirebaseFirestore.instance;
      // Desafios encerrados (com vencedor) — leitura pública.
      final snap = await db
          .collection('challenges')
          .where('status', isEqualTo: 'finished')
          .limit(40)
          .get();

      // Desafios de VÍDEO estão sendo desativados — o tipo não fica no doc do
      // desafio, só nas participações (contentType). Buscamos os challengeIds
      // que têm participação de vídeo e os excluímos do ticker.
      final videoIds = <String>{};
      try {
        final vSnap = await db
            .collection('entries')
            .where('contentType', isEqualTo: 'video')
            .get();
        for (final e in vSnap.docs) {
          final cid = e.data()['challengeId'] as String?;
          if (cid != null) videoIds.add(cid);
        }
      } catch (_) {/* sem índice/erro: segue sem filtrar */}

      final winners = <String, String>{}; // uid -> @/nome (cache)
      final raw = <_WinItem>[];
      final rows = snap.docs.where((d) {
        final w = d.data()['winnerIds'];
        return w is List && w.isNotEmpty && !videoIds.contains(d.id);
      }).toList();
      if (rows.isEmpty) return;

      // Busca os perfis dos vencedores (uids distintos), em paralelo.
      final uids = <String>{};
      for (final d in rows) {
        final w = (d.data()['winnerIds'] as List);
        if (w.isNotEmpty) uids.add('${w.first}');
      }
      final profiles = await Future.wait(
          uids.map((id) => db.collection('publicProfiles').doc(id).get()));
      for (final p in profiles) {
        final data = p.data();
        final username = data?['username'] as String?;
        final name = data?['name'] as String?;
        winners[p.id] = (username != null && username.isNotEmpty)
            ? '@$username'
            : (name ?? '');
      }

      final rand = Random();
      for (final d in rows) {
        final data = d.data();
        final w = (data['winnerIds'] as List);
        final who = winners['${w.first}'] ?? '';
        final title = data['title'] as String? ?? '';
        final amount = (data['amount'] as num?)?.toDouble() ?? 0;
        if (who.isEmpty || title.isEmpty || amount <= 0) continue;
        raw.add(_WinItem(
          who: who,
          amount: amount,
          challengeTitle: title,
          template: rand.nextInt(_winTemplates.length),
        ));
      }
      if (!mounted || raw.isEmpty) return;

      raw.shuffle(rand); // ordem aleatória
      setState(() => _items = raw);
      _timer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (!mounted) return;
        setState(() => _index = (_index + 1) % _items.length);
      });
    } catch (_) {
      // silencioso — sem vitórias, o ticker simplesmente não aparece
    }
  }

  // Monta os spans da frase a partir do template ({who}/{amt}/{t} com estilo).
  List<InlineSpan> _spansFor(_WinItem item) {
    final tpl = _winTemplates[item.template % _winTemplates.length];
    const bold = TextStyle(fontWeight: FontWeight.bold);
    const money = TextStyle(
        fontWeight: FontWeight.bold, color: Color(0xFF00875A));
    final spans = <InlineSpan>[];
    var i = 0;
    for (final m in RegExp(r'\{(who|amt|t)\}').allMatches(tpl)) {
      if (m.start > i) spans.add(TextSpan(text: tpl.substring(i, m.start)));
      switch (m.group(1)) {
        case 'who':
          spans.add(TextSpan(text: item.who, style: bold));
        case 'amt':
          spans.add(TextSpan(text: Fmt.brl(item.amount), style: money));
        case 't':
          spans.add(TextSpan(text: item.challengeTitle));
      }
      i = m.end;
    }
    if (i < tpl.length) spans.add(TextSpan(text: tpl.substring(i)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final item = _items[_index % _items.length];
    return WebFrame(
      maxWidth: 600,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF3E2B3)),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.5),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: Row(
            key: ValueKey(_index),
            children: [
              const Icon(Icons.emoji_events,
                  size: 16, color: Color(0xFFF59E0B)),
              const SizedBox(width: 6),
              Expanded(
                child: RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black87),
                    children: _spansFor(item),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
