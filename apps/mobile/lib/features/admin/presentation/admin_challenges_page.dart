import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/widgets/web_frame.dart';
import '../infrastructure/admin_repository.dart';
import 'admin_add_entry_page.dart';

final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

// "Fixar como novo" é exclusivo do super admin (o backend também valida).
const _superAdminEmail = 'gustavo.a.tinti3@gmail.com';

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
        final msg = (e.message != null && e.message != e.code)
            ? e.message!
            : '[${e.code}] ${e.message ?? 'Erro desconhecido'}';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
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
  bool get _pinned => data['pinned'] == true;

  Future<void> _togglePinned(BuildContext context) async {
    final next = !_pinned;
    try {
      await AdminRepository().setChallengePinned(id, next);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next
                ? 'Fixado como novo no topo ✅'
                : 'Removido do topo'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

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
    final isSuper =
        FirebaseAuth.instance.currentUser?.email == _superAdminEmail;

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
                if (_pinned) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3D6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'NOVO',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF9A6B00)),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
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
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                // Editar — disponível para qualquer desafio (ativo ou encerrado)
                OutlinedButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) =>
                        EditChallengeDialog(id: id, data: data),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Editar'),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      textStyle: const TextStyle(fontSize: 12)),
                ),
                if (_isActive && isSuper)
                  OutlinedButton.icon(
                    onPressed: () => _togglePinned(context),
                    icon: Icon(
                        _pinned
                            ? Icons.push_pin
                            : Icons.push_pin_outlined,
                        size: 16,
                        color: const Color(0xFFB8860B)),
                    label: Text(_pinned ? 'Desafixar' : 'Fixar (novo)',
                        style: const TextStyle(color: Color(0xFFB8860B))),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        textStyle: const TextStyle(fontSize: 12),
                        side: const BorderSide(color: Color(0xFFE0B84D))),
                  ),
                if (_isActive) ...[
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
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AdminAddEntryPage(
                          challengeId: id,
                          challengeTitle: title,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.person_add_outlined,
                        size: 16, color: Colors.purple),
                    label: const Text('Add participação',
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
              ],
            ),
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

// ─── Edit challenge dialog ────────────────────────────────────────────────────

class EditChallengeDialog extends StatefulWidget {
  final String id;
  final Map<String, dynamic> data;
  const EditChallengeDialog({super.key, required this.id, required this.data});

  @override
  State<EditChallengeDialog> createState() => EditChallengeDialogState();
}

class EditChallengeDialogState extends State<EditChallengeDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _amountCtrl;
  DateTime? _deadline;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl =
        TextEditingController(text: widget.data['title'] as String? ?? '');
    _descCtrl = TextEditingController(
        text: widget.data['description'] as String? ?? '');
    final amount = (widget.data['amount'] as num?)?.toDouble() ?? 0.0;
    _amountCtrl = TextEditingController(text: amount.toStringAsFixed(2));
    final exp = widget.data['expiresAt'] as String?;
    if (exp != null) _deadline = DateTime.tryParse(exp);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final base = _deadline ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: base.isBefore(DateTime.now()) ? DateTime.now() : base,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _deadline =
          DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
    });
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Título não pode ficar vazio')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await AdminRepository().updateChallenge(
        challengeId: widget.id,
        title: title,
        description: _descCtrl.text.trim(),
        amount:
            double.tryParse(_amountCtrl.text.trim().replaceAll(',', '.')),
        expiresAtIso: _deadline?.toIso8601String(),
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Desafio atualizado ✅')),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message ?? 'Erro')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dl = _deadline;
    return AlertDialog(
      title: const Text('Editar desafio'),
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
                helperText: 'Não movimenta saldo — só o valor exibido',
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDeadline,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Prazo',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today, size: 18),
                ),
                child: Text(
                  dl == null
                      ? 'Sem prazo'
                      : '${dl.day.toString().padLeft(2, '0')}/'
                          '${dl.month.toString().padLeft(2, '0')}/${dl.year}',
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Salvar'),
        ),
      ],
    );
  }
}

