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

## Status das fases
- Fase 1 (Setup): quase completo
- Fase 2 (Banco): parcial
- Fase 3 (Usuário): parcial
- Fase 4 (Admin): parcial
- Fase 5 (Financeiro): parcial
- Fases 6 a 19: não iniciadas

## O que já existe
- Flutter + Firebase funcionando
- Login Google + AuthGate
- Usuário salvo automaticamente
- Admin com painel de saques (aprovar/rejeitar)
- Lógica de saldo automático implementada (pendente de teste)
- Estrutura inicial core/services
- Git + GitHub conectados (repositório: gustavotinti/desafio-pago)

## Próximo passo
Fase 5: testar lógica de saldo automático
Depois: Fase 2 — completar modelo do banco de dados