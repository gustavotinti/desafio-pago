import 'package:flutter/material.dart';

import '../../../core/widgets/web_frame.dart';
import '../../challenge/infrastructure/get_challenges.dart';
import '../../entry/presentation/challenge_entries_page.dart';
import '../infrastructure/notification_repository.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _repo = NotificationRepository();

  @override
  void initState() {
    super.initState();
    // Abriu a tela → marca tudo como lido.
    _repo.markAllRead();
  }

  (IconData, Color) _icon(String type) {
    switch (type) {
      case 'vote':
        return (Icons.thumb_up, const Color(0xFF0cc0df));
      case 'win':
        return (Icons.emoji_events, const Color(0xFFF5B301));
      case 'follow':
        return (Icons.person_add, const Color(0xFF003b8a));
      case 'comment':
        return (Icons.mode_comment, const Color(0xFF6C63FF));
      case 'verification_priority':
        return (Icons.verified, Colors.blue);
      default:
        return (Icons.notifications, Colors.grey);
    }
  }

  String _ago(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'agora';
    if (d.inHours < 1) return '${d.inMinutes}min';
    if (d.inDays < 1) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    return '${(d.inDays / 7).floor()}sem';
  }

  Future<void> _open(AppNotification n) async {
    final cid = n.challengeId;
    if (cid == null || cid.isEmpty) return;
    final challenge = await GetChallenges().getById(cid);
    if (challenge == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChallengeEntriesPage(challenge: challenge),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notificações')),
      body: WebFrame(
        maxWidth: 600,
        child: StreamBuilder<List<AppNotification>>(
          stream: _repo.watch(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snap.data!;
            if (items.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Sem novidades por aqui ainda.\n'
                    'Participe, vote e siga gente pra movimentar!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final n = items[i];
                final (icon, color) = _icon(n.type);
                final tappable =
                    (n.challengeId != null && n.challengeId!.isNotEmpty);
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.14),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  title: Text(n.title,
                      style: TextStyle(
                          fontWeight:
                              n.read ? FontWeight.w500 : FontWeight.bold)),
                  subtitle: Text(n.body),
                  trailing: Text(
                    _ago(n.createdAt),
                    style:
                        const TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                  tileColor: n.read ? null : const Color(0xFFF1F7FF),
                  onTap: tappable ? () => _open(n) : null,
                );
              },
            );
          },
        ),
      ),
    );
  }
}
