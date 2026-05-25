import 'package:cloud_firestore/cloud_firestore.dart';

class GetVoteCount {
  final _firestore = FirebaseFirestore.instance;

  Future<int> call(String challengeId) async {
    final snapshot = await _firestore
        .collection('votes')
        .where('challengeId', isEqualTo: challengeId)
        .get();

    return snapshot.docs.length;
  }
}