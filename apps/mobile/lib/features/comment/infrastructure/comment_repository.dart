import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
    String parentId = '',
  }) async {
    try {
      await _functions.httpsCallable('addComment').call({
        'challengeId': challengeId,
        'entryId': entryId,
        'parentId': parentId,
        'text': text,
      });
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Erro ao comentar');
    }
  }

  /// Curte/descurte um comentário. Retorna true se ficou curtido.
  Future<bool> toggleLike(String commentId) async {
    try {
      final res = await _functions
          .httpsCallable('toggleCommentLike')
          .call({'commentId': commentId});
      return (res.data as Map)['liked'] == true;
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Erro ao curtir');
    }
  }

  /// IDs dos comentários que o usuário logado já curtiu.
  Future<Set<String>> loadMyLikedIds() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return {};
    final snap = await _db
        .collection('commentLikes')
        .where('uid', isEqualTo: uid)
        .get();
    return snap.docs
        .map((d) => d.data()['commentId'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
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
