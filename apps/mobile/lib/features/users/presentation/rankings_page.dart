import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/format.dart';
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
            child: Image.asset('assets/images/2.png', fit: BoxFit.contain),
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
              _RankingTab(orderBy: 'totalEarned', isEarnings: true),
              _RankingTab(orderBy: 'totalVotesReceived', isEarnings: false),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Medal config ──────────────────────────────────────────────────────────────

const _medals = [
  (color: Color(0xFFFFD700), bg: Color(0xFFFFFBE6), label: '🥇'),
  (color: Color(0xFFB0BEC5), bg: Color(0xFFF5F7FA), label: '🥈'),
  (color: Color(0xFFCD7F32), bg: Color(0xFFFFF3E0), label: '🥉'),
];

// ── Tab ───────────────────────────────────────────────────────────────────────

class _RankingTab extends StatelessWidget {
  final String orderBy;
  final bool isEarnings;

  const _RankingTab({required this.orderBy, required this.isEarnings});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('publicProfiles')
          .orderBy(orderBy, descending: true)
          .limit(200)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.leaderboard_outlined,
                    size: 48, color: Colors.black26),
                SizedBox(height: 12),
                Text('Nenhum dado ainda',
                    style: TextStyle(color: Colors.black45)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final name = data['name'] as String? ?? 'Usuário';
            final username = data['username'] as String? ?? '';
            final photoUrl = data['photoUrl'] as String? ?? '';
            final isVerified = data['isVerified'] == true;
            final rawValue = (data[orderBy] as num? ?? 0);
            final displayValue = isEarnings
                ? Fmt.brl(rawValue)
                : '${Fmt.number(rawValue)} votos';

            if (index < 3) {
              return _PodiumTile(
                index: index,
                docId: doc.id,
                name: name,
                username: username,
                photoUrl: photoUrl,
                isVerified: isVerified,
                displayValue: displayValue,
              );
            }

            return _RegularTile(
              index: index,
              docId: doc.id,
              name: name,
              username: username,
              photoUrl: photoUrl,
              isVerified: isVerified,
              displayValue: displayValue,
            );
          },
        );
      },
    );
  }
}

// ── Podium tile (top 3) ───────────────────────────────────────────────────────

class _PodiumTile extends StatelessWidget {
  final int index;
  final String docId;
  final String name;
  final String username;
  final String photoUrl;
  final bool isVerified;
  final String displayValue;

  const _PodiumTile({
    required this.index,
    required this.docId,
    required this.name,
    required this.username,
    required this.photoUrl,
    required this.isVerified,
    required this.displayValue,
  });

  @override
  Widget build(BuildContext context) {
    final medal = _medals[index];

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => UserProfilePage(userId: docId)),
      ),
      child: Container(
        margin: EdgeInsets.fromLTRB(12, index == 0 ? 12 : 4, 12, 4),
        decoration: BoxDecoration(
          color: medal.bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: medal.color.withValues(alpha: 0.35),
          ),
          boxShadow: [
            BoxShadow(
              color: medal.color.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // ── Medal + avatar ───────────────────────────────────────
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: index == 0 ? 28 : 24,
                    backgroundImage:
                        photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                    backgroundColor: medal.color.withValues(alpha: 0.2),
                    child: photoUrl.isEmpty
                        ? Icon(Icons.person,
                            size: index == 0 ? 28 : 24,
                            color: medal.color)
                        : null,
                  ),
                  Positioned(
                    bottom: -4,
                    right: -4,
                    child: Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: medal.color.withValues(alpha: 0.4)),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 4)
                        ],
                      ),
                      child: Text(
                        medal.label,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),

              // ── Name + username ──────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: index == 0 ? 16 : 15,
                              color: const Color(0xFF1A1A2E),
                            ),
                          ),
                        ),
                        if (isVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified,
                              color: Colors.blue, size: 15),
                        ],
                      ],
                    ),
                    if (username.isNotEmpty)
                      Text(
                        '@$username',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black45),
                      ),
                  ],
                ),
              ),

              // ── Value ────────────────────────────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${index + 1}°',
                    style: TextStyle(
                      fontSize: 11,
                      color: medal.color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    displayValue,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: index == 0 ? 14 : 13,
                      color: const Color(0xFF1A1A2E),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Regular tile (#4+) ────────────────────────────────────────────────────────

class _RegularTile extends StatelessWidget {
  final int index;
  final String docId;
  final String name;
  final String username;
  final String photoUrl;
  final bool isVerified;
  final String displayValue;

  const _RegularTile({
    required this.index,
    required this.docId,
    required this.name,
    required this.username,
    required this.photoUrl,
    required this.isVerified,
    required this.displayValue,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => UserProfilePage(userId: docId)),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '${index + 1}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Colors.black45,
              ),
            ),
          ),
          const SizedBox(width: 10),
          CircleAvatar(
            radius: 18,
            backgroundImage:
                photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
            backgroundColor: const Color(0xFFF0F1F8),
            child: photoUrl.isEmpty
                ? const Icon(Icons.person, size: 18, color: Colors.black38)
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
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
          if (isVerified) ...[
            const SizedBox(width: 4),
            const Icon(Icons.verified, color: Colors.blue, size: 14),
          ],
        ],
      ),
      subtitle: username.isNotEmpty
          ? Text('@$username',
              style:
                  const TextStyle(fontSize: 11, color: Colors.black45))
          : null,
      trailing: Text(
        displayValue,
        style: const TextStyle(
            fontWeight: FontWeight.bold, fontSize: 13,
            color: Color(0xFF1A1A2E)),
      ),
    );
  }
}
