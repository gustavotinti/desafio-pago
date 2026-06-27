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

module.exports = {splitPrizeCents, withdrawalFee, withdrawalNet};
