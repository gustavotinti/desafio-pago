import '../domain/entities/challenge.dart';
import '../infrastructure/firebase_challenge_repository.dart';

class CreateChallenge {
  final FirebaseChallengeRepository repository;

  CreateChallenge(this.repository);

  Future<void> call(Challenge challenge) async {
    await repository.createChallenge(challenge);
  }
}