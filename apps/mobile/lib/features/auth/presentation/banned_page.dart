import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BannedPage extends StatelessWidget {
  final String? reason;

  const BannedPage({super.key, this.reason});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.block, size: 72, color: Colors.red),
                const SizedBox(height: 24),
                const Text(
                  'Conta suspensa',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  reason ?? 'Sua conta foi suspensa por violação dos termos de uso.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 32),
                OutlinedButton(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  child: const Text('Sair'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
