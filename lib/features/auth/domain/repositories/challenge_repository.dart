import '../entities/challenge.dart';

abstract class ChallengeRepository {
  Future<void> createChallenge(Challenge challenge);
}