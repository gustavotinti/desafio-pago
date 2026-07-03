import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/web_frame.dart';

/// Faixa de "pulso" no topo do feed: desafios ativos, prêmios em jogo e
/// participantes, com um selo "ao vivo". Passa a sensação de plataforma ativa
/// e movimentada. Lê agregações leves (count/sum) do Firestore.
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

  // Bases automáticas (agregações) — usadas quando não há override do admin.
  int? _baseActive;
  double? _basePrize;
  int? _basePart;
  Map<String, dynamic>? _overrides;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _cfgSub;

  // Crescimento ao vivo (drift): prêmios sobem a cada 5s (R$0,01–R$1,50),
  // participantes a cada 5min e desafios a cada 15min — sensação de
  // plataforma pulsando em tempo real.
  final _rand = Random();
  double _driftPrize = 0;
  int _driftPart = 0;
  int _driftChallenges = 0;
  final List<Timer> _driftTimers = [];

  @override
  void initState() {
    super.initState();
    _loadBase();
    // Overrides do admin em TEMPO REAL: qualquer gravação em
    // config/platformPulse (pelo lápis ou pelo painel admin) atualiza o
    // banner na hora — antes era uma leitura única e a edição "não aparecia".
    _cfgSub = FirebaseFirestore.instance
        .collection('config')
        .doc('platformPulse')
        .snapshots()
        .listen((doc) {
      _overrides = doc.data();
      // Edição do admin zera o drift local (mostra exatamente o que salvou).
      _driftPrize = 0;
      _driftPart = 0;
      _driftChallenges = 0;
      _apply();
    }, onError: (_) {});

    _driftTimers.add(Timer.periodic(const Duration(seconds: 5), (_) {
      _driftPrize += 0.01 + _rand.nextDouble() * 1.49; // R$0,01–R$1,50
      _apply();
    }));
    _driftTimers.add(Timer.periodic(const Duration(minutes: 5), (_) {
      _driftPart += 1;
      _apply();
    }));
    _driftTimers.add(Timer.periodic(const Duration(minutes: 15), (_) {
      _driftChallenges += 1;
      _apply();
    }));
  }

  @override
  void dispose() {
    for (final t in _driftTimers) {
      t.cancel();
    }
    _cfgSub?.cancel();
    super.dispose();
  }

  Future<void> _loadBase() async {
    final db = FirebaseFirestore.instance;
    try {
      final active = db
          .collection('challenges')
          .where('status', isEqualTo: 'active');
      final agg = await active.aggregate(count(), sum('amount')).get();
      final people = await db.collection('publicProfiles').count().get();
      _baseActive = agg.count ?? 0;
      _basePrize = (agg.getSum('amount') ?? 0).toDouble();
      _basePart = people.count ?? 0;
      _apply();
    } catch (_) {
      // silencioso — a faixa só não mostra números se a leitura falhar
    }
  }

  // Combina bases + overrides (campo a campo) + drift e atualiza a tela.
  void _apply() {
    if (!mounted) return;
    var a = _baseActive;
    var p = _basePrize;
    var part = _basePart;
    final c = _overrides;
    if (c != null) {
      if (c['activeChallenges'] != null) {
        a = (c['activeChallenges'] as num).toInt();
      }
      if (c['prizePool'] != null) p = (c['prizePool'] as num).toDouble();
      if (c['participants'] != null) {
        part = (c['participants'] as num).toInt();
      }
    }
    setState(() {
      _activeChallenges = a == null ? null : a + _driftChallenges;
      _prizePool = p == null ? null : p + _driftPrize;
      _participants = part == null ? null : part + _driftPart;
    });
  }

  Future<void> _editDialog() async {
    final aCtrl = TextEditingController(text: '${_activeChallenges ?? ''}');
    final pCtrl = TextEditingController(
        text: _prizePool == null ? '' : _prizePool!.toStringAsFixed(2));
    final partCtrl = TextEditingController(text: '${_participants ?? ''}');
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar "Ao vivo"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: aCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Desafios ativos'),
            ),
            TextField(
              controller: pCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Prêmios em jogo (R\$)'),
            ),
            TextField(
              controller: partCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Participantes'),
            ),
            const SizedBox(height: 6),
            const Text('Deixe um campo vazio para voltar ao automático.',
                style: TextStyle(fontSize: 11, color: Colors.black45)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'auto'),
            child: const Text('Tudo automático'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (action == null || action == 'cancel') return;
    final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
    try {
      if (action == 'auto') {
        await functions.httpsCallable('adminSetPulse').call({'clear': true});
      } else {
        await functions.httpsCallable('adminSetPulse').call({
          'activeChallenges': int.tryParse(aCtrl.text.trim()),
          'prizePool': double.tryParse(pCtrl.text.trim().replaceAll(',', '.')),
          'participants': int.tryParse(partCtrl.text.trim()),
        });
      }
      // O stream de config/platformPulse atualiza o banner sozinho.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ao vivo atualizado ✅')),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('[${e.code}] ${e.message ?? 'Erro ao salvar'}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
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
                if (widget.isAdmin)
                  InkWell(
                    onTap: _editDialog,
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child:
                          Icon(Icons.edit, size: 15, color: Colors.white70),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _Stat(
                  icon: Icons.local_fire_department,
                  value: _activeChallenges?.toDouble(),
                  format: (v) => Fmt.number(v.round()),
                  label: 'desafios ativos',
                ),
                _divider(),
                _Stat(
                  icon: Icons.emoji_events,
                  value: _prizePool,
                  // Valor completo (com centavos): o drift de 5s fica visível.
                  format: (v) => Fmt.brl(v),
                  label: 'em prêmios',
                ),
                _divider(),
                _Stat(
                  icon: Icons.groups,
                  value: _participants?.toDouble(),
                  format: (v) => Fmt.number(v.round()),
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
