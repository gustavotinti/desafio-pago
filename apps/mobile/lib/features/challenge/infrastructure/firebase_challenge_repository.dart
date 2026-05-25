import 'package:cloud_functions/cloud_functions.dart';

import '../domain/entities/challenge.dart';

class FirebaseChallengeRepository {
  final _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  Future<void> createChallenge(Challenge challenge) async {
    final durationDays =
        challenge.expiresAt.difference(challenge.createdAt).inDays;

    try {
      await _functions.httpsCallable('createChallenge').call({
        'title': challenge.title,
        'description': challenge.description,
        'amount': challenge.amount,
        'durationDays': durationDays < 1 ? 1 : durationDays,
      });
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Erro ao criar desafio');
    }
  }
}
