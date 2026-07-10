import 'dart:convert';

import 'package:http/http.dart' as http;

import 'format.dart';

/// Carrega as cotações de mercado (CoinGecko, grátis e com CORS liberado)
/// usadas pelo build INTERNACIONAL: preço do XRP em USD e BRL — de onde
/// derivam USD/BRL (exibição) e BRL→XRP (saldo/saque em cripto).
/// Falha silenciosa: mantém os fallbacks conservadores do Fmt.
Future<void> loadIntlRates() async {
  try {
    final r = await http
        .get(Uri.parse('https://api.coingecko.com/api/v3/simple/price'
            '?ids=ripple&vs_currencies=usd,brl'))
        .timeout(const Duration(seconds: 8));
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final xrpUsd = ((j['ripple'] as Map)['usd'] as num).toDouble();
    final xrpBrl = ((j['ripple'] as Map)['brl'] as num).toDouble();
    if (xrpUsd > 0 && xrpBrl > 0) {
      Fmt.usdPerBrl = xrpUsd / xrpBrl;
      Fmt.xrpPerBrl = 1 / xrpBrl;
    }
  } catch (_) {
    // sem rede/limite: usa fallback estático do Fmt
  }
}
