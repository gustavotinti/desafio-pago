import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/safe_avatar.dart';
import '../../../core/widgets/web_frame.dart';
import '../../admin/presentation/admin_edit_virtual_user_page.dart';
import '../../auth/presentation/auth_guard.dart';
import '../infrastructure/follow_repository.dart';
import 'achievements.dart';
import 'followers_page.dart';

class UserProfilePage extends StatefulWidget {
  final String userId;
  const UserProfilePage({super.key, required this.userId});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final _repo = FollowRepository();
  bool _isFollowing = false;
  bool _actionLoading = false;
  Map<String, dynamic> _userData = {};
  bool _dataLoaded = false;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isGuest = uid == null;
    final results = await Future.wait([
      // Lê do espelho público (sem PII) — funciona para visitantes também.
      FirebaseFirestore.instance
          .collection('publicProfiles')
          .doc(widget.userId)
          .get(),
      isGuest ? Future.value(false) : _repo.isFollowing(widget.userId),
      isGuest
          ? Future.value(false)
          : FirebaseFirestore.instance
              .collection('admins')
              .doc(uid)
              .get()
              .then((d) => d.exists),
    ]);
    if (!mounted) return;
    setState(() {
      _userData = (results[0] as DocumentSnapshot).data() as Map<String, dynamic>? ?? {};
      _isFollowing = results[1] as bool;
      _isAdmin = results[2] as bool;
      _dataLoaded = true;
    });
  }

  Future<void> _toggleFollow() async {
    if (!await ensureLoggedIn(context)) return;
    setState(() => _actionLoading = true);
    try {
      if (_isFollowing) {
        await _repo.unfollow(widget.userId);
      } else {
        await _repo.follow(widget.userId);
      }
      if (!mounted) return;
      setState(() {
        _isFollowing = !_isFollowing;
        final delta = _isFollowing ? 1 : -1;
        _userData['followersCount'] =
            (_userData['followersCount'] as int? ?? 0) + delta;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _openFollowers(FollowType type) async {
    if (!await ensureLoggedIn(context)) return;
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FollowersPage(userId: widget.userId, type: type),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isOwnProfile = currentUid == widget.userId;

    final name = _userData['name'] as String? ?? 'Usuário';
    final username = _userData['username'] as String? ?? '';
    final photoUrl = _userData['photoUrl'] as String? ?? '';
    final bio = _userData['bio'] as String? ?? '';
    final isVerified = _userData['isVerified'] == true;
    final followersCount = _userData['followersCount'] as int? ?? 0;
    final followingCount = _userData['followingCount'] as int? ?? 0;
    final totalVotes = _userData['totalVotesReceived'] ?? 0;
    final totalEarned = (_userData['totalEarned'] as num? ?? 0).toDouble();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name),
            if (isVerified) ...[
              const SizedBox(width: 4),
              const Icon(Icons.verified, color: Colors.blue, size: 18),
            ],
          ],
        ),
        actions: [
          // Lápis de edição direto no perfil (fora do dashboard) — só admin.
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar perfil (admin)',
              onPressed: () async {
                final changed = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminEditVirtualUserPage(
                      userId: widget.userId,
                      data: _userData,
                    ),
                  ),
                );
                if (changed == true) _load();
              },
            ),
        ],
      ),
      body: !_dataLoaded
          ? const Center(child: CircularProgressIndicator())
          : WebFrame(
              child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // — Avatar + nome + bio —
                Center(
                  child: Column(
                    children: [
                      SafeAvatar(photoUrl: photoUrl, radius: 44),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          if (isVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.verified,
                                color: Colors.blue, size: 20),
                          ],
                        ],
                      ),
                      if (username.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '@$username',
                          style: const TextStyle(
                              color: Colors.black54, fontSize: 13),
                        ),
                      ],
                      if (bio.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          bio,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                      if (!isOwnProfile) ...[
                        const SizedBox(height: 12),
                        _actionLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : FilledButton.tonal(
                                onPressed: _toggleFollow,
                                child: Text(
                                    _isFollowing ? 'Seguindo' : 'Seguir'),
                              ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // — Stats row —
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _TappableStat(
                      label: 'Seguidores',
                      value: '$followersCount',
                      onTap: () => _openFollowers(FollowType.followers),
                    ),
                    _TappableStat(
                      label: 'Seguindo',
                      value: '$followingCount',
                      onTap: () => _openFollowers(FollowType.following),
                    ),
                    _TappableStat(
                        label: 'Votos', value: Fmt.number(totalVotes)),
                    _TappableStat(
                        label: 'Ganhos', value: Fmt.brlCompact(totalEarned)),
                  ],
                ),
                const SizedBox(height: 24),
                AchievementsSection(userId: widget.userId),
              ],
              ),
            ),
    );
  }
}

class _TappableStat extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _TappableStat({
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(padding: const EdgeInsets.all(4), child: content),
    );
  }
}
