// ─── COTAÇÕES (USD/BRL/XRP) — fonte única ────────────────────────────────────
// Usada pelos pagamentos internacionais (PayPal/XRP) e pelo SSR do TrialsPaid
// (prêmios em US$ no /novidades). Uma fonte só = o mesmo valor no depósito e
// na vitrine.
//
// ATENÇÃO: este módulo NÃO é espalhado no `exports` do index.js (não tem
// Cloud Function aqui) — é só `require` normal.

const admin = require("firebase-admin");
const {normalizeRates, isSaneBrlPerUsd} = require("./money");

// Fallback conservador (só usado se CoinGecko E o último valor salvo falharem).
// usdBrl = BRL por 1 USD (mesma convenção do caminho feliz: xrpBrl / xrpUsd).
const FALLBACK_RATES = {xrpUsd: 2.5, xrpBrl: 13.5, usdBrl: 13.5 / 2.5};

// Cotações de mercado (CoinGecko) com timeout + cache do último bom valor em
// config/rates. NUNCA lança: crédito de pagamento não pode travar por causa
// de uma API de cotação fora do ar (o dinheiro já foi cobrado no PayPal).
const rawRates = async () => {
  try {
    const r = await fetch(
        "https://api.coingecko.com/api/v3/simple/price" +
        "?ids=ripple&vs_currencies=usd,brl",
        {signal: AbortSignal.timeout(8000)});
    const j = await r.json();
    const xrpUsd = Number(j.ripple && j.ripple.usd);
    const xrpBrl = Number(j.ripple && j.ripple.brl);
    // Só aceita (e só salva) cotação plausível — senão tenta o último salvo.
    if (xrpUsd > 0 && xrpBrl > 0 && isSaneBrlPerUsd(xrpBrl / xrpUsd)) {
      const rates = {xrpUsd, xrpBrl, usdBrl: xrpBrl / xrpUsd,
        at: new Date().toISOString()};
      admin.firestore().collection("config").doc("rates")
          .set(rates).catch(() => {});
      return rates;
    }
  } catch (e) {
    console.warn("rates: CoinGecko falhou —", e.message);
  }
  // Último valor salvo (bom o suficiente para converter).
  try {
    const doc = await admin.firestore().collection("config").doc("rates").get();
    const d = doc.exists ? doc.data() : null;
    if (d && d.xrpUsd > 0 && d.xrpBrl > 0) return d;
  } catch (e) {
    // segue pro fallback
  }
  return FALLBACK_RATES;
};

// Sempre passa por normalizeRates: usdBrl (BRL por 1 USD) fora de 1..20 é
// recalculado como xrpBrl / xrpUsd (ou cai no fallback).
const getRates = async () => normalizeRates(await rawRates(), FALLBACK_RATES);

module.exports = {FALLBACK_RATES, getRates};
