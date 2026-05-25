import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class VoteRepository {
  final _firestore = FirebaseFirestore.instance;

  Future<void> vote(String challengeId, String entryId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Usuário não logado');

    final challengeDoc =
        await _firestore.collection('challenges').doc(challengeId).get();
    if (!challengeDoc.exists) throw Exception('Desafio não encontrado');

    final challengeData = challengeDoc.data()!;

    if ((challengeData['createdBy'] as String? ?? '') == user.uid) {
      throw Exception('Você não pode votar no próprio desafio');
    }

    if ((challengeData['status'] as String? ?? '') != 'active') {
      throw Exception('Desafio não está ativo');
    }

    // Deterministic ID prevents duplicate votes via race condition
    final voteId = '${user.uid}_$challengeId';
    final voteRef = _firestore.collection('votes').doc(voteId);
    final existing = await voteRef.get();

    if (existing.exists) throw Exception('Você já votou neste desafio');

    final entryRef = _firestore.collection('entries').doc(entryId);
    final challengeRef =
        _firestore.collection('challenges').doc(challengeId);

    await _firestore.runTransaction((tx) async {
      tx.set(voteRef, {
        'userId': user.uid,
        'challengeId': challengeId,
        'entryId': entryId,
        'createdAt': DateTime.now().toIso8601String(),
      });
      tx.update(entryRef, {'voteCount': FieldValue.increment(1)});
      tx.update(challengeRef, {'voteCount': FieldValue.increment(1)});
    });
  }

  Future<bool> hasVoted(String challengeId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final voteId = '${user.uid}_$challengeId';
    final doc = await _firestore.collection('votes').doc(voteId).get();
    return doc.exists;
  }
}
