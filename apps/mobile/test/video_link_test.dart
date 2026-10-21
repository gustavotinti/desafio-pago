import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/utils/video_link.dart';

void main() {
  group('VideoLink', () {
    // Mesmos vetores de functions/test/video_link.test.js — o app mostra o
    // código e o servidor recalcula: os dois PRECISAM bater.
    test('verificationCode: vetores compartilhados com o servidor', () {
      expect(VideoLink.verificationCode('abc123', 'c1'), 'DPSW36B');
      expect(VideoLink.verificationCode('uidXYZ789', 'chal_42'), 'DP5XKBD');
      expect(
          VideoLink.verificationCode('Zk3mQp9TtYh2LsR8vWx1', '8hJ2kL0pQr'),
          'DPXEEDX');
    });

    test('formatos do YouTube viram o mesmo Short', () {
      for (final l in [
        'https://youtube.com/shorts/il_MMI2MOYM?si=abc',
        'youtu.be/il_MMI2MOYM',
        'https://m.youtube.com/watch?v=il_MMI2MOYM&t=3',
        'https://www.youtube.com/embed/il_MMI2MOYM',
      ]) {
        final v = VideoLink.parse(l);
        expect(v, isNotNull, reason: l);
        expect(v!.provider, 'youtube');
        expect(v.url, 'https://www.youtube.com/shorts/il_MMI2MOYM');
        expect(v.thumbUrl, 'https://i.ytimg.com/vi/il_MMI2MOYM/oar2.jpg');
      }
    });

    test('Instagram: reel, p e o formato com usuário', () {
      final r =
          VideoLink.parse('https://www.instagram.com/reel/DAz1J3gNVgI/?igsh=x')!;
      expect(r.provider, 'instagram');
      expect(r.url, 'https://www.instagram.com/reel/DAz1J3gNVgI/');
      expect(r.embedUrl, 'https://www.instagram.com/reel/DAz1J3gNVgI/embed/');
      expect(r.thumbUrl, isNull);
      expect(VideoLink.parse('instagram.com/fulano/reel/DAz1J3gNVgI')!.url,
          'https://www.instagram.com/reel/DAz1J3gNVgI/');
      expect(VideoLink.parse('https://www.instagram.com/p/DAz1J3gNVgI/')!.url,
          'https://www.instagram.com/p/DAz1J3gNVgI/');
    });

    test('recusa o que não é vídeo do YouTube/Instagram', () {
      for (final l in [
        '',
        '   ',
        'https://vimeo.com/123',
        'https://youtube.com/shorts/curto',
        'javascript:alert(1)',
        'https://www.instagram.com/fulano/',
        'https://youtube.com.evil.com/shorts/il_MMI2MOYM',
        'https://evilyoutube.com/shorts/il_MMI2MOYM',
        'https://youtu.be/il_MMI2MOYM extra',
      ]) {
        expect(VideoLink.parse(l), isNull, reason: l);
      }
    });
  });
}
