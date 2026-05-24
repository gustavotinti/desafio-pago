import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/entities/challenge.dart';
import '../domain/repositories/challenge_repository.dart';

class FirebaseChallengeRepository implements ChallengeRepository {
  final _firestore = FirebaseFirestore.instance;

  @override
  Future<void> createChallenge(Challenge challenge) async {
    await _firestore.collection('challenges').doc(challenge.id).set({
      'title': challenge.title,
      'description': challenge.description,
      'createdBy': challenge.createdBy,
      'amount': challenge.amount,
      'createdAt': challenge.createdAt.toIso8601String(),
      'expiresAt': challenge.expiresAt.toIso8601String(),
    });
  }
}