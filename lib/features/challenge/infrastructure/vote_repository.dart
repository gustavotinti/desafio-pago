import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class VoteRepository {
  final _firestore = FirebaseFirestore.instance;

  Future<void> vote(String challengeId) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception("Usuário não logado");
    }

    final existingVote = await _firestore
        .collection('votes')
        .where('userId', isEqualTo: user.uid)
        .where('challengeId', isEqualTo: challengeId)
        .get();

    if (existingVote.docs.isNotEmpty) {
      throw Exception("Você já votou nesse desafio");
    }

    await _firestore.collection('votes').add({
      'userId': user.uid,
      'challengeId': challengeId,
      'createdAt': DateTime.now().toIso8601String(),
    });

    await _firestore.collection('challenges').doc(challengeId).update({
      'voteCount': FieldValue.increment(1),
    });
  }
}