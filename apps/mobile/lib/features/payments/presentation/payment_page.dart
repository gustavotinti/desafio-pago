import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/widgets/web_frame.dart';

class PaymentPage extends StatefulWidget {
  final String paymentId;
  final String qrCode;
  final String qrCodeBase64;
  final double amount;
  final DateTime expiresAt;
  final String successTitle;
  final String? successMessage;

  const PaymentPage({
    super.key,
    required this.paymentId,
    required this.qrCode,
    required this.qrCodeBase64,
    required this.amount,
    required this.expiresAt,
    this.successTitle = 'Pagamento confirmado!',
    this.successMessage,
  });

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  StreamSubscription? _statusSub;
  String _status = 'pending';
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    _listenToStatus();
  }

  void _listenToStatus() {
    _statusSub = FirebaseFirestore.instance
        .collection('payments')
        .doc(widget.paymentId)
        .snapshots()
        .listen((doc) {
      if (!doc.exists) return;
      final status = doc.data()?['status'] as String? ?? 'pending';
      if (!mounted) return;
      setState(() => _status = status);
      if (status == 'approved' && !_confirmed) {
        _confirmed = true;
        _showSuccess();
      }
    });
  }

  void _showSuccess() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(widget.successTitle),
        content: Text(
          widget.successMessage ??
              'R\$ ${widget.amount.toStringAsFixed(2)} adicionados aos seus créditos.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.qrCode));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Código Pix copiado!')),
    );
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }

  Duration get _timeLeft => widget.expiresAt.difference(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final expired = _timeLeft.isNegative;
    final qrBytes = base64Decode(widget.qrCodeBase64);

    return Scaffold(
      appBar: AppBar(title: const Text('Pagar via Pix')),
      body: WebFrame(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'R\$ ${widget.amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (_status == 'approved')
                  const Chip(
                    label: Text('Pago'),
                    backgroundColor: Colors.green,
                    labelStyle: TextStyle(color: Colors.white),
                  )
                else if (expired)
                  const Chip(
                    label: Text('Expirado'),
                    backgroundColor: Colors.red,
                    labelStyle: TextStyle(color: Colors.white),
                  )
                else
                  const Chip(label: Text('Aguardando pagamento')),
                const SizedBox(height: 24),
                if (!expired && _status != 'approved') ...[
                  Image.memory(qrBytes, width: 240, height: 240),
                  const SizedBox(height: 16),
                  const Text(
                    'Escaneie o QR Code com o app do seu banco\nou copie o código Pix abaixo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _copyCode,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copiar código Pix'),
                  ),
                  const SizedBox(height: 12),
                  _CountdownTimer(expiresAt: widget.expiresAt),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountdownTimer extends StatefulWidget {
  final DateTime expiresAt;
  const _CountdownTimer({required this.expiresAt});

  @override
  State<_CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<_CountdownTimer> {
  late Timer _timer;
  late Duration _left;

  @override
  void initState() {
    super.initState();
    _left = widget.expiresAt.difference(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(
          () => _left = widget.expiresAt.difference(DateTime.now()));
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_left.isNegative) return const SizedBox.shrink();
    final m = _left.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _left.inSeconds.remainder(60).toString().padLeft(2, '0');
    return Text(
      'Expira em $m:$s',
      style: const TextStyle(color: Colors.black54, fontSize: 13),
    );
  }
}
