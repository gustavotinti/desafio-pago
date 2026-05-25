import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/domain/entities/auth_user.dart';

class UserRepository {
  final _firestore = FirebaseFirestore.instance;

  Future<void> saveUser(AuthUser user) async {
    final doc = _firestore.collection('users').doc(user.id);
    final snapshot = await doc.get();

    if (!snapshot.exists) {
      // First login — initialize all fields including financial ones
      await doc.set({
        'name': user.name ?? '',
        'email': user.email ?? '',
        'photoUrl': user.photoUrl ?? '',
        'createdAt': DateTime.now().toIso8601String(),
        'balance': 0.0,
        'pendingBalance': 0.0,
        'lockedBalance': 0.0,
        'totalEarned': 0.0,
        'totalVotesReceived': 0,
        'followersCount': 0,
        'followingCount': 0,
        'bio': '',
        'pixKey': '',
        'termsAccepted': false,
      });
    } else {
      // Subsequent logins — only sync Google profile fields
      await doc.update({
        'name': user.name ?? '',
        'email': user.email ?? '',
        'photoUrl': user.photoUrl ?? '',
      });
    }
  }
}
