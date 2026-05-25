import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/entities/challenge.dart';

class FirebaseChallengeRepository {
  final _firestore = FirebaseFirestore.instance;

  Future<void> createChallenge(Challenge challenge) async {
    await _firestore.collection('challenges').doc(challenge.id).set({
  'title': challenge.title,
  'description': challenge.description,
  'createdBy': challenge.createdBy,
  'amount': challenge.amount,
  'createdAt': challenge.createdAt.toIso8601String(),
  'expiresAt': challenge.expiresAt.toIso8601String(),
  'voteCount': 0,
});
  }
}