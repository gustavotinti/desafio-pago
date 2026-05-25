import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../entry/domain/entities/content_type.dart';

class EntryRepository {
  final _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');
  final _storage = FirebaseStorage.instance;

  Future<void> submitEntry({
    required String challengeId,
    required ContentType contentType,
    String? contentText,
    File? contentFile,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Usuário não logado');

    // File upload remains client-side (Storage SDK requirement)
    String? contentUrl;
    if (contentFile != null && contentType != ContentType.text) {
      final ext = contentType == ContentType.image ? 'jpg' : 'mp4';
      final ref = _storage.ref(
          'entries/$challengeId/${user.uid}_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await ref.putFile(contentFile);
      contentUrl = await ref.getDownloadURL();
    }

    try {
      await _functions.httpsCallable('submitEntry').call({
        'challengeId': challengeId,
        'contentType': contentType.name,
        if (contentText != null) 'contentText': contentText,
        if (contentUrl != null) 'contentUrl': contentUrl,
      });
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'Erro ao submeter participação');
    }
  }
}
