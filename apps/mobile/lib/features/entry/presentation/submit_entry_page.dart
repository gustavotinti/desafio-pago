import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/widgets/web_frame.dart';
import '../application/submit_entry.dart';
import '../domain/entities/content_type.dart';
import '../infrastructure/entry_repository.dart';
import '../../../core/widgets/image_crop_page.dart';

// Formatos aceitos: 9:16, 4:5, 1:1 — garantidos pelo editor de recorte.
// Vídeo desativado por enquanto — só texto e imagem.
const _maxTextLength = 5000;

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
  // Só imagem por enquanto — texto e vídeo desativados.
  final ContentType _selectedType = ContentType.image;
  XFile? _selectedFile;
  bool _isLoading = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  // ── Pegar imagem + recortar no formato certo ──────────────────────────────
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    // Abre o editor de recorte — qualquer imagem vira 9:16, 4:5 ou 1:1.
    final cropped = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(builder: (_) => ImageCropPage(imageBytes: bytes)),
    );
    if (cropped == null || !mounted) return; // usuário cancelou

    setState(() {
      _selectedFile = XFile.fromData(
        cropped,
        mimeType: 'image/jpeg',
        name: 'participacao.jpg',
      );
    });
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
          SnackBar(content: Text(I18n.tr('select_file'))),
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
          SnackBar(content: Text(I18n.tr('entry_sent'))),
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
            // ── Imagem (único tipo por enquanto) ────────────────────
            Text(
              I18n.tr('your_entry'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _FormatGuide(
              lines: [
                I18n.tr('img_rule_title'),
                '  9:16 (1080 × 1920)  ·  4:5 (1080 × 1350)',
                '  1:1 (1080 × 1080)',
                I18n.tr('img_rule_size'),
                I18n.tr('img_rule_crop'),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _pickImage,
              icon: Icon(_selectedFile == null
                  ? Icons.photo_library
                  : Icons.crop_rotate),
              label: Text(_selectedFile == null
                  ? I18n.tr('choose_image')
                  : I18n.tr('change_image')),
            ),
            _buildImagePreview(),
            if (_selectedFile != null) ...[
              const SizedBox(height: 8),
              _SelectedFileTile(name: _selectedFile!.name),
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
                    : Text(I18n.tr('send_entry')),
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
