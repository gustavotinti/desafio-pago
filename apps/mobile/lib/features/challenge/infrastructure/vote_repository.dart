import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/utils/friendly_error.dart';

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
      throw AppException.fromFunctions(e, 'Erro ao votar');
    }
  }

  Future<bool> hasVoted(String challengeId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final voteId = '${user.uid}_$challengeId';
    // A regra de /votes nega o get quando o doc NÃO existe (quem ainda não
    // votou) — trata como "não votou" em vez de deixar o erro escapar. O
    // servidor continua barrando voto duplicado.
    try {
      final doc =
          await _firestore.collection('votes').doc(voteId).get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }
}
