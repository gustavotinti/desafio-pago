import 'package:firebase_auth/firebase_auth.dart';

import '../domain/entities/auth_user.dart';

class FirebaseAuthRepository {
  final FirebaseAuth _firebaseAuth;

  FirebaseAuthRepository(this._firebaseAuth);

  Future<AuthUser?> signInWithGoogle() async {
    try {
      final provider = GoogleAuthProvider();

      // 🔥 USAR POPUP (mais estável aqui)
      final result = await _firebaseAuth.signInWithPopup(provider);

      final user = result.user;

      if (user == null) return null;

      return AuthUser(
        id: user.uid,
        name: user.displayName ?? '',
        email: user.email ?? '',
        photoUrl: user.photoURL ?? '',
      );
    } catch (e) {
      print("ERRO LOGIN: $e");
      rethrow;
    }
  }
}