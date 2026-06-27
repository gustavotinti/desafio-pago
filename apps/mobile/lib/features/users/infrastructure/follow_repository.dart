import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FollowRepository {
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  final _firestore = FirebaseFirestore.instance;

  Future<void> follow(String targetUserId) => _toggle(targetUserId, true);
  Future<void> unfollow(String targetUserId) => _toggle(targetUserId, false);

  // Seguir/deixar de seguir passa por Cloud Function (Admin SDK) — os
  // contadores de seguidores ficam protegidos contra manipulação no cliente.
  Future<void> _toggle(String targetUserId, bool follow) async {
    try {
      await _functions.httpsCallable('toggleFollow').call({
        'targetUserId': targetUserId,
        'follow': follow,
      });
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Erro ao seguir');
    }
  }

  Future<bool> isFollowing(String targetUserId) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return false;
    final doc = await _firestore
        .collection('follows')
        .doc('${currentUid}_$targetUserId')
        .get();
    return doc.exists;
  }
}
