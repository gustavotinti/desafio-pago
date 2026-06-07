import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Player de vídeo leve para participações.
/// - [hoverToPlay] true: toca ao passar o mouse (preview), mudo + loop.
/// - [hoverToPlay] false: toca ao tocar/clicar (com som), play/pause.
/// O vídeo preenche o espaço (cover), cortando o excedente.
class AutoVideo extends StatefulWidget {
  final String url;
  final bool hoverToPlay;

  const AutoVideo({super.key, required this.url, this.hoverToPlay = false});

  @override
  State<AutoVideo> createState() => _AutoVideoState();
}

class _AutoVideoState extends State<AutoVideo> {
  VideoPlayerController? _c;
  bool _init = false;
  bool _hovering = false;

  Future<void> _ensure() async {
    if (_c != null) return;
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _c = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
    } catch (_) {
      return;
    }
    if (!mounted) {
      c.dispose();
      _c = null;
      return;
    }
    c.addListener(_tick);
    setState(() => _init = true);
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  Future<void> _enter() async {
    _hovering = true;
    await _ensure();
    if (_hovering && _c != null) _c!.play();
  }

  void _exit() {
    _hovering = false;
    if (_c != null) {
      _c!.pause();
      _c!.seekTo(Duration.zero);
    }
  }

  Future<void> _tap() async {
    await _ensure();
    final c = _c;
    if (c == null) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      await c.setVolume(1);
      c.play();
    }
  }

  @override
  void dispose() {
    _c?.removeListener(_tick);
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final playing = c?.value.isPlaying ?? false;
    final ready = _init && c != null && c.value.isInitialized;

    final stack = Stack(
      fit: StackFit.expand,
      children: [
        Container(color: const Color(0xFF15171C)),
        if (ready)
          FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: c.value.size.width,
              height: c.value.size.height,
              child: VideoPlayer(c),
            ),
          ),
        if (!playing)
          const Center(
            child: Icon(Icons.play_circle_fill,
                color: Colors.white70, size: 30),
          ),
        const Positioned(
          right: 4,
          top: 4,
          child: Icon(Icons.videocam, size: 14, color: Colors.white70),
        ),
      ],
    );

    if (widget.hoverToPlay) {
      return MouseRegion(
        onEnter: (_) => _enter(),
        onExit: (_) => _exit(),
        child: stack,
      );
    }
    return GestureDetector(onTap: _tap, child: stack);
  }
}
