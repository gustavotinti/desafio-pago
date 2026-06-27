import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/safe_image.dart';
import '../../../core/widgets/web_frame.dart';
import '../../challenge/domain/entities/challenge.dart';
import '../../challenge/domain/entities/challenge_status.dart';
import '../../challenge/infrastructure/get_challenges.dart';
import '../../entry/domain/entities/content_type.dart';
import '../../entry/domain/entities/entry.dart';
import '../../entry/infrastructure/get_entries.dart';
import '../../entry/presentation/challenge_entries_page.dart';

/// "Minha atividade": desafios que criei + participações que enviei.
/// Resolve o gap de os encerrados não aparecerem mais no feed.
class MyActivityPage extends StatefulWidget {
  const MyActivityPage({super.key});

  @override
  State<MyActivityPage> createState() => _MyActivityPageState();
}

class _MyActivityPageState extends State<MyActivityPage> {
  late Future<_ActivityData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ActivityData> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const _ActivityData([], [], {});
    final challenges = await GetChallenges().byCreator(uid);
    final entries = await GetEntries().byUser(uid);
    // Resolve os desafios das participações (para abrir + mostrar título).
    final byId = <String, Challenge>{};
    for (final id in entries.map((e) => e.challengeId).toSet()) {
      final c = await GetChallenges().getById(id);
      if (c != null) byId[id] = c;
    }
    return _ActivityData(challenges, entries, byId);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Minha atividade'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Meus desafios'),
              Tab(text: 'Minhas participações'),
            ],
          ),
        ),
        body: WebFrame(
          maxWidth: 600,
          child: FutureBuilder<_ActivityData>(
            future: _future,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final d = snap.data!;
              return TabBarView(
                children: [
                  _ChallengesTab(challenges: d.challenges),
                  _EntriesTab(entries: d.entries, byId: d.challengesById),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ActivityData {
  final List<Challenge> challenges;
  final List<Entry> entries;
  final Map<String, Challenge> challengesById;
  const _ActivityData(this.challenges, this.entries, this.challengesById);
}

// ─── Empty state ──────────────────────────────────────────────────────────────

Widget _empty(String msg) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          msg,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54),
        ),
      ),
    );

void _openChallenge(BuildContext context, Challenge c, {String? entryId}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          ChallengeEntriesPage(challenge: c, highlightEntryId: entryId),
    ),
  );
}

Widget _statusChip(bool finished) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: finished ? Colors.grey.shade200 : Colors.green.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        finished ? 'Encerrado' : 'Ativo',
        style: TextStyle(
          fontSize: 11,
          color: finished ? Colors.grey.shade700 : Colors.green.shade800,
        ),
      ),
    );

// ─── Tab: meus desafios ───────────────────────────────────────────────────────

class _ChallengesTab extends StatelessWidget {
  final List<Challenge> challenges;
  const _ChallengesTab({required this.challenges});

  @override
  Widget build(BuildContext context) {
    if (challenges.isEmpty) {
      return _empty('Você ainda não criou desafios.');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: challenges.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final c = challenges[i];
        final finished = c.status == ChallengeStatus.finished;
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            onTap: () => _openChallenge(context, c),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            title: Text(c.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  _statusChip(finished),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '${c.entryCount} participações · ${c.voteCount} votos',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            trailing: Text(
              Fmt.brl(c.amount),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF00A86B),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Tab: minhas participações ────────────────────────────────────────────────

class _EntriesTab extends StatelessWidget {
  final List<Entry> entries;
  final Map<String, Challenge> byId;
  const _EntriesTab({required this.entries, required this.byId});

  IconData _icon(ContentType t) => switch (t) {
        ContentType.text => Icons.notes,
        ContentType.image => Icons.image_outlined,
        ContentType.video => Icons.videocam_outlined,
      };

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return _empty('Você ainda não participou de nenhum desafio.');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final e = entries[i];
        final c = byId[e.challengeId];
        final hasImage =
            e.contentType == ContentType.image && (e.contentUrl ?? '').isNotEmpty;
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            onTap: c == null ? null : () => _openChallenge(context, c, entryId: e.id),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            leading: SizedBox(
              width: 44,
              height: 44,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: hasImage
                    ? SafeImage(url: e.contentUrl!)
                    : Container(
                        color: const Color(0xFFEDF1F8),
                        child: Icon(_icon(e.contentType),
                            color: Colors.black45, size: 20),
                      ),
              ),
            ),
            title: Text(
              c?.title ?? 'Desafio removido',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: c == null ? Colors.black45 : null,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Sua participação · ${e.voteCount} voto${e.voteCount == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            trailing: c == null
                ? null
                : const Icon(Icons.chevron_right, color: Colors.black26),
          ),
        );
      },
    );
  }
}
