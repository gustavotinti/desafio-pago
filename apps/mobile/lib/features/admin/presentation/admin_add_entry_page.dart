import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/widgets/image_crop_page.dart';
import '../../../core/widgets/safe_avatar.dart';
import '../../../core/widgets/web_frame.dart';

/// Admin adiciona uma participação a um desafio, atribuída a um **usuário
/// virtual** escolhido. Suporta texto e imagem (com recorte no app).
class AdminAddEntryPage extends StatefulWidget {
  final String challengeId;
  final String challengeTitle;

  const AdminAddEntryPage({
    super.key,
    required this.challengeId,
    required this.challengeTitle,
  });

  @override
  State<AdminAddEntryPage> createState() => _AdminAddEntryPageState();
}

class _AdminAddEntryPageState extends State<AdminAddEntryPage> {
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  final _searchCtrl = TextEditingController();

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _results = [];
  bool _searching = false;

  String? _userId;
  String _userName = '';
  String _userPhoto = '';

  final String _type = 'image'; // só imagem por enquanto (texto/vídeo off)
  Uint8List? _mediaBytes; // imagem recortada
  String _mediaExt = 'jpg';
  String _mediaMime = 'image/jpeg';

  bool _saving = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final raw = _searchCtrl.text.trim().toLowerCase();
    final q = raw.startsWith('@') ? raw.substring(1) : raw;
    if (q.isEmpty) return;
    setState(() => _searching = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isGreaterThanOrEqualTo: q)
          .where('username', isLessThan: '$q~')
          .orderBy('username')
          .limit(30)
          .get();
      final virtual =
          snap.docs.where((d) => d.data()['isVirtual'] == true).toList();
      if (mounted) setState(() => _results = virtual);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _pickImage() async {
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    final cropped = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(builder: (_) => ImageCropPage(imageBytes: bytes)),
    );
    if (cropped == null || !mounted) return;
    setState(() {
      _mediaBytes = cropped;
      _mediaExt = 'jpg';
      _mediaMime = 'image/jpeg';
    });
  }

  Future<String> _upload(Uint8List bytes) async {
    final ref = FirebaseStorage.instance.ref(
        'entries/${widget.challengeId}/admin_'
        '${DateTime.now().millisecondsSinceEpoch}.$_mediaExt');
    await ref.putData(bytes, SettableMetadata(contentType: _mediaMime));
    return ref.getDownloadURL();
  }

  Future<void> _submit() async {
    if (_userId == null) {
      _snack('Escolha um usuário virtual');
      return;
    }
    if (_mediaBytes == null) {
      _snack('Selecione a imagem');
      return;
    }
    setState(() => _saving = true);
    try {
      final contentUrl = await _upload(_mediaBytes!);
      await _functions.httpsCallable('adminSubmitDemoEntry').call({
        'challengeId': widget.challengeId,
        'contentType': _type,
        'userId': _userId,
        'contentUrl': contentUrl,
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Participação adicionada como $_userName ✅')),
      );
    } on FirebaseFunctionsException catch (e) {
      if (mounted) _snack(e.message ?? 'Erro');
    } catch (e) {
      if (mounted) _snack(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Adicionar participação')),
      body: WebFrame(
        maxWidth: 600,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(widget.challengeTitle,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 16),

            // ── 1) Usuário virtual ───────────────────────────────────────
            const Text('1. Quem participa (usuário virtual)',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (_userId != null)
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: SafeAvatar(photoUrl: _userPhoto, radius: 18),
                  title: Text(_userName),
                  trailing: TextButton(
                    onPressed: () => setState(() => _userId = null),
                    child: const Text('Trocar'),
                  ),
                ),
              )
            else ...[
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  labelText: 'Buscar por @username',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: _searching
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.arrow_forward),
                    onPressed: _searching ? null : _search,
                  ),
                ),
                onSubmitted: (_) => _search(),
              ),
              const SizedBox(height: 8),
              ..._results.map((d) {
                final m = d.data();
                final name = m['name'] as String? ?? '';
                final username = m['username'] as String? ?? '';
                final photo = m['photoUrl'] as String? ?? '';
                return ListTile(
                  leading: SafeAvatar(photoUrl: photo, radius: 16),
                  title: Text(name),
                  subtitle: Text('@$username'),
                  onTap: () => setState(() {
                    _userId = d.id;
                    _userName = name;
                    _userPhoto = photo;
                    _results = [];
                    _searchCtrl.clear();
                  }),
                );
              }),
            ],
            const Divider(height: 32),

            // ── 2) Conteúdo (só imagem por enquanto) ─────────────────────
            const Text('2. Conteúdo (imagem)',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.photo_library),
              label: const Text('Escolher e recortar imagem'),
            ),
            if (_mediaBytes != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(_mediaBytes!,
                    height: 220, fit: BoxFit.contain),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add),
                label: Text(_saving ? 'Enviando...' : 'Adicionar participação'),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
