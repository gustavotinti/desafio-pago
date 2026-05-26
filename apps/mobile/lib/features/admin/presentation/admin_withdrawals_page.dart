import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminWithdrawalsPage extends StatelessWidget {
  const AdminWithdrawalsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin — Saques'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Pendentes'),
              Tab(text: 'Aprovados'),
              Tab(text: 'Pagos'),
              Tab(text: 'Rejeitados'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _WithdrawalList(status: 'pending'),
            _WithdrawalList(status: 'approved'),
            _WithdrawalList(status: 'paid'),
            _WithdrawalList(status: 'rejected'),
          ],
        ),
      ),
    );
  }
}

class _WithdrawalList extends StatelessWidget {
  final String status;
  const _WithdrawalList({required this.status});

  Future<Map<String, dynamic>?> _getUser(String userId) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();
    return doc.exists ? doc.data() : null;
  }

  Future<void> _approve(
      BuildContext context, String id, Map<String, dynamic> data) async {
    final firestore = FirebaseFirestore.instance;
    final userId = data['userId'] as String;
    final amount = (data['amount'] ?? 0).toDouble();
    try {
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
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Saque aprovado')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _reject(
      BuildContext context, String id, Map<String, dynamic> data) async {
    final firestore = FirebaseFirestore.instance;
    final userId = data['userId'] as String;
    final amount = (data['amount'] ?? 0).toDouble();
    try {
      await firestore.runTransaction((tx) async {
        tx.update(firestore.collection('users').doc(userId), {
          'balance': FieldValue.increment(amount),
          'lockedBalance': FieldValue.increment(-amount),
        });
        tx.update(
            firestore.collection('withdrawals').doc(id), {'status': 'rejected'});
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Saque rejeitado')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _markPaid(BuildContext context, String id) async {
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('adminMarkWithdrawalPaid')
          .call({'withdrawalId': id});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pix confirmado como pago!')),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message ?? 'Erro')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('withdrawals')
          .where('status', isEqualTo: status)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('Nenhum saque'));
        }

        final docs = snapshot.data!.docs;

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final amount = data['amount'] ?? 0;
            final fee = data['fee'] ?? 0;
            final netAmount = data['netAmount'] ?? amount;
            final pixKey = data['pixKey'] ?? '';
            final userId = data['userId'] ?? '';

            return FutureBuilder<Map<String, dynamic>?>(
              future: _getUser(userId),
              builder: (context, userSnap) {
                final user = userSnap.data;
                final name = user?['name'] ?? (userSnap.hasData ? '—' : '...');
                final email = user?['email'] ?? '';

                return Card(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'R\$ ${netAmount.toStringAsFixed != null ? netAmount.toStringAsFixed(2) : netAmount}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            _StatusChip(status: status),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                            'Bruto: R\$ $amount  ·  Taxa: R\$ $fee',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54)),
                        const SizedBox(height: 6),
                        Text('Nome: $name'),
                        Text('Email: $email',
                            style:
                                const TextStyle(color: Colors.black54, fontSize: 13)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.pix, size: 16, color: Colors.teal),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                pixKey,
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (status == 'pending')
                          Row(
                            children: [
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () =>
                                    _approve(context, doc.id, data),
                                child: const Text('Aprovar'),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red),
                                onPressed: () =>
                                    _reject(context, doc.id, data),
                                child: const Text('Rejeitar'),
                              ),
                            ],
                          ),
                        if (status == 'approved')
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _markPaid(context, doc.id),
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Confirmar Pix pago'),
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
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'pending' => ('Pendente', Colors.orange),
      'approved' => ('Aprovado', Colors.blue),
      'paid' => ('Pago', Colors.green),
      'rejected' => ('Rejeitado', Colors.red),
      _ => (status, Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
