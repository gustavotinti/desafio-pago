import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

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
              'Saque solicitado — você receberá R\$${net.toStringAsFixed(2)} (taxa: R\$${fee.toStringAsFixed(2)})',
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
                Text(
                  name,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
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
                value: '$followersCount',
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
                value: '$followingCount',
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
              _Stat(label: 'Votos', value: '$totalVotes'),
              _Stat(
                  label: 'Ganhos',
                  value: 'R\$${totalEarned.toStringAsFixed(0)}'),
            ],
          ),
          const Divider(height: 32),

          // — Saldo —
          Text(
            'Créditos disponíveis: R\$ ${balance.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          if (pendingBalance > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Em desafios ativos: R\$ ${pendingBalance.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 14, color: Colors.orange),
            ),
          ],
          if (lockedBalance > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Aguardando saque: R\$ ${lockedBalance.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 14, color: Colors.blue),
            ),
          ],
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
