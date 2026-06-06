import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/widgets/web_frame.dart';

class AdminUsersPage extends StatelessWidget {
  const AdminUsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gerenciar Usuários'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Acessos'),
              Tab(text: 'Banimentos'),
              Tab(text: 'Verificados'),
              Tab(text: 'Manutenção'),
            ],
          ),
        ),
        body: WebFrame(
          maxWidth: 900,
          child: const TabBarView(
            children: [
              _AccessTab(),
              _BanTab(),
              _VerifiedTab(),
              _MaintenanceTab(),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Aba Acessos ───────────────────────────────────────────────────────────────

class _AccessTab extends StatefulWidget {
  const _AccessTab();

  @override
  State<_AccessTab> createState() => _AccessTabState();
}

class _AccessTabState extends State<_AccessTab> {
  final _emailCtrl = TextEditingController();

  Future<void> _addModerator() async {
    final email = _emailCtrl.text.trim();
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

    await FirebaseFirestore.instance
        .collection('admins')
        .doc(query.docs.first.id)
        .set({'role': 'moderator'}, SetOptions(merge: true));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Moderador adicionado')),
    );
    _emailCtrl.clear();
  }

  Future<void> _removeAdmin(String uid) async {
    await FirebaseFirestore.instance.collection('admins').doc(uid).delete();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Removido')));
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
                keyboardType: TextInputType.emailAddress,
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
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream:
                FirebaseFirestore.instance.collection('admins').snapshots(),
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
                  final adminData = doc.data() as Map<String, dynamic>;
                  final role = adminData['role'] as String? ?? 'super';
                  // Look up the full user profile for name + email
                  return FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('users')
                        .doc(doc.id)
                        .get(),
                    builder: (context, userSnap) {
                      final userData =
                          userSnap.data?.data() as Map<String, dynamic>?;
                      final name =
                          (userData?['name'] as String? ?? '').trim();
                      final email = (userData?['email'] as String? ??
                              adminData['email'] as String? ??
                              '')
                          .trim();
                      final display =
                          name.isNotEmpty ? name : email;
                      final initial = display.isNotEmpty
                          ? display[0].toUpperCase()
                          : '?';

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              Colors.orange.withValues(alpha: 0.15),
                          child: Text(
                            initial,
                            style:
                                const TextStyle(color: Colors.orange),
                          ),
                        ),
                        title: Text(
                          display.isNotEmpty ? display : doc.id,
                          style: const TextStyle(
                              fontWeight: FontWeight.w500),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (name.isNotEmpty && email.isNotEmpty)
                              Text(
                                email,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black45),
                              ),
                            _RoleChip(role: role),
                          ],
                        ),
                        isThreeLine:
                            name.isNotEmpty && email.isNotEmpty,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (role != 'admin' && role != 'super')
                              IconButton(
                                icon: const Icon(Icons.upgrade,
                                    color: Colors.orange),
                                tooltip: 'Promover a admin',
                                onPressed: () => _makeAdmin(doc.id),
                              ),
                            IconButton(
                              icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red),
                              tooltip: 'Remover acesso',
                              onPressed: () => _removeAdmin(doc.id),
                            ),
                          ],
                        ),
                      );
                    },
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

class _RoleChip extends StatelessWidget {
  final String role;
  const _RoleChip({required this.role});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (role) {
      'super' => ('Super Admin', Colors.deepPurple),
      'admin' => ('Admin', Colors.orange),
      'moderator' => ('Moderador', Colors.blue),
      _ => (role, Colors.grey),
    };
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
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
                keyboardType: TextInputType.emailAddress,
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
        const Divider(height: 1),
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
                return const Center(
                    child: Text('Nenhum usuário banido'));
              }
              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final data = doc.data() as Map<String, dynamic>;
                  final name =
                      (data['name'] as String? ?? '').trim();
                  final email =
                      (data['email'] as String? ?? '').trim();
                  return ListTile(
                    leading: const Icon(Icons.block, color: Colors.red),
                    title:
                        Text(name.isNotEmpty ? name : email),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (name.isNotEmpty && email.isNotEmpty)
                          Text(email,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black45)),
                        if ((data['banReason'] as String? ?? '')
                            .isNotEmpty)
                          Text(data['banReason'] as String,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54)),
                      ],
                    ),
                    isThreeLine: name.isNotEmpty,
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

// ── Aba Verificados ───────────────────────────────────────────────────────────

class _VerifiedTab extends StatefulWidget {
  const _VerifiedTab();

  @override
  State<_VerifiedTab> createState() => _VerifiedTabState();
}

class _VerifiedTabState extends State<_VerifiedTab> {
  final _searchCtrl = TextEditingController();
  Map<String, dynamic>? _foundUser;
  String? _foundUserId;
  bool _searching = false;
  bool _toggling = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return;
    setState(() {
      _searching = true;
      _foundUser = null;
      _foundUserId = null;
    });

    try {
      QuerySnapshot? snap;

      // Try by username first (strip leading @)
      final username = query.startsWith('@') ? query.substring(1) : query;
      snap = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      // Fallback: try by email
      if (snap.docs.isEmpty) {
        snap = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: query)
            .limit(1)
            .get();
      }

      if (!mounted) return;
      if (snap.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usuário não encontrado')),
        );
      } else {
        setState(() {
          _foundUserId = snap!.docs.first.id;
          _foundUser = snap.docs.first.data() as Map<String, dynamic>;
        });
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _toggle(bool setVerified) async {
    if (_foundUserId == null) return;
    setState(() => _toggling = true);
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('setUserVerified')
          .call({'userId': _foundUserId, 'isVerified': setVerified});
      if (!mounted) return;
      setState(() {
        _foundUser = {
          ..._foundUser!,
          'isVerified': setVerified,
        };
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(setVerified
              ? 'Badge verificado concedido ✅'
              : 'Badge verificado removido'),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Search ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  labelText: 'Buscar por @username ou email',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                ),
                onSubmitted: (_) => _search(),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: _searching ? null : _search,
                icon: _searching
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(_searching ? 'Buscando...' : 'Buscar'),
              ),

              // ── Result card ───────────────────────────────────────────────
              if (_foundUser != null) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundImage:
                              (_foundUser!['photoUrl'] as String? ?? '').isNotEmpty
                                  ? NetworkImage(
                                      _foundUser!['photoUrl'] as String)
                                  : null,
                          child: (_foundUser!['photoUrl'] as String? ?? '').isEmpty
                              ? const Icon(Icons.person)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    _foundUser!['name'] as String? ?? '',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  if (_foundUser!['isVerified'] == true) ...[
                                    const SizedBox(width: 4),
                                    const Icon(Icons.verified,
                                        color: Colors.blue, size: 16),
                                  ],
                                ],
                              ),
                              if ((_foundUser!['username'] as String? ?? '')
                                  .isNotEmpty)
                                Text(
                                  '@${_foundUser!['username']}',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.black54),
                                ),
                            ],
                          ),
                        ),
                        _toggling
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : _foundUser!['isVerified'] == true
                                ? OutlinedButton.icon(
                                    onPressed: () => _toggle(false),
                                    icon: const Icon(Icons.verified_outlined,
                                        color: Colors.red),
                                    label: const Text('Remover',
                                        style:
                                            TextStyle(color: Colors.red)),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                          color: Colors.red),
                                    ),
                                  )
                                : FilledButton.icon(
                                    onPressed: () => _toggle(true),
                                    icon: const Icon(Icons.verified),
                                    label: const Text('Verificar'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                    ),
                                  ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        const Divider(height: 1),

        // ── List of currently verified users ──────────────────────────────
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            children: [
              Icon(Icons.verified, color: Colors.blue, size: 16),
              SizedBox(width: 6),
              Text(
                'Usuários verificados',
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: Colors.black54),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('isVerified', isEqualTo: true)
                .limit(100)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return const Center(
                    child: Text('Nenhum usuário verificado'));
              }
              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final d = doc.data() as Map<String, dynamic>;
                  final name = d['name'] as String? ?? '';
                  final username = d['username'] as String? ?? '';
                  final photoUrl = d['photoUrl'] as String? ?? '';
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundImage: photoUrl.isNotEmpty
                          ? NetworkImage(photoUrl)
                          : null,
                      child: photoUrl.isEmpty
                          ? const Icon(Icons.person, size: 18)
                          : null,
                    ),
                    title: Row(
                      children: [
                        Text(name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w500)),
                        const SizedBox(width: 4),
                        const Icon(Icons.verified,
                            color: Colors.blue, size: 14),
                      ],
                    ),
                    subtitle: username.isNotEmpty
                        ? Text('@$username',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black45))
                        : null,
                    trailing: TextButton(
                      onPressed: () async {
                        await FirebaseFunctions.instanceFor(
                                region: 'us-central1')
                            .httpsCallable('setUserVerified')
                            .call({
                          'userId': doc.id,
                          'isVerified': false,
                        });
                      },
                      child: const Text('Remover',
                          style: TextStyle(color: Colors.red)),
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

// ── Aba Manutenção ────────────────────────────────────────────────────────────

class _MaintenanceTab extends StatefulWidget {
  const _MaintenanceTab();

  @override
  State<_MaintenanceTab> createState() => _MaintenanceTabState();
}

class _MaintenanceTabState extends State<_MaintenanceTab> {
  bool _running = false;
  String? _result;

  Future<void> _migrateUsers() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Migrar usuários'),
        content: const Text(
          'Percorre todos os usuários do Firebase Auth e cria ou corrige documentos no Firestore que estejam incompletos ou ausentes.\n\nNão altera saldos existentes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Executar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _running = true;
      _result = null;
    });

    try {
      final res = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('adminMigrateUsers',
              options: HttpsCallableOptions(
                  timeout: const Duration(minutes: 5)))
          .call();
      final count = (res.data as Map)['migrated'] ?? 0;
      if (mounted) {
        setState(
            () => _result = 'Concluído: $count perfis criados/corrigidos.');
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() => _result = 'Erro: ${e.message}');
    } catch (e) {
      if (mounted) setState(() => _result = 'Erro: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ferramentas de manutenção',
            style:
                TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Operações que afetam todos os usuários. Use com cuidado.',
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.build_circle_outlined,
                          color: Colors.orange),
                      SizedBox(width: 8),
                      Text(
                        'Corrigir perfis em limbo',
                        style:
                            TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Cria documentos Firestore faltantes e preenche campos ausentes com valores padrão. Não altera saldos existentes.',
                    style: TextStyle(
                        fontSize: 13, color: Colors.black54),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _running ? null : _migrateUsers,
                      icon: _running
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_fix_high),
                      label: Text(_running
                          ? 'Executando...'
                          : 'Migrar usuários'),
                    ),
                  ),
                  if (_result != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          _result!.startsWith('Erro')
                              ? Icons.error_outline
                              : Icons.check_circle_outline,
                          size: 16,
                          color: _result!.startsWith('Erro')
                              ? Colors.red
                              : Colors.green.shade700,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _result!,
                            style: TextStyle(
                              color: _result!.startsWith('Erro')
                                  ? Colors.red
                                  : Colors.green.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
