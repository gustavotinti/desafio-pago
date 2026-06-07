import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/web_frame.dart';
import '../../payments/infrastructure/payment_repository.dart';
import '../../payments/presentation/payment_page.dart';
import '../infrastructure/verification_repository.dart';

class VerificationRequestPage extends StatefulWidget {
  final String currentName;
  const VerificationRequestPage({super.key, this.currentName = ''});

  @override
  State<VerificationRequestPage> createState() =>
      _VerificationRequestPageState();
}

class _VerificationRequestPageState extends State<VerificationRequestPage> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _cpf = TextEditingController();
  final _repo = VerificationRepository();

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Pré-preenche nome/sobrenome a partir do nome do perfil.
    final parts = widget.currentName.trim().split(RegExp(r'\s+'));
    if (parts.isNotEmpty && parts.first.isNotEmpty) {
      _firstName.text = parts.first;
      if (parts.length > 1) _lastName.text = parts.sublist(1).join(' ');
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _cpf.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_firstName.text.trim().length < 2) return 'Informe seu nome';
    if (_lastName.text.trim().length < 2) return 'Informe seu sobrenome';
    final phoneDigits = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (phoneDigits.length < 10 || phoneDigits.length > 11) {
      return 'Telefone inválido (com DDD)';
    }
    final cpfDigits = _cpf.text.replaceAll(RegExp(r'\D'), '');
    if (cpfDigits.length != 11) return 'CPF deve ter 11 dígitos';
    return null;
  }

  Future<void> _submit() async {
    final err = _validate();
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
      return;
    }

    setState(() => _loading = true);
    try {
      await _repo.submit(
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        phone: _phone.text.replaceAll(RegExp(r'\D'), ''),
        cpf: _cpf.text.replaceAll(RegExp(r'\D'), ''),
      );
      if (!mounted) return;
      await _afterSubmit();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('[firebase_functions/', '['))),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _afterSubmit() async {
    final goPriority = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pedido enviado! ✅'),
        content: const Text(
          'Seu pedido entrou na fila de análise.\n\n'
          'Quer entrar na FILA PRIORITÁRIA por R\$ 500,00 via Pix? '
          'Pedidos prioritários são analisados primeiro.\n\n'
          'A taxa não é reembolsável e não garante a aprovação.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Agora não'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Fila prioritária'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (goPriority == true) {
      await _startPriorityPayment();
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _startPriorityPayment() async {
    try {
      final data = await PaymentRepository()
          .createPixPayment(500, purpose: 'verification_priority');
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentPage(
            paymentId: data['paymentId'] as String,
            qrCode: data['qrCode'] as String,
            qrCodeBase64: data['qrCodeBase64'] as String,
            amount: 500,
            expiresAt: DateTime.parse(data['expiresAt'] as String),
            successTitle: '⭐ Fila prioritária confirmada!',
            successMessage:
                'Seu pedido de verificação entrou na fila prioritária '
                'e será analisado primeiro.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pedir selo verificado')),
      body: WebFrame(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: const Row(
                children: [
                  Icon(Icons.verified, color: Colors.blue),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Preencha seus dados para análise. Eles ficam visíveis '
                      'apenas para a equipe de moderação.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _firstName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nome',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _lastName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Sobrenome',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              decoration: const InputDecoration(
                labelText: 'Telefone (com DDD)',
                hintText: '11999998888',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _cpf,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              decoration: const InputDecoration(
                labelText: 'CPF (somente números)',
                hintText: '00000000000',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enviar pedido'),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Opcional: após enviar, você pode entrar na fila prioritária '
              'por R\$ 500,00 (Pix) para ser analisado primeiro.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
