import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionRepository {
  final _firestore = FirebaseFirestore.instance;

  Future<void> addTransaction({
    required String userId,
    required double amount,
    required String type, // deposit | withdraw | reward
    required String description,
  }) async {
    await _firestore.collection('transactions').add({
      'userId': userId,
      'amount': amount,
      'type': type,
      'description': description,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }
}