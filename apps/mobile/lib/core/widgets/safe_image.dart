import 'package:flutter/material.dart';

/// Imagem de rede robusta para Flutter Web (CanvasKit).
///
/// Usa `frameBuilder` (confiável na web) em vez de `loadingBuilder` — este
/// último costuma nunca "fechar" na web, deixando um spinner infinito. Mostra
/// um placeholder enquanto carrega e um estado de erro claro se falhar, em vez
/// de girar para sempre.
class SafeImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;

  const SafeImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return _placeholder(loading: true);
      },
      errorBuilder: (context, error, stack) => _placeholder(loading: false),
    );
  }

  Widget _placeholder({required bool loading}) {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFFEDF1F8),
      alignment: Alignment.center,
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image_outlined,
                    color: Colors.black26, size: 28),
                SizedBox(height: 4),
                Text('Imagem indisponível',
                    style: TextStyle(fontSize: 11, color: Colors.black38)),
              ],
            ),
    );
  }
}
