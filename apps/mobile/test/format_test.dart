import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/utils/format.dart';

void main() {
  group('Fmt', () {
    test('number agrupa milhares com ponto', () {
      expect(Fmt.number(89432), '89.432');
      expect(Fmt.number(1000000), '1.000.000');
    });

    test('brl formata moeda brasileira', () {
      expect(Fmt.brl(10), startsWith('R\$'));
      expect(Fmt.brl(10), contains('10,00'));
      expect(Fmt.brl(1557280), contains('1.557.280,00'));
    });
  });
}
