import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/web_frame.dart';

/// Faixa de "pulso" no topo do feed: desafios ativos, prêmios em jogo e
/// participantes REAIS (sem demonstração), via agregações leves do Firestore.
class PlatformPulse extends StatefulWidget {
  final bool isAdmin;
  const PlatformPulse({super.key, this.isAdmin = false});

  @override
  State<PlatformPulse> createState() => _PlatformPulseState();
}

class _PlatformPulseState extends State<PlatformPulse> {
  int? _activeChallenges;
  double? _prizePool;
  int? _participants;

  // TRANSPARÊNCIA (v3.10): o pulso mostra SÓ números reais — sem crescimento
  // automático (drift), sem números editados à mão e sem contar desafios ou
  // perfis de demonstração. É o que um avaliador externo (ex.: XRPL Grants)
  // vai conferir no código e no banco.
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
          .where('status', isEqualTo: 'active')
          .where('region', isEqualTo: AppConfig.intl ? 'INTL' : 'BR');
      // Desafios reais não têm o campo isVirtual: total − demonstração.
      final all = await active.aggregate(count(), sum('amount')).get();
      final demo = await active
          .where('isVirtual', isEqualTo: true)
          .aggregate(count(), sum('amount'))
          .get();
      final people = await db
          .collection('publicProfiles')
          .where('isVirtual', isEqualTo: false)
          .count()
          .get();
      if (!mounted) return;
      setState(() {
        _activeChallenges = (all.count ?? 0) - (demo.count ?? 0);
        _prizePool = ((all.getSum('amount') ?? 0) -
                (demo.getSum('amount') ?? 0))
            .toDouble();
        _participants = people.count ?? 0;
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
            Row(
              children: [
                const _LiveTag(),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _Stat(
                  icon: Icons.local_fire_department,
                  value: _activeChallenges?.toDouble(),
                  format: (v) => Fmt.number(v.round()),
                  label: I18n.tr('stat_active'),
                ),
                _divider(),
                _Stat(
                  icon: Icons.emoji_events,
                  value: _prizePool,
                  format: (v) => Fmt.brl(v),
                  label: I18n.tr('stat_prizes'),
                ),
                _divider(),
                _Stat(
                  icon: Icons.groups,
                  value: _participants?.toDouble(),
                  format: (v) => Fmt.number(v.round()),
                  label: I18n.tr('stat_participants'),
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
          I18n.tr('live_now'),
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
  // Valor numérico (null = ainda carregando). Anima contando de 0 até o valor.
  final double? value;
  final String Function(double) format;
  final String label;

  const _Stat({
    required this.icon,
    required this.value,
    required this.format,
    required this.label,
  });

  static const _numStyle = TextStyle(
    color: Colors.white,
    fontSize: 17,
    fontWeight: FontWeight.bold,
  );

  @override
  Widget build(BuildContext context) {
    final v = value;
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: v == null
                ? const Text('—', style: _numStyle)
                : TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: v),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOut,
                    builder: (context, animated, _) =>
                        Text(format(animated), style: _numStyle),
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
