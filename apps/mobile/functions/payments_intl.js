// ─── PAGAMENTOS INTERNACIONAIS (trialspaid.web.app) ──────────────────────────
// Depósito via PayPal (conta empresa do dono) e saque em cripto (XRP).
//
// Modelo de dinheiro: o ledger interno continua em BRL (todas as transações
// atômicas existentes valem). O site internacional só EXIBE em USD/XRP:
//  - Depósito: usuário paga USD no PayPal → convertemos para BRL na cotação
//    de mercado e creditamos o saldo (idempotente).
//  - Saque: usuário informa endereço XRP → valor sai do ledger (taxa 10%),
//    fica travado, e o admin envia o XRP manualmente e marca como pago
//    (mesmo fluxo manual do Pix — zero custo de PSP).
//
// Env (functions/.env): PAYPAL_CLIENT_ID, PAYPAL_SECRET,
// PAYPAL_MODE=live|sandbox (default live).

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {getSecret} = require("./secrets");
const {xrpFromBrl} = require("./money");

// ─── Mensagens localizadas (pt no BR, en no internacional) ───────────────────
const langOf = (data) => (data && data.lang === "en" ? "en" : "pt");
const MSG = {
  paypalNotConfigured: {
    pt: "PayPal ainda não configurado.",
    en: "PayPal isn't set up yet.",
  },
  amountRange: {
    pt: "Valor entre US$ 1 e US$ 10.000.",
    en: "Amount must be between $1 and $10,000.",
  },
  orderNotFound: {pt: "Ordem não encontrada.", en: "Order not found."},
  userNotFound: {pt: "Usuário não encontrado.", en: "User not found."},
  insufficient: {pt: "Saldo insuficiente.", en: "Insufficient balance."},
  xrpInvalid: {pt: "Endereço XRP inválido.", en: "Invalid XRP address."},
  tagInvalid: {pt: "Destination tag inválida.", en: "Invalid destination tag."},
  orderIdRequired: {pt: "orderId obrigatório.", en: "orderId is required."},
};
const t = (lang, key) => (MSG[key] && MSG[key][lang]) || MSG[key].pt;
const minWithdrawMsg = (lang, minBrl, usdBrl) => lang === "en" ?
  `Minimum withdrawal is about $${(minBrl * usdBrl).toFixed(2)}.` :
  `Valor mínimo de saque: R$${minBrl} (≈ US$ ${(minBrl * usdBrl).toFixed(2)}).`;

const _paypalBase = async () =>
  ((await getSecret("PAYPAL_MODE")) === "sandbox" ?
    "https://api-m.sandbox.paypal.com" : "https://api-m.paypal.com");

// Cache do token do PayPal por instância (o token vale horas; TTL curto).
let _tokCache = null;
let _tokAt = 0;
const _paypalToken = async (lang) => {
  if (_tokCache && (Date.now() - _tokAt) < 8 * 60 * 1000) return _tokCache;
  const id = await getSecret("PAYPAL_CLIENT_ID");
  const secret = await getSecret("PAYPAL_SECRET");
  if (!id || !secret) {
    throw new functions.https.HttpsError(
        "failed-precondition", t(lang, "paypalNotConfigured"));
  }
  const r = await fetch(`${await _paypalBase()}/v1/oauth2/token`, {
    method: "POST",
    headers: {
      "Authorization": "Basic " +
          Buffer.from(`${id}:${secret}`).toString("base64"),
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: "grant_type=client_credentials",
  });
  const j = await r.json();
  if (!j.access_token) {
    throw new functions.https.HttpsError(
        "internal", "PayPal auth failed: " + JSON.stringify(j));
  }
  _tokCache = j.access_token;
  _tokAt = Date.now();
  return _tokCache;
};

// Fallback conservador (só usado se CoinGecko E o último valor salvo falharem).
const _FALLBACK_RATES = {xrpUsd: 2.5, xrpBrl: 13.5, usdBrl: 0.185};

// Cotações de mercado (CoinGecko) com timeout + cache do último bom valor em
// config/rates. NUNCA lança: crédito de pagamento não pode travar por causa
// de uma API de cotação fora do ar (o dinheiro já foi cobrado no PayPal).
const _rates = async () => {
  try {
    const r = await fetch(
        "https://api.coingecko.com/api/v3/simple/price" +
        "?ids=ripple&vs_currencies=usd,brl",
        {signal: AbortSignal.timeout(8000)});
    const j = await r.json();
    const xrpUsd = Number(j.ripple && j.ripple.usd);
    const xrpBrl = Number(j.ripple && j.ripple.brl);
    if (xrpUsd > 0 && xrpBrl > 0) {
      const rates = {xrpUsd, xrpBrl, usdBrl: xrpBrl / xrpUsd,
        at: new Date().toISOString()};
      admin.firestore().collection("config").doc("rates")
          .set(rates).catch(() => {});
      return rates;
    }
  } catch (e) {
    console.warn("_rates: CoinGecko falhou —", e.message);
  }
  // Último valor salvo (bom o suficiente para converter).
  try {
    const doc = await admin.firestore().collection("config").doc("rates").get();
    const d = doc.exists ? doc.data() : null;
    if (d && d.xrpUsd > 0 && d.xrpBrl > 0) return d;
  } catch (e) {
    // segue pro fallback
  }
  return _FALLBACK_RATES;
};

// ─── DEPÓSITO: criar ordem PayPal ────────────────────────────────────────────

exports.paypalCreateOrder = functions.https.onCall(async (data, context) => {
  const lang = langOf(data);
  if (!context.auth) {
    throw new functions.https.HttpsError(
        "unauthenticated", lang === "en" ? "Not signed in." : "Não autenticado");
  }
  const amountUsd = Math.round(Number(data.amountUsd) * 100) / 100;
  if (!isFinite(amountUsd) || amountUsd < 1 || amountUsd > 10000) {
    throw new functions.https.HttpsError(
        "invalid-argument", t(lang, "amountRange"));
  }
  const token = await _paypalToken(lang);
  const r = await fetch(`${await _paypalBase()}/v2/checkout/orders`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${token}`,
    },
    body: JSON.stringify({
      intent: "CAPTURE",
      purchase_units: [{
        amount: {currency_code: "USD", value: amountUsd.toFixed(2)},
        description: "TrialsPaid credits",
      }],
      application_context: {
        brand_name: "TrialsPaid",
        user_action: "PAY_NOW",
        shipping_preference: "NO_SHIPPING",
        return_url: "https://trialspaid.web.app/",
        cancel_url: "https://trialspaid.web.app/",
      },
    }),
  });
  const order = await r.json();
  if (!order.id) {
    throw new functions.https.HttpsError(
        "internal", "PayPal did not create the order: " + JSON.stringify(order));
  }
  const approve = (order.links || [])
      .find((l) => l.rel === "approve" || l.rel === "payer-action");
  const db = admin.firestore();
  await db.collection("payments").doc(`pp_${order.id}`).set({
    userId: context.auth.uid,
    provider: "paypal",
    purpose: "topup",
    amountUsd,
    status: "created",
    createdAt: new Date().toISOString(),
  });
  return {orderId: order.id, approveUrl: approve ? approve.href : null};
});

// ─── DEPÓSITO: capturar e creditar (idempotente) ─────────────────────────────

exports.paypalCaptureOrder = functions.https.onCall(async (data, context) => {
  const lang = langOf(data);
  if (!context.auth) {
    throw new functions.https.HttpsError(
        "unauthenticated", lang === "en" ? "Not signed in." : "Não autenticado");
  }
  const orderId = String(data.orderId || "");
  if (!orderId) {
    throw new functions.https.HttpsError(
        "invalid-argument", t(lang, "orderIdRequired"));
  }
  const db = admin.firestore();
  const payRef = db.collection("payments").doc(`pp_${orderId}`);
  const payDoc = await payRef.get();
  if (!payDoc.exists || payDoc.data().userId !== context.auth.uid) {
    throw new functions.https.HttpsError("not-found", t(lang, "orderNotFound"));
  }
  if (payDoc.data().status === "completed") {
    return {success: true, alreadyCredited: true};
  }

  const token = await _paypalToken(lang);
  // Tenta capturar; se já foi capturada, consulta o status real.
  let status = null;
  const cap = await fetch(
      `${await _paypalBase()}/v2/checkout/orders/${orderId}/capture`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${token}`,
        },
      });
  const capJson = await cap.json();
  status = capJson.status;
  if (status !== "COMPLETED") {
    const chk = await fetch(
        `${await _paypalBase()}/v2/checkout/orders/${orderId}`, {
          headers: {"Authorization": `Bearer ${token}`},
        });
    const chkJson = await chk.json();
    status = chkJson.status;
  }
  if (status !== "COMPLETED") {
    return {success: false, status: status || "PENDING"};
  }

  const {usdBrl, xrpBrl} = await _rates();
  const amountUsd = Number(payDoc.data().amountUsd);
  const amountBrl = Math.round(amountUsd * usdBrl * 100) / 100;

  // Credita com transação (revalida idempotência dentro dela).
  const userRef = db.collection("users").doc(context.auth.uid);
  await db.runTransaction(async (tx) => {
    const p = await tx.get(payRef);
    if (p.data().status === "completed") return;
    const u = await tx.get(userRef);
    if (!u.exists) {
      throw new functions.https.HttpsError(
          "not-found", t(lang, "userNotFound"));
    }
    tx.update(userRef, {
      balance: admin.firestore.FieldValue.increment(amountBrl),
    });
    tx.set(db.collection("transactions").doc(), {
      userId: context.auth.uid,
      type: "deposit",
      amount: amountBrl,
      description: `Depósito PayPal (US$ ${amountUsd.toFixed(2)})`,
      createdAt: new Date().toISOString(),
    });
    tx.update(payRef, {
      status: "completed",
      amountBrl,
      usdBrl,
      completedAt: new Date().toISOString(),
    });
  });
  const xrpEquiv = xrpFromBrl(amountBrl, xrpBrl);
  return {success: true, amountBrl, xrpEquiv};
});

// ─── SAQUE EM CRIPTO (XRP) — pedido do usuário ───────────────────────────────
// Mesmo modelo do saque Pix: trava o valor, taxa de 10%, admin envia o XRP
// manualmente (da própria carteira/exchange) e marca como pago.

exports.requestCryptoWithdraw =
    functions.https.onCall(async (data, context) => {
      const lang = langOf(data);
      if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated",
            lang === "en" ? "Not signed in." : "Não autenticado");
      }
      const userId = context.auth.uid;
      const amount = Math.round(Number(data.amount) * 100) / 100; // BRL ledger
      const xrpAddress = String(data.xrpAddress || "").trim();
      const xrpTag = String(data.xrpTag || "").trim();

      // Endereço/tag primeiro (feedback claro antes de qualquer cálculo).
      if (!/^r[1-9A-HJ-NP-Za-km-z]{24,34}$/.test(xrpAddress)) {
        throw new functions.https.HttpsError(
            "invalid-argument", t(lang, "xrpInvalid"));
      }
      if (xrpTag && !/^\d{1,10}$/.test(xrpTag)) {
        throw new functions.https.HttpsError(
            "invalid-argument", t(lang, "tagInvalid"));
      }

      const {xrpBrl, usdBrl} = await _rates();
      const minWithdrawal = Number(process.env.MIN_WITHDRAWAL || 100);
      if (!isFinite(amount) || amount < minWithdrawal) {
        throw new functions.https.HttpsError("invalid-argument",
            minWithdrawMsg(lang, minWithdrawal, usdBrl));
      }
      const fee = Math.round(amount * 0.10 * 100) / 100;
      const netAmount = Math.round((amount - fee) * 100) / 100;
      const xrpEstimate = xrpFromBrl(netAmount, xrpBrl);

      const db = admin.firestore();
      const userRef = db.collection("users").doc(userId);
      const withdrawalRef = db.collection("withdrawals").doc();
      const now = new Date().toISOString();

      await db.runTransaction(async (tx) => {
        const u = await tx.get(userRef);
        if (!u.exists) {
          throw new functions.https.HttpsError(
              "not-found", "Usuário não encontrado");
        }
        const balance = Number(u.data().balance || 0);
        if (balance < amount) {
          throw new functions.https.HttpsError(
              "failed-precondition", t(lang, "insufficient"));
        }
        tx.set(withdrawalRef, {
          userId,
          amount,
          fee,
          netAmount,
          method: "xrp",
          xrpAddress,
          xrpTag: xrpTag || null,
          xrpEstimate,
          xrpRateBrl: xrpBrl,
          status: "pending",
          createdAt: now,
        });
        tx.update(userRef, {
          balance: admin.firestore.FieldValue.increment(-amount),
          lockedBalance: admin.firestore.FieldValue.increment(amount),
        });
        tx.set(db.collection("transactions").doc(), {
          userId,
          type: "withdraw",
          amount: -amount,
          description: `Saque em XRP solicitado (≈ ${xrpEstimate} XRP)`,
          createdAt: now,
        });
      });
      return {success: true, netAmount, xrpEstimate};
    });
