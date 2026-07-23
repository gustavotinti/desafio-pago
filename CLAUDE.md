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

## Estado atual (v3.3.0 — julho/2026)
No ar: https://desafiopago.com.br (e https://desafiopago.web.app)
**Internacional: https://trialspaid.web.app** (mesmo projeto/DB)
Firebase: projeto `desafio-app-b8665` · Functions região `us-central1`

### 🌍 Internacional (TrialsPaid — v3.0.0)
- **Mesmo codebase, 2 builds**: BR (padrão, idêntico) e intl via
  `--dart-define=INTL_BUILD=true` → deploy no site hosting `trialspaid`
  (targets: `app`=desafiopago, `intl`=trialspaid; `build/web_intl` é cópia
  pós-build com meta/manifest rebrandados via sed — ver histórico do deploy).
- **AppConfig** (`core/config/app_config.dart`): intl/brand/siteUrl/logos
  (logo internacional: `assets/images/logo_intl.png` + `logo_anim_intl.gif`,
  vindas de "LOGO 3-1 ENG" do usuário).
- **i18n** (`core/i18n/i18n.dart`): en (padrão), es, fr, it, de — seletor de
  bandeiras 🇬🇧🇪🇸🇫🇷🇮🇹🇩🇪 no AppBar (persistido em localStorage). BR fica
  travado em pt e o código intl é tree-shaken do bundle BR.
- **Moeda**: ledger interno continua 100% BRL (todas as transações atômicas
  valem). Intl só EXIBE em USD (Fmt.brl converte num ponto único; cotação
  CoinGecko no arranque) e mostra equivalência do saldo em XRP.
- **Depósito**: PayPal (`paypalCreateOrder`/`paypalCaptureOrder` — cria
  ordem, abre aprovação em nova aba, captura idempotente e credita o ledger
  convertido). REQUER usuário preencher PAYPAL_CLIENT_ID/PAYPAL_SECRET no
  functions/.env (placeholders já criados; PAYPAL_MODE=live) + redeploy.
- **Saque**: cripto XRP (`requestCryptoWithdraw` — valida endereço r...,
  taxa 10%, trava saldo, cria withdrawal method:'xrp' com xrpEstimate);
  admin envia XRP manualmente e marca pago (mesmo fluxo manual do Pix).
- No intl: seções Pix/verificação OCULTAS; visitante vê benefício "saque em
  cripto"; footer sem "apenas Brasil".
- **Separação de feeds por `region`** (BR x INTL): challenge tem campo
  `region` ('BR' padrão, 'INTL' no trialspaid); `createChallenge` grava a
  região do site; feed (page + pinnedActive), pulso e ticker filtram por
  região (índice composto `status+region+amount`). **Ranking é
  compartilhado** (lê publicProfiles global). Backfill + seed via
  `seedInternational` (30 BR + 8 desafios INTL em inglês com participações).

### 🔐 Cofre de chaves (Admin → Chaves & integrações — super admin)
- Credenciais (MP token, MP webhook secret, PayPal client/secret/mode,
  Gemini/OpenAI) ficam em `secure_config/keys` — doc **TRANCADO** (rules
  negam todo acesso do client). Funções `adminSetSecret`/`adminGetSecretStatus`
  (só super admin). `getSecret(k)` (functions/secrets.js) prioriza o cofre e
  cai no `.env`; usado por MP (`mpPaymentClient` async), webhook, PayPal, IA
  de moderação e SEO. **Trocar chave vale na hora, sem redeploy.**
- Painel: campos write-only (nunca lê o valor de volta — só status mascarado
  `••••1234`) + instruções de onde/como obter cada chave.

### ✅ Implementado e no ar
**Acesso & onboarding**
- Login Google; visitante (sem login) navega o conteúdo (desafios,
  participações, comentários, rankings, perfis públicos)
- Ações que exigem login (participar, votar, criar, aportar, seguir,
  comentar, perfil) abrem uma folha de login
- 1º login: onboarding obrigatório — telefone + aceite das políticas
  (LGPD, incluindo uso dos dados para campanhas Google/Meta)

**Desafios & participações**
- Criar (debita saldo), participar (**só IMAGEM** em 9:16, 4:5 ou 1:1 —
  sem 16:9), votar, aumentar prêmio (aporte).
  **Texto e vídeo DESATIVADOS por enquanto** — envio só imagem (no app e no
  admin: sem seletor de tipo, vai direto pro cropper). Player `AutoVideo`
  mantido só p/ conteúdo de vídeo já existente; o ticker de vitórias só
  mostra desafios de imagem (exclui challengeIds com entry texto/vídeo).
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
  GANHOU quais desafios, lendo desafios reais encerrados + vencedores (prova
  social) — troca a cada 4s, com **8 variações de frase** ("ganhou/levou/
  faturou/venceu/prêmio pago para...")
- **Banner "ao vivo" cresce sozinho (drift client-side)**: prêmios sobem a
  cada 5s (R$0,01–R$1,50, valor completo com centavos visíveis),
  participantes +1 a cada 5min, desafios +1 a cada 15min; edição do admin
  zera o drift local
- **Auto-votos (cron 3min, `autoVoteRealEntries`)**: +1 voto em CADA
  participação de usuário REAL em desafio ativo (entry + challenge +
  users.totalVotesReceived; sem notificação pra não virar spam).
  Kill-switch: `config/engagement.autoVotes == false`
- **Seed re-executável `seedActiveEngagement`** (POST + secret): enche os
  desafios ativos de comentários realistas de perfis virtuais (curtidas +
  respostas, últimas 36h) e soma votos (+2..13) nas participações
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
- **Hub do painel redesenhado** (v2.8.1): visão geral ao vivo (desafios
  ativos, prêmios, saques pendentes, denúncias — com count-up e alerta
  vermelho de pendências), grid responsivo (2 colunas >620px), cards com
  ícone gradiente + hover + badges de pendências, seções (Operações /
  Conteúdo / Pessoas / Marketing), entrada escalonada e pull-to-refresh;
  contadores recarregam ao voltar de uma subpágina
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

**SEO orgânico (v2.9.0 — máquina de tráfego sem mídia paga)**
- **Hub `/novidades`** renderizado no SERVIDOR (função `seoPage` via rewrite —
  o app Flutter é canvas e invisível pro Google): índice + artigos com
  JSON-LD (Article/FAQPage/Breadcrumb), OG tags, CSS leve, bloco de desafios
  ativos reais (CTA) e links internos. Cache s-maxage.
- **`/sitemap.xml`** automático (função `seoSitemap`): home, /novidades,
  artigos e todos os /challenges/{id}. `web/robots.txt` aponta pro sitemap.
- **Geração de conteúdo por IA** (`functions/seo.js`): lê a chave via
  `getSecret` (cofre do admin → fallback .env): GEMINI_API_KEY se houver,
  senão OPENAI_API_KEY. Artigos PT-BR úteis (900-1300 palavras, sem promessas
  falsas), slug único, sanitização de HTML. **Basta colar a chave em
  Admin→Chaves — funciona sem redeploy.**
- **Artigos escritos à mão** já publicados (`seedSeoArticles` — `?lang=en`
  para o conjunto EN) — conteúdo real/indexável hoje, sem depender de IA.
- **Hub SSR é host-aware** (v3.2.0): `seoPage`/`seoSitemap` detectam o host
  (trialspaid → EN + branding TrialsPaid + desafios INTL; desafiopago → PT).
  Artigos têm campo `lang` (legado sem lang = 'pt'); cada hub/sitemap mostra
  só o seu idioma e sua região. Rewrites /novidades + /sitemap.xml também no
  target `intl`.
- **Links internos**: cada artigo mostra "Leia também / Read next" (3
  relacionados do mesmo idioma) — reforça SEO. Crédito "Criado por
  {AppConfig.creator}" no rodapé SSR e no app.
- **Descoberta no app**: card "Novidades/News" no perfil abre o hub.
- **Consultor de SEO por IA** (v3.3.0, Admin→SEO): `adminSeoAdvisor` junta o
  estado (artigos pt/en, fila, desafios ativos por região) + os resultados
  que o admin cola do Search Console → Gemini/OpenAI devolve diagnóstico,
  prioridades, ganhos rápidos e temas sugeridos; botão joga os temas na fila
  (`adminAddSeoTopics`, source 'advisor'). Requer a chave de IA no cofre.
- **Guia do Search Console** (Admin→SEO): passo a passo de submissão, os 2
  sitemaps com botão copiar e o e-mail do service account do loop de demanda.

### 🌐 Seletor de idioma cruzando os sites (v3.2.0)
- `LanguageSelector` aparece nos DOIS builds. No BR: 🇧🇷 fica ativo e escolher
  outro idioma abre `trialspaid.web.app/?lang=xx` já naquele idioma (main.dart
  lê `?lang`). No intl: troca na hora e 🇧🇷 volta pro desafiopago.
- Crédito do criador (`AppConfig.creator = 'Gustavo Tinti'`) no rodapé de
  ambos (fácil de trocar/ocultar).
- **Cron diário** `seoDailyPublish` (9h BRT): publica 1 artigo/dia da fila
  `seo_topics` (~48 temas seed). Kill-switch: `config/seo.autoPublish`.
- **Loop de demanda GSC** `gscSyncQueries` (toda segunda 8h): lê o Search
  Console (queries com impressões e posição ruim = oportunidade) e alimenta
  a fila de tópicos. REQUER: adicionar
  `desafio-app-b8665@appspot.gserviceaccount.com` como usuário na
  propriedade do GSC + API searchconsole.googleapis.com habilitada.
- **Admin → SEO/Novidades**: gerar artigo na hora (tema livre ou fila),
  toggle da publicação automática, fila de tópicos e lista dos publicados.
- Meta tags/JSON-LD da home melhorados (web/index.html).

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
- `functions/.env` fora do git (token MP, MP_WEBHOOK_SECRET; a linha
  `OPENAI_API_KEY=` existe mas está VAZIA — IA de conteúdo/moderação só
  funciona quando o usuário preencher OPENAI_API_KEY ou GEMINI_API_KEY
  e as functions forem redeployadas)

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