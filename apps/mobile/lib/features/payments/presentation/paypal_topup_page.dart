import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/local_store_stub.dart'
    if (dart.library.js_interop) '../../../core/utils/local_store_web.dart';
import '../../../core/utils/open_url_stub.dart'
    if (dart.library.js_interop) '../../../core/utils/open_url_web.dart';
import '../../../core/widgets/web_frame.dart';

/// Depósito internacional via PayPal (trialspaid.web.app).
/// Fluxo: cria a ordem → abre a aprovação do PayPal em nova aba → usuário
/// volta e confirma → capturamos no servidor e o saldo é creditado
/// (convertido na cotação de mercado; exibido em US$/XRP).
///
/// A ordem aberta fica salva no navegador ([PaypalPendingOrder]): se o
/// usuário recarregar/fechar a aba ou voltar pelo return_url do PayPal numa
/// aba nova, a tela ainda oferece "confirmar" (senão o pagamento aprovado
/// nunca era capturado).
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
  String? _approveUrl; // para reabrir a aprovação (popup bloqueado etc.)
  bool _restored = false; // ordem recuperada de uma sessão anterior

  @override
  void initState() {
    super.initState();
    final pending = PaypalPendingOrder.read();
    if (pending != null) {
      _orderId = pending.orderId;
      _approveUrl = pending.approveUrl;
      _restored = true;
    }
  }

  void _forgetOrder() {
    PaypalPendingOrder.clear();
    if (!mounted) return;
    setState(() {
      _orderId = null;
      _approveUrl = null;
      _restored = false;
    });
  }

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
          .call({'amountUsd': usd, 'lang': 'en'});
      final data = Map<String, dynamic>.from(res.data as Map);
      final approveUrl = data['approveUrl'] as String?;
      final orderId = data['orderId'] as String?;
      // Salva ANTES de abrir o PayPal: se a aba recarregar (ou o usuário
      // voltar pelo return_url numa aba nova), a ordem não se perde.
      if (orderId != null) PaypalPendingOrder.save(orderId, approveUrl);
      if (approveUrl != null) openExternalUrl(approveUrl);
      if (!mounted) return;
      setState(() {
        _orderId = orderId;
        _approveUrl = approveUrl;
        _restored = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(I18n.tr('paypal_opened'))));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(e, serverLocalized: true))));
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
          .call({'orderId': _orderId, 'lang': 'en'});
      final data = Map<String, dynamic>.from(res.data as Map);
      final status = data['status'] as String?;
      // Ordem morta no PayPal (cancelada/expirada): não há o que confirmar.
      final dead = status == 'VOIDED' || status == 'EXPIRED';
      // Creditado agora ou antes (alreadyCredited): limpa a pendência.
      if (data['success'] == true) PaypalPendingOrder.clear();
      if (!mounted) return;
      if (data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(I18n.tr('deposit_success'))));
        Navigator.pop(context, true);
      } else if (dead) {
        _forgetOrder();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(I18n.tr('paypal_order_expired'))));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(I18n.tr('deposit_not_completed'))));
      }
    } catch (e) {
      // Ordem inexistente/de outro usuário: descarta a pendência.
      if (e is FirebaseFunctionsException && e.code == 'not-found') {
        _forgetOrder();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(e, serverLocalized: true))));
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
            if (_restored && _orderId != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFE082)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.hourglass_top,
                        color: Color(0xFFB26A00), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        I18n.tr('paypal_pending_open'),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
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
              // Popup bloqueado / aba do PayPal fechada: reabre a aprovação.
              if (_approveUrl != null)
                TextButton(
                  onPressed:
                      _loading ? null : () => openExternalUrl(_approveUrl!),
                  child: Text(I18n.tr('paypal_reopen')),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Ordem PayPal aberta, persistida no navegador até ser capturada.
///
/// Só existe no build internacional (no BR nunca é lida nem gravada). Vale
/// para o usuário que a criou e por até 3h (depois disso a aprovação do
/// PayPal expira e a entrada é descartada).
class PaypalPendingOrder {
  const PaypalPendingOrder._(this.orderId, this.approveUrl);

  final String orderId;
  final String? approveUrl;

  static const _key = 'pendingPaypalOrder';
  static const _maxAge = Duration(hours: 3);

  static void save(String orderId, String? approveUrl) {
    if (!AppConfig.intl) return;
    localStoreWrite(
        _key,
        jsonEncode({
          'orderId': orderId,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'approveUrl': ?approveUrl,
          'uid': FirebaseAuth.instance.currentUser?.uid,
        }));
  }

  /// Ordem pendente válida do usuário logado, ou null.
  static PaypalPendingOrder? read() {
    if (!AppConfig.intl) return null;
    final raw = localStoreRead(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final orderId = m['orderId'] as String?;
      final createdAt = (m['createdAt'] as num?)?.toInt() ?? 0;
      final age = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(createdAt));
      if (orderId == null || orderId.isEmpty || age > _maxAge) {
        clear();
        return null;
      }
      // Outra conta no mesmo navegador: não oferece a ordem de outro usuário.
      final uid = m['uid'] as String?;
      if (uid != null && uid != FirebaseAuth.instance.currentUser?.uid) {
        return null;
      }
      return PaypalPendingOrder._(orderId, m['approveUrl'] as String?);
    } catch (_) {
      clear();
      return null;
    }
  }

  static void clear() {
    if (!AppConfig.intl) return;
    localStoreRemove(_key);
  }
}
