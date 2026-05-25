class Vote {
  final String id;
  final String challengeId;
  final String entryId;
  final String voterId;
  final DateTime createdAt;

  Vote({
    required this.id,
    required this.challengeId,
    required this.entryId,
    required this.voterId,
    required this.createdAt,
  });
}
