import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/config/app_config.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/widgets/web_frame.dart';

// Termos por região. BR (Pix/LGPD) e internacional (cripto/genérico).
const _termsBr = [
  ('1. Elegibilidade',
      'Uso exclusivo para maiores de 18 anos residentes no Brasil.'),
  ('2. Créditos e pagamentos',
      'Créditos são adquiridos via Pix e não são reembolsáveis. Saques têm '
          'taxa de 10% e mínimo de R\$100.'),
  ('3. Desafios e votos',
      'Ao criar um desafio o prêmio é debitado na hora e não pode ser '
          'cancelado. Cada usuário tem 1 voto por desafio e o criador não '
          'vota no próprio.'),
  ('4. Conteúdo',
      'É proibido conteúdo ofensivo, ilegal ou que viole direitos de '
          'terceiros, sob pena de banimento.'),
  ('5. Dados pessoais (LGPD)',
      'Coletamos nome, e-mail, telefone e foto para operar a plataforma, '
          'comunicar você e cumprir obrigações legais. Base legal: execução '
          'do contrato, consentimento e legítimo interesse.'),
  ('6. Marketing e publicidade',
      'Você concorda que seus dados de contato possam ser usados para '
          'anúncios e remarketing, inclusive o envio de forma criptografada '
          '(hash) ao Google Ads e à Meta para criação de públicos. Não '
          'vendemos seus dados.'),
  ('7. Seus direitos',
      'Você pode acessar, corrigir ou excluir seus dados e revogar o '
          'consentimento a qualquer momento, excluindo a conta no app ou '
          'falando com o suporte.'),
];

const _termsIntl = [
  ('1. Eligibility',
      'For users aged 18 or older. Void where prohibited by local law.'),
  ('2. Credits and payments',
      'Credits are purchased via PayPal and are non-refundable. Withdrawals '
          'are paid in crypto (XRP) with a 10% fee. Crypto values fluctuate '
          'with the market.'),
  ('3. Challenges and votes',
      'When you create a challenge the prize is charged immediately and '
          'cannot be cancelled. Each user gets 1 vote per challenge and the '
          'creator cannot vote on their own.'),
  ('4. Content',
      'Offensive, illegal or infringing content is prohibited and may lead '
          'to a ban.'),
  ('5. Personal data',
      'We collect your name, email, phone and photo to operate the platform, '
          'communicate with you and meet legal obligations.'),
  ('6. Marketing',
      'You agree that your contact data may be used for advertising and '
          'remarketing, including hashed uploads to Google Ads and Meta for '
          'audience building. We do not sell your data.'),
  ('7. Your rights',
      'You can access, correct or delete your data and withdraw consent at '
          'any time by deleting your account in the app or contacting '
          'support.'),
];

class TermsPage extends StatefulWidget {
  final VoidCallback onAccepted;
  const TermsPage({super.key, required this.onAccepted});

  @override
  State<TermsPage> createState() => _TermsPageState();
}

class _TermsPageState extends State<TermsPage> {
  final _phone = TextEditingController();
  bool _accepted = false;
  bool _saving = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  bool get _phoneValid {
    final d = _phone.text.replaceAll(RegExp(r'\D'), '');
    // BR: 10-11 dígitos (DDD). Internacional: aceita 7-15 dígitos (E.164).
    return AppConfig.intl
        ? (d.length >= 7 && d.length <= 15)
        : (d.length == 10 || d.length == 11);
  }

  Future<void> _accept() async {
    if (!_phoneValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(I18n.tr('phone_invalid'))),
      );
      return;
    }
    if (!_accepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(I18n.tr('must_accept'))),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('acceptTerms')
          .call({'phone': _phone.text.replaceAll(RegExp(r'\D'), '')});
      widget.onAccepted();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${I18n.tr('terms_error')}: ${e.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${I18n.tr('terms_error')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text(I18n.tr('welcome')),
          automaticallyImplyLeading: false,
        ),
        body: WebFrame(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppConfig.intl
                            ? 'Welcome to ${AppConfig.brand}'
                            : 'Bem-vindo ao ${AppConfig.brand}',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        I18n.tr('onboarding_sub'),
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 20),

                      // ── Telefone ──────────────────────────────────────────
                      TextField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          // BR: 11 dígitos (DDD+9). Intl: até 15 (E.164).
                          LengthLimitingTextInputFormatter(
                              AppConfig.intl ? 15 : 11),
                        ],
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: I18n.tr('phone_label'),
                          hintText: AppConfig.intl ? '15551234567' : '11999998888',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.phone),
                        ),
                      ),
                      const SizedBox(height: 24),

                      Text(
                        I18n.tr('terms_title'),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      // Termos por região (BR: Pix/LGPD · intl: cripto/EN).
                      for (final t in (AppConfig.intl ? _termsIntl : _termsBr))
                        _TermsItem(title: t.$1, body: t.$2),
                      const SizedBox(height: 4),
                      Text(
                        I18n.tr('terms_updated'),
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black38),
                      ),
                    ],
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    children: [
                      CheckboxListTile(
                        value: _accepted,
                        onChanged: (v) =>
                            setState(() => _accepted = v ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          I18n.tr('accept_checkbox'),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed:
                              (_saving || !_phoneValid || !_accepted)
                                  ? null
                                  : _accept,
                          child: _saving
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : Text(I18n.tr('finish_signup')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TermsItem extends StatelessWidget {
  final String title;
  final String body;
  const _TermsItem({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(body,
              style: const TextStyle(color: Colors.black54, height: 1.5)),
        ],
      ),
    );
  }
}
