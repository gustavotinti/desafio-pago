import 'package:flutter/material.dart';

import 'payment_page.dart';
import '../infrastructure/payment_repository.dart';

class TopUpPage extends StatefulWidget {
  const TopUpPage({super.key});

  @override
  State<TopUpPage> createState() => _TopUpPageState();
}

class _TopUpPageState extends State<TopUpPage> {
  final _amountController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Valor mínimo R\$1,00')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final data = await PaymentRepository().createPixPayment(amount);
      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentPage(
            paymentId: data['paymentId'] as String,
            qrCode: data['qrCode'] as String,
            qrCodeBase64: data['qrCodeBase64'] as String,
            amount: amount,
            expiresAt: DateTime.parse(data['expiresAt'] as String),
          ),
        ),
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Adicionar créditos')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Quanto deseja adicionar?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: const InputDecoration(
                prefixText: 'R\$ ',
                labelText: 'Valor',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'O pagamento é via Pix e confirmado em segundos.',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _continue,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Gerar QR Code Pix'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
