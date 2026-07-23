import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/web_frame.dart';
import 'admin_withdrawals_page.dart';
import 'admin_users_page.dart';
import 'admin_challenges_page.dart';
import 'admin_verification_page.dart';
import 'admin_virtual_users_page.dart';
import 'admin_audience_page.dart';
import 'admin_platform_page.dart';
import 'admin_seo_page.dart';
import 'admin_keys_page.dart';

const _superAdminEmail = 'gustavo.a.tinti3@gmail.com';

/// Painel Admin — hub com visão geral ao vivo (contadores), atalhos em grid
/// responsivo (2 colunas no desktop, 1 no celular), badges de pendências e
/// animações de entrada.
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  int? _activeChallenges;
  int? _pendingWithdrawals;
  int? _pendingVerifications;
  int? _pendingReports;
  double? _prizePool;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final db = FirebaseFirestore.instance;
    // Contagens em paralelo; cada uma falha sem derrubar as outras.
    Future<int?> count(Query<Map<String, dynamic>> q) async {
      try {
        return (await q.count().get()).count;
      } catch (_) {
        return null;
      }
    }

    final results = await Future.wait([
      count(db.collection('challenges').where('status', isEqualTo: 'active')),
      count(db.collection('withdrawals').where('status', isEqualTo: 'pending')),
      count(db
          .collection('verificationRequests')
          .where('status', isEqualTo: 'pending')),
      count(db.collection('reports').where('status', isEqualTo: 'pending')),
    ]);
    double? prize;
    try {
      final agg = await db
          .collection('challenges')
          .where('status', isEqualTo: 'active')
          .aggregate(sum('amount'))
          .get();
      prize = agg.getSum('amount');
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _activeChallenges = results[0];
      _pendingWithdrawals = results[1];
      _pendingVerifications = results[2];
      _pendingReports = results[3];
      _prizePool = prize;
    });
  }

  void _open(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page))
        .then((_) => _loadStats()); // volta → atualiza pendências
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Painel Admin')),
      body: WebFrame(
        maxWidth: 900,
        child: RefreshIndicator(
          onRefresh: _loadStats,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final twoCols = constraints.maxWidth > 620;
              final cardW = twoCols
                  ? (constraints.maxWidth - 32 - 12) / 2
                  : constraints.maxWidth - 32;

              var i = 0; // índice p/ animação escalonada
              Widget card({
                required IconData icon,
                required String title,
                required String subtitle,
                required List<Color> gradient,
                required Widget page,
                _Badge? badge,
              }) {
                return _Entrance(
                  index: i++,
                  child: SizedBox(
                    width: cardW,
                    child: _AdminCard(
                      icon: icon,
                      title: title,
                      subtitle: subtitle,
                      gradient: gradient,
                      badge: badge,
                      onTap: () => _open(page),
                    ),
                  ),
                );
              }

              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
                children: [
                  _Entrance(
                    index: i++,
                    child: _OverviewHeader(
                      activeChallenges: _activeChallenges,
                      prizePool: _prizePool,
                      pendingWithdrawals: _pendingWithdrawals,
                      pendingVerifications: _pendingVerifications,
                      pendingReports: _pendingReports,
                    ),
                  ),
                  const SizedBox(height: 18),

                  const _SectionLabel('Operações'),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      card(
                        icon: Icons.payments_rounded,
                        title: 'Saques',
                        subtitle: 'Aprovar, rejeitar e marcar como pago',
                        gradient: const [Color(0xFF00875A), Color(0xFF36B37E)],
                        badge: _pendingBadge(_pendingWithdrawals),
                        page: const AdminWithdrawalsPage(),
                      ),
                      card(
                        icon: Icons.verified_rounded,
                        title: 'Verificação',
                        subtitle: 'Pedidos de selo (prioritários primeiro)',
                        gradient: const [Color(0xFF3F51B5), Color(0xFF7986CB)],
                        badge: _pendingBadge(_pendingVerifications),
                        page: const AdminVerificationPage(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  const _SectionLabel('Conteúdo & plataforma'),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      card(
                        icon: Icons.emoji_events_rounded,
                        title: 'Desafios',
                        subtitle:
                            'Criar, editar, fixar "novo", encerrar e prazos',
                        gradient: const [Color(0xFF003b8a), Color(0xFF0cc0df)],
                        badge: _activeChallenges == null
                            ? null
                            : _Badge('$_activeChallenges ativos',
                                const Color(0xFF0cc0df)),
                        page: const AdminChallengesPage(),
                      ),
                      card(
                        icon: Icons.sensors_rounded,
                        title: 'Plataforma',
                        subtitle: 'Números do "Ao vivo" e rodapé de demanda',
                        gradient: const [Color(0xFFE65100), Color(0xFFFF9800)],
                        page: const AdminPlatformPage(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  const _SectionLabel('Pessoas'),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      card(
                        icon: Icons.admin_panel_settings_rounded,
                        title: 'Usuários',
                        subtitle: 'Moderadores, admins e banimentos',
                        gradient: const [Color(0xFFBF360C), Color(0xFFFF7043)],
                        page: const AdminUsersPage(),
                      ),
                      card(
                        icon: Icons.face_retouching_natural_rounded,
                        title: 'Editar perfis',
                        subtitle: 'Nome, @, bio, foto e selo — todos os perfis',
                        gradient: const [Color(0xFF00695C), Color(0xFF26A69A)],
                        page: const AdminVirtualUsersPage(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  const _SectionLabel('Marketing'),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      card(
                        icon: Icons.travel_explore_rounded,
                        title: 'SEO / Novidades',
                        subtitle:
                            'Artigos por IA, fila de temas e demanda do Google',
                        gradient: const [Color(0xFF1565C0), Color(0xFF42A5F5)],
                        page: const AdminSeoPage(),
                      ),
                      card(
                        icon: Icons.campaign_rounded,
                        title: 'Dados para campanhas',
                        subtitle: 'Exportar público p/ Google Ads e Meta (CSV)',
                        gradient: const [Color(0xFF6A1B9A), Color(0xFFAB47BC)],
                        page: const AdminAudiencePage(),
                      ),
                    ],
                  ),

                  // ── Sistema (super admin) ────────────────────────
                  if (FirebaseAuth.instance.currentUser?.email ==
                      _superAdminEmail) ...[
                    const SizedBox(height: 18),
                    const _SectionLabel('Sistema (super admin)'),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        card(
                          icon: Icons.vpn_key_rounded,
                          title: 'Chaves & integrações',
                          subtitle:
                              'Mercado Pago, PayPal e IA — com instruções',
                          gradient: const [
                            Color(0xFF37474F),
                            Color(0xFF78909C)
                          ],
                          page: const AdminKeysPage(),
                        ),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  _Badge? _pendingBadge(int? n) {
    if (n == null || n == 0) return null;
    return _Badge('$n pendente${n == 1 ? '' : 's'}', const Color(0xFFE53935));
  }
}

// ─── Visão geral (stats ao vivo com count-up) ────────────────────────────────

class _OverviewHeader extends StatelessWidget {
  final int? activeChallenges;
  final double? prizePool;
  final int? pendingWithdrawals;
  final int? pendingVerifications;
  final int? pendingReports;

  const _OverviewHeader({
    required this.activeChallenges,
    required this.prizePool,
    required this.pendingWithdrawals,
    required this.pendingVerifications,
    required this.pendingReports,
  });

  @override
  Widget build(BuildContext context) {
    final pendings = (pendingWithdrawals ?? 0) +
        (pendingVerifications ?? 0) +
        (pendingReports ?? 0);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E3A5F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.30),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.space_dashboard_rounded,
                  color: Color(0xFF0cc0df), size: 18),
              const SizedBox(width: 8),
              const Text(
                'VISÃO GERAL',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              if (pendings > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53935),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$pendings pendência${pendings == 1 ? '' : 's'}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                )
              else
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle,
                        color: Color(0xFF4ADE80), size: 14),
                    SizedBox(width: 4),
                    Text('Tudo em dia',
                        style: TextStyle(
                            color: Color(0xFF4ADE80),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _MiniStat(
                icon: Icons.local_fire_department_rounded,
                value: activeChallenges?.toDouble(),
                format: (v) => Fmt.number(v.round()),
                label: 'desafios ativos',
              ),
              _div(),
              _MiniStat(
                icon: Icons.emoji_events_rounded,
                value: prizePool,
                format: Fmt.brlCompact,
                label: 'em prêmios',
              ),
              _div(),
              _MiniStat(
                icon: Icons.payments_rounded,
                value: pendingWithdrawals?.toDouble(),
                format: (v) => Fmt.number(v.round()),
                label: 'saques pend.',
                alert: (pendingWithdrawals ?? 0) > 0,
              ),
              _div(),
              _MiniStat(
                icon: Icons.flag_rounded,
                value: pendingReports?.toDouble(),
                format: (v) => Fmt.number(v.round()),
                label: 'denúncias',
                alert: (pendingReports ?? 0) > 0,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _div() => Container(
        width: 1,
        height: 34,
        color: Colors.white.withValues(alpha: 0.15),
      );
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final double? value;
  final String Function(double) format;
  final String label;
  final bool alert;

  const _MiniStat({
    required this.icon,
    required this.value,
    required this.format,
    required this.label,
    this.alert = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = alert ? const Color(0xFFFF8A80) : Colors.white;
    final v = value;
    return Expanded(
      child: Column(
        children: [
          Icon(icon,
              color: alert ? const Color(0xFFFF8A80) : const Color(0xFF7DD3FC),
              size: 17),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: v == null
                ? Text('—',
                    style: TextStyle(
                        color: color,
                        fontSize: 16,
                        fontWeight: FontWeight.bold))
                : TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: v),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOut,
                    builder: (context, animated, _) => Text(
                      format(animated),
                      style: TextStyle(
                          color: color,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65), fontSize: 10),
          ),
        ],
      ),
    );
  }
}

// ─── Rótulo de seção ─────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 2),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: Colors.black45,
        ),
      ),
    );
  }
}

// ─── Badge (pendências / contagens) ──────────────────────────────────────────

class _Badge {
  final String text;
  final Color color;
  const _Badge(this.text, this.color);
}

// ─── Card de atalho (hover + gradiente no ícone) ─────────────────────────────

class _AdminCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final _Badge? badge;
  final VoidCallback onTap;

  const _AdminCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
    this.badge,
  });

  @override
  State<_AdminCard> createState() => _AdminCardState();
}

class _AdminCardState extends State<_AdminCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final badge = widget.badge;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hover
                  ? widget.gradient.last.withValues(alpha: 0.55)
                  : const Color(0xFFE6E9F2),
            ),
            boxShadow: [
              BoxShadow(
                color: _hover
                    ? widget.gradient.first.withValues(alpha: 0.18)
                    : Colors.black.withValues(alpha: 0.04),
                blurRadius: _hover ? 14 : 6,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    // Ícone com gradiente
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: widget.gradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: [
                          BoxShadow(
                            color: widget.gradient.first
                                .withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child:
                          Icon(widget.icon, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.5),
                                ),
                              ),
                              if (badge != null) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color:
                                        badge.color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: badge.color
                                            .withValues(alpha: 0.45)),
                                  ),
                                  child: Text(
                                    badge.text,
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: badge.color),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                                height: 1.3),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.chevron_right_rounded,
                        color: _hover
                            ? widget.gradient.last
                            : Colors.black26),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Entrada animada (fade + slide escalonado) ───────────────────────────────

class _Entrance extends StatefulWidget {
  final int index;
  final Widget child;
  const _Entrance({required this.index, required this.child});

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _fade = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    _slide = Tween(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));
    Future.delayed(Duration(milliseconds: 40 * widget.index.clamp(0, 10)), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
