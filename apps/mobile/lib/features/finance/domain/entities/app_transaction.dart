import 'transaction_type.dart';

class AppTransaction {
  final String id;
  final String userId;
  final double amount;
  final TransactionType type;
  final String description;
  final String? challengeId;
  final DateTime createdAt;

  AppTransaction({
    required this.id,
    required this.userId,
    required this.amount,
    required this.type,
    required this.description,
    required this.createdAt,
    this.challengeId,
  });
}
