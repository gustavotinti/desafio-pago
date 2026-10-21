import 'content_type.dart';

class Entry {
  final String id;
  final String challengeId;
  final String userId;
  final ContentType contentType;
  final String? contentUrl;
  final String? contentText;
  final int voteCount;
  final bool isActive;
  final DateTime createdAt;

  // Vídeo por link (só quando contentType == videoLink).
  final String? videoProvider; // 'youtube' | 'instagram'
  final String? videoEmbed;
  final String? videoThumb;

  /// 'verified' | 'pending' (Instagram, aguardando o admin) | 'rejected' |
  /// 'unavailable' (sumiu/ficou privado antes do encerramento).
  final String? videoCheck;

  Entry({
    required this.id,
    required this.challengeId,
    required this.userId,
    required this.contentType,
    required this.voteCount,
    required this.isActive,
    required this.createdAt,
    this.contentUrl,
    this.contentText,
    this.videoProvider,
    this.videoEmbed,
    this.videoThumb,
    this.videoCheck,
  });

  bool get isVideoLink => contentType == ContentType.videoLink;
}
