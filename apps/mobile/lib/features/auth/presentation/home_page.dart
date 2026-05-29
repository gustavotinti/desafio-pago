import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../challenge/domain/entities/challenge.dart';
import '../../challenge/domain/entities/challenge_status.dart';
import '../../challenge/infrastructure/add_amount_repository.dart';
import '../../challenge/infrastructure/get_challenges.dart';
import '../../challenge/presentation/create_challenge_page.dart';
import '../../entry/presentation/challenge_entries_page.dart';
import '../../entry/presentation/submit_entry_page.dart';
import '../../admin/presentation/admin_page.dart';
import '../../../core/widgets/web_frame.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  ChallengeSortBy _activeSort   = ChallengeSortBy.amount;
  ChallengeSortBy _finishedSort = ChallengeSortBy.newest;

  late Future<List<Challenge>> _activeFuture;
  late Future<List<Challenge>> _finishedFuture;

  final String? _currentUserId =
      FirebaseAuth.instance.currentUser?.uid;
  bool _isAdmin    = false;
  bool _logoSettled = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadActive();
    _loadFinished();
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

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadActive() {
    _activeFuture = GetChallenges()(
      status: ChallengeStatus.active,
      sortBy: _activeSort,
    );
  }

  void _loadFinished() {
    _finishedFuture = GetChallenges()(
      status: ChallengeStatus.finished,
      sortBy: _finishedSort,
    );
  }

  void _reload() {
    setState(() {
      _loadActive();
      _loadFinished();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: SizedBox(
            key: ValueKey(_logoSettled),
            height: 45,
            width: 200,
            child: Image.asset(
              _logoSettled
                  ? 'assets/images/2.png'
                  : 'assets/images/logo_anim_sq_dark.gif',
              fit: BoxFit.contain,
            ),
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Ativos'),
            Tab(text: 'Encerrados'),
          ],
        ),
        actions: [
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
      body: TabBarView(
        controller: _tabController,
        children: [
          _FeedTab(
            future: _activeFuture,
            sortBy: _activeSort,
            onSortChanged: (s) =>
                setState(() { _activeSort = s; _loadActive(); }),
            onRefresh: () async { setState(_loadActive); },
            currentUserId: _currentUserId,
            onNavigated: _reload,
          ),
          _FeedTab(
            future: _finishedFuture,
            sortBy: _finishedSort,
            onSortChanged: (s) =>
                setState(() { _finishedSort = s; _loadFinished(); }),
            onRefresh: () async { setState(_loadFinished); },
            currentUserId: _currentUserId,
            onNavigated: _reload,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
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
        content: Text(
            'R\$ ${value.toStringAsFixed(2)} adicionados ao prêmio!'),
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

class _FeedTab extends StatelessWidget {
  final Future<List<Challenge>> future;
  final ChallengeSortBy sortBy;
  final ValueChanged<ChallengeSortBy> onSortChanged;
  final Future<void> Function() onRefresh;
  final String? currentUserId;
  final VoidCallback onNavigated;

  const _FeedTab({
    required this.future,
    required this.sortBy,
    required this.onSortChanged,
    required this.onRefresh,
    required this.currentUserId,
    required this.onNavigated,
  });

  @override
  Widget build(BuildContext context) {
    return WebFrame(
      child: Column(
      children: [
        _SortBar(sortBy: sortBy, onChanged: onSortChanged),
        Expanded(
          child: FutureBuilder<List<Challenge>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                    child: Text('Erro: ${snapshot.error}'));
              }

              final challenges = snapshot.data ?? [];

              if (challenges.isEmpty) {
                return const Center(
                  child: Text(
                    'Nenhum desafio aqui ainda.',
                    style: TextStyle(color: Colors.black54),
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: onRefresh,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                  itemCount: challenges.length,
                  itemBuilder: (context, i) => _ChallengeCard(
                    challenge: challenges[i],
                    currentUserId: currentUserId,
                    onNavigated: onNavigated,
                    onAddAmount: () => _showAddAmountDialog(
                      context,
                      challenges[i],
                      onNavigated,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
    );
  }
}

// ─── Sort bar — chip row ──────────────────────────────────────────────────────

class _SortBar extends StatelessWidget {
  final ChallengeSortBy sortBy;
  final ValueChanged<ChallengeSortBy> onChanged;

  const _SortBar({required this.sortBy, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const labels = {
      ChallengeSortBy.amount:     'Maior prêmio',
      ChallengeSortBy.voteCount:  'Mais votados',
      ChallengeSortBy.newest:     'Mais recentes',
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: ChallengeSortBy.values.map((s) {
          final selected = sortBy == s;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(labels[s]!),
              selected: selected,
              onSelected: (_) => onChanged(s),
              selectedColor: const Color(0xFF003b8a),
              backgroundColor: const Color(0xFFF0F1F8),
              labelStyle: TextStyle(
                fontFamily: 'Garet',
                fontSize: 13,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? Colors.white : Colors.black54,
              ),
              side: BorderSide.none,
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              showCheckmark: false,
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Challenge card ───────────────────────────────────────────────────────────

class _ChallengeCard extends StatelessWidget {
  final Challenge challenge;
  final String? currentUserId;
  final VoidCallback onNavigated;
  final VoidCallback onAddAmount;

  const _ChallengeCard({
    required this.challenge,
    required this.currentUserId,
    required this.onNavigated,
    required this.onAddAmount,
  });

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Gradient accent strip (active only) ──────────────────
          if (!_isFinished)
            Container(
              height: 3,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF003b8a), Color(0xFF0cc0df)],
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                        'R\$ ${challenge.amount.toStringAsFixed(2)}',
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
                      Text(
                        challenge.winnerIds.length == 1
                            ? 'Vencedor definido'
                            : '${challenge.winnerIds.length} vencedores (empate)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600,
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
