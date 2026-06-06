/// Biblioteca de avatares prontos.
///
/// As imagens ficam hospedadas no nosso próprio Firebase Hosting
/// (pasta `web/avatars/`), servidas em `/avatars/avatar_NN.png`.
/// Escolher um avatar custa ZERO de Storage — guardamos apenas a URL
/// no campo `photoUrl` do usuário.
class AvatarLibrary {
  AvatarLibrary._();

  /// Base canônica (Firebase Hosting). Cross-origin liberado via headers
  /// em firebase.json (`Access-Control-Allow-Origin: *`).
  static const String base = 'https://desafiopago.web.app/avatars';

  /// Quantidade de avatares disponíveis na biblioteca.
  static const int count = 24;

  /// URLs de todos os avatares da biblioteca.
  static final List<String> all = List<String>.generate(
    count,
    (i) => '$base/avatar_${(i + 1).toString().padLeft(2, '0')}.png',
  );

  /// Indica se uma URL pertence à biblioteca.
  static bool isLibraryUrl(String? url) =>
      url != null && url.startsWith(base);
}
