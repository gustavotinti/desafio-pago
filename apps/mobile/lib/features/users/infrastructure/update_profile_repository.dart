import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class UpdateProfileRepository {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _storage = FirebaseStorage.instance;

  Future<void> updateProfile({
    required String userId,
    required String name,
    required String bio,
    required String pixKey,
    XFile? photo,
  }) async {
    String? photoUrl;

    if (photo != null) {
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
    if (photoUrl != null) updates['photoUrl'] = photoUrl;

    await _firestore.collection('users').doc(userId).update(updates);
  }
}
