import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/widgets/web_frame.dart';
import '../infrastructure/update_profile_repository.dart';

class EditProfilePage extends StatefulWidget {
  final String currentName;
  final String currentBio;
  final String currentPixKey;
  final String? currentPhotoUrl;
  final String currentUsername;
  final bool pixLocked;

  const EditProfilePage({
    super.key,
    required this.currentName,
    required this.currentBio,
    required this.currentPixKey,
    required this.currentUsername,
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
  late final TextEditingController _usernameController;
  XFile? _newPhoto;
  bool _isLoading = false;

  // Username availability state
  Timer? _debounce;
  bool _checkingUsername = false;
  bool? _usernameAvailable; // null = unchanged / not checked
  String _usernameError = '';

  final _repo = UpdateProfileRepository();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentName);
    _bioController = TextEditingController(text: widget.currentBio);
    _pixController = TextEditingController(text: widget.currentPixKey);
    _usernameController =
        TextEditingController(text: widget.currentUsername);
    _usernameController.addListener(_onUsernameChanged);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _pixController.dispose();
    _usernameController.removeListener(_onUsernameChanged);
    _usernameController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onUsernameChanged() {
    final val = _usernameController.text.trim().toLowerCase();

    // Reset state
    _debounce?.cancel();
    if (val == widget.currentUsername) {
      setState(() {
        _checkingUsername = false;
        _usernameAvailable = null;
        _usernameError = '';
      });
      return;
    }

    // Validate format
    final valid = RegExp(r'^[a-z0-9][a-z0-9._]{2,29}$').hasMatch(val);
    if (!valid) {
      setState(() {
        _checkingUsername = false;
        _usernameAvailable = false;
        _usernameError = 'Use 3–30 chars: letras, números, ponto ou _.';
      });
      return;
    }

    setState(() {
      _checkingUsername = true;
      _usernameAvailable = null;
      _usernameError = '';
    });

    _debounce = Timer(const Duration(milliseconds: 600), () async {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final taken = await _repo.isUsernameTaken(val, uid);
      if (!mounted) return;
      if (_usernameController.text.trim().toLowerCase() != val) return;
      setState(() {
        _checkingUsername = false;
        _usernameAvailable = !taken;
        _usernameError = taken ? 'Username já está em uso.' : '';
      });
    });
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

    final newUsername = _usernameController.text.trim().toLowerCase();
    final usernameChanged = newUsername != widget.currentUsername;

    // Don't save if username is invalid or taken
    if (usernameChanged && _usernameAvailable != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_usernameError.isNotEmpty
              ? _usernameError
              : 'Aguarde a verificação do username.'),
        ),
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isLoading = true);
    try {
      await _repo.updateProfile(
        userId: uid,
        name: name,
        bio: _bioController.text.trim(),
        pixKey: _pixController.text.trim(),
        newUsername: usernameChanged ? newUsername : null,
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
    if (_newPhoto != null) return null;
    if (widget.currentPhotoUrl != null &&
        widget.currentPhotoUrl!.isNotEmpty) {
      return NetworkImage(widget.currentPhotoUrl!);
    }
    return null;
  }

  // ── Username field suffix icon ─────────────────────────────────────────────
  Widget? _usernameSuffix() {
    if (_checkingUsername) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_usernameAvailable == true) {
      return const Icon(Icons.check_circle, color: Colors.green, size: 20);
    }
    if (_usernameAvailable == false) {
      return const Icon(Icons.cancel, color: Colors.red, size: 20);
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
              // ── Foto ──────────────────────────────────────────────────────
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
                        child: const Icon(Icons.edit,
                            size: 16, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Center(child: Text('Toque para alterar a foto')),
              const SizedBox(height: 24),

              // ── Nome ──────────────────────────────────────────────────────
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nome',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // ── Username ──────────────────────────────────────────────────
              TextField(
                controller: _usernameController,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.text,
                inputFormatters: [
                  // Force lowercase on every keystroke
                  TextInputFormatter.withFunction((oldVal, newVal) {
                    final lower = newVal.text.toLowerCase();
                    return newVal.copyWith(
                      text: lower,
                      selection: newVal.selection.copyWith(
                        baseOffset:
                            newVal.selection.baseOffset.clamp(0, lower.length),
                        extentOffset:
                            newVal.selection.extentOffset.clamp(0, lower.length),
                      ),
                    );
                  }),
                ],
                decoration: InputDecoration(
                  labelText: 'Username',
                  prefixText: '@',
                  border: const OutlineInputBorder(),
                  helperText: 'Letras minúsculas, números, ponto ou _',
                  errorText: _usernameError.isNotEmpty
                      ? _usernameError
                      : null,
                  suffixIcon: _usernameSuffix() != null
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: _usernameSuffix(),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 16),

              // ── Bio ───────────────────────────────────────────────────────
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

              // ── Chave Pix ─────────────────────────────────────────────────
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
