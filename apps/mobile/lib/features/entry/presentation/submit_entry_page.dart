import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/widgets/web_frame.dart';
import '../application/submit_entry.dart';
import '../domain/entities/content_type.dart';
import '../infrastructure/entry_repository.dart';

// Aspect ratios aceitos: 9:16, 4:5, 1:1 (vertical/quadrado — sem 16:9)
const _allowedRatios = [9 / 16, 4 / 5, 1.0];
const _ratioTolerance = 0.08; // 8% de margem
const _maxTextLength = 5000;
const _maxVideoSeconds = 15;

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
  XFile? _selectedFile;
  bool _isLoading = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  // ── Valida aspect ratio de uma imagem ────────────────────────────────────
  Future<bool> _isValidAspectRatio(XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final w = img.width.toDouble();
      final h = img.height.toDouble();
      img.dispose();
      if (h == 0) return false;
      final ratio = w / h;
      return _allowedRatios.any(
        (a) => (ratio - a).abs() <= a * _ratioTolerance,
      );
    } catch (_) {
      return true; // Se não conseguir ler, deixa passar
    }
  }

  // ── Pegar imagem ─────────────────────────────────────────────────────────
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final valid = await _isValidAspectRatio(picked);
    if (!valid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Proporção inválida. Use 9:16 (1080×1920), 4:5 (1080×1350) '
              'ou 1:1 (1080×1080).\n'
              'Recorte a imagem antes de selecioná-la.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    setState(() => _selectedFile = picked);
  }

  // ── Pegar vídeo ──────────────────────────────────────────────────────────
  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: _maxVideoSeconds),
    );
    if (picked == null) return;
    setState(() => _selectedFile = picked);
  }

  // ── Enviar ───────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (_selectedType == ContentType.text) {
      final text = _textController.text.trim();
      if (text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Escreva seu conteúdo')),
        );
        return;
      }
      if (text.length > _maxTextLength) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Texto muito longo (${text.length}/$_maxTextLength caracteres)',
            ),
          ),
        );
        return;
      }
    } else {
      if (_selectedFile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecione um arquivo')),
        );
        return;
      }
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Preview da imagem ─────────────────────────────────────────────────────
  Widget _buildImagePreview() {
    if (_selectedFile == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: kIsWeb
            ? Image.network(
                _selectedFile!.path,
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
              )
            : Image.file(
                File(_selectedFile!.path),
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.challengeTitle)),
      body: WebFrame(
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Seletor de tipo ─────────────────────────────────────
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

            // ── Texto ───────────────────────────────────────────────
            if (_selectedType == ContentType.text)
              TextField(
                controller: _textController,
                maxLines: 8,
                maxLength: _maxTextLength,
                decoration: const InputDecoration(
                  labelText: 'Seu conteúdo',
                  alignLabelWithHint: true,
                ),
              ),

            // ── Imagem ──────────────────────────────────────────────
            if (_selectedType == ContentType.image) ...[
              _FormatGuide(
                lines: const [
                  'Proporções aceitas:',
                  '  9:16 (1080 × 1920)  ·  4:5 (1080 × 1350)',
                  '  1:1 (1080 × 1080)',
                  'Tamanho máximo: 10 MB',
                  'Se necessário, recorte a imagem no seu dispositivo antes de selecionar.',
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.photo_library),
                label: const Text('Escolher imagem'),
              ),
              _buildImagePreview(),
              if (_selectedFile != null) ...[
                const SizedBox(height: 8),
                _SelectedFileTile(name: _selectedFile!.name),
              ],
            ],

            // ── Vídeo ───────────────────────────────────────────────
            if (_selectedType == ContentType.video) ...[
              _FormatGuide(
                lines: const [
                  'Proporções aceitas:',
                  '  9:16 (1080 × 1920)  ·  4:5 (1080 × 1350)',
                  '  1:1 (1080 × 1080)',
                  'Duração máxima: 15 segundos',
                  'Tamanho máximo: 50 MB',
                  'Edite e recorte antes de selecionar, se necessário.',
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _pickVideo,
                icon: const Icon(Icons.video_library),
                label: const Text('Escolher vídeo'),
              ),
              if (_selectedFile != null) ...[
                const SizedBox(height: 8),
                _SelectedFileTile(name: _selectedFile!.name),
              ],
            ],

            const SizedBox(height: 28),

            // ── Enviar ──────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Enviar participação'),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

// ── Caixa de orientações ──────────────────────────────────────────────────────

class _FormatGuide extends StatelessWidget {
  final List<String> lines;
  const _FormatGuide({required this.lines});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBDCAF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines
            .map(
              (l) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ',
                        style: TextStyle(
                            color: Color(0xFF003b8a),
                            fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Text(
                        l,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF003b8a)),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

// ── Arquivo selecionado ───────────────────────────────────────────────────────

class _SelectedFileTile extends StatelessWidget {
  final String name;
  const _SelectedFileTile({required this.name});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 16),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(color: Colors.green, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
