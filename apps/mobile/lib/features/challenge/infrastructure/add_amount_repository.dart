import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/utils/friendly_error.dart';

class AddAmountRepository {
  final _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  /// [value] SEMPRE em BRL (ledger) — no intl a tela converte o US$ digitado
  /// antes de chamar (Fmt.typedToBrl).
  Future<void> addAmount(String challengeId, double value) async {
    try {
      await _functions.httpsCallable('addAmount').call({
        'challengeId': challengeId,
        'value': value,
      });
    } on FirebaseFunctionsException catch (e) {
      throw AppException.fromFunctions(e, 'Erro ao adicionar valor');
    }
  }
}
