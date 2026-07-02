import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../challenge/domain/entities/challenge.dart';
import '../../challenge/domain/entities/challenge_status.dart';
import '../../challenge/infrastructure/add_amount_repository.dart';
import '../../challenge/infrastructure/get_challenges.dart';
import '../../challenge/presentation/create_challenge_page.dart';
import '../../challenge/presentation/platform_pulse.dart';
import '../../notifications/presentation/notification_bell.dart';
import '../../entry/presentation/challenge_entries_page.dart';
import '../../entry/presentation/entry_preview_strip.dart';
import '../../entry/presentation/submit_entry_page.dart';
import '../../admin/presentation/admin_challenges_page.dart';
import '../../admin/presentation/admin_page.dart';
import '../../admin/infrastructure/admin_repository.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/web_frame.dart';
import 'auth_guard.dart';

// Recurso "fixar como novo" é exclusivo do super admin (o backend também valida).
const _superAdminEmail = 'gustavo.a.tinti3@gmail.com';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _reloadTick = 0;

  final String? _currentUserId =
      FirebaseAuth.instance.currentUser?.uid;
  final bool _isSuperAdmin =
      FirebaseAuth.instance.currentUser?.email == _superAdminEmail;
  bool _isAdmin    = false;
  bool _logoSettled = false;

  @override
  void initState() {
    super.initState();
    _loadAdminStatus();
    Future.delayed(const Duration(milliseconds: 9600), () {
      if (mounted) setState(() => _logoSettled = true);
    });
  }

  Future<void> _loadAdminStatus() async {
    final uid = _currentUserId;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('admins')
        .doc(uid)
        .get();
    if (mounted) setState(() => _isAdmin = doc.exists);
  }

  // Recarrega o feed do início (recria o _FeedTab pela key).
  void _reload() {
    setState(() => _reloadTick++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: SizedBox(
            key: ValueKey(_logoSettled),
            height: 52,
            width: 220,
            child: Image.asset(
              _logoSettled
                  ? 'assets/images/2.png'
                  : 'assets/images/logo_anim_sq_dark.gif',
              fit: BoxFit.contain,
            ),
          ),
        ),
        actions: [
          if (_currentUserId != null) const NotificationBell(),
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings),
              tooltip: 'Admin',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminPage()),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          PlatformPulse(isAdmin: _isAdmin),
          Expanded(
            child: _FeedTab(
              key: ValueKey(_reloadTick),
              currentUserId: _currentUserId,
              isAdmin: _isAdmin,
              isSuperAdmin: _isSuperAdmin,
              onNavigated: _reload,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          if (!await ensureLoggedIn(context,
              message: 'Entre para criar um desafio')) {
            return;
          }
          if (!context.mounted) return;
          await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const CreateChallengePage()),
          );
          _reload();
        },
        icon: const Icon(Icons.add),
        label: const Text('Criar desafio'),
      ),
    );
  }
}

// ─── Add-amount dialog ────────────────────────────────────────────────────────

Future<void> _showAddAmountDialog(
  BuildContext context,
  Challenge challenge,
  VoidCallback onSuccess,
) async {
  if (!await ensureLoggedIn(context,
      message: 'Entre para aumentar o prêmio')) {
    return;
  }
  if (!context.mounted) return;
  final controller = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Aumentar prêmio'),
      content: TextField(
        controller: controller,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Valor a adicionar (R\$)',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Confirmar'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  final value = double.tryParse(controller.text.trim()) ?? 0;
  if (value <= 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Valor inválido')),
    );
    return;
  }

  try {
    await AddAmountRepository().addAmount(challenge.id, value);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${Fmt.brl(value)} adicionados ao prêmio!'),
      ),
    );
    onSuccess();
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(e.toString())));
  }
}

// ─── Feed tab ────────────────────────────────────────────────────────────────

class _FeedTab extends StatefulWidget {
  final String? currentUserId;
  final bool isAdmin;
  final bool isSuperAdmin;
  final VoidCallback onNavigated;

  const _FeedTab({
    super.key,
    required this.currentUserId,
    required this.isAdmin,
    required this.isSuperAdmin,
    required this.onNavigated,
  });

  @override
  State<_FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<_FeedTab> {
  static const _pageSize = 12;
  final _scroll = ScrollController();
  final List<Challenge> _items = [];
  // Ids fixados como "novo" — filtrados das páginas normais pra não duplicar.
  Set<String> _pinnedIds = {};
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadFirst();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadFirst() async {
    setState(() {
      _initialLoading = true;
      _error = null;
    });
    try {
      // Fixados ("novo") + 1ª página normal em paralelo.
      final pinnedFuture = GetChallenges().pinnedActive();
      final pageFuture = GetChallenges()
          .page(status: ChallengeStatus.active, limit: _pageSize);
      final pinned = await pinnedFuture;
      final (items, cursor) = await pageFuture;
      if (!mounted) return;
      _pinnedIds = pinned.map((c) => c.id).toSet();
      final rest =
          items.where((c) => !_pinnedIds.contains(c.id)).toList();
      setState(() {
        _items
          ..clear()
          ..addAll(pinned) // fixados sempre no topo
          ..addAll(rest);
        _cursor = cursor;
        _hasMore = items.length == _pageSize;
        _initialLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _initialLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final (items, cursor) = await GetChallenges().page(
        status: ChallengeStatus.active,
        startAfter: _cursor,
        limit: _pageSize,
      );
      if (!mounted) return;
      final rest =
          items.where((c) => !_pinnedIds.contains(c.id)).toList();
      setState(() {
        _items.addAll(rest);
        _cursor = cursor ?? _cursor;
        _hasMore = items.length == _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebFrame(
      maxWidth: 600,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('Erro: $_error'));
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadFirst,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 140),
            Center(
              child: Text('Nenhum desafio aqui ainda.',
                  style: TextStyle(color: Colors.black54)),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadFirst,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
        // +1 slot final: spinner de paginação (se há mais) ou o rodapé de
        // "alta demanda" quando o feed chega ao fim.
        itemCount: _items.length + 1,
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            return _hasMore
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : const _HighDemandFooter();
          }
          final c = _items[i];
          return _FeedEntrance(
            child: _ChallengeCard(
              challenge: c,
              currentUserId: widget.currentUserId,
              isAdmin: widget.isAdmin,
              isSuperAdmin: widget.isSuperAdmin,
              onNavigated: widget.onNavigated,
              onAddAmount: () =>
                  _showAddAmountDialog(context, c, widget.onNavigated),
            ),
          );
        },
      ),
    );
  }
}

// ─── Challenge card ───────────────────────────────────────────────────────────

class _ChallengeCard extends StatelessWidget {
  final Challenge challenge;
  final String? currentUserId;
  final bool isAdmin;
  final bool isSuperAdmin;
  final VoidCallback onNavigated;
  final VoidCallback onAddAmount;

  const _ChallengeCard({
    required this.challenge,
    required this.currentUserId,
    required this.isAdmin,
    required this.isSuperAdmin,
    required this.onNavigated,
    required this.onAddAmount,
  });

  Future<void> _togglePinned(BuildContext context) async {
    final next = !challenge.pinned;
    try {
      await AdminRepository().setChallengePinned(challenge.id, next);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(next
              ? 'Fixado como novo no topo ✅'
              : 'Removido do topo'),
        ),
      );
      onNavigated();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  bool get _isFinished => challenge.status == ChallengeStatus.finished;
  bool get _isCreator  => challenge.createdBy == currentUserId;

  String _timeLeft() {
    final diff = challenge.expiresAt.difference(DateTime.now());
    if (diff.isNegative) return 'Expirado';
    if (diff.inDays > 0) {
      return 'Expira em ${diff.inDays}d ${diff.inHours.remainder(24)}h';
    }
    if (diff.inHours > 0) {
      return 'Expira em ${diff.inHours}h ${diff.inMinutes.remainder(60)}min';
    }
    return 'Expira em ${diff.inMinutes}min';
  }

  @override
  Widget build(BuildContext context) {
    final diff   = challenge.expiresAt.difference(DateTime.now());
    final urgent = !_isFinished && diff.inHours < 3;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      shape: challenge.pinned
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFF59E0B), width: 1.4),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Gradient accent strip (active only) ──────────────────
          if (!_isFinished)
            Container(
              height: challenge.pinned ? 4 : 3,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: challenge.pinned
                      ? const [Color(0xFFF59E0B), Color(0xFFFFD54F)]
                      : const [Color(0xFF003b8a), Color(0xFF0cc0df)],
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (challenge.pinned) ...[
                  const _NewBadge(),
                  const SizedBox(height: 8),
                ],
                // ── Title + prize badge ────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        challenge.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Prize badge — gradient for active, muted for finished
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _isFinished
                              ? [
                                  Colors.grey.shade400,
                                  Colors.grey.shade500
                                ]
                              : const [
                                  Color(0xFF00B09B),
                                  Color(0xFF0cc0df),
                                ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: _isFinished
                            ? null
                            : [
                                BoxShadow(
                                  color: const Color(0xFF00B09B)
                                      .withValues(alpha: 0.30),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                      ),
                      child: Text(
                        Fmt.brl(challenge.amount),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // ── Description ───────────────────────────────────
                Text(
                  challenge.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),

                // ── Stats row ─────────────────────────────────────
                Row(
                  children: [
                    _StatPill(
                      icon: Icons.people_outline,
                      label: '${challenge.entryCount}',
                    ),
                    const SizedBox(width: 8),
                    _StatPill(
                      icon: Icons.thumb_up_outlined,
                      label: '${challenge.voteCount}',
                    ),
                    const Spacer(),
                    if (!_isFinished)
                      _TimePill(text: _timeLeft(), urgent: urgent),
                  ],
                ),

                // ── Winner info (finished) ─────────────────────────
                if (_isFinished &&
                    challenge.winnerIds.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.emoji_events,
                          size: 16, color: Colors.amber),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          challenge.winnerIds.length == 1
                              ? 'Vencedor definido • ${Fmt.brl(challenge.amount)}'
                              : '${challenge.winnerIds.length} vencedores '
                                  '(empate) • ${Fmt.brl(challenge.amount)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_isFinished &&
                    challenge.winnerIds.isEmpty) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Sem participações',
                    style: TextStyle(
                        fontSize: 12, color: Colors.black45),
                  ),
                ],

                // ── Prévia: 3 participações mais votadas (4:5) ─────
                const SizedBox(height: 12),
                EntryPreviewStrip(
                  entries: challenge.topEntries,
                  onOpen: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ChallengeEntriesPage(challenge: challenge),
                      ),
                    );
                    onNavigated();
                  },
                ),

                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // ── Action buttons (Wrap = responsive) ────────────
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!_isFinished && !_isCreator)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          textStyle: const TextStyle(
                              fontSize: 13,
                              fontFamily: 'Garet',
                              fontWeight: FontWeight.w600),
                        ),
                        onPressed: () async {
                          if (!await ensureLoggedIn(context,
                              message: 'Entre para participar do desafio')) {
                            return;
                          }
                          if (!context.mounted) return;
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SubmitEntryPage(
                                challengeId: challenge.id,
                                challengeTitle: challenge.title,
                              ),
                            ),
                          );
                          onNavigated();
                        },
                        child: const Text('Participar'),
                      ),
                    if (!_isFinished)
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          textStyle: const TextStyle(
                              fontSize: 13, fontFamily: 'Garet'),
                        ),
                        onPressed: onAddAmount,
                        child: const Text('+ Prêmio'),
                      ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        textStyle: const TextStyle(
                            fontSize: 13, fontFamily: 'Garet'),
                      ),
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ChallengeEntriesPage(
                                    challenge: challenge),
                          ),
                        );
                        onNavigated();
                      },
                      child: const Text('Ver participações'),
                    ),
                    // ── Share button ──────────────────────────────────
                    IconButton(
                      tooltip: 'Compartilhar desafio',
                      icon: const Icon(Icons.share_outlined, size: 20),
                      style: IconButton.styleFrom(
                        padding: const EdgeInsets.all(8),
                        minimumSize: const Size(36, 36),
                        side: BorderSide(
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () async {
                        final url =
                            'https://desafiopago.com.br/challenges/${challenge.id}';
                        await Clipboard.setData(
                            ClipboardData(text: url));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Link do desafio copiado!')),
                        );
                      },
                    ),
                    // ── Editar (admin) — lápis direto no feed ─────────
                    if (isAdmin)
                      IconButton(
                        tooltip: 'Editar desafio (admin)',
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        style: IconButton.styleFrom(
                          padding: const EdgeInsets.all(8),
                          minimumSize: const Size(36, 36),
                          side: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () async {
                          await showDialog(
                            context: context,
                            builder: (_) => EditChallengeDialog(
                              id: challenge.id,
                              data: {
                                'title': challenge.title,
                                'description': challenge.description,
                                'amount': challenge.amount,
                                'expiresAt':
                                    challenge.expiresAt.toIso8601String(),
                                'status':
                                    _isFinished ? 'finished' : 'active',
                              },
                            ),
                          );
                          onNavigated();
                        },
                      ),
                    // ── Fixar como "novo" (super admin) ───────────────
                    if (isSuperAdmin && !_isFinished)
                      IconButton(
                        tooltip: challenge.pinned
                            ? 'Remover do topo'
                            : 'Fixar como novo (topo)',
                        icon: Icon(
                          challenge.pinned
                              ? Icons.push_pin
                              : Icons.push_pin_outlined,
                          size: 20,
                          color: challenge.pinned
                              ? const Color(0xFFF59E0B)
                              : null,
                        ),
                        style: IconButton.styleFrom(
                          padding: const EdgeInsets.all(8),
                          minimumSize: const Size(36, 36),
                          side: BorderSide(
                              color: challenge.pinned
                                  ? const Color(0xFFF59E0B)
                                  : Theme.of(context)
                                      .colorScheme
                                      .outlineVariant),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _togglePinned(context),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Stat pill ────────────────────────────────────────────────────────────────

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F1F8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.black45),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: Colors.black54)),
        ],
      ),
    );
  }
}

// ─── Time pill ────────────────────────────────────────────────────────────────

class _TimePill extends StatelessWidget {
  final String text;
  final bool urgent;
  const _TimePill({required this.text, required this.urgent});

  @override
  Widget build(BuildContext context) {
    final bg = urgent ? Colors.red.shade50 : const Color(0xFFF0F1F8);
    final fg = urgent ? Colors.red.shade700 : Colors.black45;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: urgent
            ? Border.all(color: Colors.red.shade200)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.access_time_rounded, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: fg,
              fontWeight:
                  urgent ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── "NOVO" badge (pinned pelo super admin) ──────────────────────────────────
// Selo pulsante dourado que sinaliza um desafio recém-fixado no topo.

class _NewBadge extends StatefulWidget {
  const _NewBadge();

  @override
  State<_NewBadge> createState() => _NewBadgeState();
}

class _NewBadgeState extends State<_NewBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.65, end: 1.0).animate(_c),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF59E0B), Color(0xFFFFD54F)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 13, color: Colors.white),
            SizedBox(width: 5),
            Text(
              'NOVO',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Entrada animada dos cards do feed ───────────────────────────────────────
// Fade + leve deslize pra cima quando o card aparece — dá sensação de vida.

class _FeedEntrance extends StatefulWidget {
  final Widget child;
  const _FeedEntrance({required this.child});

  @override
  State<_FeedEntrance> createState() => _FeedEntranceState();
}

class _FeedEntranceState extends State<_FeedEntrance>
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
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));
    _c.forward();
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

// ─── Rodapé "alta demanda" (fim do feed) ─────────────────────────────────────
// Loader sutil no fim da rolagem: passa a sensação de plataforma movimentada,
// como se houvesse muito mais conteúdo chegando. Responsivo (texto centraliza
// e quebra em telas estreitas).

class _HighDemandFooter extends StatelessWidget {
  const _HighDemandFooter();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                height: 30,
                width: 30,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Color(0xFF0cc0df),
                ),
              ),
              const SizedBox(height: 14),
              const _DotsText(text: 'Carregando mais desafios'),
              const SizedBox(height: 6),
              Text(
                'Estamos com alta demanda de usuários agora — '
                'o servidor pode levar um instante para carregar mais.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Colors.black.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Texto com reticências animadas ("Carregando mais desafios" + . .. ...).
class _DotsText extends StatefulWidget {
  final String text;
  const _DotsText({required this.text});

  @override
  State<_DotsText> createState() => _DotsTextState();
}

class _DotsTextState extends State<_DotsText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final n = (_c.value * 3).floor() % 4; // 0..3 pontos
        return Text(
          '${widget.text}${'.' * n}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black.withValues(alpha: 0.6),
          ),
        );
      },
    );
  }
}
