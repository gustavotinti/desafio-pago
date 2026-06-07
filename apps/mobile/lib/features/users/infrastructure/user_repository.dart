import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import '../../auth/domain/entities/auth_user.dart';

class UserRepository {
  final _firestore = FirebaseFirestore.instance;

  // ── Username generation ────────────────────────────────────────────────────

  /// Converts an arbitrary string to a safe username fragment:
  /// lowercase, accents stripped, only [a-z0-9.], no leading/trailing dots.
  String _normalizeUsername(String raw) {
    // Simple accent removal via codepoint checks for common Portuguese chars
    const accents = {
      'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
      'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
      'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
      'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
      'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n',
    };
    final buf = StringBuffer();
    for (final ch in raw.toLowerCase().split('')) {
      final mapped = accents[ch];
      if (mapped != null) {
        buf.write(mapped);
      } else if (RegExp(r'[a-z0-9]').hasMatch(ch)) {
        buf.write(ch);
      } else {
        buf.write('.');
      }
    }
    // Collapse consecutive dots and trim
    return buf.toString()
        .replaceAll(RegExp(r'\.+'), '.')
        .replaceAll(RegExp(r'^\.+|\.+$'), '');
  }

  /// Finds an available username derived from the email address.
  /// If the base is taken, appends incrementing numeric suffixes.
  Future<String> _generateUniqueUsername(String email) async {
    final localPart = email.split('@').first;
    final normalized = _normalizeUsername(localPart);
    final base = normalized.length > 25
        ? normalized.substring(0, 25)
        : (normalized.isEmpty ? 'usuario' : normalized);

    String candidate = base;
    int suffix = 0;

    while (true) {
      final doc =
          await _firestore.collection('usernames').doc(candidate).get();
      if (!doc.exists) return candidate;
      suffix++;
      candidate = '$base.$suffix';
    }
  }

  // ── Save / update user on login ────────────────────────────────────────────

  Future<void> saveUser(AuthUser user) async {
    final doc = _firestore.collection('users').doc(user.id);
    final snapshot = await doc.get();

    if (!snapshot.exists) {
      // First login — generate username and initialize all fields
      final username =
          await _generateUniqueUsername(user.email ?? user.id);

      await _firestore.runTransaction((tx) async {
        tx.set(doc, {
          'name': user.name ?? '',
          'email': user.email ?? '',
          'username': username,
          'photoUrl': user.photoUrl ?? '',
          'createdAt': DateTime.now().toIso8601String(),
          'balance': 0.0,
          'pendingBalance': 0.0,
          'lockedBalance': 0.0,
          'totalEarned': 0.0,
          'totalVotesReceived': 0,
          'followersCount': 0,
          'followingCount': 0,
          'bio': '',
          'pixKey': '',
          'termsAccepted': false,
          'isVerified': false,
          'isVirtual': false,
          'photoIsCustom': false,
        });
        tx.set(
          _firestore.collection('usernames').doc(username),
          {'uid': user.id},
        );
      });
    } else {
      // Subsequent logins — sync Google profile fields, but NEVER overwrite
      // a photo the user customized (library avatar or upload).
      final isCustom = snapshot.data()?['photoIsCustom'] == true;
      final updates = <String, dynamic>{
        'name': user.name ?? '',
        'email': user.email ?? '',
      };
      if (!isCustom) {
        updates['photoUrl'] = user.photoUrl ?? '';
      }
      await doc.update(updates);
    }

    // Marca a instalação do app (somente mobile) para públicos de campanha.
    if (!kIsWeb) {
      try {
        await FirebaseFunctions.instanceFor(region: 'us-central1')
            .httpsCallable('registerAppInstall')
            .call({'platform': defaultTargetPlatform.name});
      } catch (_) {
        // Falha não deve bloquear o login.
      }
    }
  }
}
