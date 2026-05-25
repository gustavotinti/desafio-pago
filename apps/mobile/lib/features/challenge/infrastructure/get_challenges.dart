import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/entities/challenge.dart';
import '../domain/entities/challenge_status.dart';

class GetChallenges {
  final _firestore = FirebaseFirestore.instance;

  Future<List<Challenge>> call() async {
    final snapshot = await _firestore
        .collection('challenges')
        .orderBy('voteCount', descending: true)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return Challenge(
        id: doc.id,
        title: data['title'] ?? '',
        description: data['description'] ?? '',
        createdBy: data['createdBy'] ?? '',
        amount: (data['amount'] as num).toDouble(),
        status: ChallengeStatus.values.firstWhere(
          (s) => s.name == (data['status'] ?? ''),
          orElse: () => ChallengeStatus.active,
        ),
        voteCount: data['voteCount'] ?? 0,
        entryCount: data['entryCount'] ?? 0,
        winnerIds: List<String>.from(data['winnerIds'] ?? []),
        createdAt: DateTime.parse(data['createdAt']),
        expiresAt: DateTime.parse(data['expiresAt']),
      );
    }).toList();
  }
}
