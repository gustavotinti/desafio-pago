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
  final List<String> winnerIds;
  final DateTime createdAt;
  final DateTime expiresAt;
  // Top-3 participações mais votadas, desnormalizadas no doc (evita N+1 no feed).
  // Cada item: {entryId, userId, contentType, contentUrl, contentText, voteCount}.
  final List<Map<String, dynamic>> topEntries;
  // "Novo" — fixado no topo do feed pelo super admin (recurso manual exclusivo).
  final bool pinned;
  final DateTime? pinnedAt;
  // Região do desafio: 'BR' (padrão) ou 'INTL' (site trialspaid).
  final String region;
  // Desafio de demonstração (seed): mostrado com selo, não conta nos números.
  final bool isVirtual;
  // Prova pública no XRP Ledger (hash das transações): prêmio registrado na
  // criação e resultado na liberação. Null enquanto não houver.
  final String? xrplEscrowTx;
  final String? xrplReleaseTx;
  final String xrplNetwork;

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
    this.winnerIds = const [],
    this.topEntries = const [],
    this.pinned = false,
    this.pinnedAt,
    this.region = 'BR',
    this.isVirtual = false,
    this.xrplEscrowTx,
    this.xrplReleaseTx,
    this.xrplNetwork = 'testnet',
  });
}