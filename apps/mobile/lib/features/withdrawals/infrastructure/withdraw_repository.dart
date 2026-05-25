import 'package:cloud_firestore/cloud_firestore.dart';
import '../../finance/infrastructure/transaction_repository.dart';

class WithdrawRepository {
  static const double _feeRate = 0.10;
  static const double minimumAmount = 100.0;

  final _firestore = FirebaseFirestore.instance;
  final _transactionRepo = TransactionRepository();

  Future<void> requestWithdraw(String userId, double amount) async {
    if (amount < minimumAmount) {
      throw Exception(
          'Valor mínimo para saque é R\$${minimumAmount.toStringAsFixed(0)}');
    }

    final userDoc = await _firestore.collection('users').doc(userId).get();
    final userData = userDoc.data() ?? {};

    final balance = (userData['balance'] ?? 0).toDouble();
    final pixKey = (userData['pixKey'] ?? '') as String;

    if (pixKey.isEmpty) {
      throw Exception('Cadastre uma chave Pix primeiro');
    }

    if (amount > balance) {
      throw Exception('Saldo insuficiente');
    }

    final fee = double.parse((amount * _feeRate).toStringAsFixed(2));
    final netAmount = double.parse((amount - fee).toStringAsFixed(2));

    await _firestore.collection('withdrawals').add({
      'userId': userId,
      'amount': amount,
      'fee': fee,
      'netAmount': netAmount,
      'pixKey': pixKey,
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
    });

    await _firestore.collection('users').doc(userId).update({
      'balance': balance - amount,
    });

    await _transactionRepo.addTransaction(
      userId: userId,
      amount: amount,
      type: 'withdraw',
      description: 'Saque solicitado — taxa R\$${fee.toStringAsFixed(2)} (10%)',
    );
  }
}