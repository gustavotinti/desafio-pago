import 'package:intl/intl.dart';

/// Brazilian number/currency formatting utilities used throughout the app.
class Fmt {
  Fmt._();

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

  static final _num = NumberFormat.decimalPattern('pt_BR');

  /// Full currency: 1557280 → "R$ 1.557.280,00"
  static String brl(num value) => _brl.format(value);

  /// Compact currency: 1557280 → "R$ 1,6 M"
  static String brlCompact(num value) => _brlCompact.format(value);

  /// Plain number with thousands dots: 89432 → "89.432"
  static String number(num value) => _num.format(value);
}
