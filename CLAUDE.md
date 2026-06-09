# DESAFIO PAGO — Contexto do Projeto

## O que é
Plataforma de desafios pagos. Usuários criam desafios com valor em dinheiro,
outros participam com conteúdo (texto/imagem/vídeo), e o mais votado vence o prêmio.

## Stack
- Flutter (frontend web + mobile)
- Firebase (Auth, Firestore, Storage, Cloud Functions)
- Mercado Pago + Pix (pagamentos)
- Instagram Graph API (automação — fase futura)
- Arquitetura: DDD + Clean Architecture + Event-Driven

## Regras de negócio críticas
- Taxa: 10% apenas no saque
- Saque mínimo: R$100
- Vence quem tem mais votos ao final do prazo
- Empate: prêmio dividido; centavo indivisível fica na plataforma
- Criador não pode participar do próprio desafio
- 1 voto por usuário por desafio
- Desafio não pode ser editado ou excluído
- Limite: 20 desafios criados por dia por usuário
- Aporte bloqueado nas últimas 3h do desafio
- Duração máxima: 30 dias
- Prêmio vai para saldo do vencedor

## Financeiro
- Saldo interno (chamar de "créditos", nunca "wallet")
- Saldo + Pix combinado permitido
- Pix não pago cancela apenas o aumento, não o desafio
- Reembolso: não
- Cancelamento de desafio: não
- Chave Pix não pode ser alterada com saque pendente

## Usuário
- Login apenas Google (1 conta por e-mail)
- Termos aceitos no primeiro login
- Perfil editável (foto/nome/bio)
- Sistema de seguidores
- Notificações de votos
- Deletar conta: permitido

## Rankings
- Ranking 1: por faturamento total em reais
- Ranking 2: por votos recebidos

## Segurança
- Bloquear prints e gravação de tela
- Denúncia de conteúdo
- Banimento automático e manual
- Moderação com IA
- Logs completos de ações
- Webhook Mercado Pago
- Apenas usuários do Brasil (bloquear VPN futuramente)

## Automação Instagram (Fase 16)
- Evento: ChallengeReachedThresholdEvent
- Threshold inicial: R$100 (configurável)
- Gatilho por transição de estado
- Domínio nunca conhece Instagram
- 1 post por desafio
- Retry automático em falha
- Status: pending | posted | failed

## Estado atual (v2.2.2 — junho/2026)
No ar: https://desafiopago.com.br (e https://desafiopago.web.app)
Firebase: projeto `desafio-app-b8665` · Functions região `us-central1`

### ✅ Implementado e no ar
**Acesso & onboarding**
- Login Google; visitante (sem login) navega o conteúdo (desafios,
  participações, comentários, rankings, perfis públicos)
- Ações que exigem login (participar, votar, criar, aportar, seguir,
  comentar, perfil) abrem uma folha de login
- 1º login: onboarding obrigatório — telefone + aceite das políticas
  (LGPD, incluindo uso dos dados para campanhas Google/Meta)

**Desafios & participações**
- Criar (debita saldo), participar (texto/imagem/vídeo em 9:16, 4:5 ou
  1:1 — sem 16:9), votar, aumentar prêmio (aporte)
- Feed ordenado por maior prêmio (ativos e encerrados); prévia das 3
  participações mais votadas em 4:5 (vídeo toca ao passar o mouse)
- Card de prêmio em destaque; prêmio mostrado ao lado de "Vencedor definido"
- Encerramento automático (cron 5min) + divisão de prêmio (centavo
  indivisível fica na plataforma)

**Conteúdo virtual (seed, para parecer movimentado)**
- 1002 usuários virtuais (retratos realistas auto-hospedados, usernames
  variados, ~40% estilo gamertag)
- 26 desafios virtuais (texto < R$20, imagem < R$100, vídeo > R$100;
  valores quebrados/orgânicos) + participações + comentários
- Comentários virtuais com curtidas e respostas

**Social**
- Comentários com curtidas + respostas (thread)
- Seguidores; rankings (faturamento e votos) lendo do espelho público
- Compartilhar participação: deep link abre direto na arte (destacada,
  pronta pra votar) + prévia rica (Open Graph) no WhatsApp

**Admin (painel)**
- Saques (aprovar/rejeitar/marcar pago), desafios, usuários/moderadores,
  verificação, perfis virtuais (editar nome/@/bio/selo/foto), exportar
  público para campanhas (Google Customer Match / Meta Custom Audiences)

**Verificação**
- Pedido de selo (nome/sobrenome/telefone/CPF) + fila prioritária paga
  (R$500 via Pix); admin aprova/recusa

**Pagamentos**
- Depósito via Pix (Mercado Pago) → webhook credita o saldo
  (idempotente; validação de assinatura opcional via MP_WEBHOOK_SECRET)
- Saque manual (admin envia o Pix e marca como pago)
- Todas as operações de dinheiro em **transações atômicas** (sem saldo
  negativo, sem crédito/prêmio em dobro)

**Privacidade & segurança**
- `/users` (e-mail, telefone, saldo, Pix) só para logado; espelho
  `/publicProfiles` (sem PII) é público para o visitante
- `functions/.env` fora do git (token MP, etc.)

### ⚙️ Infra / pontos técnicos importantes
- **Storage bucket REAL: `desafio-app-b8665.firebasestorage.app`**
  (o `.appspot.com` NÃO existe — não usar). Bucket com **CORS** liberado
  (uploads + render no Flutter Web/CanvasKit).
- Assets auto-hospedados no Hosting com CORS (headers no firebase.json):
  `/avatars`, `/portraits`, `/challenge_images`, `/challenge_videos`,
  `/og-default.png`. O `copy_web_assets.js` (predeploy do hosting) copia
  essas pastas para `build/web` (o `flutter build web` não copia pastas
  novas sozinho).
- Domínio custom `desafiopago.com.br` ativo; `authDomain` segue
  `firebaseapp.com` (não mudar — quebra o login).
- Prévia de link: rewrite `/challenges/**` → função `entryPreview`
  (injeta Open Graph). Demais rotas → SPA (`/index.html`).
- Cloud Functions gen1, Node 22. Seeds/migrações são funções HTTP
  one-shot protegidas pelo secret `SEED_2026_DP`.

### 🔜 Próximos passos / pendências
- Testar o ciclo de dinheiro ponta a ponta com Pix real
  (depósito → saldo → desafio → prêmio → saque)
- Confirmar o webhook MP em produção ("Simular notificação" = 200)
- Pagamento automático de saque (precisa de PSP de payout — Asaas/Efí)
- Moderação com IA; bloqueio de VPN; automação Instagram (Fase 16)
- Atualizar dependências (opcional)

## Checkpoints (git tags)
v2.0.1 · v2.1.0 · v2.2.0 · v2.2.1 · v2.2.2 — restaurar: `git checkout vX.Y.Z`

## Comandos úteis (em apps/mobile)
- Build web: `flutter build web --release`
- Deploy hosting: `firebase deploy --only hosting --project desafio-app-b8665`
- Deploy função: `firebase deploy --only functions:NOME --project desafio-app-b8665`
- Lint functions: `npm --prefix functions run lint`