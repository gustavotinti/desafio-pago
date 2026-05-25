import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class UpdateProfileRepository {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _storage = FirebaseStorage.instance;

  Future<void> updateProfile({
    required String userId,
    required String name,
    required String bio,
    File? photo,
  }) async {
    String? photoUrl;

    if (photo != null) {
      final ref = _storage.ref('profiles/$userId.jpg');
      await ref.putFile(photo);
      photoUrl = await ref.getDownloadURL();
      await _auth.currentUser?.updatePhotoURL(photoUrl);
    }

    await _auth.currentUser?.updateDisplayName(name);

    final updates = <String, dynamic>{'name': name, 'bio': bio};
    if (photoUrl != null) updates['photoUrl'] = photoUrl;

    await _firestore.collection('users').doc(userId).update(updates);
  }
}
