import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/open_url_stub.dart'
    if (dart.library.js_interop) '../../../core/utils/open_url_web.dart';
import '../../../core/widgets/web_frame.dart';

/// Depósito internacional via PayPal (trialspaid.web.app).
/// Fluxo: cria a ordem → abre a aprovação do PayPal em nova aba → usuário
/// volta e confirma → capturamos no servidor e o saldo é creditado
/// (convertido na cotação de mercado; exibido em US$/XRP).
class PaypalTopUpPage extends StatefulWidget {
  const PaypalTopUpPage({super.key});

  @override
  State<PaypalTopUpPage> createState() => _PaypalTopUpPageState();
}

class _PaypalTopUpPageState extends State<PaypalTopUpPage> {
  final _amountCtrl = TextEditingController();
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  bool _loading = false;
  String? _orderId; // preenchido depois de abrir o PayPal

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final usd = double.tryParse(_amountCtrl.text.trim().replaceAll(',', '.'));
    if (usd == null || usd < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(I18n.tr('invalid_value'))));
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await _functions
          .httpsCallable('paypalCreateOrder')
          .call({'amountUsd': usd});
      final data = Map<String, dynamic>.from(res.data as Map);
      final approveUrl = data['approveUrl'] as String?;
      if (approveUrl != null) openExternalUrl(approveUrl);
      if (!mounted) return;
      setState(() => _orderId = data['orderId'] as String?);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(I18n.tr('paypal_opened'))));
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message ?? 'Error')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm() async {
    if (_orderId == null) return;
    setState(() => _loading = true);
    try {
      final res = await _functions
          .httpsCallable('paypalCaptureOrder')
          .call({'orderId': _orderId});
      final data = Map<String, dynamic>.from(res.data as Map);
      if (!mounted) return;
      if (data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(I18n.tr('deposit_success'))));
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(I18n.tr('deposit_not_completed'))));
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message ?? 'Error')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usd = double.tryParse(
            _amountCtrl.text.trim().replaceAll(',', '.')) ??
        0;
    final xrp = usd > 0 ? Fmt.xrp(Fmt.usdToBrl(usd)) : null;
    return Scaffold(
      appBar: AppBar(title: Text(I18n.tr('deposit_paypal_title'))),
      body: WebFrame(
        maxWidth: 440,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixText: '\$ ',
                labelText: I18n.tr('deposit_amount_usd'),
                helperText: xrp == null
                    ? null
                    : I18n.trp('xrp_balance_note', {'xrp': xrp}),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              I18n.tr('deposit_paypal_note'),
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading ? null : _start,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF003087), // azul PayPal
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: _loading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.account_balance_wallet),
                label: Text(I18n.tr('pay_with_paypal')),
              ),
            ),
            if (_orderId != null) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _confirm,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(I18n.tr('i_have_paid')),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
