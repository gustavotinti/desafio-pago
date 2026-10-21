/// Vídeo por link (YouTube Shorts / Reels do Instagram).
///
/// Espelho EXATO de `functions/video_link.js`: os testes dos dois lados usam
/// os mesmos vetores. O código de verificação mostrado aqui precisa ser o
/// mesmo que o servidor recalcula — se mudar lá, mude aqui.
class VideoLink {
  const VideoLink({
    required this.provider,
    required this.id,
    required this.url,
    required this.embedUrl,
    this.thumbUrl,
  });

  /// 'youtube' | 'instagram'
  final String provider;
  final String id;

  /// Link público canônico (abre no app do YouTube/Instagram).
  final String url;

  /// Player oficial para iframe.
  final String embedUrl;

  /// Capa vertical (só YouTube — o Instagram exige app da Meta para isso).
  final String? thumbUrl;

  bool get isYouTube => provider == 'youtube';

  static final _ytId = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static final _igCode = RegExp(r'^[A-Za-z0-9_-]{5,40}$');
  static const _igKinds = ['reel', 'reels', 'p', 'tv'];

  static VideoLink _youtube(String id) => VideoLink(
        provider: 'youtube',
        id: id,
        url: 'https://www.youtube.com/shorts/$id',
        embedUrl: 'https://www.youtube-nocookie.com/embed/$id',
        thumbUrl: 'https://i.ytimg.com/vi/$id/oar2.jpg',
      );

  static VideoLink _instagram(String kind, String code) => VideoLink(
        provider: 'instagram',
        id: code,
        url: 'https://www.instagram.com/$kind/$code/',
        embedUrl: 'https://www.instagram.com/$kind/$code/embed/',
      );

  /// Link colado → vídeo reconhecido, ou null.
  static VideoLink? parse(String? raw) {
    var s = (raw ?? '').trim();
    if (s.isEmpty || RegExp(r'\s').hasMatch(s)) return null;
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(s)) {
      s = 'https://$s';
    }
    final u = Uri.tryParse(s);
    if (u == null || u.host.isEmpty) return null;
    final host =
        u.host.toLowerCase().replaceFirst(RegExp(r'^(www\.|m\.|music\.)'), '');
    final parts = u.pathSegments.where((p) => p.isNotEmpty).toList();
    String? at(int i) => i < parts.length ? parts[i] : null;

    if (host == 'youtube.com' || host == 'youtube-nocookie.com') {
      String? id;
      if (const ['shorts', 'embed', 'live', 'v'].contains(at(0))) {
        id = at(1);
      } else if (at(0) == 'watch') {
        id = u.queryParameters['v'];
      }
      return id != null && _ytId.hasMatch(id) ? _youtube(id) : null;
    }
    if (host == 'youtu.be') {
      final id = at(0);
      return id != null && _ytId.hasMatch(id) ? _youtube(id) : null;
    }
    if (host == 'instagram.com' || host == 'instagr.am') {
      var i = -1;
      if (_igKinds.contains(at(0))) {
        i = 0;
      } else if (_igKinds.contains(at(1))) {
        i = 1; // /{usuario}/reel/CODE
      }
      if (i < 0) return null;
      final code = at(i + 1);
      if (code == null || !_igCode.hasMatch(code)) return null;
      return _instagram(at(i) == 'p' ? 'p' : 'reel', code);
    }
    return null;
  }

  // Sem 0/O/1/I: o participante digita o código no título/legenda.
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// Código do participante NESTE desafio (ex.: "DPK7M2Q"). Só aritmética
  /// inteira pequena (< 2^38): o resultado é o mesmo no Node, no Dart da VM e
  /// no Dart compilado para JavaScript (onde inteiros são double).
  static String verificationCode(String uid, String challengeId) {
    final s = '$uid:$challengeId';
    var h = 5381;
    for (final c in s.codeUnits) {
      h = (h * 33 + c) % 2147483647;
    }
    final out = StringBuffer('DP');
    for (var k = 0; k < 5; k++) {
      out.write(_alphabet[h % 32]);
      h = h ~/ 32;
    }
    return out.toString();
  }
}
