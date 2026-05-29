import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../auth/infrastructure/firebase_auth_repository.dart';
import '../../users/infrastructure/user_repository.dart';
import '../../../core/widgets/web_frame.dart';

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
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // ── Decorative blob — top-right outer ─────────────────────
          Positioned(
            top: -90, right: -90,
            child: Container(
              width: 260, height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF003b8a).withValues(alpha: 0.06),
              ),
            ),
          ),
          // ── Decorative blob — top-right inner ─────────────────────
          Positioned(
            top: -30, right: -30,
            child: Container(
              width: 130, height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0cc0df).withValues(alpha: 0.09),
              ),
            ),
          ),
          // ── Decorative blob — bottom-left ─────────────────────────
          Positioned(
            bottom: 50, left: -70,
            child: Container(
              width: 200, height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF003b8a).withValues(alpha: 0.05),
              ),
            ),
          ),
          // ── Decorative blob — bottom-right accent ─────────────────
          Positioned(
            bottom: -20, right: -20,
            child: Container(
              width: 110, height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFff00bf).withValues(alpha: 0.06),
              ),
            ),
          ),

          // ── Main content ──────────────────────────────────────────
          SafeArea(
            child: WebFrame(
              maxWidth: 420,
              child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  const Spacer(flex: 2),

                  // Logo
                  Image.asset(
                    'assets/images/logo_stacked.png',
                    height: 200,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Vença desafios, fature muito!',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.black54,
                      letterSpacing: 0.3,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const Spacer(flex: 3),

                  // Google sign-in button with elevation shadow
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.09),
                          blurRadius: 18,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _loading ? null : _signIn,
                        child: _loading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Image.asset(
                                      'assets/images/google.png',
                                      height: 22),
                                  const SizedBox(width: 12),
                                  const Text(
                                    'Entrar com Google',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  const Text(
                    'Apenas para usuários no Brasil · +18 anos',
                    style:
                        TextStyle(fontSize: 11, color: Colors.black38),
                    textAlign: TextAlign.center,
                  ),

                  const Spacer(flex: 1),
                ],
              ),
            ),
          ),
        ),
        ],
      ),
    );
  }
}
