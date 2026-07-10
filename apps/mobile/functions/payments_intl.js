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

const _paypalBase = () =>
  (process.env.PAYPAL_MODE === "sandbox" ?
    "https://api-m.sandbox.paypal.com" : "https://api-m.paypal.com");

const _paypalToken = async () => {
  const id = process.env.PAYPAL_CLIENT_ID;
  const secret = process.env.PAYPAL_SECRET;
  if (!id || !secret) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "PayPal ainda não configurado (PAYPAL_CLIENT_ID/PAYPAL_SECRET).");
  }
  const r = await fetch(`${_paypalBase()}/v1/oauth2/token`, {
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
        "internal", "PayPal auth falhou: " + JSON.stringify(j));
  }
  return j.access_token;
};

// Cotações de mercado (CoinGecko): XRP em USD e BRL → cross USD/BRL.
const _rates = async () => {
  const r = await fetch("https://api.coingecko.com/api/v3/simple/price" +
      "?ids=ripple&vs_currencies=usd,brl");
  const j = await r.json();
  const xrpUsd = Number(j.ripple && j.ripple.usd);
  const xrpBrl = Number(j.ripple && j.ripple.brl);
  if (!(xrpUsd > 0) || !(xrpBrl > 0)) {
    throw new functions.https.HttpsError(
        "unavailable", "Cotação indisponível — tente de novo.");
  }
  return {xrpUsd, xrpBrl, usdBrl: xrpBrl / xrpUsd};
};

// ─── DEPÓSITO: criar ordem PayPal ────────────────────────────────────────────

exports.paypalCreateOrder = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Não autenticado");
  }
  const amountUsd = Math.round(Number(data.amountUsd) * 100) / 100;
  if (!isFinite(amountUsd) || amountUsd < 1 || amountUsd > 10000) {
    throw new functions.https.HttpsError(
        "invalid-argument", "Valor entre US$ 1 e US$ 10.000.");
  }
  const token = await _paypalToken();
  const r = await fetch(`${_paypalBase()}/v2/checkout/orders`, {
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
        "internal", "PayPal não criou a ordem: " + JSON.stringify(order));
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
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Não autenticado");
  }
  const orderId = String(data.orderId || "");
  if (!orderId) {
    throw new functions.https.HttpsError(
        "invalid-argument", "orderId obrigatório");
  }
  const db = admin.firestore();
  const payRef = db.collection("payments").doc(`pp_${orderId}`);
  const payDoc = await payRef.get();
  if (!payDoc.exists || payDoc.data().userId !== context.auth.uid) {
    throw new functions.https.HttpsError("not-found", "Ordem não encontrada");
  }
  if (payDoc.data().status === "completed") {
    return {success: true, alreadyCredited: true};
  }

  const token = await _paypalToken();
  // Tenta capturar; se já foi capturada, consulta o status real.
  let status = null;
  const cap = await fetch(
      `${_paypalBase()}/v2/checkout/orders/${orderId}/capture`, {
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
        `${_paypalBase()}/v2/checkout/orders/${orderId}`, {
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
          "not-found", "Usuário não encontrado");
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
  const xrpEquiv = Math.round((amountBrl / xrpBrl) * 100) / 100;
  return {success: true, amountBrl, xrpEquiv};
});

// ─── SAQUE EM CRIPTO (XRP) — pedido do usuário ───────────────────────────────
// Mesmo modelo do saque Pix: trava o valor, taxa de 10%, admin envia o XRP
// manualmente (da própria carteira/exchange) e marca como pago.

exports.requestCryptoWithdraw =
    functions.https.onCall(async (data, context) => {
      if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated", "Não autenticado");
      }
      const userId = context.auth.uid;
      const amount = Math.round(Number(data.amount) * 100) / 100; // BRL ledger
      const xrpAddress = String(data.xrpAddress || "").trim();
      const xrpTag = String(data.xrpTag || "").trim();

      const minWithdrawal = Number(process.env.MIN_WITHDRAWAL || 100);
      if (!isFinite(amount) || amount < minWithdrawal) {
        throw new functions.https.HttpsError("invalid-argument",
            `Valor mínimo de saque: R$${minWithdrawal} ` +
            "(equivalente em US$).");
      }
      // Validação básica de endereço XRP (classic address).
      if (!/^r[1-9A-HJ-NP-Za-km-z]{24,34}$/.test(xrpAddress)) {
        throw new functions.https.HttpsError(
            "invalid-argument", "Endereço XRP inválido.");
      }
      if (xrpTag && !/^\d{1,10}$/.test(xrpTag)) {
        throw new functions.https.HttpsError(
            "invalid-argument", "Destination tag inválida.");
      }

      const {xrpBrl} = await _rates();
      const fee = Math.round(amount * 0.10 * 100) / 100;
      const netAmount = Math.round((amount - fee) * 100) / 100;
      const xrpEstimate = Math.round((netAmount / xrpBrl) * 10000) / 10000;

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
              "failed-precondition", "Saldo insuficiente");
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
