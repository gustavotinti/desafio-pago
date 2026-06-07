import 'package:cloud_functions/cloud_functions.dart';

class AdminRepository {
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Edita um perfil virtual. Campos nulos não são alterados.
  /// Para foto: passe [photoUrl] (biblioteca/retrato) OU [photoBase64] (upload).
  /// Retorna a nova photoUrl quando houve upload.
  Future<String?> updateVirtualUser({
    required String userId,
    String? name,
    String? username,
    String? bio,
    bool? isVerified,
    String? photoUrl,
    String? photoBase64,
    String? photoContentType,
  }) async {
    final payload = <String, dynamic>{'userId': userId};
    if (name != null) payload['name'] = name;
    if (username != null) payload['username'] = username;
    if (bio != null) payload['bio'] = bio;
    if (isVerified != null) payload['isVerified'] = isVerified;
    if (photoUrl != null) payload['photoUrl'] = photoUrl;
    if (photoBase64 != null) payload['photoBase64'] = photoBase64;
    if (photoContentType != null) payload['photoContentType'] = photoContentType;

    final res =
        await _functions.httpsCallable('adminUpdateVirtualUser').call(payload);
    return (res.data as Map)['photoUrl'] as String?;
  }

  /// Exporta o público para campanhas.
  /// [segment]: 'signups' | 'installs' · [platform]: 'google' | 'meta'.
  /// Retorna { csv, count, filename }.
  Future<Map<String, dynamic>> exportAudience(
    String segment,
    String platform,
  ) async {
    final res = await _functions.httpsCallable('exportAudience').call({
      'segment': segment,
      'platform': platform,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }
}

