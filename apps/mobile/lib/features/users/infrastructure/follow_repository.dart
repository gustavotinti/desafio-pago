import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FollowRepository {
  final _firestore = FirebaseFirestore.instance;

  Future<void> follow(String targetUserId) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) throw Exception('Usuário não logado');
    if (currentUid == targetUserId) throw Exception('Você não pode seguir a si mesmo');

    final followId = '${currentUid}_$targetUserId';
    final followRef = _firestore.collection('follows').doc(followId);
    final existing = await followRef.get();
    if (existing.exists) return;

    await _firestore.runTransaction((tx) async {
      tx.set(followRef, {
        'followerId': currentUid,
        'followedId': targetUserId,
        'createdAt': DateTime.now().toIso8601String(),
      });
      tx.update(_firestore.collection('users').doc(targetUserId), {
        'followersCount': FieldValue.increment(1),
      });
      tx.update(_firestore.collection('users').doc(currentUid), {
        'followingCount': FieldValue.increment(1),
      });
    });
  }

  Future<void> unfollow(String targetUserId) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) throw Exception('Usuário não logado');

    final followId = '${currentUid}_$targetUserId';
    final followRef = _firestore.collection('follows').doc(followId);
    final existing = await followRef.get();
    if (!existing.exists) return;

    await _firestore.runTransaction((tx) async {
      tx.delete(followRef);
      tx.update(_firestore.collection('users').doc(targetUserId), {
        'followersCount': FieldValue.increment(-1),
      });
      tx.update(_firestore.collection('users').doc(currentUid), {
        'followingCount': FieldValue.increment(-1),
      });
    });
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
