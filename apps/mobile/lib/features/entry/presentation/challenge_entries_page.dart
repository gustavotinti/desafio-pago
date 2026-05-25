import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../challenge/domain/entities/challenge.dart';
import '../../challenge/domain/entities/challenge_status.dart';
import '../../challenge/infrastructure/vote_repository.dart';
import '../../moderation/infrastructure/report_repository.dart';
import '../domain/entities/content_type.dart';
import '../domain/entities/entry.dart';
import '../infrastructure/get_entries.dart';

class ChallengeEntriesPage extends StatefulWidget {
  final Challenge challenge;

  const ChallengeEntriesPage({super.key, required this.challenge});

  @override
  State<ChallengeEntriesPage> createState() => _ChallengeEntriesPageState();
}

class _ChallengeEntriesPageState extends State<ChallengeEntriesPage> {
  late Future<List<Entry>> _entriesFuture;
  late Future<bool> _hasVotedFuture;

  final _voteRepo = VoteRepository();
  final _reportRepo = ReportRepository();

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _entriesFuture = GetEntries()(widget.challenge.id);
    _hasVotedFuture = _voteRepo.hasVoted(widget.challenge.id);
  }

  void _reload() => setState(() => _load());

  bool get _isCreator {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == widget.challenge.createdBy;
  }

  Future<void> _vote(String entryId) async {
    try {
      await _voteRepo.vote(widget.challenge.id, entryId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voto registrado!')),
      );
      _reload();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _showReportDialog(String entryId) async {
    const reasons = [
      'Conteúdo ofensivo ou inadequado',
      'Spam ou propaganda',
      'Violência ou automutilação',
      'Assédio ou bullying',
      'Outro',
    ];

    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Motivo da denúncia'),
        children: reasons
            .map(
              (r) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, r),
                child: Text(r),
              ),
            )
            .toList(),
      ),
    );

    if (selected == null) return;

    try {
      await _reportRepo.reportEntry(entryId, selected);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Denúncia enviada. Obrigado!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFinished = widget.challenge.status == ChallengeStatus.finished;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.challenge.title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Prêmio: R\$ ${widget.challenge.amount.toStringAsFixed(2)}'
              '  •  ${widget.challenge.entryCount} participações',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (isFinished) _FinishedBanner(challenge: widget.challenge),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: Future.wait([_entriesFuture, _hasVotedFuture]),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final entries = snapshot.data![0] as List<Entry>;
                final hasVoted = snapshot.data![1] as bool;
                final canVote = !hasVoted && !_isCreator && !isFinished;

                if (entries.isEmpty) {
                  return const Center(child: Text('Nenhuma participação ainda'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final isWinner = isFinished &&
                        widget.challenge.winnerIds.contains(entry.userId);
                    final uid = FirebaseAuth.instance.currentUser?.uid;
                    return _EntryCard(
                      entry: entry,
                      canVote: canVote,
                      isWinner: isWinner,
                      onVote: () => _vote(entry.id),
                      canReport: uid != null && uid != entry.userId,
                      onReport: () => _showReportDialog(entry.id),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FinishedBanner extends StatelessWidget {
  final Challenge challenge;

  const _FinishedBanner({required this.challenge});

  @override
  Widget build(BuildContext context) {
    final hasWinners = challenge.winnerIds.isNotEmpty;
    return Container(
      width: double.infinity,
      color: hasWinners ? Colors.green.shade50 : Colors.grey.shade100,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Text(
        hasWinners
            ? (challenge.winnerIds.length == 1
                ? 'Desafio encerrado — vencedor definido!'
                : 'Desafio encerrado — empate entre ${challenge.winnerIds.length} participantes!')
            : 'Desafio encerrado — sem vencedor',
        style: TextStyle(
          color: hasWinners ? Colors.green.shade800 : Colors.grey.shade700,
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final Entry entry;
  final bool canVote;
  final bool isWinner;
  final bool canReport;
  final VoidCallback onVote;
  final VoidCallback onReport;

  const _EntryCard({
    required this.entry,
    required this.canVote,
    required this.isWinner,
    required this.onVote,
    required this.canReport,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: isWinner
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Colors.amber, width: 2),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isWinner) ...[
                  const Icon(Icons.emoji_events, color: Colors.amber, size: 18),
                  const SizedBox(width: 4),
                  const Text(
                    'Vencedor',
                    style: TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                ] else
                  const Spacer(),
                if (canReport)
                  IconButton(
                    icon: const Icon(Icons.flag_outlined, size: 18),
                    tooltip: 'Denunciar',
                    visualDensity: VisualDensity.compact,
                    color: Colors.grey,
                    onPressed: onReport,
                  ),
              ],
            ),
            _buildContent(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${entry.voteCount} voto${entry.voteCount == 1 ? '' : 's'}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                ElevatedButton(
                  onPressed: canVote ? onVote : null,
                  child: const Text('Votar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (entry.contentType) {
      case ContentType.text:
        return Text(entry.contentText ?? '');
      case ContentType.image:
        if (entry.contentUrl == null) return const SizedBox.shrink();
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            entry.contentUrl!,
            height: 200,
            width: double.infinity,
            fit: BoxFit.cover,
            loadingBuilder: (_, child, progress) => progress == null
                ? child
                : const Center(child: CircularProgressIndicator()),
          ),
        );
      case ContentType.video:
        return Row(
          children: [
            const Icon(Icons.videocam),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                entry.contentUrl ?? 'Vídeo',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
    }
  }
}
