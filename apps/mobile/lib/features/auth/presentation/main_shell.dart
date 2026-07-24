import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'home_page.dart';
import 'auth_guard.dart';
import '../../../core/config/app_config.dart';
import '../../../core/deep_link.dart';
import '../../../core/i18n/i18n.dart';
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

  static const _version = '${AppConfig.brand} v3.5.0';

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
          // ── Version + crédito do criador ────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              children: [
                const Text(
                  _version,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFFB0B8CC),
                    fontFamily: 'Garet',
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  '${I18n.tr('created_by')} ${AppConfig.creator}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFFB0B8CC),
                    fontFamily: 'Garet',
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),

          // ── Navigation bar ──────────────────────────────────────────
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.explore_outlined),
                selectedIcon: const Icon(Icons.explore),
                label: I18n.tr('tab_challenges'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.leaderboard_outlined),
                selectedIcon: const Icon(Icons.leaderboard),
                label: I18n.tr('tab_rankings'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.person_outline),
                selectedIcon: const Icon(Icons.person),
                label: I18n.tr('tab_profile'),
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
      appBar: AppBar(title: Text(I18n.tr('tab_profile'))),
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
            Text(
              I18n.tr('guest_title'),
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              I18n.tr('guest_sub'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.black54, fontSize: 14, height: 1.4),
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
              child: Column(
                children: [
                  _GuestBenefit(
                    icon: Icons.emoji_events,
                    color: const Color(0xFFF5A623),
                    title: I18n.tr('guest_b1_title'),
                    subtitle: I18n.tr('guest_b1_sub'),
                  ),
                  const Divider(height: 1),
                  _GuestBenefit(
                    icon: Icons.how_to_vote,
                    color: const Color(0xFF003b8a),
                    title: I18n.tr('guest_b2_title'),
                    subtitle: I18n.tr('guest_b2_sub'),
                  ),
                  const Divider(height: 1),
                  _GuestBenefit(
                    icon: Icons.add_circle,
                    color: const Color(0xFFff00bf),
                    title: I18n.tr('guest_b3_title'),
                    subtitle: I18n.tr('guest_b3_sub'),
                  ),
                  const Divider(height: 1),
                  _GuestBenefit(
                    icon: AppConfig.intl ? Icons.currency_bitcoin : Icons.pix,
                    color: const Color(0xFF00A86B),
                    title: I18n.tr('guest_b4_title'),
                    subtitle: I18n.tr('guest_b4_sub'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // — Botão oficial do Google —
            const GoogleSignInButton(),
            const SizedBox(height: 14),
            Text(
              I18n.tr('guest_footer'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.black38),
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
