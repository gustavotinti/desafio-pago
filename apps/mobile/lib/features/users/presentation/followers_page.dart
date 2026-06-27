import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/widgets/safe_avatar.dart';
import '../../../core/widgets/web_frame.dart';
import 'user_profile_page.dart';

enum FollowType { followers, following }

class FollowersPage extends StatelessWidget {
  final String userId;
  final FollowType type;

  const FollowersPage({
    super.key,
    required this.userId,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    final isFollowers = type == FollowType.followers;
    final filterField = isFollowers ? 'followedId' : 'followerId';
    final returnField = isFollowers ? 'followerId' : 'followedId';

    return Scaffold(
      appBar: AppBar(
        title: Text(isFollowers ? 'Seguidores' : 'Seguindo'),
      ),
      body: WebFrame(
        child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('follows')
            .where(filterField, isEqualTo: userId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return Center(
              child: Text(
                isFollowers
                    ? 'Sem seguidores ainda'
                    : 'Não está seguindo ninguém',
                style: const TextStyle(color: Colors.black54),
              ),
            );
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final uid = data[returnField] as String;

              return FutureBuilder<DocumentSnapshot>(
                // Lê do espelho público (sem PII) — funciona p/ qualquer usuário.
                future: FirebaseFirestore.instance
                    .collection('publicProfiles')
                    .doc(uid)
                    .get(),
                builder: (context, userSnap) {
                  if (!userSnap.hasData) {
                    return const ListTile(
                      leading: CircleAvatar(child: Icon(Icons.person)),
                      title: Text('...'),
                    );
                  }

                  final userData =
                      userSnap.data!.data() as Map<String, dynamic>? ?? {};
                  final name = userData['name'] as String? ?? 'Usuário';
                  final photoUrl = userData['photoUrl'] as String? ?? '';
                  final totalVotes = userData['totalVotesReceived'] ?? 0;

                  return ListTile(
                    leading: SafeAvatar(photoUrl: photoUrl, radius: 20),
                    title: Text(name),
                    subtitle: Text('$totalVotes votos'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UserProfilePage(userId: uid),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
        ),
      ),
    );
  }
}
