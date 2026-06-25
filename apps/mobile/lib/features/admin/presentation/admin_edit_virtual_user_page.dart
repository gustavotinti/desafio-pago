import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/avatars.dart';
import '../../../core/portraits.dart';
import '../../../core/widgets/image_crop_page.dart';
import '../../../core/widgets/web_frame.dart';
import '../infrastructure/admin_repository.dart';

class AdminEditVirtualUserPage extends StatefulWidget {
  final String userId;
  final Map<String, dynamic> data;

  const AdminEditVirtualUserPage({
    super.key,
    required this.userId,
    required this.data,
  });

  @override
  State<AdminEditVirtualUserPage> createState() =>
      _AdminEditVirtualUserPageState();
}

class _AdminEditVirtualUserPageState extends State<AdminEditVirtualUserPage> {
  late final TextEditingController _name;
  late final TextEditingController _username;
  late final TextEditingController _bio;
  late bool _isVerified;

  late String _photoUrl; // URL atual (biblioteca/retrato/existente)
  Uint8List? _photoBytes; // upload pendente
  late final String _originalPhotoUrl;

  bool _saving = false;
  final _repo = AdminRepository();

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.data['name'] as String? ?? '');
    _username =
        TextEditingController(text: widget.data['username'] as String? ?? '');
    _bio = TextEditingController(text: widget.data['bio'] as String? ?? '');
    _isVerified = widget.data['isVerified'] == true;
    _photoUrl = widget.data['photoUrl'] as String? ?? '';
    _originalPhotoUrl = _photoUrl;
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _bio.dispose();
    super.dispose();
  }

  ImageProvider? get _preview {
    if (_photoBytes != null) return MemoryImage(_photoBytes!);
    if (_photoUrl.isNotEmpty) return NetworkImage(_photoUrl);
    return null;
  }

  Future<void> _pickUpload() async {
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    // Recorta em 1:1 (avatar) antes de salvar.
    final cropped = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(
        builder: (_) => ImageCropPage(
          imageBytes: bytes,
          ratios: ImageCropPage.squareOnly,
        ),
      ),
    );
    if (cropped == null || !mounted) return;
    setState(() => _photoBytes = cropped);
  }

  Future<void> _pickFromGrid(List<String> urls, String title) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ImageGridSheet(urls: urls, title: title),
    );
    if (chosen == null) return;
    setState(() {
      _photoUrl = chosen;
      _photoBytes = null;
    });
  }

  Future<void> _pickPortraits() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _PortraitSheet(),
    );
    if (chosen == null) return;
    setState(() {
      _photoUrl = chosen;
      _photoBytes = null;
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nome não pode ficar vazio')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      String? photoUrl;
      String? photoBase64;
      if (_photoBytes != null) {
        photoBase64 = base64Encode(_photoBytes!);
      } else if (_photoUrl != _originalPhotoUrl) {
        photoUrl = _photoUrl;
      }

      await _repo.updateVirtualUser(
        userId: widget.userId,
        name: _name.text.trim(),
        username: _username.text.trim().toLowerCase(),
        bio: _bio.text.trim(),
        isVerified: _isVerified,
        photoUrl: photoUrl,
        photoBase64: photoBase64,
        photoContentType: photoBase64 != null ? 'image/jpeg' : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perfil atualizado ✅')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar perfil'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Salvar'),
          ),
        ],
      ),
      body: WebFrame(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: CircleAvatar(
                radius: 48,
                backgroundImage: _preview,
                child: _preview == null
                    ? const Icon(Icons.person, size: 48)
                    : null,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () =>
                      _pickFromGrid(AvatarLibrary.all, 'Avatares'),
                  icon: const Icon(Icons.face_retouching_natural, size: 18),
                  label: const Text('Avatares'),
                ),
                OutlinedButton.icon(
                  onPressed: _pickPortraits,
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Retratos'),
                ),
                OutlinedButton.icon(
                  onPressed: _pickUpload,
                  icon: const Icon(Icons.upload, size: 18),
                  label: const Text('Enviar foto'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nome',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _username,
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters: [
                TextInputFormatter.withFunction((oldV, newV) =>
                    newV.copyWith(text: newV.text.toLowerCase())),
              ],
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixText: '@',
                border: OutlineInputBorder(),
                helperText: 'Letras minúsculas, números, ponto ou _',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _bio,
              maxLines: 3,
              maxLength: 150,
              decoration: const InputDecoration(
                labelText: 'Bio',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Selo verificado'),
              secondary: const Icon(Icons.verified, color: Colors.blue),
              value: _isVerified,
              onChanged: (v) => setState(() => _isVerified = v),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Salvando...' : 'Salvar alterações'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Grade simples de imagens (avatares) ────────────────────────────────────────

class _ImageGridSheet extends StatelessWidget {
  final List<String> urls;
  final String title;
  const _ImageGridSheet({required this.urls, required this.title});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemCount: urls.length,
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => Navigator.pop(context, urls[i]),
                  child: CircleAvatar(
                    backgroundColor: const Color(0xFFE9EEF6),
                    backgroundImage: NetworkImage(urls[i]),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Retratos realistas (abas Homens / Mulheres) ────────────────────────────────

class _PortraitSheet extends StatelessWidget {
  const _PortraitSheet();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            children: [
              const TabBar(
                tabs: [Tab(text: 'Homens'), Tab(text: 'Mulheres')],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _portraitGrid(context, PortraitLibrary.men),
                    _portraitGrid(context, PortraitLibrary.women),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _portraitGrid(BuildContext context, List<String> urls) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: urls.length,
      itemBuilder: (_, i) => GestureDetector(
        onTap: () => Navigator.pop(context, urls[i]),
        child: CircleAvatar(
          backgroundColor: const Color(0xFFE9EEF6),
          backgroundImage: NetworkImage(urls[i]),
        ),
      ),
    );
  }
}
