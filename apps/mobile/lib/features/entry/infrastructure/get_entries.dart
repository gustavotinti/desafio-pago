import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/entities/content_type.dart';
import '../domain/entities/entry.dart';

class GetEntries {
  final _firestore = FirebaseFirestore.instance;

  Future<List<Entry>> call(String challengeId) async {
    final snapshot = await _firestore
        .collection('entries')
        .where('challengeId', isEqualTo: challengeId)
        .where('isActive', isEqualTo: true)
        .orderBy('voteCount', descending: true)
        .get();

    return snapshot.docs.map(_map).toList();
  }

  /// Stream em tempo real das participações de um desafio (mais votadas
  /// primeiro). Os votos aparecem na hora conforme as pessoas votam.
  Stream<List<Entry>> watch(String challengeId) {
    return _firestore
        .collection('entries')
        .where('challengeId', isEqualTo: challengeId)
        .where('isActive', isEqualTo: true)
        .orderBy('voteCount', descending: true)
        .snapshots()
        .map((s) => s.docs.map(_map).toList());
  }

  /// Participações de um usuário (mais recentes primeiro), em todos os desafios.
  Future<List<Entry>> byUser(String uid) async {
    final snapshot = await _firestore
        .collection('entries')
        .where('userId', isEqualTo: uid)
        .get();
    final list = snapshot.docs.map(_map).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Entry _map(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return Entry(
      id: doc.id,
      challengeId: data['challengeId'] ?? '',
      userId: data['userId'] ?? '',
      contentType: ContentType.values.firstWhere(
        (t) => t.name == (data['contentType'] ?? ''),
        orElse: () => ContentType.text,
      ),
      contentText: data['contentText'] as String?,
      contentUrl: data['contentUrl'] as String?,
      voteCount: data['voteCount'] ?? 0,
      isActive: data['isActive'] ?? true,
      createdAt: DateTime.parse(data['createdAt']),
    );
  }
}
