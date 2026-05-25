import '../entities/challenge.dart';

abstract class ChallengeRepository {
  Future<void> create(Challenge challenge);
  Future<List<Challenge>> getAll();
  Future<Challenge?> getById(String id);
}
