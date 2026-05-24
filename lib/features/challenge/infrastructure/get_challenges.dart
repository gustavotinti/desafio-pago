import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/entities/challenge.dart';

class GetChallenges {
  final _firestore = FirebaseFirestore.instance;

  Future<List<Challenge>> call() async {
    final snapshot = await _firestore
        .collection('challenges')
        .orderBy('voteCount', descending: true)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();

      return Challenge(
        id: doc.id,
        title: data['title'],
        description: data['description'],
        createdBy: data['createdBy'],
        amount: (data['amount'] as num).toDouble(),

        // 🔥 AQUI ESTAVA FALTANDO
        voteCount: data['voteCount'] ?? 0,

        createdAt: DateTime.parse(data['createdAt']),
        expiresAt: DateTime.parse(data['expiresAt']),
      );
    }).toList();
  }
}