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
      final authRepo = FirebaseAuthRepository(FirebaseAuth.instance);
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
      backgroundColor: const Color(0xFFF0F4FF),
      body: SafeArea(
        child: WebFrame(
          maxWidth: 420,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 32),

                // ── Hero card ─────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(32, 44, 32, 44),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF001830),
                        Color(0xFF003b8a),
                        Color(0xFF0077cc),
                      ],
                      stops: [0.0, 0.55, 1.0],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF003b8a).withValues(alpha: 0.40),
                        blurRadius: 40,
                        offset: const Offset(0, 16),
                      ),
                      BoxShadow(
                        color: const Color(0xFF0cc0df).withValues(alpha: 0.15),
                        blurRadius: 60,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Logo renderizado em branco sobre o gradiente
                      ColorFiltered(
                        colorFilter: const ColorFilter.mode(
                          Colors.white,
                          BlendMode.srcIn,
                        ),
                        child: Image.asset(
                          'assets/images/logo_stacked.png',
                          height: 170,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 28,
                            height: 1,
                            color: Colors.white24,
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Vença desafios, fature muito!',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white60,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            width: 28,
                            height: 1,
                            color: Colors.white24,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // ── Botão Google ──────────────────────────────────────
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.asset(
                                  'assets/images/google.png',
                                  height: 22,
                                ),
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

                const SizedBox(height: 16),
                const Text(
                  'Apenas para usuários no Brasil · +18 anos',
                  style: TextStyle(fontSize: 11, color: Colors.black38),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
