import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../application/submit_entry.dart';
import '../domain/entities/content_type.dart';
import '../infrastructure/entry_repository.dart';

class SubmitEntryPage extends StatefulWidget {
  final String challengeId;
  final String challengeTitle;

  const SubmitEntryPage({
    super.key,
    required this.challengeId,
    required this.challengeTitle,
  });

  @override
  State<SubmitEntryPage> createState() => _SubmitEntryPageState();
}

class _SubmitEntryPageState extends State<SubmitEntryPage> {
  final _textController = TextEditingController();
  ContentType _selectedType = ContentType.text;
  File? _selectedFile;
  bool _isLoading = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) setState(() => _selectedFile = File(picked.path));
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked != null) setState(() => _selectedFile = File(picked.path));
  }

  Future<void> _submit() async {
    if (_selectedType == ContentType.text &&
        _textController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escreva seu conteúdo')),
      );
      return;
    }

    if (_selectedType != ContentType.text && _selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione um arquivo')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await SubmitEntry(EntryRepository()).call(
        challengeId: widget.challengeId,
        contentType: _selectedType,
        contentText: _selectedType == ContentType.text
            ? _textController.text.trim()
            : null,
        contentFile: _selectedFile,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Participação enviada!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.challengeTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tipo de conteúdo',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SegmentedButton<ContentType>(
              segments: const [
                ButtonSegment(
                  value: ContentType.text,
                  label: Text('Texto'),
                  icon: Icon(Icons.text_fields),
                ),
                ButtonSegment(
                  value: ContentType.image,
                  label: Text('Imagem'),
                  icon: Icon(Icons.image),
                ),
                ButtonSegment(
                  value: ContentType.video,
                  label: Text('Vídeo'),
                  icon: Icon(Icons.videocam),
                ),
              ],
              selected: {_selectedType},
              onSelectionChanged: (s) => setState(() {
                _selectedType = s.first;
                _selectedFile = null;
                _textController.clear();
              }),
            ),
            const SizedBox(height: 20),
            if (_selectedType == ContentType.text)
              TextField(
                controller: _textController,
                decoration: const InputDecoration(
                  labelText: 'Seu conteúdo',
                  border: OutlineInputBorder(),
                ),
                maxLines: 5,
              ),
            if (_selectedType == ContentType.image) ...[
              ElevatedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.photo_library),
                label: const Text('Escolher imagem'),
              ),
              if (_selectedFile != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    _selectedFile!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
            ],
            if (_selectedType == ContentType.video) ...[
              ElevatedButton.icon(
                onPressed: _pickVideo,
                icon: const Icon(Icons.video_library),
                label: const Text('Escolher vídeo'),
              ),
              if (_selectedFile != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Arquivo selecionado: ${_selectedFile!.path.split('/').last}',
                  style: const TextStyle(color: Colors.green),
                ),
              ],
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enviar participação'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
