import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../challenge/domain/entities/challenge.dart';
import '../../challenge/domain/entities/challenge_status.dart';
import '../../challenge/infrastructure/get_challenges.dart';
import '../../challenge/presentation/create_challenge_page.dart';
import '../../entry/presentation/challenge_entries_page.dart';
import '../../entry/presentation/submit_entry_page.dart';
import '../../users/presentation/rankings_page.dart';
import '../presentation/profile_page.dart';
import '../../admin/presentation/admin_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  ChallengeSortBy _activeSort = ChallengeSortBy.amount;
  ChallengeSortBy _finishedSort = ChallengeSortBy.newest;

  late Future<List<Challenge>> _activeFuture;
  late Future<List<Challenge>> _finishedFuture;

  final String? _currentUserId =
      FirebaseAuth.instance.currentUser?.uid;
  final String? _currentEmail =
      FirebaseAuth.instance.currentUser?.email;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadActive();
    _loadFinished();
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

  bool get _isAdmin => _currentEmail == 'gustavo.a.tinti3@gmail.com';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Desafio Pago'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Ativos'),
            Tab(text: 'Encerrados'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.leaderboard),
            tooltip: 'Rankings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RankingsPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.person),
            tooltip: 'Perfil',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
              _reload();
            },
          ),
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings),
              tooltip: 'Admin',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminPage()),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
            onPressed: () => FirebaseAuth.instance.signOut(),
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
            MaterialPageRoute(builder: (_) => const CreateChallengePage()),
          );
          _reload();
        },
        icon: const Icon(Icons.add),
        label: const Text('Criar desafio'),
      ),
    );
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
    return Column(
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
                return Center(child: Text('Erro: ${snapshot.error}'));
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
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                  itemCount: challenges.length,
                  itemBuilder: (context, i) => _ChallengeCard(
                    challenge: challenges[i],
                    currentUserId: currentUserId,
                    onNavigated: onNavigated,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Sort bar ─────────────────────────────────────────────────────────────────

class _SortBar extends StatelessWidget {
  final ChallengeSortBy sortBy;
  final ValueChanged<ChallengeSortBy> onChanged;

  const _SortBar({required this.sortBy, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const Text('Ordenar:',
              style: TextStyle(fontSize: 13, color: Colors.black54)),
          const SizedBox(width: 8),
          DropdownButton<ChallengeSortBy>(
            value: sortBy,
            underline: const SizedBox.shrink(),
            style: const TextStyle(fontSize: 13, color: Colors.black87),
            items: const [
              DropdownMenuItem(
                value: ChallengeSortBy.amount,
                child: Text('Maior prêmio'),
              ),
              DropdownMenuItem(
                value: ChallengeSortBy.voteCount,
                child: Text('Mais votados'),
              ),
              DropdownMenuItem(
                value: ChallengeSortBy.newest,
                child: Text('Mais recentes'),
              ),
            ],
            onChanged: (v) { if (v != null) onChanged(v); },
          ),
        ],
      ),
    );
  }
}

// ─── Challenge card ───────────────────────────────────────────────────────────

class _ChallengeCard extends StatelessWidget {
  final Challenge challenge;
  final String? currentUserId;
  final VoidCallback onNavigated;

  const _ChallengeCard({
    required this.challenge,
    required this.currentUserId,
    required this.onNavigated,
  });

  bool get _isFinished => challenge.status == ChallengeStatus.finished;
  bool get _isCreator => challenge.createdBy == currentUserId;

  String _timeLeft() {
    final diff = challenge.expiresAt.difference(DateTime.now());
    if (diff.isNegative) return 'Expirado';
    if (diff.inDays > 0) return 'Expira em ${diff.inDays}d ${diff.inHours.remainder(24)}h';
    if (diff.inHours > 0) return 'Expira em ${diff.inHours}h ${diff.inMinutes.remainder(60)}min';
    return 'Expira em ${diff.inMinutes}min';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row + prize badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    challenge.title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade600,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'R\$ ${challenge.amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              challenge.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 8),

            // Stats row
            Row(
              children: [
                const Icon(Icons.people_outline, size: 14,
                    color: Colors.black45),
                const SizedBox(width: 3),
                Text('${challenge.entryCount}',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black54)),
                const SizedBox(width: 12),
                const Icon(Icons.thumb_up_outlined, size: 14,
                    color: Colors.black45),
                const SizedBox(width: 3),
                Text('${challenge.voteCount}',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black54)),
                const Spacer(),
                if (!_isFinished)
                  Text(
                    _timeLeft(),
                    style: TextStyle(
                      fontSize: 12,
                      color: challenge.expiresAt
                              .difference(DateTime.now())
                              .inHours <
                          3
                          ? Colors.red.shade600
                          : Colors.black45,
                    ),
                  ),
              ],
            ),

            // Winner info (finished)
            if (_isFinished && challenge.winnerIds.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.emoji_events,
                      size: 15, color: Colors.amber),
                  const SizedBox(width: 4),
                  Text(
                    challenge.winnerIds.length == 1
                        ? 'Vencedor definido'
                        : '${challenge.winnerIds.length} vencedores (empate)',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Colors.green,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
            if (_isFinished && challenge.winnerIds.isEmpty) ...[
              const SizedBox(height: 6),
              const Text('Sem participações',
                  style:
                      TextStyle(fontSize: 12, color: Colors.black45)),
            ],

            const SizedBox(height: 10),

            // Action buttons
            Row(
              children: [
                if (!_isFinished && !_isCreator)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        textStyle: const TextStyle(fontSize: 13)),
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
                if (!_isFinished && !_isCreator)
                  const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      textStyle: const TextStyle(fontSize: 13)),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ChallengeEntriesPage(challenge: challenge),
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
    );
  }
}
