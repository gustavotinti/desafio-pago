import 'package:flutter/material.dart';

/// Avatar circular robusto. Diferente do `CircleAvatar(backgroundImage: ...)`,
/// quando a URL está quebrada/sem CORS ele mostra o ícone de pessoa em vez de
/// um círculo em branco. URL vazia também cai no ícone.
class SafeAvatar extends StatelessWidget {
  final String? photoUrl;
  final double radius;
  final Color background;

  const SafeAvatar({
    super.key,
    required this.photoUrl,
    this.radius = 20,
    this.background = const Color(0xFFE9EEF6),
  });

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final url = photoUrl ?? '';
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url.isEmpty
            ? _fallback()
            : Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                frameBuilder: (context, child, frame, wasSync) {
                  if (wasSync || frame != null) return child;
                  return Container(color: background);
                },
                errorBuilder: (_, _, _) => _fallback(),
              ),
      ),
    );
  }

  Widget _fallback() => Container(
        color: background,
        alignment: Alignment.center,
        child: Icon(Icons.person, size: radius, color: Colors.black38),
      );
}
