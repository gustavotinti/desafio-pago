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

## Estado atual (v2.7.1 — julho/2026)
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
- **Editor de recorte (cropper)** no envio de imagem — qualquer imagem vira
  9:16/4:5/1:1 (não barra mais por formato). Mesmo cropper na foto de perfil (1:1)
- Feed único de **ativos** (encerrados não aparecem no feed — ficam em
  "Minha atividade"); ordenado por maior prêmio. Prévia das 3 mais votadas em
  4:5 (vídeo carrega o pôster + toca no hover) com **taça ouro/prata/bronze**
  ("Vencendo" no 1º)
- Encerramento automático (cron 5min) + divisão de prêmio (centavo
  indivisível fica na plataforma)
- Texto selecionável (`SelectionArea`); imagens robustas (`SafeImage` —
  sem spinner infinito); avatares à prova de falha (`SafeAvatar`)
- Upload de imagem comprime para JPEG (`compressToJpg`, até 1440px/640px)
- Feed pagina (12 por vez) e lê `topEntries` desnormalizado do desafio
  (trigger `syncChallengeTopEntries` — mata o N+1 das prévias)

**Conteúdo virtual (seed, para parecer movimentado)**
- 1002 usuários virtuais (retratos realistas auto-hospedados, usernames
  variados, ~40% estilo gamertag)
- 26 desafios virtuais (texto < R$20, imagem < R$100, vídeo > R$100;
  valores quebrados/orgânicos) + participações + comentários
- Comentários virtuais com curtidas e respostas

**Social & perfil**
- Comentários com curtidas + respostas (thread)
- Seguidores via função `toggleFollow` (contadores protegidos); rankings
  (faturamento e votos) lendo do espelho público
- **"Minha atividade"** no perfil: meus desafios criados + minhas participações
- Compartilhar participação: deep link abre direto na arte (destacada,
  pronta pra votar) + prévia rica (Open Graph) no WhatsApp

**Engajamento (plataforma viva + sensação de poder)**
- **Pulso da plataforma** no topo do feed: selo "AO VIVO" + desafios ativos,
  prêmios em jogo (agregação count/sum) e participantes. Overrides do admin
  em `config/platformPulse` aplicados via **stream em tempo real** (edição
  aparece na hora, sem recarregar)
- **Ticker de vitórias** sob o pulso: mostra em rotação aleatória quem
  GANHOU quais desafios ("🏆 @user ganhou R$X · '...'"), lendo desafios reais
  encerrados + vencedores (prova social) — troca a cada 4s
- **Card da participação mostra o autor** (avatar + nome + @username + selo,
  toca → perfil), **botão de compartilhar** (share sheet nativo / Web Share
  API — compartilha o link dinâmico, cuja prévia OG já diz "{autor} quer o
  seu voto") e **botão de votar em destaque** (largura total) embaixo de cada
  participação. Ao chegar pelo link compartilhado, o **botão de votar da arte
  destacada PISCA** (zoom + brilho pulsante) pra guiar o clique no voto
- **"Sua posição"** na arte: rank do usuário + votos pra liderar + CTA Divulgar
- **Votos ao vivo**: página da arte em `StreamBuilder` (votos/posição em tempo real)
- **Notificações in-app** persistidas (`users/{uid}/notifications`, sininho com
  badge) — voto, vitória, novo seguidor, novo comentário; funciona sem push
- **Ranking pessoal** em destaque ("Você está em #N") e **conquistas/badges**
  no perfil (calculadas dos dados reais)
- **Números do pulso animam** (count-up de 0→valor) e **cards do feed entram
  com fade + slide** — sensação de vida ao carregar
- **Rodapé de "alta demanda"** no fim da rolagem do feed: loader sutil +
  mensagem responsiva ("muitos usuários agora, o servidor pode demorar") —
  reforça a percepção de plataforma movimentada. Liga/desliga em
  Admin→Plataforma (`config/feed.highDemandFooter`, stream em tempo real)

**Admin / super admin**
- **Painel "Plataforma"** (Admin→Plataforma): edita os 3 números do "Ao vivo"
  (vazio = automático; função `adminSetPulse`) e o toggle do rodapé de alta
  demanda (função `adminSetFeedConfig`) — tudo reflete na hora via streams
- **Fixar desafio como "NOVO"** (`adminSetChallengePinned`, EXCLUSIVO do super
  admin — backend valida o e-mail): sobe pro topo do feed com selo dourado
  pulsante. Recurso 100% MANUAL — nada fixa/desfixa sozinho (sem trigger/cron).
  Toggle no lápis do feed e na aba Admin→Desafios. Feed lê `where('pinned',
  ==true)` (índice automático) e prepend, deduplicando das páginas normais
- Saques (aprovar/rejeitar/marcar pago), usuários/moderadores, verificação,
  exportar público p/ campanhas (Google Customer Match / Meta Custom Audiences)
- **Editar qualquer desafio** (título/descrição/prêmio/prazo) e **qualquer
  perfil** (virtual ou real); lápis de edição inline no feed e no perfil público
- **Excluir participação** (reverte contadores) + **editar/excluir comentários**;
  editar votos (ajusta `totalVotesReceived`)

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
- `/users` (e-mail, telefone, saldo, Pix) só o **dono + admin** lê; espelho
  `/publicProfiles` (sem PII) é público para o visitante
- Contadores de follow só via Cloud Function; `isFullAdmin()` nas regras
  (moderador não mexe no roster de admins); `/follows` write travado
- `functions/.env` fora do git (token MP, MP_WEBHOOK_SECRET, OpenAI)

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
- Ampliar testes (hoje: lógica de dinheiro + utils; falta integração c/ emulador)

## Checkpoints (git tags)
v2.0.1 · v2.1.0 · v2.2.0 · v2.2.1 · v2.2.2 · v2.3.0 · v2.4.0 · v2.5.0 — restaurar: `git checkout vX.Y.Z`

## Comandos úteis (em apps/mobile)
- Build web: `flutter build web --release`
- Deploy hosting: `firebase deploy --only hosting --project desafio-app-b8665`
- Deploy função: `firebase deploy --only functions:NOME --project desafio-app-b8665`
- Lint functions: `npm --prefix functions run lint`
- Testes: `flutter test` (Dart) · `npm --prefix functions test` (dinheiro)