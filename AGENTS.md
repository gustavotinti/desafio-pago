# Desafio Pago — instruções para agentes

O contexto completo e atualizado do projeto (stack, regras de negócio, estado
atual, infra, comandos) vive em um único arquivo:

👉 **[CLAUDE.md](CLAUDE.md)** — leia antes de mexer em qualquer coisa.

Este arquivo existia como uma **cópia** do CLAUDE.md e ficou defasado
(travado na v3.5.0, de julho/2026, enquanto o projeto já estava na v3.7.0).
Virou um ponteiro justamente para não haver duas verdades: toda atualização
de contexto é feita em `CLAUDE.md` e vale para qualquer agente.

## O essencial em 30 segundos
- App: Flutter Web + Firebase (projeto `desafio-app-b8665`, functions em `us-central1`).
- Código do app e das functions: `apps/mobile/`.
- Dois sites, **um só codebase**: BR (`desafiopago.com.br`) e internacional
  (`trialspaid.web.app`, build com `--dart-define=INTL_BUILD=true`).
- **O ledger é sempre em BRL.** O site internacional apenas *exibe* em USD.
- Segredos ficam no cofre Firestore (`secure_config/keys`) ou em
  `apps/mobile/functions/.env` — **nunca** commitados, nunca colados em código.
