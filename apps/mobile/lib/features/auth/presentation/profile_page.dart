import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/web_frame.dart';
import '../../withdrawals/infrastructure/withdraw_repository.dart';
import '../../finance/infrastructure/get_transactions.dart';
import '../../users/presentation/edit_profile_page.dart';
import '../../users/presentation/followers_page.dart';
import '../../payments/presentation/topup_page.dart';

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
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // — Header —
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundImage: photoUrl.isNotEmpty
                      ? NetworkImage(photoUrl)
                      : null,
                  child: photoUrl.isEmpty
                      ? const Icon(Icons.person, size: 40)
                      : null,
                ),
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
