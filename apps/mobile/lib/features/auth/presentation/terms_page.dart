import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TermsPage extends StatefulWidget {
  final VoidCallback onAccepted;
  const TermsPage({super.key, required this.onAccepted});

  @override
  State<TermsPage> createState() => _TermsPageState();
}

class _TermsPageState extends State<TermsPage> {
  bool _saving = false;

  Future<void> _accept() async {
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'termsAccepted': true}, SetOptions(merge: true));
      widget.onAccepted();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao aceitar termos: $e')),
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
        appBar: AppBar(title: const Text('Termos de Uso')),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Bem-vindo ao Desafio Pago',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Ao usar este aplicativo, você concorda com os seguintes termos:',
                      style: TextStyle(color: Colors.black54),
                    ),
                    SizedBox(height: 16),
                    _TermsItem(
                      title: '1. Elegibilidade',
                      body:
                          'O app é destinado exclusivamente a usuários no Brasil, maiores de 18 anos.',
                    ),
                    _TermsItem(
                      title: '2. Créditos e pagamentos',
                      body:
                          'Os créditos são adquiridos via Pix e não são reembolsáveis. Saques estão sujeitos a uma taxa de 10% e valor mínimo de R\$100.',
                    ),
                    _TermsItem(
                      title: '3. Desafios',
                      body:
                          'Ao criar um desafio, o valor do prêmio é debitado do seu saldo imediatamente e não pode ser cancelado ou reembolsado.',
                    ),
                    _TermsItem(
                      title: '4. Conteúdo',
                      body:
                          'É proibido publicar conteúdo ofensivo, ilegal ou que viole direitos de terceiros. Conteúdo impróprio pode resultar em banimento.',
                    ),
                    _TermsItem(
                      title: '5. Votos',
                      body:
                          'Cada usuário tem direito a um voto por desafio. O criador do desafio não pode votar no próprio desafio.',
                    ),
                    _TermsItem(
                      title: '6. Privacidade',
                      body:
                          'Seus dados são usados exclusivamente para operar a plataforma. Não compartilhamos informações pessoais com terceiros.',
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Última atualização: Janeiro de 2025',
                      style: TextStyle(fontSize: 11, color: Colors.black38),
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _accept,
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Li e aceito os Termos de Uso'),
                  ),
                ),
              ),
            ),
          ],
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
