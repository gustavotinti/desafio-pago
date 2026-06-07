import 'package:flutter/material.dart';

import '../../../core/utils/file_download.dart';
import '../../../core/widgets/web_frame.dart';
import '../infrastructure/admin_repository.dart';

class AdminAudiencePage extends StatefulWidget {
  const AdminAudiencePage({super.key});

  @override
  State<AdminAudiencePage> createState() => _AdminAudiencePageState();
}

class _AdminAudiencePageState extends State<AdminAudiencePage> {
  final _repo = AdminRepository();
  String? _busyKey; // "segment_platform" em andamento

  Future<void> _export(String segment, String platform) async {
    final key = '${segment}_$platform';
    setState(() => _busyKey = key);
    try {
      final res = await _repo.exportAudience(segment, platform);
      final csv = res['csv'] as String? ?? '';
      final count = res['count'] as int? ?? 0;
      final filename = res['filename'] as String? ?? 'export.csv';

      if (count == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Nenhum contato neste segmento ainda.')),
          );
        }
        return;
      }

      downloadTextFile(filename, csv);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count contatos exportados — $filename')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dados para campanhas')),
      body: WebFrame(
        maxWidth: 900,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _InfoCard(),
            const SizedBox(height: 16),
            _SegmentCard(
              icon: Icons.person_add_alt_1,
              color: Colors.blue,
              title: 'Cadastros',
              subtitle: 'Todos os usuários que criaram conta',
              segment: 'signups',
              busyKey: _busyKey,
              onExport: _export,
            ),
            const SizedBox(height: 12),
            _SegmentCard(
              icon: Icons.install_mobile,
              color: Colors.teal,
              title: 'Instalações do app',
              subtitle: 'Usuários que abriram o app no celular',
              segment: 'installs',
              busyKey: _busyKey,
              onExport: _export,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Colors.orange, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Os arquivos saem no modelo de cada plataforma:\n'
              '• Google → Customer Match (Email, Phone, First/Last Name…)\n'
              '• Meta → Custom Audiences (email, phone, fn, ln, country)\n\n'
              'Os dados vão sem hash; o próprio Google/Meta faz o hash no '
              'upload. Perfis virtuais e banidos são excluídos. O telefone '
              'só aparece para quem informou (ex.: pedido de verificação).',
              style: TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String segment;
  final String? busyKey;
  final Future<void> Function(String segment, String platform) onExport;

  const _SegmentCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.segment,
    required this.busyKey,
    required this.onExport,
  });

  bool _isBusy(String platform) => busyKey == '${segment}_$platform';

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1A73E8)),
                    onPressed:
                        busyKey != null ? null : () => onExport(segment, 'google'),
                    icon: _isBusy('google')
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.download, size: 18),
                    label: const Text('Google'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0866FF)),
                    onPressed:
                        busyKey != null ? null : () => onExport(segment, 'meta'),
                    icon: _isBusy('meta')
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.download, size: 18),
                    label: const Text('Meta'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
