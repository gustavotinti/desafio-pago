"use strict";

// Lógica de dinheiro pura e testável (sem Firestore).
// Espelha o que finalizeChallenge e requestWithdraw fazem no index.js.

/**
 * Divide o prêmio (em centavos) entre N vencedores.
 * O centavo indivisível (resto) fica com a plataforma.
 * @param {number} prizeCents prêmio total em centavos
 * @param {number} numWinners número de vencedores
 * @return {{perWinnerCents:number, platformCents:number}}
 */
function splitPrizeCents(prizeCents, numWinners) {
  let cents = prizeCents;
  if (!Number.isFinite(cents) || cents < 0) cents = 0;
  cents = Math.round(cents);
  if (numWinners <= 0) return {perWinnerCents: 0, platformCents: cents};
  const perWinnerCents = Math.floor(cents / numWinners);
  const platformCents = cents - perWinnerCents * numWinners;
  return {perWinnerCents, platformCents};
}

/**
 * Taxa de saque: 10% do valor, arredondada a 2 casas.
 * @param {number} amount valor bruto do saque
 * @return {number} taxa
 */
function withdrawalFee(amount) {
  return Math.round(amount * 0.10 * 100) / 100;
}

/**
 * Valor líquido do saque (após a taxa de 10%).
 * @param {number} amount valor bruto do saque
 * @return {number} valor líquido
 */
function withdrawalNet(amount) {
  return Math.round((amount - withdrawalFee(amount)) * 100) / 100;
}

/**
 * Estimativa de XRP a partir de um valor em BRL, dado o preço de 1 XRP em BRL.
 * Arredonda a 4 casas. Retorna 0 se a cotação for inválida.
 * @param {number} brl valor em BRL (ledger interno)
 * @param {number} xrpBrl preço de 1 XRP em BRL
 * @return {number} quantidade de XRP
 */
function xrpFromBrl(brl, xrpBrl) {
  if (!(xrpBrl > 0)) return 0;
  return Math.round((brl / xrpBrl) * 10000) / 10000;
}

module.exports = {
  splitPrizeCents, withdrawalFee, withdrawalNet, xrpFromBrl,
};
