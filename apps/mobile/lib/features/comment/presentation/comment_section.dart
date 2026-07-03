import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/widgets/safe_avatar.dart';
import '../../auth/presentation/auth_guard.dart';
import '../domain/entities/comment.dart';
import '../infrastructure/comment_repository.dart';

class CommentSection extends StatefulWidget {
  final String challengeId;
  final String entryId;
  final bool isAdmin;

  const CommentSection({
    super.key,
    required this.challengeId,
    this.entryId = '',
    this.isAdmin = false,
  });

  @override
  State<CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends State<CommentSection> {
  final _repo = CommentRepository();
  final _controller = TextEditingController();
  final _inputFocus = FocusNode();
  bool _sending = false;
  Set<String> _liked = {};
  String? _replyToId;
  String? _replyToName;

  // Fotos de perfil dos autores (publicProfiles) — cache por userId.
  final Map<String, String?> _photos = {};

  @override
  void initState() {
    super.initState();
    _loadLikes();
  }

  Future<void> _ensurePhotos(List<Comment> comments) async {
    final missing = comments
        .map((c) => c.userId)
        .toSet()
        .where((id) => id.isNotEmpty && !_photos.containsKey(id))
        .toList();
    if (missing.isEmpty) return;
    for (final id in missing) {
      _photos[id] = null; // em andamento — evita busca duplicada
    }
    try {
      final db = FirebaseFirestore.instance;
      final docs = await Future.wait(
          missing.map((id) => db.collection('publicProfiles').doc(id).get()));
      if (!mounted) return;
      setState(() {
        for (final d in docs) {
          _photos[d.id] = d.data()?['photoUrl'] as String?;
        }
      });
    } catch (_) {/* sem foto, o avatar mostra o ícone padrão */}
  }

  @override
  void dispose() {
    _controller.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _loadLikes() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    try {
      final ids = await _repo.loadMyLikedIds();
      if (mounted) setState(() => _liked = ids);
    } catch (_) {/* silencioso */}
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await _repo.addComment(
        challengeId: widget.challengeId,
        entryId: widget.entryId,
        text: text,
        parentId: _replyToId ?? '',
      );
      _controller.clear();
      setState(() {
        _replyToId = null;
        _replyToName = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleLike(Comment c) async {
    if (!await ensureLoggedIn(context, message: 'Entre para curtir')) return;
    final wasLiked = _liked.contains(c.id);
    setState(() {
      if (wasLiked) {
        _liked.remove(c.id);
      } else {
        _liked.add(c.id);
      }
    });
    try {
      await _repo.toggleLike(c.id);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (wasLiked) {
          _liked.add(c.id);
        } else {
          _liked.remove(c.id);
        }
      });
    }
  }

  void _startReply(Comment c) {
    setState(() {
      _replyToId = c.id;
      _replyToName = c.userName ?? 'Usuário';
    });
    _inputFocus.requestFocus();
  }

  Future<void> _generateFake() async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gerar comentário'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          maxLength: 500,
          decoration: const InputDecoration(
            hintText: 'Texto do comentário...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Gerar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final text = ctrl.text.trim();
    if (text.isEmpty) return;
    try {
      await _repo.adminGenerateComment(
        challengeId: widget.challengeId,
        entryId: widget.entryId,
        text: text,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  // ── Admin: editar comentário (texto + curtidas) ─────────────────────────────
  Future<void> _adminEditComment(Comment c) async {
    final textCtrl = TextEditingController(text: c.text);
    final likesCtrl = TextEditingController(text: '${c.likeCount}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar comentário'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: textCtrl,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                  labelText: 'Texto', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: likesCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Curtidas', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.adminUpdateComment(
        commentId: c.id,
        text: textCtrl.text.trim().isEmpty ? null : textCtrl.text.trim(),
        likeCount: int.tryParse(likesCtrl.text.trim()),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Comentário atualizado ✅')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  // ── Admin: excluir comentário ───────────────────────────────────────────────
  Future<void> _adminDeleteComment(Comment c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir comentário?'),
        content: const Text(
            'O comentário (e respostas, se houver) será removido. '
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
    if (ok != true) return;
    try {
      await _repo.adminDeleteComment(c.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Text(
              'Comentários',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const Spacer(),
            if (widget.isAdmin)
              TextButton.icon(
                onPressed: _generateFake,
                icon: const Icon(Icons.auto_fix_high, size: 16),
                label: const Text('Gerar', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        StreamBuilder<List<Comment>>(
          stream: _repo.watchComments(widget.challengeId, widget.entryId),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(8),
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            final all = snapshot.data!;
            _ensurePhotos(all); // async; re-renderiza quando as fotos chegam
            if (all.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Nenhum comentário ainda.',
                  style: TextStyle(color: Colors.black45, fontSize: 12),
                ),
              );
            }
            final tops = all.where((c) => !c.isReply).toList();
            final repliesByParent = <String, List<Comment>>{};
            for (final c in all.where((c) => c.isReply)) {
              repliesByParent.putIfAbsent(c.parentId, () => []).add(c);
            }

            final widgets = <Widget>[];
            for (final top in tops) {
              widgets.add(_CommentTile(
                comment: top,
                photoUrl: _photos[top.userId],
                isLiked: _liked.contains(top.id),
                onLike: () => _toggleLike(top),
                onReply: () => _startReply(top),
                isAdmin: widget.isAdmin,
                onAdminEdit: () => _adminEditComment(top),
                onAdminDelete: () => _adminDeleteComment(top),
              ));
              for (final reply in (repliesByParent[top.id] ?? [])) {
                widgets.add(Padding(
                  padding: const EdgeInsets.only(left: 36),
                  child: _CommentTile(
                    comment: reply,
                    photoUrl: _photos[reply.userId],
                    isLiked: _liked.contains(reply.id),
                    onLike: () => _toggleLike(reply),
                    isAdmin: widget.isAdmin,
                    onAdminEdit: () => _adminEditComment(reply),
                    onAdminDelete: () => _adminDeleteComment(reply),
                  ),
                ));
              }
            }
            return Column(children: widgets);
          },
        ),
        if (uid != null) ...[
          const SizedBox(height: 8),
          if (_replyToId != null)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEDF1F8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.reply, size: 14, color: Colors.black54),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Respondendo a $_replyToName',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54),
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() {
                      _replyToId = null;
                      _replyToName = null;
                    }),
                    child: const Icon(Icons.close, size: 16),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _inputFocus,
                  maxLines: 1,
                  maxLength: 500,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: _replyToId != null
                        ? 'Escreva sua resposta...'
                        : 'Adicionar comentário...',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _sending
                  ? const SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      onPressed: _submit,
                      icon: const Icon(Icons.send),
                      tooltip: 'Enviar',
                      visualDensity: VisualDensity.compact,
                    ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  final Comment comment;
  final String? photoUrl;
  final bool isLiked;
  final VoidCallback onLike;
  final VoidCallback? onReply;
  final bool isAdmin;
  final VoidCallback? onAdminEdit;
  final VoidCallback? onAdminDelete;

  const _CommentTile({
    required this.comment,
    required this.isLiked,
    required this.onLike,
    this.photoUrl,
    this.onReply,
    this.isAdmin = false,
    this.onAdminEdit,
    this.onAdminDelete,
  });

  String _formatDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inHours < 1) return '${diff.inMinutes}min atrás';
    if (diff.inDays < 1) return '${diff.inHours}h atrás';
    return '${diff.inDays}d atrás';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Foto real do perfil de quem comentou (fallback: ícone padrão).
          SafeAvatar(photoUrl: photoUrl, radius: 13),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        comment.userName ?? 'Usuário',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formatDate(comment.createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
                Text(comment.text, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 2),
                // ── Ações: curtir + responder ──────────────────────────
                Row(
                  children: [
                    InkWell(
                      onTap: onLike,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 2, vertical: 2),
                        child: Row(
                          children: [
                            Icon(
                              isLiked
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              size: 15,
                              color: isLiked ? Colors.red : Colors.black45,
                            ),
                            if (comment.likeCount > 0) ...[
                              const SizedBox(width: 3),
                              Text(
                                '${comment.likeCount}',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.black54),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (onReply != null) ...[
                      const SizedBox(width: 14),
                      InkWell(
                        onTap: onReply,
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 2, vertical: 2),
                          child: Text(
                            'Responder',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (isAdmin)
            SizedBox(
              width: 26,
              child: PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                iconSize: 16,
                tooltip: 'Admin',
                icon: const Icon(Icons.more_vert,
                    size: 16, color: Colors.black38),
                onSelected: (v) {
                  if (v == 'edit') onAdminEdit?.call();
                  if (v == 'delete') onAdminDelete?.call();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Editar')),
                  PopupMenuItem(
                    value: 'delete',
                    child:
                        Text('Excluir', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
