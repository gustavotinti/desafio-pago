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

// ─── Câmbio USD ↔ BRL (site internacional) ──────────────────────────────────
// Convenção ÚNICA: brlPerUsd = quantos BRL vale 1 USD (~5,4). No Firestore
// (config/rates e payments) o campo continua se chamando `usdBrl` por
// compatibilidade com o que já está salvo — mesma semântica (BRL por 1 USD).

// Faixa plausível de BRL por 1 USD. Fora dela a cotação é tratada como
// inválida (ex.: valor invertido, USD por BRL ≈ 0,185).
const BRL_PER_USD_MIN = 1;
const BRL_PER_USD_MAX = 20;

/**
 * Diz se uma cotação BRL-por-USD é plausível (entre 1 e 20).
 * @param {number} brlPerUsd BRL por 1 USD
 * @return {boolean}
 */
function isSaneBrlPerUsd(brlPerUsd) {
  const v = Number(brlPerUsd);
  return Number.isFinite(v) && v > BRL_PER_USD_MIN && v < BRL_PER_USD_MAX;
}

/**
 * Normaliza um conjunto de cotações {xrpUsd, xrpBrl, usdBrl}. Se `usdBrl`
 * (BRL por 1 USD) não for plausível, recalcula como xrpBrl / xrpUsd; se nem
 * isso for plausível, usa o `fallback` inteiro. Nunca devolve cotação inválida
 * (o crédito do depósito depende dela).
 * @param {object} rates cotações lidas (CoinGecko, config/rates ou fallback)
 * @param {object} fallback cotações conservadoras (já consistentes)
 * @return {{xrpUsd:number, xrpBrl:number, usdBrl:number}}
 */
function normalizeRates(rates, fallback) {
  const r = rates || {};
  const xrpUsd = Number(r.xrpUsd);
  const xrpBrl = Number(r.xrpBrl);
  if (xrpUsd > 0 && xrpBrl > 0) {
    if (isSaneBrlPerUsd(r.usdBrl)) {
      return {...r, xrpUsd, xrpBrl, usdBrl: Number(r.usdBrl)};
    }
    const derived = xrpBrl / xrpUsd;
    if (isSaneBrlPerUsd(derived)) {
      return {...r, xrpUsd, xrpBrl, usdBrl: derived};
    }
  }
  if (fallback && fallback !== rates) return normalizeRates(fallback, null);
  throw new Error("normalizeRates: cotação inválida e sem fallback");
}

/**
 * Converte USD → BRL (ledger), arredondando a 2 casas.
 * Lança se a cotação for implausível (nunca credita valor errado em silêncio).
 * @param {number} usd valor em USD
 * @param {number} brlPerUsd BRL por 1 USD
 * @return {number} valor em BRL
 */
function brlFromUsd(usd, brlPerUsd) {
  if (!isSaneBrlPerUsd(brlPerUsd)) {
    throw new Error(`brlFromUsd: cotação implausível (${brlPerUsd})`);
  }
  return Math.round(Number(usd) * Number(brlPerUsd) * 100) / 100;
}

/**
 * Converte BRL (ledger) → USD para EXIBIÇÃO, arredondando a 2 casas.
 * Retorna 0 se a cotação for implausível (só texto — nunca lança).
 * @param {number} brl valor em BRL
 * @param {number} brlPerUsd BRL por 1 USD
 * @return {number} valor em USD
 */
function usdFromBrl(brl, brlPerUsd) {
  if (!isSaneBrlPerUsd(brlPerUsd)) return 0;
  return Math.round((Number(brl) / Number(brlPerUsd)) * 100) / 100;
}

/**
 * Valor MÍNIMO em US$ para anunciar ao usuário um mínimo em R$ (ex.: saque).
 * Arredonda PARA CIMA e soma 1% de folga: com "mais próximo", R$100 a 5,37
 * viraria $18.62 → o app converte de volta para R$99,99 e o servidor recusa
 * de novo. A folga cobre a diferença entre a cotação do app e a do servidor.
 * Cotação implausível → 0 (quem chama decide não mostrar).
 * @param {number} minBrl
 * @param {number} brlPerUsd BRL por 1 USD.
 * @return {number}
 */
function minUsdForBrl(minBrl, brlPerUsd) {
  if (!isSaneBrlPerUsd(brlPerUsd)) return 0;
  // toFixed(6) antes do ceil: evita 18.6200000001 virar 18.63 por ruído.
  const cents = Number(((Number(minBrl) / Number(brlPerUsd)) * 1.01 * 100)
      .toFixed(6));
  return Math.ceil(cents) / 100;
}

module.exports = {
  splitPrizeCents, withdrawalFee, withdrawalNet, xrpFromBrl,
  isSaneBrlPerUsd, normalizeRates, brlFromUsd, usdFromBrl, minUsdForBrl,
};
