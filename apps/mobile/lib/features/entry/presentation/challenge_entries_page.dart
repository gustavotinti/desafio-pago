import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/safe_avatar.dart';
import '../../../core/widgets/safe_image.dart';
import '../../../core/widgets/web_frame.dart';
import '../../auth/presentation/auth_guard.dart';
import '../../challenge/domain/entities/challenge.dart';
import '../../challenge/domain/entities/challenge_status.dart';
import '../../challenge/infrastructure/vote_repository.dart';
import '../../comment/presentation/comment_section.dart';
import '../../moderation/infrastructure/report_repository.dart';
import '../../users/presentation/user_profile_page.dart';
import '../domain/entities/content_type.dart';
import '../domain/entities/entry.dart';
import '../infrastructure/get_entries.dart';
import 'auto_video.dart';

class ChallengeEntriesPage extends StatefulWidget {
  final Challenge challenge;
  final String? highlightEntryId;

  const ChallengeEntriesPage({
    super.key,
    required this.challenge,
    this.highlightEntryId,
  });

  @override
  State<ChallengeEntriesPage> createState() => _ChallengeEntriesPageState();
}

class _ChallengeEntriesPageState extends State<ChallengeEntriesPage> {
  late final Stream<List<Entry>> _entriesStream;
  bool _hasVoted = false;
  bool _isAdmin = false;

  // Cache de perfis públicos dos autores (nome/@/foto) — carrega uma vez
  // por autor; o stream de votos não refaz as leituras.
  final Map<String, Map<String, dynamic>?> _profiles = {};

  final _voteRepo = VoteRepository();
  final _reportRepo = ReportRepository();
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

  @override
  void initState() {
    super.initState();
    _entriesStream = GetEntries().watch(widget.challenge.id);
    _loadHasVoted();
    _loadAdmin();
  }

  Future<void> _ensureProfiles(List<Entry> entries) async {
    final missing = entries
        .map((e) => e.userId)
        .toSet()
        .where((id) => id.isNotEmpty && !_profiles.containsKey(id))
        .toList();
    if (missing.isEmpty) return;
    for (final id in missing) {
      _profiles[id] = null; // marca em andamento (evita busca duplicada)
    }
    try {
      final db = FirebaseFirestore.instance;
      final docs = await Future.wait(
          missing.map((id) => db.collection('publicProfiles').doc(id).get()));
      if (!mounted) return;
      setState(() {
        for (final d in docs) {
          _profiles[d.id] = d.data();
        }
      });
    } catch (_) {
      // sem perfil, o card mostra só o conteúdo — não bloqueia nada
    }
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

  Future<void> _loadHasVoted() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final v = await _voteRepo.hasVoted(widget.challenge.id);
    if (mounted) setState(() => _hasVoted = v);
  }

  bool get _isCreator {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == widget.challenge.createdBy;
  }

  Future<void> _vote(String entryId) async {
    if (!await ensureLoggedIn(context, message: 'Entre para votar')) return;
    try {
      await _voteRepo.vote(widget.challenge.id, entryId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Voto registrado!')));
      // Stream atualiza os votos ao vivo; bloqueia novo voto (exceto admin).
      if (!_isAdmin) setState(() => _hasVoted = true);
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

  /// Compartilhar pedindo voto: gera uma mensagem pronta (com o perfil de
  /// quem fez a participação) pra colar no WhatsApp/redes.
  Future<void> _shareEntry(Entry entry) async {
    final url =
        'https://desafiopago.com.br/challenges/${widget.challenge.id}?entry=${entry.id}';
    final p = _profiles[entry.userId];
    final username = p?['username'] as String?;
    final who = username != null && username.isNotEmpty
        ? '@$username'
        : (p?['name'] as String? ?? 'esta participação');
    final msg = '🗳️ Vote em $who no Desafio Pago!\n'
        'Desafio: "${widget.challenge.title}" — '
        '${Fmt.brl(widget.challenge.amount)} em jogo 🏆\n'
        'Toque no link, veja a participação e vote:\n'
        '$url';
    await Clipboard.setData(ClipboardData(text: msg));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              'Mensagem pedindo voto para $who copiada! Cole no WhatsApp 📲')),
    );
  }

  void _openProfile(String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => UserProfilePage(userId: userId)),
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
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Votos atualizados')));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message ?? 'Erro')));
    }
  }

  Future<void> _deleteEntry(Entry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir participação?'),
        content: const Text(
            'A participação, seus votos e comentários serão removidos. '
            'Não pode ser desfeito.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _functions
          .httpsCallable('adminDeleteEntry')
          .call({'entryId': entry.id});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Participação excluída')));
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
      ),
      body: WebFrame(
        child: Column(
        children: [
          _PrizeHeader(challenge: widget.challenge),
          if (widget.highlightEntryId != null)
            _SharedEntryBanner(canVote: !isFinished),
          if (isFinished) _FinishedBanner(challenge: widget.challenge),
          Expanded(
            child: StreamBuilder<List<Entry>>(
              stream: _entriesStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final entries = List<Entry>.from(snapshot.data!);
                _ensureProfiles(entries); // async; atualiza quando chegar

                // Posição do usuário (por votos, antes do reorder do destaque).
                final myUid = FirebaseAuth.instance.currentUser?.uid;
                _MyPosition? myPos;
                Entry? myEntry;
                if (myUid != null && entries.isNotEmpty) {
                  final idx = entries.indexWhere((e) => e.userId == myUid);
                  if (idx >= 0) {
                    myEntry = entries[idx];
                    final lead = entries.first.voteCount;
                    myPos = _MyPosition(
                      rank: idx + 1,
                      total: entries.length,
                      gapToLead: (lead - myEntry.voteCount).clamp(0, 1 << 30),
                    );
                  }
                }

                // Arte compartilhada (link) vai para o topo.
                if (widget.highlightEntryId != null) {
                  final hi = entries
                      .indexWhere((e) => e.id == widget.highlightEntryId);
                  if (hi > 0) {
                    final e = entries.removeAt(hi);
                    entries.insert(0, e);
                  }
                }
                // Admins bypass the creator restriction for demo voting
                final canVote =
                    !_hasVoted && (!_isCreator || _isAdmin) && !isFinished;

                final uid = FirebaseAuth.instance.currentUser?.uid;

                // entries + comentários no fim + (cabeçalho "sua posição")
                final hasHeader = myPos != null && !isFinished;
                final itemCount = entries.isEmpty
                    ? 1
                    : entries.length + 1 + (hasHeader ? 1 : 0);

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
                    if (hasHeader && index == 0) {
                      final me = myEntry;
                      return _MyPositionCard(
                        pos: myPos!,
                        onShare: me == null ? null : () => _shareEntry(me),
                      );
                    }
                    final i = hasHeader ? index - 1 : index;
                    if (i == entries.length) {
                      return _ChallengeComments(
                        challengeId: widget.challenge.id,
                        isAdmin: _isAdmin,
                      );
                    }
                    final entry = entries[i];
                    final isWinner = isFinished &&
                        widget.challenge.winnerIds.contains(entry.userId);
                    return _EntryCard(
                      entry: entry,
                      author: _profiles[entry.userId],
                      canVote: canVote,
                      hasVoted: _hasVoted,
                      isFinished: isFinished,
                      isWinner: isWinner,
                      isHighlighted: entry.id == widget.highlightEntryId,
                      isAdmin: _isAdmin,
                      onVote: () => _vote(entry.id),
                      canReport: uid != null && uid != entry.userId,
                      onReport: () => _showReportDialog(entry.id),
                      onShare: () => _shareEntry(entry),
                      onComments: () => _showEntryComments(entry),
                      onOpenProfile: () => _openProfile(entry.userId),
                      onEditVotes: _isAdmin ? () => _editVotes(entry) : null,
                      onDelete: _isAdmin ? () => _deleteEntry(entry) : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
        ),
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
                : 'Desafio encerrado — empate entre '
                    '${challenge.winnerIds.length} participantes!')
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

// ─── Prize header (destaque do prêmio) ────────────────────────────────────────

class _PrizeHeader extends StatelessWidget {
  final Challenge challenge;
  const _PrizeHeader({required this.challenge});

  @override
  Widget build(BuildContext context) {
    final finished = challenge.status == ChallengeStatus.finished;
    final colors = finished
        ? const [Color(0xFF64748B), Color(0xFF94A3B8)]
        : const [Color(0xFF00B09B), Color(0xFF0cc0df)];
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: 0.30),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.emoji_events, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  finished ? 'PRÊMIO • ENCERRADO' : 'PRÊMIO EM DISPUTA',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    Fmt.brl(challenge.amount),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.people_alt_rounded,
                        color: Colors.white70, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${challenge.entryCount} participações',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 12,
                      ),
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

// ─── Banner de participação compartilhada (deep link) ─────────────────────────

class _SharedEntryBanner extends StatelessWidget {
  final bool canVote;
  const _SharedEntryBanner({required this.canVote});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF6FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF0cc0df)),
      ),
      child: Row(
        children: [
          const Icon(Icons.how_to_vote, color: Color(0xFF003b8a), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              canVote
                  ? 'Participação compartilhada — em destaque abaixo. '
                      'Vote nela! 🗳️'
                  : 'Participação compartilhada — veja em destaque abaixo.',
              style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF003b8a),
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Entry card ───────────────────────────────────────────────────────────────

class _EntryCard extends StatelessWidget {
  final Entry entry;
  // Perfil público do autor (nome/@/foto/selo) — null enquanto carrega.
  final Map<String, dynamic>? author;
  final bool canVote;
  final bool hasVoted;
  final bool isFinished;
  final bool isWinner;
  final bool isHighlighted;
  final bool isAdmin;
  final bool canReport;
  final VoidCallback onVote;
  final VoidCallback onReport;
  final VoidCallback onShare;
  final VoidCallback onComments;
  final VoidCallback onOpenProfile;
  final VoidCallback? onEditVotes;
  final VoidCallback? onDelete;

  const _EntryCard({
    required this.entry,
    required this.author,
    required this.canVote,
    required this.hasVoted,
    required this.isFinished,
    required this.isWinner,
    required this.isAdmin,
    required this.canReport,
    this.isHighlighted = false,
    required this.onVote,
    required this.onReport,
    required this.onShare,
    required this.onComments,
    required this.onOpenProfile,
    this.onEditVotes,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final name = author?['name'] as String? ?? '';
    final username = author?['username'] as String? ?? '';
    final photoUrl = author?['photoUrl'] as String?;
    final verified = author?['isVerified'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: (isHighlighted || isWinner)
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isHighlighted
                    ? const Color(0xFF0cc0df)
                    : Colors.amber,
                width: isHighlighted ? 2.5 : 2,
              ),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Autor (perfil de quem fez a participação) ─────────────
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onOpenProfile,
                    borderRadius: BorderRadius.circular(20),
                    child: Row(
                      children: [
                        SafeAvatar(photoUrl: photoUrl, radius: 16),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      name.isEmpty ? 'Participante' : name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                    ),
                                  ),
                                  if (verified) ...[
                                    const SizedBox(width: 3),
                                    const Icon(Icons.verified,
                                        size: 14, color: Color(0xFF0cc0df)),
                                  ],
                                ],
                              ),
                              if (username.isNotEmpty)
                                Text(
                                  '@$username',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.black45),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Compartilhar pedindo voto para este perfil
                IconButton(
                  icon: const Icon(Icons.campaign_outlined, size: 20),
                  tooltip: 'Pedir votos (copia mensagem)',
                  visualDensity: VisualDensity.compact,
                  color: const Color(0xFF003b8a),
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
                // ── Menu admin: editar votos / excluir ────────────────
                if (onDelete != null)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert,
                        size: 18, color: Colors.grey),
                    tooltip: 'Admin',
                    padding: EdgeInsets.zero,
                    onSelected: (v) {
                      if (v == 'votes') onEditVotes?.call();
                      if (v == 'delete') onDelete!.call();
                    },
                    itemBuilder: (_) => [
                      if (onEditVotes != null)
                        const PopupMenuItem(
                            value: 'votes', child: Text('Editar votos')),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Excluir participação',
                            style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
              ],
            ),
            if (isHighlighted || isWinner) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  if (isHighlighted) ...[
                    const Icon(Icons.campaign,
                        color: Color(0xFF003b8a), size: 18),
                    const SizedBox(width: 4),
                    const Text(
                      'Vote nesta arte',
                      style: TextStyle(
                        color: Color(0xFF003b8a),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (isWinner) ...[
                    const Icon(Icons.emoji_events,
                        color: Colors.amber, size: 18),
                    const SizedBox(width: 4),
                    const Text(
                      'Vencedor',
                      style: TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 8),
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
              ],
            ),
            // ── Botão de voto em destaque (embaixo da participação) ──
            if (!isFinished) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: canVote ? onVote : null,
                  icon: Icon(
                      hasVoted && !canVote
                          ? Icons.check_circle
                          : Icons.how_to_vote,
                      size: 18),
                  label: Text(
                    canVote
                        ? 'Votar nesta participação'
                        : (hasVoted
                            ? 'Você já votou neste desafio ✓'
                            : 'Votar'),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    textStyle: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
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
        // Proporção natural (vertical/quadrado), com altura máxima.
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 460),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SafeImage(
              url: entry.contentUrl!,
              width: double.infinity,
              fit: BoxFit.contain,
            ),
          ),
        );
      case ContentType.video:
        if (entry.contentUrl == null) return const SizedBox.shrink();
        // Player 4:5 — toque para reproduzir com som.
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 4 / 5,
                child: AutoVideo(url: entry.contentUrl!),
              ),
            ),
          ),
        );
    }
  }
}

// ─── "Sua posição" (empoderamento + CTA de divulgação) ───────────────────────

class _MyPosition {
  final int rank;
  final int total;
  final int gapToLead;
  const _MyPosition({
    required this.rank,
    required this.total,
    required this.gapToLead,
  });

  bool get isLeading => gapToLead == 0;
}

class _MyPositionCard extends StatelessWidget {
  final _MyPosition pos;
  final VoidCallback? onShare;

  const _MyPositionCard({required this.pos, this.onShare});

  @override
  Widget build(BuildContext context) {
    final leading = pos.isLeading;
    final accent = leading ? const Color(0xFF00A86B) : const Color(0xFF003b8a);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: leading
              ? const [Color(0xFF00B09B), Color(0xFF0cc0df)]
              : const [Color(0xFF003b8a), Color(0xFF5B7CFA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(leading ? Icons.emoji_events : Icons.trending_up,
              color: Colors.white, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  leading
                      ? 'Você está liderando! 🏆'
                      : 'Você está em ${pos.rank}º de ${pos.total}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  leading
                      ? 'Continue divulgando pra manter a ponta.'
                      : 'Faltam ${pos.gapToLead} voto'
                          '${pos.gapToLead == 1 ? '' : 's'} pra liderar. '
                          'Chame a galera!',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 12.5),
                ),
              ],
            ),
          ),
          if (onShare != null) ...[
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: onShare,
              icon: const Icon(Icons.share, size: 16),
              label: const Text('Divulgar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: accent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
