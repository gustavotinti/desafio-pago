import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AppNotification {
  final String id;
  final String title;
  final String body;
  final String type;
  final String? challengeId;
  final bool read;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.challengeId,
    required this.read,
    required this.createdAt,
  });

  factory AppNotification.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    return AppNotification(
      id: d.id,
      title: m['title'] as String? ?? '',
      body: m['body'] as String? ?? '',
      type: m['type'] as String? ?? '',
      challengeId: m['challengeId'] as String?,
      read: m['read'] == true,
      createdAt:
          DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class NotificationRepository {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>>? _col() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return _db.collection('users').doc(uid).collection('notifications');
  }

  /// As 50 notificações mais recentes do usuário (tempo real).
  Stream<List<AppNotification>> watch() {
    final col = _col();
    if (col == null) return const Stream.empty();
    return col
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((s) => s.docs.map(AppNotification.fromDoc).toList());
  }

  /// Marca todas as não lidas como lidas.
  Future<void> markAllRead() async {
    final col = _col();
    if (col == null) return;
    final unread = await col.where('read', isEqualTo: false).limit(300).get();
    if (unread.docs.isEmpty) return;
    final batch = _db.batch();
    for (final d in unread.docs) {
      batch.update(d.reference, {'read': true});
    }
    await batch.commit();
  }
}
