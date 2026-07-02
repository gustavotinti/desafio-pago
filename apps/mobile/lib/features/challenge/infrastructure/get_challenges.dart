import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/entities/challenge.dart';
import '../domain/entities/challenge_status.dart';

enum ChallengeSortBy { amount, voteCount, newest }

class GetChallenges {
  final _firestore = FirebaseFirestore.instance;

  Future<List<Challenge>> call({
    ChallengeStatus? status,
    ChallengeSortBy sortBy = ChallengeSortBy.amount,
  }) async {
    Query<Map<String, dynamic>> query =
        _firestore.collection('challenges');

    if (status != null) {
      query = query.where('status', isEqualTo: status.name);
    }

    switch (sortBy) {
      case ChallengeSortBy.amount:
        query = query.orderBy('amount', descending: true);
      case ChallengeSortBy.voteCount:
        query = query.orderBy('voteCount', descending: true);
      case ChallengeSortBy.newest:
        query = query.orderBy('createdAt', descending: true);
    }

    final snapshot = await query.get();

    return snapshot.docs.map((doc) => _map(doc.id, doc.data())).toList();
  }

  /// Página do feed (ordenado por maior prêmio). Retorna os itens e o cursor
  /// (último doc) para a próxima página.
  Future<(List<Challenge>, DocumentSnapshot<Map<String, dynamic>>?)> page({
    required ChallengeStatus status,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = 12,
  }) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection('challenges')
        .where('status', isEqualTo: status.name)
        .orderBy('amount', descending: true)
        .limit(limit);
    if (startAfter != null) query = query.startAfterDocument(startAfter);
    final snap = await query.get();
    final items = snap.docs.map((d) => _map(d.id, d.data())).toList();
    return (items, snap.docs.isEmpty ? null : snap.docs.last);
  }

  /// Carrega um desafio pelo id (usado pelo deep link de compartilhamento).
  Future<Challenge?> getById(String id) async {
    final doc = await _firestore.collection('challenges').doc(id).get();
    if (!doc.exists) return null;
    return _map(doc.id, doc.data()!);
  }

  /// Desafios ativos fixados como "novo" pelo super admin (topo do feed).
  /// Consulta por campo único (`pinned`) — usa índice automático; o filtro de
  /// status é feito no cliente (conjunto pequeno). Ordena por quem foi fixado
  /// mais recentemente primeiro.
  Future<List<Challenge>> pinnedActive() async {
    final snap = await _firestore
        .collection('challenges')
        .where('pinned', isEqualTo: true)
        .get();
    final list = snap.docs
        .map((d) => _map(d.id, d.data()))
        .where((c) => c.status == ChallengeStatus.active)
        .toList();
    list.sort((a, b) {
      final at = a.pinnedAt ?? a.createdAt;
      final bt = b.pinnedAt ?? b.createdAt;
      return bt.compareTo(at);
    });
    return list;
  }

  /// Desafios criados por um usuário (mais recentes primeiro). Inclui encerrados.
  Future<List<Challenge>> byCreator(String uid) async {
    final snap = await _firestore
        .collection('challenges')
        .where('createdBy', isEqualTo: uid)
        .get();
    final list = snap.docs.map((d) => _map(d.id, d.data())).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Challenge _map(String id, Map<String, dynamic> data) {
    return Challenge(
      id: id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      createdBy: data['createdBy'] ?? '',
      amount: (data['amount'] as num).toDouble(),
      status: ChallengeStatus.values.firstWhere(
        (s) => s.name == (data['status'] ?? ''),
        orElse: () => ChallengeStatus.active,
      ),
      voteCount: data['voteCount'] ?? 0,
      entryCount: data['entryCount'] ?? 0,
      winnerIds: List<String>.from(data['winnerIds'] ?? []),
      createdAt: DateTime.parse(data['createdAt']),
      expiresAt: DateTime.parse(data['expiresAt']),
      topEntries: ((data['topEntries'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      pinned: data['pinned'] == true,
      pinnedAt: data['pinnedAt'] != null
          ? DateTime.tryParse(data['pinnedAt'].toString())
          : null,
    );
  }
}
