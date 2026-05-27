import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../auth/infrastructure/firebase_auth_repository.dart';
import '../../users/infrastructure/user_repository.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _loading = false;

  Future<void> _signIn() async {
    setState(() => _loading = true);
    try {
      final authRepo =
          FirebaseAuthRepository(FirebaseAuth.instance);
      final authUser = await authRepo.signInWithGoogle();

      if (authUser == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Login cancelado')),
          );
        }
        return;
      }

      await UserRepository().saveUser(authUser);
      // AuthGate handles navigation automatically
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // — Logo —
              Image.asset(
                'assets/images/logo_stacked.png',
                height: 200,
              ),
              const SizedBox(height: 12),
              const Text(
                'Vença desafios, fature muito!',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black54,
                ),
              ),

              const Spacer(flex: 3),

              // — Botão Google —
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Colors.black26),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _loading ? null : _signIn,
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset('assets/images/google.png',
                                height: 22),
                            const SizedBox(width: 12),
                            const Text(
                              'Entrar com Google',
                              style: TextStyle(fontSize: 15),
                            ),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 16),
              const Text(
                'Apenas para usuários no Brasil · +18 anos',
                style: TextStyle(fontSize: 11, color: Colors.black38),
                textAlign: TextAlign.center,
              ),

              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }
}
