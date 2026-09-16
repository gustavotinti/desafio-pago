import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_config.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/web_frame.dart';
import '../../payments/presentation/paypal_topup_page.dart';
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

  // Valores em BRL (ledger); Fmt.brl exibe em US$ no site internacional.
  void _showAddCreditsDialog(double required, double available) {
    final gap = required - available;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(I18n.tr('insufficient_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(I18n.trp('need_amount', {'v': Fmt.brl(required)})),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined,
                    size: 15, color: Colors.black45),
                const SizedBox(width: 6),
                Text(
                  I18n.trp('your_balance', {'v': Fmt.brl(available)}),
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
                    I18n.trp('missing_amount', {'v': Fmt.brl(gap)}),
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Text(
              I18n.tr('add_credits_hint'),
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(I18n.tr('cancel')),
          ),
          ElevatedButton.icon(
            icon: Icon(
                AppConfig.intl ? Icons.account_balance_wallet : Icons.pix,
                size: 16),
            label: Text(I18n.tr('add_via')),
            onPressed: () async {
              Navigator.pop(ctx);
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => AppConfig.intl
                        ? const PaypalTopUpPage()
                        : const TopUpPage()),
              );
              await _loadBalance();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(I18n.tr('balance_updated')),
                    duration: const Duration(seconds: 4),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  /// Valor digitado → BRL do ledger. No intl o usuário digita US$.
  double _typedToBrl() {
    final typed =
        double.tryParse(_amountController.text.trim().replaceAll(',', '.')) ??
            0;
    return AppConfig.intl ? Fmt.usdToBrl(typed) : typed;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // amount SEMPRE em BRL (ledger) — no intl converte o US$ digitado.
    final amount = _typedToBrl();
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
      appBar: AppBar(title: Text(I18n.tr('create_title'))),
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
                    _typedToBrl(),
                    _userBalance ?? 0.0,
                  ),
                ),
                const SizedBox(height: 16),

                // ── Form fields ───────────────────────────────────────
                TextFormField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: I18n.tr('title_label'),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? I18n.tr('title_required')
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: I18n.tr('desc_label'),
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? I18n.tr('desc_required')
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amountController,
                  decoration: InputDecoration(
                    // BR digita em R$; intl digita em US$ (convertido p/ o ledger).
                    prefixText: AppConfig.intl ? '\$ ' : 'R\$ ',
                    labelText: I18n.tr('prize_label'),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}), // rebuild for balance hint
                  validator: (v) {
                    final n =
                        double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                    if (n == null || n <= 0) return I18n.tr('prize_invalid');
                    return null;
                  },
                ),
                // ── Insufficient balance hint ─────────────────────────
                Builder(builder: (ctx) {
                  final typedBrl = _typedToBrl();
                  final bal = _userBalance ?? 0.0;
                  if (!_isLoadingBalance && _userBalance != null &&
                      typedBrl > 0 && bal < typedBrl) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline,
                              size: 14, color: Colors.orange),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              I18n.trp('insufficient_hint',
                                  {'v': Fmt.brl(typedBrl - bal)}),
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.orange),
                            ),
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
                  decoration: InputDecoration(
                    labelText: I18n.tr('duration_label'),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final n = int.tryParse(v?.trim() ?? '');
                    if (n == null || n < 1) return I18n.tr('min_1_day');
                    if (n > 30) return I18n.tr('max_30_days');
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
                      : Text(I18n.tr('create_title')),
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
                  I18n.trp('balance_label', {'v': Fmt.brl(balance ?? 0.0)}),
                  style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF003b8a),
                      fontWeight: FontWeight.w600),
                ),
          const Spacer(),
          TextButton.icon(
            onPressed: onAddCredits,
            icon: const Icon(Icons.add, size: 14),
            label: Text(I18n.tr('add_short'),
                style: const TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 16),
            visualDensity: VisualDensity.compact,
            tooltip: I18n.tr('refresh_balance'),
            onPressed: onRefresh,
          ),
        ],
      ),
    );
  }
}
