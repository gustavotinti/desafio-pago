import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../withdraw/infrastructure/withdraw_repository.dart';
import '../../finance/infrastructure/get_transactions.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final pixController = TextEditingController();
  final amountController = TextEditingController();

  double balance = 0;
  List transactions = [];

  @override
  void initState() {
    super.initState();
    loadUser();
  }

  Future<void> loadUser() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final data = doc.data();

    if (data != null) {
      balance = (data['balance'] ?? 0).toDouble();
      pixController.text = data['pixKey'] ?? '';
    }

    transactions = await GetTransactions()(user.uid);

    setState(() {});
  }

  Future<void> savePix() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .update({
      'pixKey': pixController.text,
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Pix salvo")),
    );
  }

  Future<void> requestWithdraw() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final amount = double.tryParse(amountController.text) ?? 0;

    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Valor inválido")),
      );
      return;
    }

    try {
      await WithdrawRepository().requestWithdraw(
        user.uid,
        amount,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Saque solicitado")),
      );

      loadUser(); // 🔥 atualiza tela
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Color getColor(String type) {
    if (type == 'withdraw') return Colors.red;
    if (type == 'reward') return Colors.green;
    return Colors.black;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text("Perfil")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Nome: ${user?.displayName ?? ''}"),
            const SizedBox(height: 10),

            Text(
              "Saldo: R\$ $balance",
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

            TextField(
              controller: pixController,
              decoration: const InputDecoration(
                labelText: "Chave Pix",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 10),

            ElevatedButton(
              onPressed: savePix,
              child: const Text("Salvar Pix"),
            ),

            const SizedBox(height: 20),

            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Valor para saque",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 10),

            ElevatedButton(
              onPressed: requestWithdraw,
              child: const Text("Solicitar saque"),
            ),

            const SizedBox(height: 20),

            const Text(
              "Histórico",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            Expanded(
              child: ListView.builder(
                itemCount: transactions.length,
                itemBuilder: (context, index) {
                  final t = transactions[index];

                  return ListTile(
                    title: Text(t['description'] ?? ''),
                    subtitle: Text(t['type'] ?? ''),
                    trailing: Text(
                      "R\$ ${t['amount']}",
                      style: TextStyle(color: getColor(t['type'])),
                    ),
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}