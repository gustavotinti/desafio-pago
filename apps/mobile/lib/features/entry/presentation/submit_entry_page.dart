import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/utils/friendly_error.dart';
import '../../../core/utils/video_link.dart';
import '../../../core/widgets/video_link_view.dart';
import '../../../core/widgets/web_frame.dart';
import '../application/submit_entry.dart';
import '../domain/entities/content_type.dart';
import '../infrastructure/entry_repository.dart';
import '../../../core/widgets/image_crop_page.dart';

// Imagem: 9:16, 4:5 ou 1:1 — garantidos pelo editor de recorte.
// Vídeo: por LINK (YouTube Shorts / Reels do Instagram), vertical e com o
// código do participante no título/legenda — o vídeo fica hospedado lá
// (custo zero). Texto e vídeo enviado como arquivo seguem desativados.

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
  final _linkController = TextEditingController();
  ContentType _type = ContentType.image;
  XFile? _selectedFile;
  VideoLink? _link;
  bool _isLoading = false;

  /// Código deste participante neste desafio — o servidor recalcula igual.
  late final String _code = VideoLink.verificationCode(
      FirebaseAuth.instance.currentUser?.uid ?? '', widget.challengeId);

  @override
  void dispose() {
    _linkController.dispose();
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

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: _code));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(I18n.tr('video_code_copied'))));
  }

  // ── Enviar ───────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    final isVideo = _type == ContentType.videoLink;
    if (isVideo && _link == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(I18n.tr('video_link_invalid'))));
      return;
    }
    if (!isVideo && _selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(I18n.tr('select_file'))),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final check = await SubmitEntry(EntryRepository()).call(
        challengeId: widget.challengeId,
        contentType: _type,
        contentFile: isVideo ? null : _selectedFile,
        videoUrl: isVideo ? _linkController.text.trim() : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(I18n.tr(
                  check == 'pending' ? 'video_sent_pending' : 'entry_sent'))),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        // O servidor responde no idioma do site e com o motivo exato (ex.:
        // "coloque o código DPXXXXX no título") — mostra a mensagem dele.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 8),
            content: Text(friendlyError(e, serverLocalized: true))));
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

  List<Widget> _imageSection() => [
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
          icon: Icon(
              _selectedFile == null ? Icons.photo_library : Icons.crop_rotate),
          label: Text(_selectedFile == null
              ? I18n.tr('choose_image')
              : I18n.tr('change_image')),
        ),
        _buildImagePreview(),
        if (_selectedFile != null) ...[
          const SizedBox(height: 8),
          _SelectedFileTile(name: _selectedFile!.name),
        ],
      ];

  List<Widget> _videoSection() {
    final typed = _linkController.text.trim();
    final link = _link;
    return [
      _FormatGuide(
        lines: [
          I18n.tr('video_rules_title'),
          I18n.tr('video_rule_vertical'),
          I18n.tr('video_rule_public'),
          I18n.tr('video_rule_code'),
        ],
      ),
      const SizedBox(height: 12),
      _CodeBox(code: _code, onCopy: _copyCode),
      const SizedBox(height: 16),
      TextField(
        controller: _linkController,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: I18n.tr('video_link_label'),
          hintText: 'youtube.com/shorts/…  ·  instagram.com/reel/…',
          prefixIcon: const Icon(Icons.link),
          border: const OutlineInputBorder(),
          errorText: typed.isNotEmpty && link == null
              ? I18n.tr('video_link_invalid')
              : null,
          errorMaxLines: 3,
        ),
        onChanged: (v) => setState(() => _link = VideoLink.parse(v)),
      ),
      if (link != null) ...[
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                I18n.tr(link.isYouTube
                    ? 'video_detected_youtube'
                    : 'video_detected_instagram'),
                style: const TextStyle(color: Colors.green, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Center(
          child: SizedBox(
            width: 150,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: VideoLinkCover(
                  provider: link.provider,
                  thumbUrl: link.thumbUrl,
                  onTap: () => showVideoLinkPlayer(context,
                      provider: link.provider,
                      embedUrl: link.embedUrl,
                      url: link.url),
                ),
              ),
            ),
          ),
        ),
        if (!link.isYouTube) ...[
          const SizedBox(height: 10),
          Text(
            I18n.tr('video_ig_review_note'),
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ],
    ];
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
            Text(
              I18n.tr('your_entry'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            // ── Imagem ou vídeo por link ────────────────────────────
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ContentType>(
                segments: [
                  ButtonSegment(
                    value: ContentType.image,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(I18n.tr('entry_kind_image')),
                  ),
                  ButtonSegment(
                    value: ContentType.videoLink,
                    icon: const Icon(Icons.smart_display_outlined),
                    label: Text(I18n.tr('entry_kind_video')),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: _isLoading
                    ? null
                    : (s) => setState(() => _type = s.first),
              ),
            ),
            const SizedBox(height: 16),
            ...(_type == ContentType.videoLink
                ? _videoSection()
                : _imageSection()),

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

// ── Código de verificação do vídeo ───────────────────────────────────────────

class _CodeBox extends StatelessWidget {
  final String code;
  final VoidCallback onCopy;
  const _CodeBox({required this.code, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF5B301)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(I18n.tr('video_your_code'),
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black54)),
                    SelectableText(
                      code,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: I18n.tr('video_code_copied'),
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            I18n.tr('video_rule_why'),
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
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
