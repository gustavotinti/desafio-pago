import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class VerificationRepository {
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  final _db = FirebaseFirestore.instance;

  /// Envia (ou atualiza) o pedido de selo verificado.
  Future<void> submit({
    required String firstName,
    required String lastName,
    required String phone,
    required String cpf,
  }) async {
    await _functions.httpsCallable('submitVerificationRequest').call({
      'firstName': firstName,
      'lastName': lastName,
      'phone': phone,
      'cpf': cpf,
    });
  }

  /// Stream do pedido do usuário logado (status, prioridade, etc.).
  Stream<DocumentSnapshot<Map<String, dynamic>>> myRequest() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '_';
    return _db.collection('verificationRequests').doc(uid).snapshots();
  }

  /// Admin aprova ou recusa um pedido.
  Future<void> decide(String userId, bool approved) async {
    await _functions.httpsCallable('decideVerificationRequest').call({
      'userId': userId,
      'approved': approved,
    });
  }
}
