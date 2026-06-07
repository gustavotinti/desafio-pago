import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/entities/challenge.dart';
import '../domain/entities/challenge_status.dart';

enum ChallengeSortBy { amount, voteCount, newest }

class GetChallenges {
  final _firestore = FirebaseFirestore.instance;

  Future<List<Challenge>> call({
    ChallengeStatus? status,
    ChallengeSortBy sortBy = ChallengeSortBy.amount,
  }) async {
    Query<Map<String, dynamic>> query =
        _firestore.collection('challenges');

    if (status != null) {
      query = query.where('status', isEqualTo: status.name);
    }

    switch (sortBy) {
      case ChallengeSortBy.amount:
        query = query.orderBy('amount', descending: true);
      case ChallengeSortBy.voteCount:
        query = query.orderBy('voteCount', descending: true);
      case ChallengeSortBy.newest:
        query = query.orderBy('createdAt', descending: true);
    }

    final snapshot = await query.get();

    return snapshot.docs.map((doc) => _map(doc.id, doc.data())).toList();
  }

  /// Carrega um desafio pelo id (usado pelo deep link de compartilhamento).
  Future<Challenge?> getById(String id) async {
    final doc = await _firestore.collection('challenges').doc(id).get();
    if (!doc.exists) return null;
    return _map(doc.id, doc.data()!);
  }

  Challenge _map(String id, Map<String, dynamic> data) {
    return Challenge(
      id: id,
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
  }
}
