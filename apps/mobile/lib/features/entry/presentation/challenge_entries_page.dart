import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../challenge/domain/entities/challenge.dart';
import '../../challenge/infrastructure/vote_repository.dart';
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

  @override
  Widget build(BuildContext context) {
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
      body: FutureBuilder<List<dynamic>>(
        future: Future.wait([_entriesFuture, _hasVotedFuture]),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final entries = snapshot.data![0] as List<Entry>;
          final hasVoted = snapshot.data![1] as bool;
          final canVote = !hasVoted && !_isCreator;

          if (entries.isEmpty) {
            return const Center(child: Text('Nenhuma participação ainda'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return _EntryCard(
                entry: entry,
                canVote: canVote,
                onVote: () => _vote(entry.id),
              );
            },
          );
        },
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final Entry entry;
  final bool canVote;
  final VoidCallback onVote;

  const _EntryCard({
    required this.entry,
    required this.canVote,
    required this.onVote,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
