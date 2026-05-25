import 'package:cloud_functions/cloud_functions.dart';

class AddAmountRepository {
  final _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  Future<void> addAmount(String challengeId, double value) async {
    try {
      await _functions.httpsCallable('addAmount').call({
        'challengeId': challengeId,
        'value': value,
      });
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Erro ao adicionar valor');
    }
  }
}
