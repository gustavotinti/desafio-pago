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

    test('parseTyped aceita vírgula decimal e zera o inválido', () {
      expect(Fmt.parseTyped('10,50'), 10.5);
      expect(Fmt.parseTyped(' 10.5 '), 10.5);
      expect(Fmt.parseTyped(''), 0);
      expect(Fmt.parseTyped('abc'), 0);
      expect(Fmt.parseTyped('NaN'), 0);
      expect(Fmt.parseTyped('Infinity'), 0);
    });

    test('typedToBrl no BR usa o valor digitado (já em R\$)', () {
      Fmt.usdPerBrl = 0.20;
      expect(Fmt.typedToBrl('50', intl: false), 50);
      expect(Fmt.typedToBrl('10,50', intl: false), 10.5);
    });

    test('typedToBrl no intl converte US\$ → BRL do ledger', () {
      Fmt.usdPerBrl = 0.20; // 1 USD = 5 BRL
      expect(Fmt.typedToBrl('50', intl: true), closeTo(250, 0.0001));
      expect(Fmt.typedToBrl('10,50', intl: true), closeTo(52.5, 0.0001));
      expect(Fmt.typedToBrl('abc', intl: true), 0);
    });

    test('typedToBrl no intl arredonda ao centavo', () {
      Fmt.usdPerBrl = 0.18; // 50 / 0,18 = 277,777...
      expect(Fmt.typedToBrl('50', intl: true), 277.78);
    });

    test('typedToBrl sem intl explícito segue o build (BR nos testes)', () {
      expect(Fmt.typedToBrl('50'), 50);
    });

    test('xrp converte BRL pela cotação e mostra 2 casas', () {
      Fmt.xrpPerBrl = 0.08; // 1 BRL = 0,08 XRP
      expect(Fmt.xrp(100), '8.00');
    });

    test('typedToBrl no BR também arredonda ao centavo', () {
      // O ledger não guarda fração de centavo ("10,555" não vira 10,555).
      expect(Fmt.typedToBrl('10,555', intl: false), 10.56);
      expect(Fmt.typedToBrl('150,50', intl: false), 150.5);
    });

    test('ceilCents sobe ao centavo sem pular por ruído', () {
      expect(Fmt.ceilCents(99.991), 100.0);
      expect(Fmt.ceilCents(100.0), 100.0);
      expect(Fmt.ceilCents(100.0000000001), 100.0);
    });

    test('saque em US\$: o mínimo anunciado nunca vira menos de R\$100', () {
      // O servidor anuncia o mínimo arredondado para cima (+1%); o app
      // converte de volta arredondando para cima. Com qualquer cotação do
      // app perto da do servidor, o resultado fica ≥ R$100.
      for (var r = 4.0; r <= 7.0; r += 0.05) {
        Fmt.usdPerBrl = 1 / r;
        final minUsd = ((100 / r) * 1.01 * 100).ceil() / 100;
        expect(Fmt.ceilCents(Fmt.usdToBrl(minUsd)),
            greaterThanOrEqualTo(100.0),
            reason: 'cotação $r');
      }
      Fmt.usdPerBrl = 0.18;
    });
  });
}
