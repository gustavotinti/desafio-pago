class Comment {
  final String id;
  final String challengeId;
  final String entryId;
  final String parentId;
  final String userId;
  final String? userName;
  final String text;
  final int likeCount;
  final bool isActive;
  final DateTime createdAt;

  Comment({
    required this.id,
    required this.challengeId,
    required this.entryId,
    required this.userId,
    required this.text,
    required this.isActive,
    required this.createdAt,
    this.parentId = '',
    this.likeCount = 0,
    this.userName,
  });

  bool get isReply => parentId.isNotEmpty;

  factory Comment.fromMap(String id, Map<String, dynamic> data) {
    return Comment(
      id: id,
      challengeId: data['challengeId'] as String,
      entryId: data['entryId'] as String? ?? '',
      parentId: data['parentId'] as String? ?? '',
      userId: data['userId'] as String,
      userName: data['userName'] as String?,
      text: data['text'] as String,
      likeCount: (data['likeCount'] as num?)?.toInt() ?? 0,
      isActive: data['isActive'] as bool? ?? true,
      createdAt: DateTime.parse(data['createdAt'] as String),
    );
  }
}
