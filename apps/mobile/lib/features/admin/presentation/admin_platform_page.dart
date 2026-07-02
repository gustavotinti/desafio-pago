import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/web_frame.dart';

final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

/// Painel "Plataforma": controla o banner "Ao vivo" (números do topo do feed)
/// e o rodapé de "alta demanda" do feed. Tudo grava em `config/*` via Cloud
/// Functions (Admin SDK) e o app reflete em tempo real (streams).
class AdminPlatformPage extends StatefulWidget {
  const AdminPlatformPage({super.key});

  @override
  State<AdminPlatformPage> createState() => _AdminPlatformPageState();
}

class _AdminPlatformPageState extends State<AdminPlatformPage> {
  final _aCtrl = TextEditingController();
  final _pCtrl = TextEditingController();
  final _partCtrl = TextEditingController();
  bool _savingPulse = false;
  bool _prefilled = false;

  @override
  void dispose() {
    _aCtrl.dispose();
    _pCtrl.dispose();
    _partCtrl.dispose();
    super.dispose();
  }

  Future<void> _savePulse({bool clear = false}) async {
    setState(() => _savingPulse = true);
    try {
      if (clear) {
        await _functions.httpsCallable('adminSetPulse').call({'clear': true});
        _aCtrl.clear();
        _pCtrl.clear();
        _partCtrl.clear();
      } else {
        await _functions.httpsCallable('adminSetPulse').call({
          'activeChallenges': int.tryParse(_aCtrl.text.trim()),
          'prizePool':
              double.tryParse(_pCtrl.text.trim().replaceAll(',', '.')),
          'participants': int.tryParse(_partCtrl.text.trim()),
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(clear
                ? 'Ao vivo voltou ao automático ✅'
                : 'Ao vivo atualizado ✅ (aplica na hora no feed)')));
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
    } finally {
      if (mounted) setState(() => _savingPulse = false);
    }
  }

  Future<void> _setFooter(bool enabled) async {
    try {
      await _functions
          .httpsCallable('adminSetFeedConfig')
          .call({'highDemandFooter': enabled});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(enabled
                ? 'Rodapé "alta demanda" ATIVADO ✅'
                : 'Rodapé "alta demanda" desativado')));
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('[${e.code}] ${e.message ?? 'Erro'}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin — Plataforma')),
      body: WebFrame(
        maxWidth: 700,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Ao vivo ─────────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('config')
                      .doc('platformPulse')
                      .snapshots(),
                  builder: (context, snap) {
                    final c = snap.data?.data();
                    // Prefill (uma vez) com os overrides atuais.
                    if (!_prefilled && snap.hasData) {
                      _prefilled = true;
                      if (c?['activeChallenges'] != null) {
                        _aCtrl.text = '${(c!['activeChallenges'] as num).toInt()}';
                      }
                      if (c?['prizePool'] != null) {
                        _pCtrl.text = (c!['prizePool'] as num)
                            .toDouble()
                            .toStringAsFixed(2);
                      }
                      if (c?['participants'] != null) {
                        _partCtrl.text = '${(c!['participants'] as num).toInt()}';
                      }
                    }
                    final overrideCount = [
                      c?['activeChallenges'],
                      c?['prizePool'],
                      c?['participants'],
                    ].where((v) => v != null).length;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.sensors,
                                color: Color(0xFF0cc0df)),
                            const SizedBox(width: 8),
                            const Text('Banner "Ao vivo agora"',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: overrideCount > 0
                                    ? const Color(0xFFFFF3D6)
                                    : const Color(0xFFE7F6EC),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                overrideCount > 0
                                    ? '$overrideCount campo(s) manual(is)'
                                    : 'Automático',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: overrideCount > 0
                                        ? const Color(0xFF9A6B00)
                                        : Colors.green.shade800),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Deixe um campo vazio para ele voltar ao valor '
                          'automático (agregação real). O feed atualiza na '
                          'hora, sem recarregar.',
                          style:
                              TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _aCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Desafios ativos',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _pCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                            prefixText: 'R\$ ',
                            labelText: 'Prêmios em jogo',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _partCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Participantes',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed:
                                    _savingPulse ? null : () => _savePulse(),
                                child: _savingPulse
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white))
                                    : const Text('Salvar'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton(
                              onPressed: _savingPulse
                                  ? null
                                  : () => _savePulse(clear: true),
                              child: const Text('Tudo automático'),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),

            // ── Rodapé "alta demanda" ───────────────────────────────
            Card(
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('config')
                    .doc('feed')
                    .snapshots(),
                builder: (context, snap) {
                  // Padrão: ligado (só desliga se o doc disser false).
                  final enabled =
                      snap.data?.data()?['highDemandFooter'] != false;
                  return SwitchListTile(
                    secondary: const Icon(Icons.downloading,
                        color: Color(0xFF003b8a)),
                    title: const Text('Rodapé "alta demanda" no feed',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: const Text(
                      'Loader + mensagem de servidor ocupado no fim da '
                      'rolagem dos desafios. Aplica na hora para todo mundo.',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: enabled,
                    onChanged: snap.hasData ? _setFooter : null,
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
