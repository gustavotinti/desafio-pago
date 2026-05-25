import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../auth/infrastructure/firebase_auth_repository.dart';
import '../../users/infrastructure/user_repository.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final authRepo = FirebaseAuthRepository(FirebaseAuth.instance);
    final userRepo = UserRepository();

    return Scaffold(
      body: Center(
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Colors.grey),
            ),
          ),
          onPressed: () async {
            try {
              final authUser = await authRepo.signInWithGoogle();

              if (authUser == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Login cancelado")),
                );
                return;
              }

              await userRepo.saveUser(authUser);

              // 🚫 NÃO TEM MAIS Navigator aqui
              // O AuthGate cuida da navegação automaticamente
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Erro: $e")),
              );
            }
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/google.png',
                height: 20,
              ),
              const SizedBox(width: 10),
              const Text("Entrar com Google"),
            ],
          ),
        ),
      ),
    );
  }
}