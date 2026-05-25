class Comment {
  final String id;
  final String challengeId;
  final String? entryId;
  final String userId;
  final String text;
  final bool isActive;
  final DateTime createdAt;

  Comment({
    required this.id,
    required this.challengeId,
    required this.userId,
    required this.text,
    required this.isActive,
    required this.createdAt,
    this.entryId,
  });
}
