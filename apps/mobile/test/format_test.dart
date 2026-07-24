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

    test('usdToBrl inverte usdPerBrl', () {
      Fmt.usdPerBrl = 0.20; // 1 BRL = 0,20 USD → 1 USD = 5 BRL
      expect(Fmt.usdToBrl(10), closeTo(50, 0.0001));
    });

    test('usdToBrl com cotação inválida usa fallback (~5,5)', () {
      Fmt.usdPerBrl = 0;
      expect(Fmt.usdToBrl(10), closeTo(55, 0.0001));
    });

    test('xrp converte BRL pela cotação e mostra 2 casas', () {
      Fmt.xrpPerBrl = 0.08; // 1 BRL = 0,08 XRP
      expect(Fmt.xrp(100), '8.00');
    });
  });
}
