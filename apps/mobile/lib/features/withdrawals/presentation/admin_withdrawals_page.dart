import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminWithdrawalsPage extends StatelessWidget {
  const AdminWithdrawalsPage({super.key});

  Future<Map<String, dynamic>?> getUser(String userId) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();

    if (!doc.exists) return null;

    return doc.data();
  }

  // 🚀 NOVA FUNÇÃO COMPLETA (COM SALDO AUTOMÁTICO)
  Future<void> approve(String id, Map<String, dynamic> data) async {
    final firestore = FirebaseFirestore.instance;

    final userId = data['userId'];
    final amount = data['amount'];

    final userRef = firestore.collection('users').doc(userId);
    final withdrawalRef = firestore.collection('withdrawals').doc(id);

    await firestore.runTransaction((transaction) async {
      final userSnapshot = await transaction.get(userRef);

      if (!userSnapshot.exists) {
        throw Exception("Usuário não encontrado");
      }

      final userData = userSnapshot.data() as Map<String, dynamic>;
      final currentBalance = userData['balance'] ?? 0;

      if (currentBalance < amount) {
        throw Exception("Saldo insuficiente");
      }

      // 💰 desconta saldo
      transaction.update(userRef, {
        'balance': currentBalance - amount,
      });

      // ✅ aprova saque
      transaction.update(withdrawalRef, {
        'status': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
        'approvedBy': FirebaseAuth.instance.currentUser?.uid,
      });
    });
  }

  Future<void> reject(String id) async {
    await FirebaseFirestore.instance
        .collection('withdrawals')
        .doc(id)
        .update({
      'status': 'rejected',
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Admin - Saques")),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('withdrawals')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("Nenhum saque"));
          }

          final withdrawals = snapshot.data!.docs;

          return ListView.builder(
            itemCount: withdrawals.length,
            itemBuilder: (context, index) {
              final doc = withdrawals[index];
              final data = doc.data() as Map<String, dynamic>;

              final amount = data['amount'] ?? 0;
              final pixKey = data['pixKey'] ?? '';
              final status = data['status'] ?? '';
              final userId = data['userId'] ?? '';

              return FutureBuilder<Map<String, dynamic>?>(
                future: getUser(userId),
                builder: (context, userSnapshot) {
                  String name = 'Carregando...';
                  String email = '';

                  if (userSnapshot.hasData && userSnapshot.data != null) {
                    final user = userSnapshot.data!;
                    name = user['name'] ?? '';
                    email = user['email'] ?? '';
                  }

                  return Card(
                    margin: const EdgeInsets.all(10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "R\$ $amount",
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text("Nome: $name"),
                          Text("Email: $email"),
                          Text("Pix: $pixKey"),
                          Text("Status: $status"),
                          const SizedBox(height: 10),

                          if (status == 'pending')
                            Row(
                              children: [
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                  ),
                                  onPressed: () async {
                                    await approve(doc.id, data);

                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      const SnackBar(
                                        content: Text("Saque aprovado"),
                                      ),
                                    );
                                  },
                                  child: const Text("Aprovar"),
                                ),
                                const SizedBox(width: 10),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                  ),
                                  onPressed: () async {
                                    await reject(doc.id);

                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      const SnackBar(
                                        content: Text("Saque rejeitado"),
                                      ),
                                    );
                                  },
                                  child: const Text("Rejeitar"),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}-