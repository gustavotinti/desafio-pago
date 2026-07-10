import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'home_page.dart';
import 'auth_guard.dart';
import '../../../core/deep_link.dart';
import '../../../core/widgets/web_frame.dart';
import '../../challenge/infrastructure/get_challenges.dart';
import '../../entry/presentation/challenge_entries_page.dart';
import '../../users/presentation/rankings_page.dart';
import 'profile_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _version = 'Desafio Pago v2.8.4';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _maybeOpenDeepLink());
  }

  // Abre direto a arte compartilhada (link com ?entry=...), pronta pra votar.
  Future<void> _maybeOpenDeepLink() async {
    if (PendingDeepLink.handled || !PendingDeepLink.hasLink) return;
    PendingDeepLink.handled = true;
    final challenge =
        await GetChallenges().getById(PendingDeepLink.challengeId!);
    if (challenge == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChallengeEntriesPage(
          challenge: challenge,
          highlightEntryId: PendingDeepLink.entryId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isGuest = FirebaseAuth.instance.currentUser == null;
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const HomePage(),
          const RankingsPage(),
          isGuest ? const _GuestProfile() : const ProfilePage(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Version label ───────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.only(top: 4),
            child: const Text(
              _version,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: Color(0xFFB0B8CC),
                fontFamily: 'Garet',
                letterSpacing: 0.3,
              ),
            ),
          ),

          // ── Navigation bar ──────────────────────────────────────────
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.explore_outlined),
                selectedIcon: Icon(Icons.explore),
                label: 'Desafios',
              ),
              NavigationDestination(
                icon: Icon(Icons.leaderboard_outlined),
                selectedIcon: Icon(Icons.leaderboard),
                label: 'Rankings',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Perfil',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Aba Perfil para visitantes (sem login) ──────────────────────────────────────

class _GuestProfile extends StatelessWidget {
  const _GuestProfile();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(title: const Text('Perfil')),
      body: WebFrame(
        maxWidth: 420,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          children: [
            // — Avatar com anel em gradiente —
            Center(
              child: Container(
                width: 116,
                height: 116,
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF003b8a), Color(0xFF0cc0df)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person_outline,
                      size: 54, color: Color(0xFF003b8a)),
                ),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Crie sua conta grátis',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Entre com o Google para participar dos desafios e '
              'acompanhar seus ganhos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 26),

            // — Benefícios —
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE9EEF6)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Column(
                children: [
                  _GuestBenefit(
                    icon: Icons.emoji_events,
                    color: Color(0xFFF5A623),
                    title: 'Ganhe prêmios em dinheiro',
                    subtitle: 'Participe e vença desafios pagos',
                  ),
                  Divider(height: 1),
                  _GuestBenefit(
                    icon: Icons.how_to_vote,
                    color: Color(0xFF003b8a),
                    title: 'Vote nos melhores',
                    subtitle: 'Ajude a escolher quem leva o prêmio',
                  ),
                  Divider(height: 1),
                  _GuestBenefit(
                    icon: Icons.add_circle,
                    color: Color(0xFFff00bf),
                    title: 'Crie seus desafios',
                    subtitle: 'Lance um prêmio e desafie a galera',
                  ),
                  Divider(height: 1),
                  _GuestBenefit(
                    icon: Icons.pix,
                    color: Color(0xFF00A86B),
                    title: 'Saque via Pix',
                    subtitle: 'Receba seus ganhos quando quiser',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // — Botão oficial do Google —
            const GoogleSignInButton(),
            const SizedBox(height: 14),
            const Text(
              'Apenas para usuários no Brasil · +18 anos',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.black38),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuestBenefit extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _GuestBenefit({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14.5)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        color: Colors.black54, fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
