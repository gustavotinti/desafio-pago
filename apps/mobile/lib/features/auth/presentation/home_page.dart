import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../challenge/infrastructure/get_challenges.dart';
import '../../challenge/infrastructure/vote_repository.dart';
import '../../challenge/presentation/create_challenge_page.dart';
import '../../entry/presentation/submit_entry_page.dart';
import '../presentation/profile_page.dart';
import '../../admin/presentation/admin_withdrawals_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future challengesFuture;

  @override
  void initState() {
    super.initState();
    challengesFuture = GetChallenges()();
  }

  bool isAdmin(String? email) {
    return email == "gustavo.a.tinti3@gmail.com";
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Desafios"),
        actions: [
          // 👤 PERFIL
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ProfilePage(),
                ),
              );
            },
          ),

          // 🔥 ADMIN (SÓ VOCÊ)
          if (isAdmin(user?.email))
            IconButton(
              icon: const Icon(Icons.admin_panel_settings),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdminWithdrawalsPage(),
                  ),
                );
              },
            ),

          // 🚪 LOGOUT
          IconButton(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
            icon: const Icon(Icons.logout),
          )
        ],
      ),
      body: FutureBuilder(
        future: challengesFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final challenges = snapshot.data as List;

          if (challenges.isEmpty) {
            return const Center(child: Text("Nenhum desafio ainda"));
          }

          return ListView.builder(
            itemCount: challenges.length,
            itemBuilder: (context, index) {
              final challenge = challenges[index];

              return Card(
                margin: const EdgeInsets.all(10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        challenge.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(challenge.description),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text('R\$ ${challenge.amount.toStringAsFixed(2)}'),
                          const SizedBox(width: 12),
                          Text('${challenge.entryCount} participações'),
                          const SizedBox(width: 12),
                          Text('${challenge.voteCount} votos'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ElevatedButton(
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SubmitEntryPage(
                                    challengeId: challenge.id,
                                    challengeTitle: challenge.title,
                                  ),
                                ),
                              );
                              setState(() {
                                challengesFuture = GetChallenges()();
                              });
                            },
                            child: const Text('Participar'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () async {
                              try {
                                await VoteRepository().vote(challenge.id);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Voto registrado')),
                                );
                                setState(() {
                                  challengesFuture = GetChallenges()();
                                });
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(e.toString())),
                                );
                              }
                            },
                            child: const Text('Votar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const CreateChallengePage(),
            ),
          );

          setState(() {
            challengesFuture = GetChallenges()();
          });
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}