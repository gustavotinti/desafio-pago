import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  final emailController = TextEditingController();

  Future<void> addAdmin() async {
    final email = emailController.text.trim();

    final userQuery = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: email)
        .get();

    if (userQuery.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Usuário não encontrado")),
      );
      return;
    }

    final userDoc = userQuery.docs.first;

    await FirebaseFirestore.instance
        .collection('admins')
        .doc(userDoc.id)
        .set({
      'role': 'moderator',
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Moderador adicionado")),
    );

    emailController.clear();
  }

  Future<void> removeAdmin(String uid) async {
    await FirebaseFirestore.instance
        .collection('admins')
        .doc(uid)
        .delete();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Removido")),
    );
  }

  Future<void> makeAdmin(String uid) async {
    await FirebaseFirestore.instance
        .collection('admins')
        .doc(uid)
        .update({
      'role': 'admin',
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Gerenciar Acessos")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: "Email do usuário",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: addAdmin,
                  child: const Text("Adicionar moderador"),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('admins')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;

                if (docs.isEmpty) {
                  return const Center(child: Text("Nenhum admin"));
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;

                    final role = data['role'];

                    return ListTile(
                      title: Text(doc.id),
                      subtitle: Text("Role: $role"),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (role != 'admin')
                            IconButton(
                              icon: const Icon(Icons.upgrade),
                              onPressed: () => makeAdmin(doc.id),
                            ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => removeAdmin(doc.id),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          )
        ],
      ),
    );
  }
}