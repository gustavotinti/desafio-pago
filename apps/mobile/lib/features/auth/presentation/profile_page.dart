import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/safe_avatar.dart';
import '../../../core/widgets/web_frame.dart';
import '../../withdrawals/infrastructure/withdraw_repository.dart';
import '../../finance/infrastructure/get_transactions.dart';
import '../../users/presentation/edit_profile_page.dart';
import '../../users/presentation/followers_page.dart';
import '../../users/presentation/achievements.dart';
import '../../users/presentation/my_activity_page.dart';
import '../../payments/presentation/topup_page.dart';
import '../../payments/infrastructure/payment_repository.dart';
import '../../payments/presentation/payment_page.dart';
import '../../verification/infrastructure/verification_repository.dart';
import '../../verification/presentation/verification_request_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _amountController = TextEditingController();

  Map<String, dynamic> _userData = {};
  List _transactions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    final data = doc.data() ?? {};
    _transactions = await GetTransactions()(uid);

    setState(() => _userData = data);
  }

  Future<void> _requestWithdraw() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Valor inválido')),
      );
      return;
    }

    try {
      await WithdrawRepository().requestWithdraw(uid, amount);
      final fee = amount * 0.10;
      final net = amount - fee;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saque solicitado — você receberá ${Fmt.brl(net)} (taxa: ${Fmt.brl(fee)})',
            ),
          ),
        );
        _amountController.clear();
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir conta'),
        content: const Text(
          'Esta ação é permanente e não pode ser desfeita.\n\n'
          'Seus dados pessoais serão removidos. '
          'Suas participações em desafios serão anonimizadas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Excluir permanentemente'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await FirebaseFunctions.instance
          .httpsCallable('deleteAccount')
          .call();
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Color _txColor(String type) {
    if (type == 'reward' || type == 'deposit') return Colors.green;
    if (type == 'withdraw' || type == 'challenge_created' || type == 'aporte') {
      return Colors.red;
    }
    return Colors.black87;
  }

  @override
  Widget build(BuildContext context) {
    final authUser = FirebaseAuth.instance.currentUser;
    final balance = (_userData['balance'] as num? ?? 0).toDouble();
    final pendingBalance =
        (_userData['pendingBalance'] as num? ?? 0).toDouble();
    final lockedBalance =
        (_userData['lockedBalance'] as num? ?? 0).toDouble();
    final totalEarned = (_userData['totalEarned'] ?? 0 as num).toDouble();
    final followersCount = _userData['followersCount'] ?? 0;
    final followingCount = _userData['followingCount'] ?? 0;
    final totalVotes = _userData['totalVotesReceived'] ?? 0;
    final bio = _userData['bio'] as String? ?? '';
    final pixKey = _userData['pixKey'] as String? ?? '';
    final photoUrl = _userData['photoUrl'] as String? ??
        authUser?.photoURL ??
        '';
    final name = _userData['name'] as String? ??
        authUser?.displayName ??
        '';
    final username = _userData['username'] as String? ?? '';
    final isVerified = _userData['isVerified'] == true;

    return Scaffold(
      appBar: AppBar(
        title: SizedBox(
          height: 52,
          width: 220,
          child: Image.asset(
            'assets/images/2.png',
            fit: BoxFit.contain,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Editar perfil',
            onPressed: () async {
              final updated = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => EditProfilePage(
                    currentName: name,
                    currentBio: bio,
                    currentPixKey: pixKey,
                    currentPhotoUrl: photoUrl,
                    currentUsername: username,
                    pixLocked: lockedBalance > 0,
                  ),
                ),
              );
              if (updated == true) _load();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: WebFrame(
        maxWidth: 500,
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // — Header —
          Center(
            child: Column(
              children: [
                SafeAvatar(photoUrl: photoUrl, radius: 40),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    if (isVerified) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified,
                          color: Colors.blue, size: 20),
                    ],
                  ],
                ),
                if (username.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '@$username',
                    style: const TextStyle(
                        color: Colors.black54, fontSize: 13),
                  ),
                ],
                if (bio.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(bio,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // — Verificação —
          _VerificationSection(isVerified: isVerified, currentName: name),

          // — Stats row —
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Stat(
                label: 'Seguidores',
                value: Fmt.number(followersCount),
                onTap: () {
                  final uid = FirebaseAuth.instance.currentUser?.uid;
                  if (uid == null) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FollowersPage(
                        userId: uid,
                        type: FollowType.followers,
                      ),
                    ),
                  );
                },
              ),
              _Stat(
                label: 'Seguindo',
                value: Fmt.number(followingCount),
                onTap: () {
                  final uid = FirebaseAuth.instance.currentUser?.uid;
                  if (uid == null) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FollowersPage(
                        userId: uid,
                        type: FollowType.following,
                      ),
                    ),
                  );
                },
              ),
              _Stat(label: 'Votos', value: Fmt.number(totalVotes)),
              _Stat(label: 'Ganhos', value: Fmt.brlCompact(totalEarned)),
            ],
          ),
          const SizedBox(height: 14),
          // — Minha atividade (meus desafios + participações) —
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.dashboard_customize_outlined,
                  color: Color(0xFF003b8a)),
              title: const Text('Minha atividade'),
              subtitle: const Text('Meus desafios e participações',
                  style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MyActivityPage()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (authUser != null)
            AchievementsSection(userId: authUser.uid, isOwn: true),
          const Divider(height: 32),

          // — Saldo (styled card) ——————————————————————————————————————
          _BalanceCard(
            balance: balance,
            pendingBalance: pendingBalance,
            lockedBalance: lockedBalance,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TopUpPage()),
                );
                _load();
              },
              icon: const Icon(Icons.add),
              label: const Text('Adicionar créditos'),
            ),
          ),
          const SizedBox(height: 16),

          // — Chave Pix —
          InkWell(
            onTap: () async {
              final updated = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => EditProfilePage(
                    currentName: name,
                    currentBio: bio,
                    currentPixKey: pixKey,
                    currentPhotoUrl: photoUrl,
                    currentUsername: username,
                    pixLocked: lockedBalance > 0,
                  ),
                ),
              );
              if (updated == true) _load();
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: pixKey.isEmpty
                    ? Colors.orange.shade50
                    : Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: pixKey.isEmpty
                      ? Colors.orange.shade200
                      : Colors.green.shade200,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.pix,
                    size: 18,
                    color: pixKey.isEmpty
                        ? Colors.orange.shade700
                        : Colors.green.shade700,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Chave Pix',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.black54),
                        ),
                        Text(
                          pixKey.isEmpty
                              ? 'Não configurada — toque para adicionar'
                              : pixKey,
                          style: TextStyle(
                            fontSize: 13,
                            color: pixKey.isEmpty
                                ? Colors.orange.shade800
                                : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.edit_outlined,
                      size: 15, color: Colors.black38),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // — Saque —
          TextField(
            controller: _amountController,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Valor para saque (mín. R\$100)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _requestWithdraw,
            child: const Text('Solicitar saque'),
          ),
          const Divider(height: 32),

          // — Histórico —
          const Text(
            'Histórico',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_transactions.isEmpty)
            const Text('Nenhuma transação ainda')
          else
            ...(_transactions.map((t) => ListTile(
                  dense: true,
                  title: Text(t['description'] ?? ''),
                  subtitle: Text(t['type'] ?? ''),
                  trailing: Text(
                    'R\$ ${(t['amount'] as num).toStringAsFixed(2)}',
                    style: TextStyle(color: _txColor(t['type'] ?? '')),
                  ),
                ))),

          const Divider(height: 40),
          TextButton.icon(
            onPressed: _deleteAccount,
            icon: const Icon(Icons.delete_forever, color: Colors.red),
            label: const Text(
              'Excluir minha conta',
              style: TextStyle(color: Colors.red),
            ),
          ),
          const SizedBox(height: 16),
        ],
        ),
      ),
    );
  }
}

// ── Balance card ──────────────────────────────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  final double balance;
  final double pendingBalance;
  final double lockedBalance;

  const _BalanceCard({
    required this.balance,
    required this.pendingBalance,
    required this.lockedBalance,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF003b8a), Color(0xFF0cc0df)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF003b8a).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  color: Colors.white70, size: 16),
              SizedBox(width: 6),
              Text(
                'CRÉDITOS DISPONÍVEIS',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            Fmt.brl(balance),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          if (pendingBalance > 0 || lockedBalance > 0) ...[
            const SizedBox(height: 10),
            Divider(color: Colors.white.withValues(alpha: 0.2), height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                if (pendingBalance > 0)
                  _BalanceLine(
                    icon: Icons.pending_outlined,
                    label: 'Em desafios',
                    value: Fmt.brl(pendingBalance),
                    color: Colors.amber,
                  ),
                if (pendingBalance > 0 && lockedBalance > 0)
                  const SizedBox(width: 20),
                if (lockedBalance > 0)
                  _BalanceLine(
                    icon: Icons.lock_outline,
                    label: 'Aguard. saque',
                    value: Fmt.brl(lockedBalance),
                    color: Colors.cyanAccent,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BalanceLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _BalanceLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: color.withValues(alpha: 0.85)),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.7))),
          ],
        ),
        Text(value,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
      ],
    );
  }
}

// ── Stat ──────────────────────────────────────────────────────────────────────

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _Stat({required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label,
            style:
                const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(padding: const EdgeInsets.all(4), child: content),
    );
  }
}

// ── Verification section ────────────────────────────────────────────────────────

class _VerificationSection extends StatelessWidget {
  final bool isVerified;
  final String currentName;

  const _VerificationSection({
    required this.isVerified,
    required this.currentName,
  });

  Future<void> _openRequest(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VerificationRequestPage(currentName: currentName),
      ),
    );
  }

  Future<void> _startPriority(BuildContext context) async {
    try {
      final data = await PaymentRepository()
          .createPixPayment(500, purpose: 'verification_priority');
      if (!context.mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentPage(
            paymentId: data['paymentId'] as String,
            qrCode: data['qrCode'] as String,
            qrCodeBase64: data['qrCodeBase64'] as String,
            amount: 500,
            expiresAt: DateTime.parse(data['expiresAt'] as String),
            successTitle: '⭐ Fila prioritária confirmada!',
            successMessage: 'Seu pedido entrou na fila prioritária '
                'e será analisado primeiro.',
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Widget _banner(Color color, IconData icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color,
                        fontSize: 13)),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isVerified) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: VerificationRepository().myRequest(),
      builder: (context, snap) {
        final exists = snap.hasData && snap.data!.exists;
        final data = exists ? snap.data!.data() : null;
        final status = data?['status'] as String?;
        final priority = data?['priority'] == true;

        Widget child;
        if (!exists || status == null || status == 'rejected') {
          final rejected = status == 'rejected';
          child = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (rejected) ...[
                _banner(Colors.red, Icons.cancel,
                    'Pedido de verificação recusado',
                    'Você pode enviar um novo pedido.'),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(
                onPressed: () => _openRequest(context),
                icon: const Icon(Icons.verified,
                    size: 18, color: Colors.blue),
                label: Text(
                    rejected ? 'Enviar novo pedido' : 'Pedir selo verificado'),
              ),
            ],
          );
        } else if (status == 'pending' && priority) {
          child = _banner(Colors.amber.shade800, Icons.bolt,
              'Em análise • Fila prioritária',
              'Pagamento confirmado. Seu pedido será analisado primeiro.');
        } else if (status == 'pending') {
          child = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _banner(Colors.blue, Icons.hourglass_top, 'Pedido em análise',
                  'Quer ser analisado primeiro? Entre na fila prioritária.'),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () => _startPriority(context),
                icon: const Icon(Icons.bolt, size: 18),
                label: const Text('Furar fila — R\$ 500 (Pix)'),
              ),
            ],
          );
        } else {
          child = const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: child,
        );
      },
    );
  }
}
