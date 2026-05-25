import 'package:cloud_firestore/cloud_firestore.dart';
import '../../finance/infrastructure/transaction_repository.dart';

class WithdrawRepository {
  final _firestore = FirebaseFirestore.instance;
  final _transactionRepo = TransactionRepository();

  Future<void> requestWithdraw(String userId, double amount) async {
    final userDoc =
        await _firestore.collection('users').doc(userId).get();

    final balance = (userDoc.data()?['balance'] ?? 0).toDouble();
    final pixKey = userDoc.data()?['pixKey'];

    if (pixKey == null || pixKey.isEmpty) {
      throw Exception('Cadastre uma chave Pix primeiro');
    }

    if (amount > balance) {
      throw Exception('Saldo insuficiente');
    }

    // 🔥 cria saque
    await _firestore.collection('withdrawals').add({
      'userId': userId,
      'amount': amount,
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
    });

    // 🔥 atualiza saldo
    await _firestore.collection('users').doc(userId).update({
      'balance': balance - amount,
    });

    // 🔥 salva histórico
    await _transactionRepo.addTransaction(
      userId: userId,
      amount: amount,
      type: 'withdraw',
      description: 'Solicitação de saque',
    );
  }
}