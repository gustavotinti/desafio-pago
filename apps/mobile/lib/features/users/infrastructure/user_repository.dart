import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/domain/entities/auth_user.dart';

class UserRepository {
  final _firestore = FirebaseFirestore.instance;

  Future<void> saveUser(AuthUser user) async {
    final doc = _firestore.collection('users').doc(user.id);

    await doc.set({
      'name': user.name ?? '',
      'email': user.email ?? '',
      'photoUrl': user.photoUrl ?? '',
      'createdAt': DateTime.now().toIso8601String(),
      'balance': 0,
      'pendingBalance': 0,
      'lockedBalance': 0,
      'totalEarned': 0,
      'totalVotesReceived': 0,
      'followersCount': 0,
      'followingCount': 0,
      'bio': '',
      'pixKey': '',
    }, SetOptions(merge: true));
  }
}