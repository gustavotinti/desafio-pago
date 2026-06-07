import 'package:cloud_functions/cloud_functions.dart';

class PaymentRepository {
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

  Future<Map<String, dynamic>> createPixPayment(
    double amount, {
    String purpose = 'deposit',
  }) async {
    final result = await _functions
        .httpsCallable('createPixPayment')
        .call({'amount': amount, 'purpose': purpose});

    final data = Map<String, dynamic>.from(result.data as Map);
    return data;
  }

  Future<String> checkPaymentStatus(String paymentId) async {
    final result = await _functions
        .httpsCallable('checkPaymentStatus')
        .call({'paymentId': paymentId});

    return (result.data as Map)['status'] as String;
  }
}
