import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/widgets/web_frame.dart';
import '../../verification/infrastructure/verification_repository.dart';

class AdminVerificationPage extends StatelessWidget {
  const AdminVerificationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin — Verificação'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Pendentes'),
              Tab(text: 'Aprovados'),
              Tab(text: 'Recusados'),
            ],
          ),
        ),
        body: const WebFrame(
          maxWidth: 900,
          child: TabBarView(
            children: [
              _RequestList(status: 'pending'),
              _RequestList(status: 'approved'),
              _RequestList(status: 'rejected'),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestList extends StatelessWidget {
  final String status;
  const _RequestList({required this.status});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('verificationRequests')
          .where('status', isEqualTo: status)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('Nenhum pedido'));
        }

        // Ordena: pagos (prioritários) primeiro, depois mais antigos primeiro.
        final list = docs.toList()
          ..sort((a, b) {
            final da = a.data() as Map<String, dynamic>;
            final db = b.data() as Map<String, dynamic>;
            final pa = da['priority'] == true ? 0 : 1;
            final pb = db['priority'] == true ? 0 : 1;
            if (pa != pb) return pa.compareTo(pb);
            final ca = (da['createdAt'] ?? '') as String;
            final cb = (db['createdAt'] ?? '') as String;
            return ca.compareTo(cb);
          });

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: list.length,
          itemBuilder: (_, i) => _RequestCard(
            id: list[i].id,
            data: list[i].data() as Map<String, dynamic>,
            status: status,
          ),
        );
      },
    );
  }
}

class _RequestCard extends StatefulWidget {
  final String id;
  final Map<String, dynamic> data;
  final String status;

  const _RequestCard({
    required this.id,
    required this.data,
    required this.status,
  });

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _busy = false;

  String _fmtCpf(String cpf) {
    if (cpf.length != 11) return cpf;
    return '${cpf.substring(0, 3)}.${cpf.substring(3, 6)}.'
        '${cpf.substring(6, 9)}-${cpf.substring(9)}';
  }

  String _fmtPhone(String p) {
    if (p.length == 11) {
      return '(${p.substring(0, 2)}) ${p.substring(2, 7)}-${p.substring(7)}';
    }
    if (p.length == 10) {
      return '(${p.substring(0, 2)}) ${p.substring(2, 6)}-${p.substring(6)}';
    }
    return p;
  }

  Future<void> _decide(bool approved) async {
    setState(() => _busy = true);
    try {
      await VerificationRepository().decide(widget.id, approved);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(approved ? 'Pedido aprovado' : 'Pedido recusado'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final first = d['firstName'] ?? '';
    final last = d['lastName'] ?? '';
    final username = d['username'] ?? '';
    final photoUrl = d['photoUrl'] as String? ?? '';
    final cpf = d['cpf'] as String? ?? '';
    final phone = d['phone'] as String? ?? '';
    final priority = d['priority'] == true;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundImage:
                      photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                  child: photoUrl.isEmpty ? const Icon(Icons.person) : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$first $last',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      if (username != '')
                        Text('@$username',
                            style: const TextStyle(
                                color: Colors.black54, fontSize: 13)),
                    ],
                  ),
                ),
                if (priority)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.amber.shade400),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt, size: 14, color: Color(0xFFB8860B)),
                        SizedBox(width: 2),
                        Text(
                          'PAGO • PRIORITÁRIO',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFB8860B)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const Divider(height: 20),
            _InfoLine(icon: Icons.badge_outlined, label: 'CPF', value: _fmtCpf(cpf)),
            const SizedBox(height: 4),
            _InfoLine(
                icon: Icons.phone_outlined,
                label: 'Telefone',
                value: _fmtPhone(phone)),
            if (widget.status == 'pending') ...[
              const SizedBox(height: 12),
              _busy
                  ? const Center(child: CircularProgressIndicator())
                  : Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _decide(true),
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('Aprovar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red),
                            onPressed: () => _decide(false),
                            icon: const Icon(Icons.close, size: 18),
                            label: const Text('Recusar'),
                          ),
                        ),
                      ],
                    ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoLine(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.black45),
        const SizedBox(width: 8),
        Text('$label: ',
            style: const TextStyle(fontSize: 13, color: Colors.black54)),
        SelectableText(value,
            style:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
