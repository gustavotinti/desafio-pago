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

  Future<void> approve(String id, Map<String, dynamic> data) async {
    final firestore = FirebaseFirestore.instance;
    final userId = data['userId'] as String;
    final amount = (data['amount'] ?? 0).toDouble();

    await firestore.runTransaction((tx) async {
      tx.update(firestore.collection('withdrawals').doc(id), {
        'status': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
        'approvedBy': FirebaseAuth.instance.currentUser?.uid,
      });
      tx.update(firestore.collection('users').doc(userId), {
        'lockedBalance': FieldValue.increment(-amount),
      });
    });
  }

  Future<void> reject(String id, Map<String, dynamic> data) async {
    final firestore = FirebaseFirestore.instance;
    final userId = data['userId'] as String;
    final amount = (data['amount'] ?? 0).toDouble();

    await firestore.runTransaction((tx) async {
      tx.update(firestore.collection('users').doc(userId), {
        'balance': FieldValue.increment(amount),
        'lockedBalance': FieldValue.increment(-amount),
      });
      tx.update(
          firestore.collection('withdrawals').doc(id), {'status': 'rejected'});
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
              final fee = data['fee'] ?? 0;
              final netAmount = data['netAmount'] ?? amount;
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
                            "A pagar: R\$ $netAmount",
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text("Bruto: R\$ $amount  |  Taxa: R\$ $fee"),
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
                                    await reject(doc.id, data);

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
}