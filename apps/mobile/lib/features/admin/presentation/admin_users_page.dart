import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class AdminUsersPage extends StatelessWidget {
  const AdminUsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gerenciar Usuários'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Acessos'),
              Tab(text: 'Banimentos'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _AccessTab(),
            _BanTab(),
          ],
        ),
      ),
    );
  }
}

// ── Aba Acessos (admins/moderadores) ─────────────────────────────────────────

class _AccessTab extends StatefulWidget {
  const _AccessTab();

  @override
  State<_AccessTab> createState() => _AccessTabState();
}

class _AccessTabState extends State<_AccessTab> {
  final _emailCtrl = TextEditingController();

  Future<void> _addModerator() async {
    final email = _emailCtrl.text.trim();
    final query = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: email)
        .get();

    if (!mounted) return;
    if (query.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usuário não encontrado')),
      );
      return;
    }

    await FirebaseFirestore.instance
        .collection('admins')
        .doc(query.docs.first.id)
        .set({'role': 'moderator'});

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Moderador adicionado')),
    );
    _emailCtrl.clear();
  }

  Future<void> _removeAdmin(String uid) async {
    await FirebaseFirestore.instance.collection('admins').doc(uid).delete();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Removido')),
    );
  }

  Future<void> _makeAdmin(String uid) async {
    await FirebaseFirestore.instance
        .collection('admins')
        .doc(uid)
        .update({'role': 'admin'});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              TextField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email do usuário',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _addModerator,
                child: const Text('Adicionar moderador'),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('admins').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return const Center(child: Text('Nenhum admin'));
              }
              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final role = (doc.data() as Map<String, dynamic>)['role'];
                  return ListTile(
                    title: Text(doc.id),
                    subtitle: Text('Role: $role'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (role != 'admin')
                          IconButton(
                            icon: const Icon(Icons.upgrade),
                            onPressed: () => _makeAdmin(doc.id),
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _removeAdmin(doc.id),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Aba Banimentos ────────────────────────────────────────────────────────────

class _BanTab extends StatefulWidget {
  const _BanTab();

  @override
  State<_BanTab> createState() => _BanTabState();
}

class _BanTabState extends State<_BanTab> {
  final _emailCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  Future<void> _banUser() async {
    final email = _emailCtrl.text.trim();
    final reason = _reasonCtrl.text.trim();

    if (email.isEmpty) return;

    final query = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: email)
        .get();

    if (!mounted) return;
    if (query.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usuário não encontrado')),
      );
      return;
    }

    try {
      await FirebaseFunctions.instance.httpsCallable('adminBanUser').call({
        'userId': query.docs.first.id,
        'reason': reason.isNotEmpty ? reason : null,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usuário banido')),
      );
      _emailCtrl.clear();
      _reasonCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _unbanUser(String userId) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('adminBanUser')
          .call({'userId': userId, 'unban': true});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Banimento removido')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              TextField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email do usuário',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Motivo (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: _banUser,
                icon: const Icon(Icons.block),
                label: const Text('Banir usuário'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('isBanned', isEqualTo: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return const Center(child: Text('Nenhum usuário banido'));
              }
              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final data = doc.data() as Map<String, dynamic>;
                  return ListTile(
                    leading: const Icon(Icons.block, color: Colors.red),
                    title: Text(data['email'] ?? doc.id),
                    subtitle: Text(data['banReason'] ?? ''),
                    trailing: TextButton(
                      onPressed: () => _unbanUser(doc.id),
                      child: const Text('Desbanir'),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
