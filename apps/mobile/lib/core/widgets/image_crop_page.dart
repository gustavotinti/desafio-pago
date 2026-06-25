import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

/// Editor de recorte de imagem compartilhado.
///
/// Recebe os bytes originais e devolve (via `Navigator.pop`) os bytes já
/// recortados na proporção escolhida. Funciona na web e no mobile — qualquer
/// usuário enquadra a imagem no formato certo em vez de ser barrado.
///
/// Use [ratios] para limitar as proporções (ex.: [ImageCropPage.squareOnly]
/// para foto de perfil). Sem [ratios], oferece 9:16, 4:5 e 1:1.
class ImageCropPage extends StatefulWidget {
  final Uint8List imageBytes;
  final Map<String, double>? ratios;
  final String? initialRatio;

  const ImageCropPage({
    super.key,
    required this.imageBytes,
    this.ratios,
    this.initialRatio,
  });

  /// Atalho para foto de perfil/avatar (quadrado 1:1).
  static const Map<String, double> squareOnly = {'1:1': 1.0};

  @override
  State<ImageCropPage> createState() => _ImageCropPageState();
}

class _ImageCropPageState extends State<ImageCropPage> {
  final _controller = CropController();
  bool _cropping = false;
  late final Map<String, double> _ratios;
  late String _selected;

  @override
  void initState() {
    super.initState();
    _ratios = widget.ratios ??
        const {'9:16': 9 / 16, '4:5': 4 / 5, '1:1': 1.0};
    final init = widget.initialRatio;
    _selected =
        (init != null && _ratios.containsKey(init)) ? init : _ratios.keys.first;
  }

  void _setRatio(String key) {
    setState(() => _selected = key);
    _controller.aspectRatio = _ratios[key];
  }

  void _confirm() {
    setState(() => _cropping = true);
    _controller.crop();
  }

  @override
  Widget build(BuildContext context) {
    final showChips = _ratios.length > 1;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0F13),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Recortar imagem'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Crop(
              controller: _controller,
              image: widget.imageBytes,
              aspectRatio: _ratios[_selected],
              baseColor: const Color(0xFF0E0F13),
              maskColor: Colors.black.withValues(alpha: 0.55),
              radius: 8,
              cornerDotBuilder: (size, edge) =>
                  const DotControl(color: Colors.white),
              progressIndicator: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
              onCropped: (result) {
                if (!mounted) return;
                if (result is CropSuccess) {
                  Navigator.pop(context, result.croppedImage);
                } else if (result is CropFailure) {
                  setState(() => _cropping = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Não foi possível recortar. Tente outra imagem.'),
                    ),
                  );
                }
              },
            ),
          ),
          // ── Painel inferior: proporção + ação ────────────────────────────
          Container(
            color: const Color(0xFF16181F),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  showChips
                      ? 'Arraste para enquadrar · escolha a proporção'
                      : 'Arraste para enquadrar',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                if (showChips) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: _ratios.keys.map((k) {
                      final sel = k == _selected;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: ChoiceChip(
                          label: Text(k),
                          selected: sel,
                          onSelected: _cropping ? null : (_) => _setRatio(k),
                          selectedColor: const Color(0xFF0cc0df),
                          backgroundColor: const Color(0xFF252833),
                          labelStyle: TextStyle(
                            color: sel ? Colors.black : Colors.white70,
                            fontWeight:
                                sel ? FontWeight.bold : FontWeight.normal,
                          ),
                          side: BorderSide.none,
                          showCheckmark: false,
                        ),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _cropping ? null : _confirm,
                    icon: _cropping
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check),
                    label: Text(_cropping ? 'Recortando...' : 'Cortar e usar'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0cc0df),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
