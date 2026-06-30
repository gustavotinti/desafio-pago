import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Seção de conquistas (gamificação) calculada a partir dos dados já existentes
/// — participações, votos recebidos, ganhos, seguidores, desafios criados e
/// selo verificado. Empodera: o usuário vê o que já desbloqueou.
class AchievementsSection extends StatefulWidget {
  final String userId;
  final bool isOwn;

  const AchievementsSection({
    super.key,
    required this.userId,
    this.isOwn = false,
  });

  @override
  State<AchievementsSection> createState() => _AchievementsSectionState();
}

class _Badge {
  final IconData icon;
  final String label;
  final Color color;
  const _Badge(this.icon, this.label, this.color);
}

class _AchievementsSectionState extends State<AchievementsSection> {
  List<_Badge>? _badges;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = FirebaseFirestore.instance;
    try {
      final p = await db.collection('publicProfiles').doc(widget.userId).get();
      final d = p.data() ?? {};
      final votes = (d['totalVotesReceived'] as num? ?? 0);
      final earned = (d['totalEarned'] as num? ?? 0).toDouble();
      final followers = (d['followersCount'] as num? ?? 0);
      final verified = d['isVerified'] == true;

      final entries = await db
          .collection('entries')
          .where('userId', isEqualTo: widget.userId)
          .count()
          .get();
      final created = await db
          .collection('challenges')
          .where('createdBy', isEqualTo: widget.userId)
          .count()
          .get();
      final participations = entries.count ?? 0;
      final challenges = created.count ?? 0;

      const c1 = Color(0xFF0cc0df);
      const c2 = Color(0xFFF5B301);
      const c3 = Color(0xFF00A86B);
      const c4 = Color(0xFFFF00BF);
      final list = <_Badge>[];
      void add(bool cond, IconData i, String l, Color c) {
        if (cond) list.add(_Badge(i, l, c));
      }

      add(participations >= 1, Icons.flag, 'Estreante', c1);
      add(participations >= 5, Icons.local_fire_department, 'Participativo', c1);
      add(participations >= 20, Icons.military_tech, 'Veterano', c1);
      add(votes >= 10, Icons.favorite, 'Querido', c4);
      add(votes >= 100, Icons.whatshot, 'Popular', c4);
      add(votes >= 1000, Icons.auto_awesome, 'Fenômeno', c4);
      add(earned > 0, Icons.payments, 'Premiado', c3);
      add(earned >= 1000, Icons.workspace_premium, 'Lendário', c2);
      add(followers >= 100, Icons.groups, 'Celebridade', c2);
      add(challenges >= 1, Icons.add_circle, 'Desafiante', c1);
      add(challenges >= 5, Icons.emoji_events, 'Mestre dos Desafios', c2);
      add(verified, Icons.verified, 'Verificado', Colors.blue);

      if (mounted) setState(() => _badges = list);
    } catch (_) {
      if (mounted) setState(() => _badges = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final badges = _badges;
    if (badges == null) return const SizedBox.shrink();
    if (badges.isEmpty) {
      if (!widget.isOwn) return const SizedBox.shrink();
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          '🏅 Participe e vote pra desbloquear conquistas!',
          style: TextStyle(color: Colors.black54, fontSize: 13),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.workspace_premium,
                size: 18, color: Color(0xFFF5B301)),
            const SizedBox(width: 6),
            const Text('Conquistas',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(width: 6),
            Text('${badges.length}',
                style: const TextStyle(color: Colors.black45, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: badges
              .map((b) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: b.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: b.color.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(b.icon, size: 14, color: b.color),
                        const SizedBox(width: 5),
                        Text(b.label,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: b.color)),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}
