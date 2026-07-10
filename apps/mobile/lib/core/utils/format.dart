import 'package:intl/intl.dart';

import '../config/app_config.dart';

/// Number/currency formatting used throughout the app.
///
/// No build INTERNACIONAL, todos os valores (que internamente continuam no
/// ledger em BRL) são EXIBIDOS em dólar (US$) usando a cotação de mercado
/// carregada no arranque — um único ponto de conversão para o app inteiro.
class Fmt {
  Fmt._();

  // Cotações (atualizadas no arranque via CoinGecko; fallback conservador).
  // usdPerBrl: quantos USD vale 1 BRL · xrpPerBrl: quantos XRP vale 1 BRL.
  static double usdPerBrl = 0.18;
  static double xrpPerBrl = 0.08;

  static final _brl = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$ ',
    decimalDigits: 2,
  );

  static final _brlCompact = NumberFormat.compactCurrency(
    locale: 'pt_BR',
    symbol: 'R\$ ',
    decimalDigits: 1,
  );

  static final _usd = NumberFormat.currency(
    locale: 'en_US',
    symbol: '\$',
    decimalDigits: 2,
  );

  static final _usdCompact = NumberFormat.compactCurrency(
    locale: 'en_US',
    symbol: '\$',
    decimalDigits: 1,
  );

  static final _num = NumberFormat.decimalPattern('pt_BR');
  static final _numEn = NumberFormat.decimalPattern('en_US');

  /// Moeda cheia. BR: "R$ 1.557.280,00" · Intl: "$280,310.40" (convertido).
  static String brl(num value) => AppConfig.intl
      ? _usd.format(value * usdPerBrl)
      : _brl.format(value);

  /// Moeda compacta. BR: "R$ 1,6 M" · Intl: "$280.3K".
  static String brlCompact(num value) => AppConfig.intl
      ? _usdCompact.format(value * usdPerBrl)
      : _brlCompact.format(value);

  /// Número simples com separador de milhar.
  static String number(num value) =>
      AppConfig.intl ? _numEn.format(value) : _num.format(value);

  /// Equivalente em XRP de um valor do ledger (BRL interno).
  static String xrp(num valueBrl) =>
      (valueBrl * xrpPerBrl).toStringAsFixed(2);

  /// Converte USD digitado pelo usuário para o ledger (BRL interno).
  static double usdToBrl(num usd) =>
      usdPerBrl > 0 ? usd / usdPerBrl : usd * 5.5;
}
