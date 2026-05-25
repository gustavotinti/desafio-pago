import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class VoteRepository {
  final _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');
  final _firestore = FirebaseFirestore.instance;

  Future<void> vote(String challengeId, String entryId) async {
    try {
      await _functions
          .httpsCallable('vote')
          .call({'challengeId': challengeId, 'entryId': entryId});
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Erro ao votar');
    }
  }

  Future<bool> hasVoted(String challengeId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final voteId = '${user.uid}_$challengeId';
    final doc =
        await _firestore.collection('votes').doc(voteId).get();
    return doc.exists;
  }
}
