class Challenge {
  final String id;
  final String title;
  final String description;
  final String createdBy;
  final double amount;
  final int voteCount;
  final DateTime createdAt;
  final DateTime expiresAt;

  Challenge({
    required this.id,
    required this.title,
    required this.description,
    required this.createdBy,
    required this.amount,
    required this.voteCount,
    required this.createdAt,
    required this.expiresAt,
  });
}