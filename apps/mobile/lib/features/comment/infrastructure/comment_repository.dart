import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../domain/entities/comment.dart';

class CommentRepository {
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  final _db = FirebaseFirestore.instance;

  Stream<List<Comment>> watchComments(String challengeId, String entryId) {
    return _db
        .collection('comments')
        .where('challengeId', isEqualTo: challengeId)
        .where('entryId', isEqualTo: entryId)
        .orderBy('createdAt')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Comment.fromMap(d.id, d.data()))
            .where((c) => c.isActive)
            .toList());
  }

  Future<void> addComment({
    required String challengeId,
    required String entryId,
    required String text,
  }) async {
    try {
      await _functions.httpsCallable('addComment').call({
        'challengeId': challengeId,
        'entryId': entryId,
        'text': text,
      });
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Erro ao comentar');
    }
  }

  Future<void> adminGenerateComment({
    required String challengeId,
    required String entryId,
    required String text,
  }) async {
    try {
      await _functions.httpsCallable('adminGenerateComment').call({
        'challengeId': challengeId,
        'entryId': entryId,
        'text': text,
      });
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Erro ao gerar comentário');
    }
  }
}
