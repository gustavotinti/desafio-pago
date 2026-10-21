# Pendências do Desafio Pago / TrialsPaid — o que só você pode fazer

> Atualizado em **21/10/2026**. Cada item tem o **porquê**, o **passo a passo** e o
> que **eu faço depois**.
>
> 🔴 urgente · 🟡 importante · 🟢 quando puder · ✅ feito

## Resumo em 30 segundos

| # | O quê | Tempo | Prioridade |
|---|---|---|---|
| 1 | ~~Religar o faturamento (Blaze)~~ — **resolvido em 28/09** | — | ✅ |
| 2 | Criar alerta de orçamento (para não ser pego de surpresa de novo) | 2 min | 🔴 |
| 3 | **Publicar a v3.8.0 + vídeo por link** (o deploy precisa da sua liberação) | 10 min | 🔴 |
| 3b | Testar o vídeo por link (YouTube e Instagram) | 10 min | 🟡 |
| 4 | Colar a chave do Gemini (grátis) no painel | 3 min | 🟡 |
| 5 | Conferir o Search Console + importar no Bing | 3 min | 🟡 |
| 6 | Criar o app Live do PayPal e colar as chaves (depósitos do TrialsPaid) | 15 min | 🟡 |
| 7 | Testar o dinheiro ponta a ponta (você disse que faria depois) | 30 min | 🟡 |
| 8 | Responder 3 decisões rápidas | 1 min | 🟡 |
| 9 | Instagram automático (opcional) | 40 min | 🟢 |
| 10 | Futuro: Conta PJ no MP, saque automático, Java p/ testes, domínio próprio | — | 🟢 |

---

## 1. ✅ Religar o faturamento (plano Blaze) — resolvido em 28/09/2026

Mantido abaixo só como registro do que aconteceu.

### (registro) Religar o faturamento — 5 min

**Por quê.** Desde **07/09/2026** o projeto `desafio-app-b8665` está **sem conta de
faturamento** (`billingEnabled: false`). Sem ela o Google desliga tudo que é pago:

| O que | Estado hoje |
|---|---|
| Todas as Cloud Functions (votar, criar desafio, Pix, PayPal, saque, moderação, crons) | **fora — HTTP 503** |
| `/novidades` e `/sitemap.xml` (o SEO inteiro), prévias de link `/challenges/*` | **503 — o Google está desindexando** |
| Imagens enviadas por usuários reais (Firebase Storage) | **não carregam — HTTP 402** |
| Encerramento automático de desafios (cron de 5 min) | parado há 17 dias |
| Site estático + leitura do feed | ✅ no ar (por isso "parece" funcionar) |

As 79 funções **continuam instaladas** — não foram apagadas. Voltam sozinhas quando o
faturamento voltar. Mas não demore: projetos muito tempo sem faturamento podem ter
recursos removidos pelo Google.

**Passo a passo**
1. Entre com **gustavo.a.tinti3@gmail.com** em:
   <https://console.cloud.google.com/billing/linkedaccount?project=desafio-app-b8665>
2. Se aparecer "Este projeto não tem uma conta de faturamento":
   clique em **Vincular uma conta de faturamento** → escolha a conta → **Definir conta**.
3. Se a conta aparecer como **encerrada/suspensa** (causa mais comum: cartão
   vencido/recusado, ou o período de teste gratuito acabou sem "ativar conta completa"):
   1. Abra <https://console.cloud.google.com/billing> e selecione a conta.
   2. Em **Formas de pagamento**, atualize o cartão.
   3. Clique em **Reativar** (ou **Ativar conta completa**, se era teste gratuito).
   4. Volte ao passo 2 e vincule ao projeto.
4. Confirme que o plano aparece como **Blaze** em:
   <https://console.firebase.google.com/project/desafio-app-b8665/usage/details>

> O Blaze mantém a mesma cota gratuita do plano Spark. Você só paga o que passar dela.
> Nesta rodada eu reduzi bastante as leituras mais caras do projeto (ver apêndice).

## 2. 🔴 Criar um alerta de orçamento — 2 min

**Por quê.** Para você ser avisado por e-mail **antes** de qualquer surpresa, em vez de
descobrir quando o site cai.

1. <https://console.cloud.google.com/billing> → sua conta → **Orçamentos e alertas** →
   **Criar orçamento**.
2. Nome: `Desafio Pago`. Projetos: `desafio-app-b8665`.
3. Valor: **R$ 50/mês** (ou o que fizer sentido para você).
4. Alertas em **50%, 90% e 100%**, enviados por e-mail para os administradores de faturamento.
5. **Concluir**.

> O alerta **não desliga nada**, só avisa. É o comportamento certo para um site com
> dinheiro de usuário: cortar o serviço automaticamente seria pior.

## 3. 🔴 Publicar a v3.8.0 + vídeo por link — precisa da sua liberação

**Por quê.** Tudo está pronto, testado e salvo no repositório (correções de dinheiro e
segurança, SEO e vídeo por link). Mas o **modo automático do Claude Code bloqueia
deploy em produção** sem uma liberação explícita sua. Isso é uma trava de segurança
da ferramenta, e eu não posso contorná-la. Escolha **uma** das opções:

**Opção A: você roda (4 comandos, ~10 min).** No terminal, dentro de
`C:\Users\Jessica\desafio_project\apps\mobile`, **nesta ordem** (functions primeiro:
o app novo depende delas):

```bash
firebase deploy --only functions --project desafio-app-b8665
```

```bash
firebase deploy --only firestore:rules,storage --project desafio-app-b8665
```

Se aparecer uma pergunta sobre dar ao Storage permissão de ler o Firestore, responda
**Y (sim)**. A regra nova de uploads do admin depende disso.

```bash
node build_sites.js
```

```bash
firebase deploy --only hosting --project desafio-app-b8665
```

**Opção B: me liberar para fazer.** Abra as configurações de permissão do Claude Code e
adicione uma regra que permita `Bash(firebase deploy:*)`. Depois me diga "pode
publicar".

**Depois do deploy, eu faço** (você não precisa fazer nada disto):
1. Confiro ao vivo os dois sites, o `/sitemap.xml`, o `/novidades` e uma prévia de link.
2. **Search Console 100% por API** (`gscSetup`): habilito as APIs, gero o token dos 2
   sites, coloco no `<head>`, publico, verifico a posse, **adiciono seu e-mail como
   proprietário** e envio os 2 sitemaps.
3. Encho a fila de temas de SEO (hoje está **vazia**; existem só 6 artigos).
4. Rodo o `gscSyncQueries` uma vez para puxar as buscas do Google para a fila.

## 3b. 🟡 Testar o vídeo por link — 10 min (depois do deploy)

1. Abra um desafio → **Participar** → **Vídeo (link)**. Aparece **o seu código**
   (ex.: `DPK7M2Q`, um por desafio).
2. **YouTube:** publique um **Shorts** (vertical) **público** com o código no
   **título** → cole o link → **Enviar**. A verificação é automática: se faltar o
   código, o vídeo for horizontal ou privado, a mensagem diz exatamente o que corrigir.
   Se você acabou de editar o título, espere 1–2 min (o YouTube demora para atualizar).
3. **Instagram:** publique um **Reels** com o código na **legenda** → cole o link →
   **Enviar**. Ele entra como "Aguardando verificação".
4. **Admin → Vídeos para verificar:** toque na capa (abre o vídeo **com a legenda**),
   confira o código e clique **Aprovar** ou **Recusar**.
5. **Regras de prêmio:** só vídeo **verificado** concorre. Vídeo do Instagram que não
   for aprovado **antes do fim do prazo** não ganha (o card mostra o prazo em vermelho
   nas últimas 24h). Se um vídeo do YouTube for apagado ou ficar privado antes do
   encerramento, ele sai da disputa e vence o próximo.

## 4. 🟡 Chave do Gemini (grátis) — 3 min

**O que destrava:** artigo novo todo dia às 9h (SEO no piloto automático), o consultor
de SEO por IA no painel e a **moderação automática de imagens**.

1. Abra <https://aistudio.google.com/apikey> (mesma conta Google).
2. **Criar chave de API** → escolha o projeto `desafio-app-b8665` → copie a chave.
3. No site: **Perfil → Admin → Chaves & integrações** → card
   **"IA de conteúdo (SEO / Novidades)"** → cole em **"Google Gemini API Key (grátis)"** →
   **Salvar**.
4. O card passa a mostrar `••••` + os 4 últimos dígitos. Funciona na hora, sem deploy.

> ⚠️ Não me mande a chave pelo chat. Cole direto no painel: o campo só grava, ninguém lê
> de volta.
>
> Privacidade: no **nível gratuito** o Google pode usar o que é enviado para melhorar os
> produtos dele. Os artigos não têm problema. Já a moderação envia as **fotos dos
> participantes**. Se quiser evitar isso, ative o faturamento no próprio AI Studio (o
> nível pago não usa os dados); o custo da moderação é de centavos.

## 5. 🟡 Search Console + Bing — 3 min (depois do item 3)

1. Abra <https://search.google.com/search-console>. As propriedades
   `https://desafiopago.com.br/` e `https://trialspaid.web.app/` **já vão aparecer**,
   porque eu te adiciono como proprietário pela API.
2. Em cada uma, confira **Sitemaps** → status **"Processado"**.
3. **Bing** (vale muito a pena: o índice do Bing alimenta o DuckDuckGo, o Yahoo e a
   busca do ChatGPT):
   1. <https://www.bing.com/webmasters>, entre com a mesma conta Google.
   2. Clique em **Importar do Google Search Console** → autorize → selecione os 2 sites →
      **Importar**.
   3. Pronto: sitemaps e verificação vêm juntos.

## 6. 🟡 PayPal — depósitos do TrialsPaid — 15 min

**Pré-requisito:** conta PayPal **Empresa**, verificada, com banco vinculado (você já tem).

1. <https://developer.paypal.com/dashboard/> → entre com a conta PayPal Empresa.
2. **Apps & Credentials** → no topo, mude a chave para **Live** (não Sandbox).
3. **Create App** → nome `TrialsPaid` → tipo **Merchant** → **Create App**.
4. Copie o **Client ID** e clique em **Show** para copiar o **Secret**.
5. No site: **Admin → Chaves & integrações → card "PayPal (depósito — internacional)"**:
   - Client ID → cole
   - Secret → cole
   - Modo → `live`
   - **Salvar**
6. **Teste com US$ 1:** <https://trialspaid.web.app> → Profile → **Add credits** →
   **Pay with PayPal** → aprove na aba do PayPal → volte → **I have paid** → o saldo
   aparece. Se você fechar a aba no meio, agora o app lembra o pagamento em aberto e
   oferece concluir (correção desta rodada).

## 7. 🟡 Teste do dinheiro ponta a ponta — 30 min (quando puder)

Você disse que faria depois. Guarde este roteiro. **Use 2 contas Google** (A e B).

**Brasil (Pix):**
1. Conta A: **Adicionar créditos → Pix de R$ 5** → pague → o saldo sobe sozinho em
   até ~1 min (webhook).
2. Conta A: **Criar desafio** de R$ 5 com prazo curto.
3. Conta B: **participar** com uma imagem. A não pode participar do próprio desafio.
4. Conta A (ou uma C): **votar** na participação de B. Tentar votar de novo → deve recusar.
5. **Admin → Desafios → Encerrar agora** no desafio → o prêmio cai no saldo de B.
6. **Saque:** só funciona com **R$ 100 ou mais** de saldo (regra). Para testar sem
   gastar R$ 100, me peça e eu baixo o mínimo **temporariamente** e depois volto.
7. **Admin → Saques** → aprovar → enviar o Pix manualmente → **Marcar como pago**.

**Internacional (TrialsPaid):** depósito PayPal (item 6) → pedir saque em **XRP**
(endereço `r...`) → **Admin → Saques** mostra o endereço, a tag e a estimativa em XRP →
você envia pela sua carteira → **Marcar como pago**.

**Me mande prints de qualquer passo que der erro.** Os erros agora aparecem com
mensagem amigável, e eu consigo investigar pelos logs.

## 8. 🟡 Decisões rápidas — responda com as letras

**D1 — Feed quase vazio.** Hoje há **38 desafios, só 2 ativos**; 34 são virtuais e já
encerraram. Quer que eu **reative os desafios virtuais** com prazos novos (função
`resetVirtualChallengeDeadlines`, que já existe) para o feed voltar a parecer movimentado?
- **(a)** Sim, reative *(minha recomendação — é a estratégia que você já usa)*
- **(b)** Não, deixa só os reais

Obs.: desafios virtuais continuam aparecendo para visitantes, mas **saíram do sitemap**.
Página de desafio falso indexada no Google é risco de penalização por spam, e o valor
de SEO dela é quase zero.

**D2 — Auto-votos (cron a cada 3 min).** Eu **reduzi o custo** dele sem mudar o ritmo:
agora ele só lê as participações de desafios ativos e pula as virtuais. Quer também
diminuir a frequência?
- **(a)** Manter a cada 3 min *(recomendado, o custo já caiu muito)*
- **(b)** A cada 15 min

**D3 — Excluir conta com saldo.** Antes, excluir a conta **apagava o saldo em silêncio**.
Agora o app **mostra o valor que será perdido** e pede confirmação explícita (a exclusão
continua permitida, como exige a LGPD). O valor fica registrado no log de auditoria.
- **(a)** Ok assim *(recomendado)*
- **(b)** Prefiro **bloquear** a exclusão enquanto houver saldo. Atenção: quem tem menos
  de R$ 100 não consegue sacar e ficaria preso.

## 9. 🟢 Instagram automático (opcional) — ~40 min

**Pré-requisitos:** conta do Instagram **Profissional (Empresa)** vinculada a uma
**Página do Facebook**.

1. <https://developers.facebook.com/apps> → **Criar app** → tipo **Empresa**.
2. Adicione o produto **Instagram** (opção **"API do Instagram com login do Facebook"**).
3. Abra o **Graph API Explorer** (<https://developers.facebook.com/tools/explorer>) →
   selecione o app → em permissões marque `instagram_basic`,
   `instagram_content_publish`, `pages_show_list`, `pages_read_engagement` e
   `business_management` → **Generate Access Token** → autorize.
4. Transforme em token de **60 dias**: abra o **Access Token Debugger**
   (<https://developers.facebook.com/tools/debug/accesstoken>), cole o token e clique em
   **Extend Access Token**.
5. Descubra o **ID do Instagram**: no Graph API Explorer, faça
   `GET me/accounts?fields=instagram_business_account{id,username}` e copie o `id`.
6. No site: **Admin → Chaves → card "Instagram"** → cole o token e o ID → **Salvar**.
   Depois, em **Admin → Instagram**, ligue e defina o valor mínimo (padrão R$ 100).
7. **Anote na agenda:** o token vence em 60 dias. Para renovar, repita os passos 4 e 6.

> Com o app em modo "Desenvolvimento" já funciona para **a sua própria conta**, sem
> precisar da análise da Meta. Só desafios do Brasil são postados (a conta é brasileira).

## 10. 🟢 Futuro (sem pressa)

- **Nome "Desafio Pago" no Pix do pagador:** hoje aparece o seu nome pessoal. Para
  mudar, é preciso uma **Conta PJ** no Mercado Pago registrada como "Desafio Pago".
  Depois é só colar o token novo em Admin → Chaves → Mercado Pago.
- **Saque automático:** precisa de um provedor de pagamento de saída (Asaas ou Efí),
  normalmente com CNPJ. Combinamos manter manual por enquanto.
- **Testes de integração** (simular o fluxo de dinheiro inteiro sem gastar nada):
  preciso de **Java** na sua máquina. Rode `winget install Microsoft.OpenJDK.21` no
  terminal e me avise; eu escrevo e rodo os testes.
- **Domínio próprio para o TrialsPaid** (ex.: `trialspaid.com`, ~US$ 10/ano): passa mais
  credibilidade e ajuda no SEO internacional. Se comprar, eu conecto no Firebase.
- **Bloqueio de VPN:** fica para depois; hoje o bloqueio de região é pelo site.

---

## Apêndice — o que eu corrigi nesta rodada (24/09)

Uma auditoria com 46 agentes revisou o código em 7 frentes (dinheiro, regras de
segurança, site internacional, app, custo, SEO e resiliência). Cada problema passou
por um "cético" que tentou provar que era alarme falso. Sobraram **32 problemas reais**,
e todos foram corrigidos. Está tudo pronto no código, esperando o faturamento voltar
para ir ao ar (item 3).

**Dinheiro e segurança**
- **Voto "empilhado":** dava para votar várias vezes na mesma participação usando o ID
  de outros desafios. Isso podia decidir quem leva o prêmio. Fechado.
- **Desafio travado para sempre:** se a participação mais votada fosse de uma conta
  excluída, o encerramento falhava a cada 5 min e ninguém recebia. Agora vence a próxima
  participação válida.
- **Excluir conta apagava o saldo em silêncio.** Agora o app avisa o valor e pede
  confirmação, e o valor fica registrado no log de auditoria. A exclusão também passou a
  apagar CPF e telefone do pedido de selo (LGPD), liberar o @ e apagar as notificações.
- **Usuário banido** ainda conseguia criar desafio, aportar, depositar e **sacar** (o
  bloqueio era só visual). Agora é bloqueado no servidor.
- **Aporte** podia dar erro *depois* de debitar, levando o usuário a pagar duas vezes.
- **PayPal:** a cotação de reserva estava invertida. Se a cotação online caísse, um
  depósito creditaria **~29 vezes menos**. A mensagem de saque mínimo do TrialsPaid
  mostrava $540 em vez de ~$18,52.
- **Admin → Saques:** dois cliques em "Rejeitar" devolviam o saldo **em dobro**. Agora o
  sistema confere o status antes, trava o botão e pede confirmação.
- **Saque do usuário:** dois toques criavam dois pedidos. Agora o botão trava.
- **Admin → Denúncias:** podia banir a participação **errada** quando a lista se
  reordenava.
- **Imagens:** qualquer usuário logado podia **sobrescrever a foto da participação de
  outro** (sabotagem em disputa por prêmio). Agora só o dono (ou admin) pode.

**Site internacional (TrialsPaid)**
- **Nenhum estrangeiro conseguia terminar o cadastro:** o servidor só aceitava telefone
  brasileiro (10–11 dígitos).
- **Aporte:** a pessoa digitava US$ 50 e eram debitados R$ 50 (~US$ 9).
- Login, recorte de imagem, denúncia e exclusão de conta apareciam **em português**.
  Agora estão nos 5 idiomas.
- Erros técnicos crus ("Exception: INTERNAL") viraram mensagens amigáveis no idioma certo.
- PayPal: se a pessoa fechar a aba no meio, o app lembra o pagamento em aberto.
- Instagram: desafio internacional não é mais postado na conta brasileira, em português
  e com preço em R$.

**SEO**
- **Toda página de desafio dizia ao Google "eu sou a home"** (canonical errado), então
  nenhuma era indexada. Também tinham as tags de prévia duplicadas. Agora cada uma tem
  título, descrição e prévia próprios, e no TrialsPaid saem com a marca e o link certos.
- **hreflang** entre os dois sites: o Google entende que são as versões pt-BR e inglês
  do mesmo produto, e mostra a certa para cada país.
- Sitemap sem desafios virtuais ou encerrados (conteúdo ralo, com risco de penalização).
- Artigo que não existe agora dá 404 de verdade (antes redirecionava para a home, o que
  o Google trata como "soft 404"). Erro temporário dá 503, e o Google tenta de novo sem
  desindexar.

**Custo (importante, dado o que aconteceu com o faturamento)**
- O robô de auto-votos lia **a coleção inteira de participações a cada 3 minutos**. Agora
  lê só as de desafios ativos de usuários reais.
- A faixa "fulano ganhou" lia todas as participações a cada abertura do feed, até de
  visitante. Agora lê só quando precisa, com limite e cache.
- Abrir comentários lia **todas as curtidas que o usuário já deu na vida**. Agora lê só
  as do desafio.

**Experiência**
- O feed não volta mais para o topo ao sair de um desafio.
- Autores não ficam presos como "Participante" sem foto depois de uma falha de rede.

**Infraestrutura**
- `build_sites.js`: os 2 sites saem de **um comando**, com checagens que param tudo se
  algo sair errado. Antes era uma sequência manual que só existia no histórico do
  terminal.
- Testes automáticos: **JS de 16 para 39**, **Dart de 8 para 13**.
