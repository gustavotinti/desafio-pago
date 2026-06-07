import 'package:flutter/material.dart';

import '../../../core/widgets/web_frame.dart';
import 'admin_withdrawals_page.dart';
import 'admin_users_page.dart';
import 'admin_challenges_page.dart';
import 'admin_verification_page.dart';

class AdminPage extends StatelessWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Painel Admin')),
      body: WebFrame(
        maxWidth: 900,
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _AdminCard(
            icon: Icons.attach_money,
            title: 'Saques',
            subtitle: 'Aprovar e rejeitar saques pendentes',
            color: Colors.green,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const AdminWithdrawalsPage()),
            ),
          ),
          _AdminCard(
            icon: Icons.flag,
            title: 'Desafios',
            subtitle: 'Criar, estender prazo e encerrar desafios',
            color: Colors.blue,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const AdminChallengesPage()),
            ),
          ),
          _AdminCard(
            icon: Icons.manage_accounts,
            title: 'Usuários',
            subtitle: 'Gerenciar moderadores e admins',
            color: Colors.orange,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminUsersPage()),
            ),
          ),
          _AdminCard(
            icon: Icons.verified,
            title: 'Verificação',
            subtitle: 'Pedidos de selo verificado (prioritários primeiro)',
            color: Colors.indigo,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const AdminVerificationPage()),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

class _AdminCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _AdminCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
