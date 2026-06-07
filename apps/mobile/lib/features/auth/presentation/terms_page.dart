import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/widgets/web_frame.dart';

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
    return d.length == 10 || d.length == 11;
  }

  Future<void> _accept() async {
    if (!_phoneValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um telefone válido (com DDD)')),
      );
      return;
    }
    if (!_accepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Você precisa aceitar as políticas')),
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
          SnackBar(content: Text('Erro: ${e.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
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
          title: const Text('Boas-vindas'),
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
                      const Text(
                        'Bem-vindo ao Desafio Pago',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Falta pouco! Confirme seu telefone e aceite nossas '
                        'políticas para começar.',
                        style: TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 20),

                      // ── Telefone ──────────────────────────────────────────
                      TextField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(11),
                        ],
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Telefone (com DDD)',
                          hintText: '11999998888',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.phone),
                        ),
                      ),
                      const SizedBox(height: 24),

                      const Text(
                        'Termos de Uso e Política de Privacidade',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      const _TermsItem(
                        title: '1. Elegibilidade',
                        body:
                            'Uso exclusivo para maiores de 18 anos residentes '
                            'no Brasil.',
                      ),
                      const _TermsItem(
                        title: '2. Créditos e pagamentos',
                        body:
                            'Créditos são adquiridos via Pix e não são '
                            'reembolsáveis. Saques têm taxa de 10% e mínimo de '
                            'R\$100.',
                      ),
                      const _TermsItem(
                        title: '3. Desafios e votos',
                        body:
                            'Ao criar um desafio o prêmio é debitado na hora e '
                            'não pode ser cancelado. Cada usuário tem 1 voto por '
                            'desafio e o criador não vota no próprio.',
                      ),
                      const _TermsItem(
                        title: '4. Conteúdo',
                        body:
                            'É proibido conteúdo ofensivo, ilegal ou que viole '
                            'direitos de terceiros, sob pena de banimento.',
                      ),
                      const _TermsItem(
                        title: '5. Dados pessoais (LGPD)',
                        body:
                            'Coletamos nome, e-mail, telefone e foto para operar '
                            'a plataforma, comunicar você e cumprir obrigações '
                            'legais. Base legal: execução do contrato, '
                            'consentimento e legítimo interesse.',
                      ),
                      const _TermsItem(
                        title: '6. Marketing e publicidade',
                        body:
                            'Você concorda que seus dados de contato (e-mail e '
                            'telefone) possam ser usados para anúncios e '
                            'remarketing, inclusive o envio de forma '
                            'criptografada (hash) ao Google Ads e à Meta '
                            '(Facebook/Instagram) para criação de públicos. '
                            'Não vendemos seus dados.',
                      ),
                      const _TermsItem(
                        title: '7. Seus direitos',
                        body:
                            'Você pode acessar, corrigir ou excluir seus dados e '
                            'revogar o consentimento a qualquer momento, '
                            'excluindo a conta no app ou falando com o suporte.',
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Última atualização: Junho de 2026',
                        style:
                            TextStyle(fontSize: 11, color: Colors.black38),
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
                        title: const Text(
                          'Li e aceito os Termos de Uso e a Política de '
                          'Privacidade, incluindo o uso dos meus dados para '
                          'campanhas.',
                          style: TextStyle(fontSize: 13),
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
                              : const Text('Concluir cadastro'),
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
