import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/web_frame.dart';

/// Admin → Métricas reais. Só uso real (sem demonstração e sem votos de
/// admin), calculado no servidor (`adminRealMetrics`). São os números que
/// podem ir para uma inscrição de financiamento.
class AdminMetricsPage extends StatefulWidget {
  const AdminMetricsPage({super.key});

  @override
  State<AdminMetricsPage> createState() => _AdminMetricsPageState();
}

class _AdminMetricsPageState extends State<AdminMetricsPage> {
  Map<String, dynamic>? _m;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _m = null;
      _error = null;
    });
    try {
      final res = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('adminRealMetrics')
          .call();
      if (!mounted) return;
      setState(() => _m = _deep(res.data));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Map<String, dynamic> _deep(Object? v) => Map<String, dynamic>.from(
      (v as Map).map((k, x) => MapEntry('$k', x is Map ? _deep(x) : x)));

  String _brl(Object? v) =>
      'R\$ ${((v as num?) ?? 0).toStringAsFixed(2).replaceAll('.', ',')}';

  String _summary(Map<String, dynamic> m) {
    final u = m['users'] as Map, c = m['challenges'] as Map;
    final e = m['entries'] as Map, v = m['votes'] as Map;
    final $ = m['money'] as Map;
    return 'Métricas reais do Desafio Pago (sem conteúdo de demonstração), '
        '${(m['generatedAt'] as String).substring(0, 10)}:\n'
        '- Usuários reais: ${u['real']}\n'
        '- Desafios reais criados: ${c['real']} (ativos agora: '
        '${c['realActive']}), prêmios oferecidos: ${_brl(c['realPrizeTotalBrl'])}\n'
        '- Participações reais: ${e['real']}\n'
        '- Votos de usuários: ${v['byUsers']}\n'
        '- Depósitos aprovados: ${$['depositsApproved']} '
        '(${_brl($['depositsBrl'])})\n'
        '- Saques pagos: ${$['withdrawalsPaid']} (${_brl($['withdrawalsBrl'])})\n'
        '- XRP Ledger (testnet): ${(m['onchain'] as Map)['prizesRecorded']} '
        'prêmios registrados em escrow, ${(m['onchain'] as Map)['resultsRecorded']} '
        'resultados liberados';
  }

  @override
  Widget build(BuildContext context) {
    final m = _m;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Métricas reais'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: WebFrame(
        child: _error != null
            ? Center(child: Text('Erro: $_error'))
            : m == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text(
                        'Só uso real: perfis, desafios e participações de '
                        'demonstração ficam de fora, assim como votos de '
                        'admin. É isso que um avaliador externo confere.',
                        style: TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 14),
                      Wrap(spacing: 10, runSpacing: 10, children: [
                        _Tile('Usuários reais', '${m['users']['real']}',
                            'demonstração: ${m['users']['demo']}'),
                        _Tile('Desafios reais', '${m['challenges']['real']}',
                            'ativos: ${m['challenges']['realActive']}'),
                        _Tile('Prêmios oferecidos',
                            _brl(m['challenges']['realPrizeTotalBrl']),
                            'desafios reais'),
                        _Tile('Participações reais',
                            '${m['entries']['real']}',
                            'demonstração: ${m['entries']['demo']}'),
                        _Tile('Votos de usuários', '${m['votes']['byUsers']}',
                            'de admin: ${m['votes']['byAdmins']}'),
                        _Tile('Depósitos', _brl(m['money']['depositsBrl']),
                            '${m['money']['depositsApproved']} aprovados'),
                        _Tile('Saques pagos', _brl(m['money']['withdrawalsBrl']),
                            '${m['money']['withdrawalsPaid']} pagos'),
                        _Tile('Prêmios na rede XRP',
                            '${m['onchain']['prizesRecorded']}',
                            'resultados: ${m['onchain']['resultsRecorded']}'),
                      ]),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(text: _summary(m)));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Resumo copiado')));
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Copiar resumo para a inscrição'),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value, this.sub);
  final String label;
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCE3EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()])),
          Text(sub,
              style: const TextStyle(fontSize: 11, color: Colors.black45)),
        ],
      ),
    );
  }
}
