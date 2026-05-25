import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../application/create_challenge.dart';
import '../domain/entities/challenge.dart';
import '../infrastructure/firebase_challenge_repository.dart';

class CreateChallengePage extends StatefulWidget {
  const CreateChallengePage({super.key});

  @override
  State<CreateChallengePage> createState() => _CreateChallengePageState();
}

class _CreateChallengePageState extends State<CreateChallengePage> {
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  final amountController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Criar Desafio"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: "Título"),
            ),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(labelText: "Descrição"),
            ),
            TextField(
              controller: amountController,
              decoration: const InputDecoration(labelText: "Valor"),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: () async {
                try {
                  if (user == null) {
                    throw Exception("Usuário não logado");
                  }

                  final challenge = Challenge(
                    id: const Uuid().v4(),
                    title: titleController.text,
                    description: descriptionController.text,
                    createdBy: user.uid,
                    amount: double.parse(amountController.text),

                    // 🔥 O QUE FALTAVA
                    voteCount: 0,

                    createdAt: DateTime.now(),
                    expiresAt:
                        DateTime.now().add(const Duration(days: 7)),
                  );

                  final usecase = CreateChallenge(
                    FirebaseChallengeRepository(),
                  );

                  await usecase.call(challenge);

                  Navigator.pop(context);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                }
              },
              child: const Text("Criar Desafio"),
            ),
          ],
        ),
      ),
    );
  }
}