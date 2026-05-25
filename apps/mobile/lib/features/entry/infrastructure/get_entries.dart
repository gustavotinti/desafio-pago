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

    return snapshot.docs.map((doc) {
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
    }).toList();
  }
}
