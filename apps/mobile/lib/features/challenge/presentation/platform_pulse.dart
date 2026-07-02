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
      final people = await db.collection('publicProfiles').count().get();
      var a = agg.count ?? 0;
      var p = agg.getSum('amount') ?? 0;
      var part = people.count ?? 0;
      // Overrides do admin (config/platformPulse) — por campo.
      final c = (await db.collection('config').doc('platformPulse').get())
          .data();
      if (c != null) {
        if (c['activeChallenges'] != null) {
          a = (c['activeChallenges'] as num).toInt();
        }
        if (c['prizePool'] != null) p = (c['prizePool'] as num).toDouble();
        if (c['participants'] != null) {
          part = (c['participants'] as num).toInt();
        }
      }
      if (!mounted) return;
      setState(() {
        _activeChallenges = a;
        _prizePool = p;
        _participants = part;
      });
    } catch (_) {
      // silencioso — a faixa só não mostra números se a leitura falhar
    }
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
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ao vivo atualizado ✅')),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message ?? 'Erro ao salvar')));
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
