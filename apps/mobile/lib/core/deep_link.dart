/// Captura um link compartilhado de participação ao abrir o app na web.
///
/// Formato: https://desafiopago.com.br/challenges/{challengeId}?entry={entryId}
/// Quando presente, o app abre direto na arte do participante (destacada),
/// pronta para votar — é o fluxo de compartilhar nas redes para receber votos.
class PendingDeepLink {
  PendingDeepLink._();

  static String? challengeId;
  static String? entryId;
  static bool handled = false;

  static void parse() {
    try {
      final uri = Uri.base;
      final segs = uri.pathSegments;
      final idx = segs.indexOf('challenges');
      if (idx != -1 && idx + 1 < segs.length) {
        challengeId = segs[idx + 1];
        final e = uri.queryParameters['entry'];
        if (e != null && e.isNotEmpty) entryId = e;
      }
    } catch (_) {
      // URL inesperada — ignora.
    }
  }

  static bool get hasLink => (challengeId ?? '').isNotEmpty;
}
