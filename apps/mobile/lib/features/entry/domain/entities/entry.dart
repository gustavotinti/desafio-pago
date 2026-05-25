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
  });
}
