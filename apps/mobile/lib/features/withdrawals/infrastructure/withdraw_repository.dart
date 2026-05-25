import 'package:cloud_functions/cloud_functions.dart';

class WithdrawRepository {
  static const double minimumAmount = 100.0;

  final _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  Future<void> requestWithdraw(String userId, double amount) async {
    try {
      await _functions
          .httpsCallable('requestWithdraw')
          .call({'amount': amount});
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Erro ao solicitar saque');
    }
  }
}
