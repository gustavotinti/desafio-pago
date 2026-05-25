import 'challenge_status.dart';

class Challenge {
  final String id;
  final String title;
  final String description;
  final String createdBy;
  final double amount;
  final ChallengeStatus status;
  final int voteCount;
  final int entryCount;
  final String? winnerId;
  final DateTime createdAt;
  final DateTime expiresAt;

  Challenge({
    required this.id,
    required this.title,
    required this.description,
    required this.createdBy,
    required this.amount,
    required this.status,
    required this.voteCount,
    required this.entryCount,
    required this.createdAt,
    required this.expiresAt,
    this.winnerId,
  });
}