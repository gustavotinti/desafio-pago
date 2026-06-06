import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/widgets/web_frame.dart';
import 'user_profile_page.dart';

class RankingsPage extends StatelessWidget {
  const RankingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: SizedBox(
            height: 52,
            width: 220,
            child: Image.asset(
              'assets/images/2.png',
              fit: BoxFit.contain,
            ),
          ),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Maiores ganhos'),
              Tab(text: 'Mais votados'),
            ],
          ),
        ),
        body: WebFrame(
          child: TabBarView(
            children: const [
              _RankingTab(orderBy: 'totalEarned', label: 'R\$'),
              _RankingTab(orderBy: 'totalVotesReceived', label: 'votos'),
            ],
          ),
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
          .limit(200)
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
            final name = data['name'] as String? ?? 'Usuário';
            final username = data['username'] as String? ?? '';
            final photoUrl = data['photoUrl'] as String? ?? '';
            final isVerified = data['isVerified'] == true;
            final value = (data[orderBy] ?? 0);
            final displayValue = orderBy == 'totalEarned'
                ? 'R\$ ${(value as num).toStringAsFixed(2)}'
                : '$value $label';

            // Medal colour for top 3
            Color? positionColor;
            if (index == 0) positionColor = const Color(0xFFFFD700); // gold
            if (index == 1) positionColor = const Color(0xFFB0BEC5); // silver
            if (index == 2) positionColor = const Color(0xFFBF8C60); // bronze

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
                        fontSize: index < 3 ? 16 : 14,
                        color: positionColor,
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
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (isVerified) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.verified,
                        color: Colors.blue, size: 14),
                  ],
                ],
              ),
              subtitle: username.isNotEmpty
                  ? Text('@$username',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54))
                  : null,
              trailing: Text(
                displayValue,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13),
              ),
            );
          },
        );
      },
    );
  }
}
