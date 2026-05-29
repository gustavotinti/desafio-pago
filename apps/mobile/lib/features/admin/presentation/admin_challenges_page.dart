import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/widgets/web_frame.dart';

final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

class AdminChallengesPage extends StatelessWidget {
  const AdminChallengesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin — Desafios')),
      body: WebFrame(
        maxWidth: 900,
        child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('challenges')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(child: Text('Nenhum desafio ainda.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data() as Map<String, dynamic>;
              return _AdminChallengeCard(id: doc.id, data: data);
            },
          );
        },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Criar desafio'),
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const _CreateChallengeDialog(),
    );
  }
}

// ─── Create dialog ────────────────────────────────────────────────────────────

class _CreateChallengeDialog extends StatefulWidget {
  const _CreateChallengeDialog();

  @override
  State<_CreateChallengeDialog> createState() =>
      _CreateChallengeDialogState();
}

class _CreateChallengeDialogState extends State<_CreateChallengeDialog> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  int _durationDays = 7;
  bool _saving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final title = _titleCtrl.text.trim();
    final description = _descCtrl.text.trim();
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;

    if (title.isEmpty || description.isEmpty || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha todos os campos')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await _functions.httpsCallable('createChallenge').call({
        'title': title,
        'description': description,
        'amount': amount,
        'durationDays': _durationDays,
      });

      if (mounted) Navigator.pop(context);
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message ?? 'Erro')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Criar desafio'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Título',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Descrição',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                prefixText: 'R\$ ',
                labelText: 'Prêmio',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Duração: '),
                Expanded(
                  child: Slider(
                    value: _durationDays.toDouble(),
                    min: 1,
                    max: 30,
                    divisions: 29,
                    label: '$_durationDays dias',
                    onChanged: (v) =>
                        setState(() => _durationDays = v.round()),
                  ),
                ),
                Text('$_durationDays d'),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _create,
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Criar'),
        ),
      ],
    );
  }
}

// ─── Challenge card ───────────────────────────────────────────────────────────

class _AdminChallengeCard extends StatelessWidget {
  final String id;
  final Map<String, dynamic> data;

  const _AdminChallengeCard({required this.id, required this.data});

  String get _status => data['status'] ?? 'active';
  bool get _isActive => _status == 'active';

  Future<void> _extendDeadline(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked == null) return;

    final newExpiry = DateTime(
      picked.year,
      picked.month,
      picked.day,
      23,
      59,
      59,
    );

    await FirebaseFirestore.instance
        .collection('challenges')
        .doc(id)
        .update({'expiresAt': newExpiry.toIso8601String()});

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prazo estendido')),
      );
    }
  }

  Future<void> _forceFinish(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Encerrar desafio?'),
        content: const Text(
            'O prêmio será distribuído imediatamente. Essa ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Encerrar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('adminFinishChallenge')
          .call({'challengeId': id});

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Desafio encerrado e prêmio distribuído')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = data['title'] ?? '';
    final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
    final voteCount = data['voteCount'] ?? 0;
    final entryCount = data['entryCount'] ?? 0;
    final expiresAt = data['expiresAt'] as String?;
    final winnerIds = List<String>.from(data['winnerIds'] ?? []);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _isActive
                        ? Colors.green.shade100
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _isActive ? 'Ativo' : 'Encerrado',
                    style: TextStyle(
                        fontSize: 11,
                        color: _isActive
                            ? Colors.green.shade800
                            : Colors.grey.shade700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'R\$ ${amount.toStringAsFixed(2)}  ·  $entryCount participações  ·  $voteCount votos',
              style:
                  const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            if (expiresAt != null) ...[
              const SizedBox(height: 2),
              Text(
                'Prazo: ${_formatDate(expiresAt)}',
                style:
                    const TextStyle(fontSize: 12, color: Colors.black45),
              ),
            ],
            if (!_isActive && winnerIds.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                winnerIds.length == 1 ? 'Vencedor' : '${winnerIds.length} vencedores',
                style: const TextStyle(
                    fontSize: 12, color: Colors.green),
              ),
            ],
            if (_isActive) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _extendDeadline(context),
                    icon: const Icon(Icons.schedule, size: 16),
                    label: const Text('Estender prazo'),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        textStyle: const TextStyle(fontSize: 12)),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => _DemoEntryDialog(challengeId: id),
                    ),
                    icon: const Icon(Icons.person_add_outlined,
                        size: 16, color: Colors.purple),
                    label: const Text('Demo entry',
                        style: TextStyle(color: Colors.purple)),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        textStyle: const TextStyle(fontSize: 12),
                        side: const BorderSide(color: Colors.purple)),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _forceFinish(context),
                    icon: const Icon(Icons.stop_circle_outlined,
                        size: 16, color: Colors.red),
                    label: const Text('Encerrar agora',
                        style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        textStyle: const TextStyle(fontSize: 12),
                        side: const BorderSide(color: Colors.red)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

// ─── Demo Entry Dialog ────────────────────────────────────────────────────────

class _DemoEntryDialog extends StatefulWidget {
  final String challengeId;
  const _DemoEntryDialog({required this.challengeId});

  @override
  State<_DemoEntryDialog> createState() => _DemoEntryDialogState();
}

class _DemoEntryDialogState extends State<_DemoEntryDialog> {
  final _nameCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  String _contentType = 'text';
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _contentCtrl.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha o conteúdo')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final Map<String, dynamic> callData = {
        'challengeId': widget.challengeId,
        'contentType': _contentType,
        'demoName': _nameCtrl.text.trim().isEmpty
            ? 'Participante Demo'
            : _nameCtrl.text.trim(),
      };
      if (_contentType == 'text') {
        callData['contentText'] = content;
      } else {
        callData['contentUrl'] = content;
      }

      await _functions.httpsCallable('adminSubmitDemoEntry').call(callData);
      if (mounted) Navigator.pop(context);
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Erro')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Adicionar participante demo'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nome do participante (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'text', label: Text('Texto')),
                ButtonSegment(value: 'image', label: Text('Imagem')),
                ButtonSegment(value: 'video', label: Text('Vídeo')),
              ],
              selected: {_contentType},
              onSelectionChanged: (s) => setState(() {
                _contentType = s.first;
                _contentCtrl.clear();
              }),
            ),
            const SizedBox(height: 12),
            if (_contentType == 'text')
              TextField(
                controller: _contentCtrl,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Texto do participante',
                  border: OutlineInputBorder(),
                ),
              )
            else
              TextField(
                controller: _contentCtrl,
                decoration: InputDecoration(
                  labelText: _contentType == 'image'
                      ? 'URL da imagem'
                      : 'URL do vídeo',
                  border: const OutlineInputBorder(),
                  hintText: 'https://...',
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Adicionar'),
        ),
      ],
    );
  }
}
