import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../challenge/domain/entities/challenge.dart';
import '../../challenge/domain/entities/challenge_status.dart';
import '../../challenge/infrastructure/vote_repository.dart';
import '../../comment/presentation/comment_section.dart';
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
  bool _isAdmin = false;

  final _voteRepo = VoteRepository();
  final _reportRepo = ReportRepository();
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

  @override
  void initState() {
    super.initState();
    _load();
    _loadAdmin();
  }

  Future<void> _loadAdmin() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('admins')
        .doc(uid)
        .get();
    if (mounted) setState(() => _isAdmin = doc.exists);
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
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Voto registrado!')));
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
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
            .map((r) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, r),
                  child: Text(r),
                ))
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _shareEntry(Entry entry) async {
    final url =
        'https://desafiopago.web.app/challenges/${widget.challenge.id}?entry=${entry.id}';
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copiado!')),
    );
  }

  void _showEntryComments(Entry entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.92,
        minChildSize: 0.3,
        builder: (_, controller) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: SingleChildScrollView(
            controller: controller,
            child: CommentSection(
              challengeId: widget.challenge.id,
              entryId: entry.id,
              isAdmin: _isAdmin,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editVotes(Entry entry) async {
    final controller = TextEditingController(text: '${entry.voteCount}');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar votos'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Novo total de votos'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final newCount = int.tryParse(controller.text.trim()) ?? -1;
    if (newCount < 0) return;
    try {
      await _functions.httpsCallable('adminModifyVoteCount').call({
        'entryId': entry.id,
        'voteCount': newCount,
      });
      _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Votos atualizados')));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message ?? 'Erro')));
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

                final uid = FirebaseAuth.instance.currentUser?.uid;

                // entries + challenge-level comment section at bottom
                final itemCount = entries.isEmpty ? 1 : entries.length + 1;

                if (entries.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      const Center(child: Text('Nenhuma participação ainda')),
                      const SizedBox(height: 24),
                      _ChallengeComments(
                        challengeId: widget.challenge.id,
                        isAdmin: _isAdmin,
                      ),
                    ],
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: itemCount,
                  itemBuilder: (context, index) {
                    if (index == entries.length) {
                      return _ChallengeComments(
                        challengeId: widget.challenge.id,
                        isAdmin: _isAdmin,
                      );
                    }
                    final entry = entries[index];
                    final isWinner = isFinished &&
                        widget.challenge.winnerIds.contains(entry.userId);
                    return _EntryCard(
                      entry: entry,
                      canVote: canVote,
                      isWinner: isWinner,
                      isAdmin: _isAdmin,
                      onVote: () => _vote(entry.id),
                      canReport: uid != null && uid != entry.userId,
                      onReport: () => _showReportDialog(entry.id),
                      onShare: () => _shareEntry(entry),
                      onComments: () => _showEntryComments(entry),
                      onEditVotes: _isAdmin ? () => _editVotes(entry) : null,
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

// ─── Challenge-level comments ────────────────────────────────────────────────

class _ChallengeComments extends StatelessWidget {
  final String challengeId;
  final bool isAdmin;
  const _ChallengeComments({required this.challengeId, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const SizedBox(height: 4),
          const Text(
            'Comentários do desafio',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          CommentSection(
            challengeId: challengeId,
            entryId: '',
            isAdmin: isAdmin,
          ),
        ],
      ),
    );
  }
}

// ─── Finished banner ─────────────────────────────────────────────────────────

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

// ─── Entry card ───────────────────────────────────────────────────────────────

class _EntryCard extends StatelessWidget {
  final Entry entry;
  final bool canVote;
  final bool isWinner;
  final bool isAdmin;
  final bool canReport;
  final VoidCallback onVote;
  final VoidCallback onReport;
  final VoidCallback onShare;
  final VoidCallback onComments;
  final VoidCallback? onEditVotes;

  const _EntryCard({
    required this.entry,
    required this.canVote,
    required this.isWinner,
    required this.isAdmin,
    required this.canReport,
    required this.onVote,
    required this.onReport,
    required this.onShare,
    required this.onComments,
    this.onEditVotes,
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
                // Share button
                IconButton(
                  icon: const Icon(Icons.share_outlined, size: 18),
                  tooltip: 'Compartilhar',
                  visualDensity: VisualDensity.compact,
                  color: Colors.grey,
                  onPressed: onShare,
                ),
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
              children: [
                Text(
                  '${entry.voteCount} voto${entry.voteCount == 1 ? '' : 's'}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (isAdmin && onEditVotes != null) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: onEditVotes,
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.edit, size: 14, color: Colors.black38),
                    ),
                  ),
                ],
                const Spacer(),
                TextButton.icon(
                  onPressed: onComments,
                  icon: const Icon(Icons.comment_outlined, size: 16),
                  label: const Text('Comentários'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 4),
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
