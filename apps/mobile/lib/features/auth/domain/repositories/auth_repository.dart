import '../entities/auth_user.dart';

abstract class AuthRepository {
  Future<AuthUser?> signInWithGoogle();
}