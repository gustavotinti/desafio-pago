import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/core/utils/image_utils.dart';

void main() {
  group('compressToJpg', () {
    test('redimensiona para maxDim mantendo a proporção e gera imagem válida',
        () {
      final src = img.Image(width: 2000, height: 1000);
      img.fill(src, color: img.ColorRgb8(120, 30, 200));
      final bytes = Uint8List.fromList(img.encodePng(src));

      final out = compressToJpg(bytes, maxDim: 500, quality: 80);
      final decoded = img.decodeImage(out);

      expect(decoded, isNotNull);
      expect(decoded!.width, 500); // lado maior limitado a 500
      expect(decoded.height, 250); // proporção 2:1 mantida
    });

    test('não amplia imagens já menores que maxDim', () {
      final src = img.Image(width: 100, height: 80);
      img.fill(src, color: img.ColorRgb8(10, 20, 30));
      final bytes = Uint8List.fromList(img.encodePng(src));

      final decoded = img.decodeImage(compressToJpg(bytes, maxDim: 500));
      expect(decoded!.width, 100);
      expect(decoded.height, 80);
    });

    test('devolve os bytes originais se não conseguir decodificar', () {
      final garbage = Uint8List.fromList([1, 2, 3, 4, 5]);
      expect(compressToJpg(garbage), garbage);
    });
  });
}
