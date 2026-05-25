import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../../entry/domain/entities/content_type.dart';

class EntryRepository {
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  Future<void> submitEntry({
    required String challengeId,
    required ContentType contentType,
    String? contentText,
    File? contentFile,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Usuário não logado');

    final challengeDoc =
        await _firestore.collection('challenges').doc(challengeId).get();
    if (!challengeDoc.exists) throw Exception('Desafio não encontrado');

    final challengeData = challengeDoc.data()!;
    final status = challengeData['status'] as String? ?? '';

    if (status != 'active') throw Exception('Desafio não está ativo');

    if ((challengeData['createdBy'] as String? ?? '') == user.uid) {
      throw Exception('Você não pode participar do próprio desafio');
    }

    final existing = await _firestore
        .collection('entries')
        .where('challengeId', isEqualTo: challengeId)
        .where('userId', isEqualTo: user.uid)
        .get();

    if (existing.docs.isNotEmpty) {
      throw Exception('Você já participou deste desafio');
    }

    String? contentUrl;
    if (contentFile != null && contentType != ContentType.text) {
      final ext = contentType == ContentType.image ? 'jpg' : 'mp4';
      final ref =
          _storage.ref('entries/$challengeId/${user.uid}_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await ref.putFile(contentFile);
      contentUrl = await ref.getDownloadURL();
    }

    final entryId = const Uuid().v4();
    final entryRef = _firestore.collection('entries').doc(entryId);
    final challengeRef =
        _firestore.collection('challenges').doc(challengeId);

    await _firestore.runTransaction((tx) async {
      tx.set(entryRef, {
        'challengeId': challengeId,
        'userId': user.uid,
        'contentType': contentType.name,
        'contentText': contentText,
        'contentUrl': contentUrl,
        'voteCount': 0,
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      tx.update(challengeRef, {
        'entryCount': FieldValue.increment(1),
      });
    });
  }
}
