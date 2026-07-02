import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/web_frame.dart';

/// Ticker de atividade recente no topo do feed: mostra participações reais
/// recém-enviadas ("@fulano participou de \"...\" · há 5 min"), alternando
/// com animação. Reforça a sensação de plataforma viva usando dados reais.
class ActivityTicker extends StatefulWidget {
  const ActivityTicker({super.key});

  @override
  State<ActivityTicker> createState() => _ActivityTickerState();
}

class _TickerItem {
  final String userName;
  final String challengeTitle;
  final DateTime createdAt;
  const _TickerItem({
    required this.userName,
    required this.challengeTitle,
    required this.createdAt,
  });
}

class _ActivityTickerState extends State<ActivityTicker> {
  List<_TickerItem> _items = [];
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
      final snap = await db
          .collection('entries')
          .orderBy('createdAt', descending: true)
          .limit(12)
          .get();
      final docs =
          snap.docs.where((d) => d.data()['isActive'] != false).toList();
      if (docs.isEmpty) return;

      // Nomes (publicProfiles) e títulos (challenges) — ids distintos.
      final userIds =
          docs.map((d) => d.data()['userId'] as String? ?? '').toSet()
            ..remove('');
      final chIds =
          docs.map((d) => d.data()['challengeId'] as String? ?? '').toSet()
            ..remove('');
      final profiles = await Future.wait(
          userIds.map((id) => db.collection('publicProfiles').doc(id).get()));
      final challenges = await Future.wait(
          chIds.map((id) => db.collection('challenges').doc(id).get()));
      final nameOf = {
        for (final p in profiles)
          p.id: (p.data()?['username'] as String?) ??
              (p.data()?['name'] as String?) ??
              ''
      };
      final titleOf = {
        for (final c in challenges)
          c.id: (c.data()?['title'] as String?) ?? ''
      };

      final items = <_TickerItem>[];
      for (final d in docs) {
        final data = d.data();
        final name = nameOf[data['userId']] ?? '';
        final title = titleOf[data['challengeId']] ?? '';
        final createdAt = DateTime.tryParse('${data['createdAt']}');
        if (name.isEmpty || title.isEmpty || createdAt == null) continue;
        items.add(_TickerItem(
          userName: name,
          challengeTitle: title,
          createdAt: createdAt,
        ));
      }
      if (!mounted || items.isEmpty) return;
      setState(() => _items = items);
      _timer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (!mounted) return;
        setState(() => _index = (_index + 1) % _items.length);
      });
    } catch (_) {
      // silencioso — sem atividade, o ticker simplesmente não aparece
    }
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'agora mesmo';
    if (d.inMinutes < 60) return 'há ${d.inMinutes} min';
    if (d.inHours < 24) return 'há ${d.inHours} h';
    return 'há ${d.inDays} d';
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE3E7F2)),
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
              const Icon(Icons.bolt, size: 15, color: Color(0xFFF59E0B)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '@${item.userName} participou de '
                  '"${item.challengeTitle}"',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black87),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _ago(item.createdAt),
                style: const TextStyle(
                    fontSize: 11, color: Colors.black38),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
