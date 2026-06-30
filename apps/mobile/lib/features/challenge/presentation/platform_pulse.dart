import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/web_frame.dart';

/// Faixa de "pulso" no topo do feed: desafios ativos, prêmios em jogo e
/// participantes, com um selo "ao vivo". Passa a sensação de plataforma ativa
/// e movimentada. Lê agregações leves (count/sum) do Firestore.
class PlatformPulse extends StatefulWidget {
  const PlatformPulse({super.key});

  @override
  State<PlatformPulse> createState() => _PlatformPulseState();
}

class _PlatformPulseState extends State<PlatformPulse> {
  int? _activeChallenges;
  double? _prizePool;
  int? _participants;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = FirebaseFirestore.instance;
    try {
      final active = db
          .collection('challenges')
          .where('status', isEqualTo: 'active');
      final agg = await active.aggregate(count(), sum('amount')).get();
      final people =
          await db.collection('publicProfiles').count().get();
      if (!mounted) return;
      setState(() {
        _activeChallenges = agg.count;
        _prizePool = agg.getSum('amount') ?? 0;
        _participants = people.count;
      });
    } catch (_) {
      // silencioso — a faixa só não mostra números se a leitura falhar
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebFrame(
      maxWidth: 600,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 2),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF003b8a), Color(0xFF0cc0df)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF003b8a).withValues(alpha: 0.25),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _LiveTag(),
            const SizedBox(height: 10),
            Row(
              children: [
                _Stat(
                  icon: Icons.local_fire_department,
                  value: _activeChallenges == null
                      ? '—'
                      : Fmt.number(_activeChallenges!),
                  label: 'desafios ativos',
                ),
                _divider(),
                _Stat(
                  icon: Icons.emoji_events,
                  value: _prizePool == null
                      ? '—'
                      : Fmt.brlCompact(_prizePool!),
                  label: 'em prêmios',
                ),
                _divider(),
                _Stat(
                  icon: Icons.groups,
                  value: _participants == null
                      ? '—'
                      : Fmt.number(_participants!),
                  label: 'participantes',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 30,
        color: Colors.white.withValues(alpha: 0.22),
      );
}

class _LiveTag extends StatefulWidget {
  const _LiveTag();

  @override
  State<_LiveTag> createState() => _LiveTagState();
}

class _LiveTagState extends State<_LiveTag>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF4ADE80),
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'AO VIVO AGORA',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _Stat({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}
