import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class UpdateProfileRepository {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _storage = FirebaseStorage.instance;
  final _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  Future<void> updateProfile({
    required String userId,
    required String name,
    required String bio,
    required String pixKey,
    String? newUsername,
    XFile? photo,
    String? libraryPhotoUrl,
  }) async {
    String? photoUrl;

    if (libraryPhotoUrl != null && libraryPhotoUrl.isNotEmpty) {
      // Avatar da biblioteca: só referenciamos a URL (zero Storage).
      photoUrl = libraryPhotoUrl;
      await _auth.currentUser?.updatePhotoURL(photoUrl);
    } else if (photo != null) {
      // Upload: caminho fixo por usuário → sobrescreve, 1 imagem por conta.
      final bytes = await photo.readAsBytes();
      final ref = _storage.ref('profiles/$userId/photo.jpg');
      await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      photoUrl = await ref.getDownloadURL();
      await _auth.currentUser?.updatePhotoURL(photoUrl);
    }

    await _auth.currentUser?.updateDisplayName(name);

    final updates = <String, dynamic>{
      'name': name,
      'bio': bio,
      'pixKey': pixKey,
    };
    if (photoUrl != null) {
      updates['photoUrl'] = photoUrl;
      // Marca como personalizada para o login não sobrescrever com a do Google.
      updates['photoIsCustom'] = true;
    }

    await _firestore.collection('users').doc(userId).update(updates);

    // Username update goes through Cloud Function for atomic swap
    if (newUsername != null && newUsername.isNotEmpty) {
      await _functions.httpsCallable('updateUsername').call({
        'newUsername': newUsername,
      });
    }
  }

  /// Check whether a username is already taken by another user.
  Future<bool> isUsernameTaken(String username, String currentUserId) async {
    final doc =
        await _firestore.collection('usernames').doc(username).get();
    if (!doc.exists) return false;
    return doc.data()?['uid'] != currentUserId;
  }
}
