import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../withdrawals/infrastructure/withdraw_repository.dart';
import '../../finance/infrastructure/get_transactions.dart';
import '../../users/presentation/edit_profile_page.dart';
import '../../payments/presentation/topup_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _pixController = TextEditingController();
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
    _pixController.dispose();
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
    _pixController.text = data['pixKey'] ?? '';
    _transactions = await GetTransactions()(uid);

    setState(() => _userData = data);
  }

  Future<void> _savePix() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update({'pixKey': _pixController.text.trim()});

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Pix salvo')));
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
    final photoUrl = _userData['photoUrl'] as String? ??
        authUser?.photoURL ??
        '';
    final name = _userData['name'] as String? ??
        authUser?.displayName ??
        '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
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
                    currentPhotoUrl: photoUrl,
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
      body: ListView(
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
              _Stat(label: 'Seguidores', value: '$followersCount'),
              _Stat(label: 'Seguindo', value: '$followingCount'),
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

          // — Pix —
          TextField(
            controller: _pixController,
            decoration: const InputDecoration(
              labelText: 'Chave Pix',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: _savePix, child: const Text('Salvar Pix')),
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
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label,
            style:
                const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }
}
