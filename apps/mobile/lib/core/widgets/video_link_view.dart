import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import '../utils/open_url_stub.dart'
    if (dart.library.js_interop) '../utils/open_url_web.dart';
import 'embed_iframe_stub.dart'
    if (dart.library.js_interop) 'embed_iframe_web.dart';
import 'safe_image.dart';

/// Capa leve de um vídeo por link (YouTube Shorts / Reels do Instagram).
///
/// No feed e na lista só aparece a CAPA — o player oficial (iframe) só
/// carrega quando a pessoa toca, num diálogo. Dezenas de iframes abertos
/// deixariam o Flutter Web pesado e travariam a rolagem.
class VideoLinkCover extends StatelessWidget {
  const VideoLinkCover({
    super.key,
    required this.provider,
    this.thumbUrl,
    this.onTap,
    this.compact = false,
  });

  /// 'youtube' | 'instagram'
  final String provider;
  final String? thumbUrl;
  final VoidCallback? onTap;

  /// Versão pequena (prévia do feed): ícones menores, sem rótulo.
  final bool compact;

  bool get _yt => provider == 'youtube';

  @override
  Widget build(BuildContext context) {
    final thumb = thumbUrl;
    final cover = Stack(
      fit: StackFit.expand,
      children: [
        if (thumb != null && thumb.isNotEmpty)
          SafeImage(url: thumb)
        else
          // Instagram: a capa exige app da Meta — card da marca.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _yt
                    ? const [Color(0xFF282828), Color(0xFF0F0F0F)]
                    : const [
                        Color(0xFF833AB4),
                        Color(0xFFE1306C),
                        Color(0xFFF77737),
                      ],
              ),
            ),
          ),
        // Véu leve para o ícone de play aparecer em qualquer capa.
        const DecoratedBox(
          decoration: BoxDecoration(color: Color(0x22000000)),
        ),
        Center(
          child: Icon(Icons.play_circle_fill,
              color: Colors.white.withValues(alpha: 0.92),
              size: compact ? 30 : 56),
        ),
        Positioned(
          right: compact ? 4 : 8,
          bottom: compact ? 4 : 8,
          child: _ProviderBadge(youtube: _yt, compact: compact),
        ),
      ],
    );
    if (onTap == null) return cover;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: cover),
    );
  }
}

class _ProviderBadge extends StatelessWidget {
  const _ProviderBadge({required this.youtube, required this.compact});
  final bool youtube;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 4 : 7, vertical: compact ? 2 : 3),
      decoration: BoxDecoration(
        color: youtube ? const Color(0xFFFF0000) : const Color(0xFFC13584),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        youtube ? 'Shorts' : 'Reels',
        style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 8 : 11,
            fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// Abre o player oficial num diálogo (9:16). Fora do navegador, ou se a
/// pessoa preferir, há o botão para abrir no YouTube/Instagram.
Future<void> showVideoLinkPlayer(
  BuildContext context, {
  required String provider,
  required String embedUrl,
  required String url,
}) {
  final yt = provider == 'youtube';
  // autoplay depois do toque; rel=0 = sugestões só do mesmo canal.
  final src = yt ? '$embedUrl?autoplay=1&playsinline=1&rel=0' : embedUrl;
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final size = MediaQuery.of(ctx).size;
      // Cabe na tela: 9:16 (YouTube) ou mais alto (Instagram traz cabeçalho
      // e rodapé dentro do embed).
      final ratio = yt ? 9 / 16 : 9 / 19;
      final maxH = size.height * 0.78;
      var w = size.width * 0.9;
      if (w > 420) w = 420;
      if (w / ratio > maxH) w = maxH * ratio;
      return Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.black,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: w,
              height: w / ratio,
              child: embedSupported
                  ? embedIframe(src)
                  : Center(
                      child: Icon(Icons.play_circle_outline,
                          color: Colors.white.withValues(alpha: 0.6),
                          size: 64),
                    ),
            ),
            Container(
              width: w,
              color: const Color(0xFF15171C),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => openExternalUrl(url),
                      icon: const Icon(Icons.open_in_new,
                          size: 16, color: Colors.white70),
                      label: Text(
                        I18n.tr(yt
                            ? 'video_open_youtube'
                            : 'video_open_instagram'),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(I18n.tr('close'),
                        style: const TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
