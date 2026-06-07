import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/widgets/web_frame.dart';
import 'admin_edit_virtual_user_page.dart';

class AdminVirtualUsersPage extends StatefulWidget {
  const AdminVirtualUsersPage({super.key});

  @override
  State<AdminVirtualUsersPage> createState() => _AdminVirtualUsersPageState();
}

class _AdminVirtualUsersPageState extends State<AdminVirtualUsersPage> {
  final _searchCtrl = TextEditingController();
  List<QueryDocumentSnapshot> _results = [];
  bool _searching = false;
  bool _searched = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final raw = _searchCtrl.text.trim().toLowerCase();
    final q = raw.startsWith('@') ? raw.substring(1) : raw;
    if (q.isEmpty) return;

    setState(() {
      _searching = true;
      _searched = true;
    });
    try {
      // Busca por prefixo de username (índice automático de campo único).
      // Usernames só têm [a-z0-9._] (todos < '~'), então '~' é o limite alto.
      final upper = '$q~';
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isGreaterThanOrEqualTo: q)
          .where('username', isLessThan: upper)
          .orderBy('username')
          .limit(30)
          .get();

      final virtual = snap.docs
          .where((d) =>
              (d.data() as Map<String, dynamic>)['isVirtual'] == true)
          .toList();

      if (mounted) setState(() => _results = virtual);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editar perfis virtuais')),
      body: WebFrame(
        maxWidth: 900,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Buscar por @username (início)',
                      hintText: 'ex: caio, neymar, biel...',
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
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: !_searched
                  ? const Center(
                      child: Text('Busque um perfil virtual para editar'))
                  : _results.isEmpty
                      ? const Center(
                          child: Text('Nenhum perfil virtual encontrado'))
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (_, i) {
                            final d =
                                _results[i].data() as Map<String, dynamic>;
                            final photo = d['photoUrl'] as String? ?? '';
                            final name = d['name'] as String? ?? '';
                            final username = d['username'] as String? ?? '';
                            final verified = d['isVerified'] == true;
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: photo.isNotEmpty
                                    ? NetworkImage(photo)
                                    : null,
                                child: photo.isEmpty
                                    ? const Icon(Icons.person)
                                    : null,
                              ),
                              title: Row(
                                children: [
                                  Flexible(child: Text(name)),
                                  if (verified) ...[
                                    const SizedBox(width: 4),
                                    const Icon(Icons.verified,
                                        color: Colors.blue, size: 15),
                                  ],
                                ],
                              ),
                              subtitle: Text('@$username'),
                              trailing: const Icon(Icons.edit_outlined),
                              onTap: () async {
                                final changed = await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AdminEditVirtualUserPage(
                                      userId: _results[i].id,
                                      data: d,
                                    ),
                                  ),
                                );
                                if (changed == true) _search();
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
