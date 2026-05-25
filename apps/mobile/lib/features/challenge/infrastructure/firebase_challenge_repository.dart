import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/entities/challenge.dart';

class FirebaseChallengeRepository {
  static const int _dailyLimit = 20;

  final _firestore = FirebaseFirestore.instance;

  Future<void> createChallenge(Challenge challenge) async {
    await _checkDailyLimit(challenge.createdBy);

    await _firestore.collection('challenges').doc(challenge.id).set({
      'title': challenge.title,
      'description': challenge.description,
      'createdBy': challenge.createdBy,
      'amount': challenge.amount,
      'status': challenge.status.name,
      'voteCount': 0,
      'entryCount': 0,
      'winnerIds': [],
      'createdAt': challenge.createdAt.toIso8601String(),
      'expiresAt': challenge.expiresAt.toIso8601String(),
    });
  }

  Future<void> _checkDailyLimit(String userId) async {
    final now = DateTime.now();
    final startOfDay =
        DateTime(now.year, now.month, now.day).toIso8601String();

    final snapshot = await _firestore
        .collection('challenges')
        .where('createdBy', isEqualTo: userId)
        .where('createdAt', isGreaterThanOrEqualTo: startOfDay)
        .get();

    if (snapshot.docs.length >= _dailyLimit) {
      throw Exception('Limite de $_dailyLimit desafios por dia atingido');
    }
  }
}