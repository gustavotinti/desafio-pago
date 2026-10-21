import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/widgets/video_link_view.dart';

Widget _app(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('VideoLinkCover', () {
    testWidgets('Instagram sem capa: card da marca, play e selo Reels',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(_app(SizedBox(
        width: 180,
        height: 320,
        child: VideoLinkCover(provider: 'instagram', onTap: () => taps++),
      )));
      expect(find.text('Reels'), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
      await tester.tap(find.byType(VideoLinkCover));
      expect(taps, 1);
    });

    testWidgets('YouTube compacto (prévia do feed) cabe num tile pequeno',
        (tester) async {
      await tester.pumpWidget(_app(const SizedBox(
        width: 90,
        height: 112,
        child: VideoLinkCover(provider: 'youtube', compact: true),
      )));
      expect(find.text('Shorts'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('showVideoLinkPlayer', () {
    for (final size in const [Size(375, 667), Size(1280, 800)]) {
      testWidgets('cabe na tela ${size.width.toInt()}×${size.height.toInt()} '
          'e fecha', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showVideoLinkPlayer(context,
                    provider: 'youtube',
                    embedUrl: 'https://www.youtube-nocookie.com/embed/x',
                    url: 'https://www.youtube.com/shorts/x'),
                child: const Text('abrir'),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('abrir'));
        await tester.pumpAndSettle();
        expect(find.text('Abrir no YouTube'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'sem overflow');
        final dialog = tester.getSize(find.byType(Dialog));
        expect(dialog.height, lessThanOrEqualTo(size.height));
        expect(dialog.width, lessThanOrEqualTo(size.width));
        await tester.tap(find.text('Fechar'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
      });
    }
  });
}
