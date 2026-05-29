import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/widgets/web_frame.dart';
import '../infrastructure/update_profile_repository.dart';

class EditProfilePage extends StatefulWidget {
  final String currentName;
  final String currentBio;
  final String currentPixKey;
  final String? currentPhotoUrl;
  final bool pixLocked;

  const EditProfilePage({
    super.key,
    required this.currentName,
    required this.currentBio,
    required this.currentPixKey,
    this.currentPhotoUrl,
    this.pixLocked = false,
  });

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  late final TextEditingController _pixController;
  XFile? _newPhoto;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentName);
    _bioController = TextEditingController(text: widget.currentBio);
    _pixController = TextEditingController(text: widget.currentPixKey);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _pixController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked != null) setState(() => _newPhoto = picked);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nome não pode estar vazio')),
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isLoading = true);
    try {
      await UpdateProfileRepository().updateProfile(
        userId: uid,
        name: name,
        bio: _bioController.text.trim(),
        pixKey: _pixController.text.trim(),
        photo: _newPhoto,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  ImageProvider? get _photoProvider {
    if (_newPhoto != null) {
      // XFile.path works on mobile; on web we rely on network preview only
      return null;
    }
    if (widget.currentPhotoUrl != null && widget.currentPhotoUrl!.isNotEmpty) {
      return NetworkImage(widget.currentPhotoUrl!);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar perfil'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _save,
            child: _isLoading
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
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // — Foto —
            Center(
              child: GestureDetector(
                onTap: _pickPhoto,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundImage: _photoProvider,
                      child: _photoProvider == null && _newPhoto == null
                          ? const Icon(Icons.person, size: 48)
                          : null,
                    ),
                    Container(
                      decoration: const BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(4),
                      child:
                          const Icon(Icons.edit, size: 16, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Center(child: Text('Toque para alterar a foto')),
            const SizedBox(height: 24),

            // — Nome —
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nome',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // — Bio —
            TextField(
              controller: _bioController,
              decoration: const InputDecoration(
                labelText: 'Bio',
                border: OutlineInputBorder(),
                hintText: 'Conte um pouco sobre você...',
              ),
              maxLines: 3,
              maxLength: 150,
            ),
            const SizedBox(height: 8),

            // — Chave Pix —
            TextField(
              controller: _pixController,
              enabled: !widget.pixLocked,
              decoration: InputDecoration(
                labelText: 'Chave Pix',
                border: const OutlineInputBorder(),
                helperText: widget.pixLocked
                    ? 'Não pode alterar com saque pendente'
                    : null,
                helperStyle: const TextStyle(color: Colors.orange),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
