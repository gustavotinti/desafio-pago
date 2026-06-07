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

/// Faz o login com Google e volta à raiz (o AuthGate exibe onboarding/MainShell).
/// Retorna `true` se o login foi concluído, `false` se cancelado.
Future<bool> startGoogleLogin(BuildContext context) async {
  final authUser =
      await FirebaseAuthRepository(FirebaseAuth.instance).signInWithGoogle();
  if (authUser == null) return false;
  await UserRepository().saveUser(authUser);
  if (!context.mounted) return true;
  // Remove rotas empilhadas (e a folha de login) para revelar o AuthGate.
  Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
  return true;
}

/// Botão branco no padrão Google (logo oficial + texto), com loading próprio.
class GoogleSignInButton extends StatefulWidget {
  final String label;
  const GoogleSignInButton({super.key, this.label = 'Entrar com Google'});

  @override
  State<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<GoogleSignInButton> {
  bool _loading = false;

  Future<void> _onTap() async {
    setState(() => _loading = true);
    try {
      await startGoogleLogin(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao entrar: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _loading ? null : _onTap,
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            padding: const EdgeInsets.symmetric(vertical: 15),
            side: BorderSide(color: Colors.grey.shade200),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: _loading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset('assets/images/google.png', height: 22),
                    const SizedBox(width: 12),
                    Text(
                      widget.label,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _LoginSheet extends StatelessWidget {
  final String? message;
  const _LoginSheet({this.message});

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
              message ?? 'Entre para participar',
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
            const GoogleSignInButton(),
          ],
        ),
      ),
    );
  }
}
