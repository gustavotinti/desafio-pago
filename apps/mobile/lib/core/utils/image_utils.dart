import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Re-encoda os bytes para **JPEG comprimido**, redimensionando para no máximo
/// [maxDim] no lado maior. Deixa a imagem leve (upload rápido, render na hora,
/// menos storage/banda). Se não conseguir decodificar, devolve os bytes
/// originais — nunca quebra o envio.
Uint8List compressToJpg(
  Uint8List input, {
  int maxDim = 1440,
  int quality = 85,
}) {
  try {
    final decoded = img.decodeImage(input);
    if (decoded == null) return input;
    var out = decoded;
    final longest =
        decoded.width > decoded.height ? decoded.width : decoded.height;
    if (longest > maxDim) {
      out = decoded.width >= decoded.height
          ? img.copyResize(decoded, width: maxDim)
          : img.copyResize(decoded, height: maxDim);
    }
    return img.encodeJpg(out, quality: quality);
  } catch (_) {
    return input;
  }
}
