import '../domain/repositories/auth_repository.dart';
import '../domain/entities/auth_user.dart';

class SignInWithGoogle {
  final AuthRepository repository;

  SignInWithGoogle(this.repository);

  Future<AuthUser?> call() async {
    return await repository.signInWithGoogle();
  }
}