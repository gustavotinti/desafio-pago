import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/web_frame.dart';

final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

/// Painel "Instagram": liga/desliga a automação, define o valor de prêmio a
/// partir do qual um desafio é postado, e mostra a fila (pendentes / postados
/// / falhos) com opção de re-tentar. As credenciais ficam no cofre (Chaves).
class AdminInstagramPage extends StatefulWidget {
  const AdminInstagramPage({super.key});

  @override
  State<AdminInstagramPage> createState() => _AdminInstagramPageState();
}

class _AdminInstagramPageState extends State<AdminInstagramPage> {
  final _thresholdCtrl = TextEditingController();
  bool _prefilled = false;

  @override
  void dispose() {
    _thresholdCtrl.dispose();
    super.dispose();
  }

  Future<void> _setConfig({bool? enabled, double? threshold}) async {
    try {
      final payload = <String, dynamic>{};
      if (enabled != null) payload['enabled'] = enabled;
      if (threshold != null) payload['threshold'] = threshold;
      await _functions
          .httpsCallable('adminSetInstagramConfig')
          .call(payload);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Configuração salva ✅')));
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('[${e.code}] ${e.message ?? 'Erro'}')));
      }
    }
  }

  Future<void> _retry(String postId) async {
    try {
      await _functions
          .httpsCallable('adminRetryInstagramPost')
          .call({'postId': postId});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Reenfileirado para nova tentativa')));
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message ?? 'Erro')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin — Instagram')),
      body: WebFrame(
        maxWidth: 720,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Config: toggle + threshold ──────────────────────────
            Card(
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('config')
                    .doc('instagram')
                    .snapshots(),
                builder: (context, snap) {
                  final data = snap.data?.data();
                  final enabled = data?['enabled'] != false;
                  final threshold =
                      (data?['threshold'] as num?)?.toDouble() ?? 100.0;
                  if (!_prefilled && snap.hasData) {
                    _prefilled = true;
                    _thresholdCtrl.text = threshold.toStringAsFixed(2);
                  }
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.camera_alt,
                              color: Color(0xFFC13584)),
                          title: const Text('Automação ligada',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                          subtitle: const Text(
                            'Posta a melhor participação do desafio no '
                            'Instagram quando o prêmio cruza o valor abaixo. '
                            'A cada 10 min o sistema envia a fila.',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: enabled,
                          onChanged: snap.hasData
                              ? (v) => _setConfig(enabled: v)
                              : null,
                        ),
                        const Divider(),
                        const SizedBox(height: 4),
                        const Text('Postar quando o prêmio atingir:',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _thresholdCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: const InputDecoration(
                                  prefixText: 'R\$ ',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilledButton(
                              onPressed: () {
                                final t = double.tryParse(_thresholdCtrl.text
                                    .trim()
                                    .replaceAll(',', '.'));
                                if (t != null && t > 0) {
                                  _setConfig(threshold: t);
                                }
                              },
                              child: const Text('Salvar'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'As credenciais do Instagram ficam em '
                          'Admin → Chaves & integrações.',
                          style: TextStyle(
                              fontSize: 11.5, color: Colors.black54),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // ── Fila de posts ───────────────────────────────────────
            const Padding(
              padding: EdgeInsets.only(left: 2, bottom: 8),
              child: Text('FILA DE PUBLICAÇÕES',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: Colors.black45)),
            ),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('instagram_posts')
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(
                      child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator()));
                }
                final docs = snap.data!.docs.toList()
                  ..sort((a, b) => (b.data()['createdAt'] as String? ?? '')
                      .compareTo(a.data()['createdAt'] as String? ?? ''));
                if (docs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                        'Nenhum post ainda. Quando um desafio cruzar o valor, '
                        'ele aparece aqui.',
                        style: TextStyle(color: Colors.black54)),
                  );
                }
                return Column(
                  children: docs.map((d) => _PostTile(
                        id: d.id,
                        data: d.data(),
                        onRetry: () => _retry(d.id),
                      )).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PostTile extends StatelessWidget {
  final String id;
  final Map<String, dynamic> data;
  final VoidCallback onRetry;

  const _PostTile({
    required this.id,
    required this.data,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final status = data['status'] as String? ?? 'pending';
    final (color, label, icon) = switch (status) {
      'posted' => (const Color(0xFF00875A), 'Postado', Icons.check_circle),
      'failed' => (Colors.red, 'Falhou', Icons.error_outline),
      _ => (Colors.orange, 'Na fila', Icons.schedule),
    };
    final error = data['error'] as String?;
    final retry = data['retryCount'] as int? ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5)),
                const Spacer(),
                FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  future: FirebaseFirestore.instance
                      .collection('challenges')
                      .doc(data['challengeId'] as String? ?? '_')
                      .get(),
                  builder: (context, s) {
                    final amount =
                        (s.data?.data()?['amount'] as num?)?.toDouble();
                    return Text(amount == null ? '' : Fmt.brl(amount),
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54));
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: FirebaseFirestore.instance
                  .collection('challenges')
                  .doc(data['challengeId'] as String? ?? '_')
                  .get(),
              builder: (context, s) {
                final title = s.data?.data()?['title'] as String? ?? id;
                return Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13.5));
              },
            ),
            if (status == 'failed' && error != null) ...[
              const SizedBox(height: 4),
              Text('Erro: $error  ·  tentativas: $retry',
                  style:
                      const TextStyle(fontSize: 11.5, color: Colors.red)),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 15),
                label: const Text('Tentar de novo'),
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
