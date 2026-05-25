import 'package:cloud_firestore/cloud_firestore.dart';

class GetTransactions {
  final _firestore = FirebaseFirestore.instance;

  Future<List<Map<String, dynamic>>> call(String userId) async {
    final snapshot = await _firestore
        .collection('transactions')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .get();

    return snapshot.docs.map((doc) => doc.data()).toList();
  }
}