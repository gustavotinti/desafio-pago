import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/web_frame.dart';

class AdminWithdrawalsPage extends StatelessWidget {
  const AdminWithdrawalsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin — Saques'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Pendentes'),
              Tab(text: 'Aprovados'),
              Tab(text: 'Pagos'),
              Tab(text: 'Rejeitados'),
            ],
          ),
        ),
        body: WebFrame(
          maxWidth: 900,
          child: const TabBarView(
            children: [
              _WithdrawalList(status: 'pending'),
              _WithdrawalList(status: 'approved'),
              _WithdrawalList(status: 'paid'),
              _WithdrawalList(status: 'rejected'),
            ],
          ),
        ),
      ),
    );
  }
}

class _WithdrawalList extends StatefulWidget {
  final String status;
  const _WithdrawalList({required this.status});

  @override
  State<_WithdrawalList> createState() => _WithdrawalListState();
}

class _WithdrawalListState extends State<_WithdrawalList> {
  // Mês exibido no resumo (só usado na aba "paid")
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  void _prevMonth() => setState(() =>
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month - 1));

  void _nextMonth() {
    final now = DateTime.now();
    final next = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    if (!next.isAfter(DateTime(now.year, now.month))) {
      setState(() => _selectedMonth = next);
    }
  }

  Future<Map<String, dynamic>?> _getUser(String userId) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();
    return doc.exists ? doc.data() : null;
  }

  Future<void> _approve(
      BuildContext context, String id, Map<String, dynamic> data) async {
    final firestore = FirebaseFirestore.instance;
    final userId = data['userId'] as String;
    final amount = (data['amount'] ?? 0).toDouble();
    try {
      await firestore.runTransaction((tx) async {
        tx.update(firestore.collection('withdrawals').doc(id), {
          'status': 'approved',
          'approvedAt': FieldValue.serverTimestamp(),
          'approvedBy': FirebaseAuth.instance.currentUser?.uid,
        });
        tx.update(firestore.collection('users').doc(userId), {
          'lockedBalance': FieldValue.increment(-amount),
        });
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Saque aprovado')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _reject(
      BuildContext context, String id, Map<String, dynamic> data) async {
    final firestore = FirebaseFirestore.instance;
    final userId = data['userId'] as String;
    final amount = (data['amount'] ?? 0).toDouble();
    try {
      await firestore.runTransaction((tx) async {
        tx.update(firestore.collection('users').doc(userId), {
          'balance': FieldValue.increment(amount),
          'lockedBalance': FieldValue.increment(-amount),
        });
        tx.update(
            firestore.collection('withdrawals').doc(id), {'status': 'rejected'});
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Saque rejeitado')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _markPaid(BuildContext context, String id) async {
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('adminMarkWithdrawalPaid')
          .call({'withdrawalId': id});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saque confirmado como pago!')),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message ?? 'Erro')));
      }
    }
  }

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Copiado: $text')));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('withdrawals')
          .where('status', isEqualTo: widget.status)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('Nenhum saque'));
        }

        final docs = snapshot.data!.docs;

        // ── Resumo mensal (todas as abas) ────────────────────────────────
        final monthStart = _selectedMonth;
        final monthEnd =
            DateTime(_selectedMonth.year, _selectedMonth.month + 1);

        double monthGross = 0;
        double monthFee   = 0;
        double totalGross = 0;
        double totalFee   = 0;

        for (final doc in docs) {
          final d = doc.data() as Map<String, dynamic>;
          final fee    = (d['fee']    as num? ?? 0).toDouble();
          final amount = (d['amount'] as num? ?? 0).toDouble();
          totalGross += amount;
          totalFee   += fee;

          DateTime? dt;
          final raw = d['createdAt'];
          if (raw is Timestamp) {
            dt = raw.toDate();
          } else if (raw is String) {
            dt = DateTime.tryParse(raw);
          }
          if (dt != null &&
              !dt.isBefore(monthStart) &&
              dt.isBefore(monthEnd)) {
            monthGross += amount;
            monthFee   += fee;
          }
        }

        final monthLabel =
            DateFormat('MMMM/yyyy', 'pt_BR').format(_selectedMonth);
        final isCurrentMonth = _selectedMonth.year == DateTime.now().year &&
            _selectedMonth.month == DateTime.now().month;

        // Rótulos e cores por aba
        final (gradColors, grossLabel, feeLabel, totalLabel) =
            switch (widget.status) {
          'pending'  => (
              const [Color(0xFFE65100), Color(0xFFFB8C00)],
              'Total pendente',
              'Taxa prevista (10%)',
              'Total histórico pendente',
            ),
          'approved' => (
              const [Color(0xFF1565C0), Color(0xFF1E88E5)],
              'Total aprovado',
              'Taxa a receber (10%)',
              'Total histórico aprovado',
            ),
          'rejected' => (
              const [Color(0xFF6D4C41), Color(0xFF8D6E63)],
              'Total rejeitado',
              'Taxa não aplicada',
              'Total histórico rejeitado',
            ),
          _ => (
              const [Color(0xFF00897B), Color(0xFF26A69A)],
              'Saques brutos',
              'Meu lucro (10%)',
              'Lucro total histórico',
            ),
        };

        final summaryCard = Container(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: gradColors.first.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Mês + setas ────────────────────────────────────────
              Row(
                children: [
                  const Icon(Icons.bar_chart,
                      color: Colors.white70, size: 16),
                  const SizedBox(width: 6),
                  const Text(
                    'RESUMO DO MÊS',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.chevron_left,
                        color: Colors.white70, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: _prevMonth,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    monthLabel,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.chevron_right,
                        color: isCurrentMonth
                            ? Colors.white24
                            : Colors.white70,
                        size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: isCurrentMonth ? null : _nextMonth,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // ── Valores do mês ─────────────────────────────────────
              Row(
                children: [
                  _SummaryCell(
                    label: grossLabel,
                    value: Fmt.brl(monthGross),
                  ),
                  const SizedBox(width: 16),
                  _SummaryCell(
                    label: feeLabel,
                    value: Fmt.brl(monthFee),
                    highlight: true,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Divider(
                  color: Colors.white.withValues(alpha: 0.2),
                  height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.history,
                      color: Colors.white54, size: 13),
                  const SizedBox(width: 4),
                  Text(
                    '$totalLabel: ${Fmt.brl(totalFee)}'
                    '  (bruto: ${Fmt.brl(totalGross)})',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        );

        return Column(
          children: [
            summaryCard,
            Expanded(
              child: ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final amount = data['amount'] ?? 0;
            final fee = data['fee'] ?? 0;
            final netAmount = data['netAmount'] ?? amount;
            final pixKey = data['pixKey'] ?? '';
            final userId = data['userId'] ?? '';
            // Método: 'pix' (Brasil) ou 'xrp' (internacional / cripto).
            final isCrypto = data['method'] == 'xrp';
            final xrpAddress = data['xrpAddress'] as String? ?? '';
            final xrpTag = data['xrpTag'] as String?;
            final xrpEstimate = data['xrpEstimate'];

            return FutureBuilder<Map<String, dynamic>?>(
              future: _getUser(userId),
              builder: (context, userSnap) {
                final user = userSnap.data;
                final name = user?['name'] ?? (userSnap.hasData ? '—' : '...');
                final email = user?['email'] ?? '';

                return Card(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                Fmt.brl((netAmount as num).toDouble()),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            _StatusChip(status: widget.status),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                            'Bruto: ${Fmt.brl((amount as num).toDouble())}  ·  Taxa: ${Fmt.brl((fee as num).toDouble())}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54)),
                        const SizedBox(height: 6),
                        Text('Nome: $name'),
                        Text('Email: $email',
                            style:
                                const TextStyle(color: Colors.black54, fontSize: 13)),
                        const SizedBox(height: 4),
                        // ── Destino do pagamento (Pix ou cripto/XRP) ──────
                        if (isCrypto) ...[
                          _PayoutField(
                            icon: Icons.currency_bitcoin,
                            color: const Color(0xFF23292F),
                            label: 'Endereço XRP',
                            value: xrpAddress,
                            onCopy: () => _copy(context, xrpAddress),
                          ),
                          if (xrpTag != null && xrpTag.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            _PayoutField(
                              icon: Icons.tag,
                              color: const Color(0xFF23292F),
                              label: 'Destination tag',
                              value: xrpTag,
                              onCopy: () => _copy(context, xrpTag),
                            ),
                          ],
                          if (xrpEstimate != null) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: const Color(0xFFBFD8F5)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.send, size: 15,
                                      color: Color(0xFF1565C0)),
                                  const SizedBox(width: 6),
                                  Text('Enviar ≈ $xrpEstimate XRP',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Color(0xFF1565C0))),
                                ],
                              ),
                            ),
                          ],
                        ] else
                          Row(
                            children: [
                              const Icon(Icons.pix,
                                  size: 16, color: Colors.teal),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  pixKey,
                                  style: const TextStyle(
                                      fontFamily: 'monospace', fontSize: 13),
                                ),
                              ),
                              if (pixKey.toString().isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.copy, size: 15),
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Copiar',
                                  onPressed: () =>
                                      _copy(context, pixKey.toString()),
                                ),
                            ],
                          ),
                        const SizedBox(height: 10),
                        if (widget.status == 'pending')
                          Row(
                            children: [
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () =>
                                    _approve(context, doc.id, data),
                                child: const Text('Aprovar'),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red),
                                onPressed: () =>
                                    _reject(context, doc.id, data),
                                child: const Text('Rejeitar'),
                              ),
                            ],
                          ),
                        if (widget.status == 'approved')
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _markPaid(context, doc.id),
                            icon: const Icon(Icons.check_circle_outline),
                            label: Text(isCrypto
                                ? 'Confirmar envio do XRP'
                                : 'Confirmar Pix pago'),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Célula do resumo ──────────────────────────────────────────────────────────

class _SummaryCell extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _SummaryCell({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: highlight ? 20 : 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

// ── Campo de destino do pagamento com botão copiar (endereço XRP, tag) ────────

class _PayoutField extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final VoidCallback onCopy;

  const _PayoutField({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.black45)),
              SelectableText(
                value,
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 13),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy, size: 15),
          visualDensity: VisualDensity.compact,
          tooltip: 'Copiar',
          onPressed: onCopy,
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'pending' => ('Pendente', Colors.orange),
      'approved' => ('Aprovado', Colors.blue),
      'paid' => ('Pago', Colors.green),
      'rejected' => ('Rejeitado', Colors.red),
      _ => (status, Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
