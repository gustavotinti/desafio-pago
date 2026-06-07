import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../infrastructure/firebase_auth_repository.dart';
import '../../users/infrastructure/user_repository.dart';

/// Garante que há um usuário logado para executar uma ação que exige conta.
///
/// - Se já estiver logado, retorna `true` (a ação pode prosseguir).
/// - Se for visitante, abre o login. Após entrar, o app volta à raiz para o
///   onboarding (telefone + políticas), então retorna `false` — o usuário
///   refaz a ação depois de concluir o cadastro.
Future<bool> ensureLoggedIn(BuildContext context, {String? message}) async {
  if (FirebaseAuth.instance.currentUser != null) return true;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _LoginSheet(message: message),
  );
  return false;
}

class _LoginSheet extends StatefulWidget {
  final String? message;
  const _LoginSheet({this.message});

  @override
  State<_LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<_LoginSheet> {
  bool _loading = false;

  Future<void> _signIn() async {
    setState(() => _loading = true);
    try {
      final authUser = await FirebaseAuthRepository(FirebaseAuth.instance)
          .signInWithGoogle();
      if (authUser == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      await UserRepository().saveUser(authUser);
      if (!mounted) return;
      // Volta à raiz: o AuthGate reconstrói e exibe o onboarding/MainShell.
      Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao entrar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 36, color: Color(0xFF003b8a)),
            const SizedBox(height: 12),
            Text(
              widget.message ?? 'Entre para participar',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'Crie sua conta com o Google para participar dos desafios, '
              'votar, comentar e acessar seu perfil.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _loading ? null : _signIn,
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset('assets/images/google.png', height: 20),
                          const SizedBox(width: 10),
                          const Text(
                            'Entrar com Google',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.black87),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
