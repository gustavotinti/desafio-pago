import 'package:cloud_firestore/cloud_firestore.dart';

class AddAmountRepository {
  final _firestore = FirebaseFirestore.instance;

  Future<void> addAmount(String challengeId, double value) async {
    final challengeRef = _firestore.collection('challenges').doc(challengeId);
    final snapshot = await challengeRef.get();

    if (!snapshot.exists) {
      throw Exception('Desafio não encontrado');
    }

    final data = snapshot.data()!;
    final status = data['status'] as String? ?? '';

    if (status == 'finished') {
      throw Exception('Desafio já encerrado');
    }

    final expiresAt = DateTime.parse(data['expiresAt']);
    final timeLeft = expiresAt.difference(DateTime.now());

    if (timeLeft.inHours < 3) {
      throw Exception(
        'Não é possível aumentar o valor com menos de 3 horas para o fim do desafio',
      );
    }

    await challengeRef.update({
      'amount': FieldValue.increment(value),
    });
  }
}
