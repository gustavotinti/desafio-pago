import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../core/widgets/web_frame.dart';
import '../../payments/presentation/topup_page.dart';
import '../application/create_challenge.dart';
import '../domain/entities/challenge.dart';
import '../domain/entities/challenge_status.dart';
import '../infrastructure/firebase_challenge_repository.dart';

class CreateChallengePage extends StatefulWidget {
  const CreateChallengePage({super.key});

  @override
  State<CreateChallengePage> createState() => _CreateChallengePageState();
}

class _CreateChallengePageState extends State<CreateChallengePage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final _durationController = TextEditingController();
  bool _isLoading = false;
  double? _userBalance;
  bool _isLoadingBalance = true;

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _amountController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _loadBalance() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _isLoadingBalance = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (mounted) {
        setState(() {
          _userBalance =
              (doc.data()?['balance'] as num?)?.toDouble() ?? 0.0;
          _isLoadingBalance = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingBalance = false);
    }
  }

  void _showAddCreditsDialog(double required, double available) {
    final gap = required - available;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Créditos insuficientes'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Para criar este desafio você precisa de '
              'R\$${required.toStringAsFixed(2)}.',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined,
                    size: 15, color: Colors.black45),
                const SizedBox(width: 6),
                Text(
                  'Seu saldo: R\$${available.toStringAsFixed(2)}',
                  style:
                      const TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ],
            ),
            if (available > 0) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.arrow_forward, size: 14,
                      color: Colors.orange),
                  const SizedBox(width: 6),
                  Text(
                    'Faltam R\$${gap.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Adicione créditos via Pix e volte para criar o desafio.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.pix, size: 16),
            label: const Text('Adicionar via Pix'),
            onPressed: () async {
              Navigator.pop(ctx);
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TopUpPage()),
              );
              await _loadBalance();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Saldo atualizado — toque em "Criar Desafio" novamente.'),
                    duration: Duration(seconds: 4),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final amount = double.parse(_amountController.text.trim());
    final days = int.parse(_durationController.text.trim());
    final balance = _userBalance ?? 0.0;

    // ── Check balance before calling Cloud Function ──────────────────
    if (balance < amount) {
      _showAddCreditsDialog(amount, balance);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final now = DateTime.now();

      final challenge = Challenge(
        id: const Uuid().v4(),
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        createdBy: user.uid,
        amount: amount,
        status: ChallengeStatus.active,
        voteCount: 0,
        entryCount: 0,
        createdAt: now,
        expiresAt: now.add(Duration(days: days)),
      );

      await CreateChallenge(FirebaseChallengeRepository()).call(challenge);

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        // CF returned insufficient balance — show Pix dialog
        if (msg.contains('nsuficiente') ||
            msg.contains('failed-precondition')) {
          _showAddCreditsDialog(amount, _userBalance ?? 0.0);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Criar Desafio')),
      body: WebFrame(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Balance indicator ─────────────────────────────────
                _BalanceTile(
                  balance: _userBalance,
                  isLoading: _isLoadingBalance,
                  onRefresh: _loadBalance,
                  onAddCredits: () => _showAddCreditsDialog(
                    double.tryParse(_amountController.text.trim()) ?? 0,
                    _userBalance ?? 0.0,
                  ),
                ),
                const SizedBox(height: 16),

                // ── Form fields ───────────────────────────────────────
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Título',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Título obrigatório'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Descrição',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Descrição obrigatória'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amountController,
                  decoration: const InputDecoration(
                    prefixText: 'R\$ ',
                    labelText: 'Valor do prêmio',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}), // rebuild for balance hint
                  validator: (v) {
                    final n = double.tryParse(v?.trim() ?? '');
                    if (n == null || n <= 0) return 'Informe um valor válido';
                    return null;
                  },
                ),
                // ── Insufficient balance hint ─────────────────────────
                Builder(builder: (ctx) {
                  final typed =
                      double.tryParse(_amountController.text.trim()) ?? 0;
                  final bal = _userBalance ?? 0.0;
                  if (!_isLoadingBalance && _userBalance != null &&
                      typed > 0 && bal < typed) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline,
                              size: 14, color: Colors.orange),
                          const SizedBox(width: 4),
                          Text(
                            'Saldo insuficiente — você adicionará '
                            'R\$${(typed - bal).toStringAsFixed(2)} via Pix',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.orange),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                }),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _durationController,
                  decoration: const InputDecoration(
                    labelText: 'Duração (dias, 1–30)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final n = int.tryParse(v?.trim() ?? '');
                    if (n == null || n < 1) return 'Mínimo 1 dia';
                    if (n > 30) return 'Máximo 30 dias';
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Criar Desafio'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Balance tile ──────────────────────────────────────────────────────────────

class _BalanceTile extends StatelessWidget {
  final double? balance;
  final bool isLoading;
  final VoidCallback onRefresh;
  final VoidCallback onAddCredits;

  const _BalanceTile({
    required this.balance,
    required this.isLoading,
    required this.onRefresh,
    required this.onAddCredits,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBDCAF0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet_outlined,
              size: 18, color: Color(0xFF003b8a)),
          const SizedBox(width: 10),
          isLoading
              ? const SizedBox(
                  height: 14,
                  width: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  'Saldo: R\$${(balance ?? 0.0).toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF003b8a),
                      fontWeight: FontWeight.w600),
                ),
          const Spacer(),
          TextButton.icon(
            onPressed: onAddCredits,
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Adicionar', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 16),
            visualDensity: VisualDensity.compact,
            tooltip: 'Atualizar saldo',
            onPressed: onRefresh,
          ),
        ],
      ),
    );
  }
}
