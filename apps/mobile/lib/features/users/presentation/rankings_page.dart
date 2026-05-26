import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'user_profile_page.dart';

class RankingsPage extends StatelessWidget {
  const RankingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Image.asset(
            'assets/images/logo_anim_h_dark.gif',
            height: 36,
            fit: BoxFit.contain,
          ),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Maiores ganhos'),
              Tab(text: 'Mais votados'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _RankingTab(orderBy: 'totalEarned', label: 'R\$'),
            _RankingTab(orderBy: 'totalVotesReceived', label: 'votos'),
          ],
        ),
      ),
    );
  }
}

class _RankingTab extends StatelessWidget {
  final String orderBy;
  final String label;

  const _RankingTab({required this.orderBy, required this.label});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .orderBy(orderBy, descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;

        if (docs.isEmpty) {
          return const Center(child: Text('Nenhum dado ainda'));
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final name = data['name'] ?? 'Usuário';
            final photoUrl = data['photoUrl'] as String? ?? '';
            final value = (data[orderBy] ?? 0);
            final displayValue = orderBy == 'totalEarned'
                ? 'R\$ ${(value as num).toStringAsFixed(2)}'
                : '$value $label';

            return ListTile(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      UserProfilePage(userId: docs[index].id),
                ),
              ),
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: index == 0
                            ? Colors.amber
                            : index == 1
                                ? Colors.grey
                                : index == 2
                                    ? Colors.brown
                                    : null,
                      ),
                    ),
                  ),
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: photoUrl.isNotEmpty
                        ? NetworkImage(photoUrl)
                        : null,
                    child: photoUrl.isEmpty
                        ? const Icon(Icons.person, size: 18)
                        : null,
                  ),
                ],
              ),
              title: Text(name),
              trailing: Text(
                displayValue,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            );
          },
        );
      },
    );
  }
}
