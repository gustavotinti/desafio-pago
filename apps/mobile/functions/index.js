const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {MercadoPagoConfig, Payment} = require("mercadopago");

admin.initializeApp();

// ─── helpers ─────────────────────────────────────────────────────────────────

function mpPaymentClient() {
  const token = functions.config().mercadopago.access_token;
  return new Payment(new MercadoPagoConfig({accessToken: token}));
}

// ─── CREATE CHALLENGE ────────────────────────────────────────────────────────

exports.createChallenge = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Usuário não logado");
  }

  const userId = context.auth.uid;
  const {title, description, amount, durationDays} = data;

  if (!title || !description || !amount || amount <= 0 ||
      !durationDays || durationDays < 1 || durationDays > 30) {
    throw new functions.https.HttpsError("invalid-argument", "Dados inválidos");
  }

  const db = admin.firestore();
  const adminDoc = await db.collection("admins").doc(userId).get();
  const isAdmin = adminDoc.exists;

  // Daily limit
  const now = new Date();
  const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate()).toISOString();
  const existing = await db.collection("challenges")
      .where("createdBy", "==", userId)
      .where("createdAt", ">=", startOfDay)
      .get();
  if (existing.size >= 20) {
    throw new functions.https.HttpsError("resource-exhausted", "Limite de 20 desafios por dia atingido");
  }

  if (!isAdmin) {
    const userDoc = await db.collection("users").doc(userId).get();
    const balance = userDoc.data()?.balance || 0;
    if (balance < amount) {
      throw new functions.https.HttpsError("failed-precondition", "Saldo insuficiente para criar o desafio");
    }
  }

  const expiresAt = new Date(now.getTime() + durationDays * 24 * 60 * 60 * 1000).toISOString();
  const challengeRef = db.collection("challenges").doc();
  const batch = db.batch();

  batch.set(challengeRef, {
    title,
    description,
    createdBy: userId,
    amount,
    creatorContribution: isAdmin ? 0 : amount,
    status: "active",
    voteCount: 0,
    entryCount: 0,
    winnerIds: [],
    createdAt: now.toISOString(),
    expiresAt,
  });

  if (!isAdmin) {
    const userRef = db.collection("users").doc(userId);
    batch.update(userRef, {
      balance: admin.firestore.FieldValue.increment(-amount),
      pendingBalance: admin.firestore.FieldValue.increment(amount),
    });
    batch.set(db.collection("transactions").doc(), {
      userId,
      amount,
      type: "challenge_created",
      description: `Desafio criado: ${title}`,
      challengeId: challengeRef.id,
      createdAt: now.toISOString(),
    });
  }

  await batch.commit();
  return {challengeId: challengeRef.id};
});

// ─── ADD AMOUNT (APORTE) ─────────────────────────────────────────────────────

exports.addAmount = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Usuário não logado");
  }

  const userId = context.auth.uid;
  const {challengeId, value} = data;

  if (!challengeId || !value || value <= 0) {
    throw new functions.https.HttpsError("invalid-argument", "Dados inválidos");
  }

  const db = admin.firestore();
  const challengeDoc = await db.collection("challenges").doc(challengeId).get();

  if (!challengeDoc.exists) {
    throw new functions.https.HttpsError("not-found", "Desafio não encontrado");
  }

  const challenge = challengeDoc.data();

  if (challenge.status === "finished") {
    throw new functions.https.HttpsError("failed-precondition", "Desafio já encerrado");
  }

  const hoursLeft = (new Date(challenge.expiresAt) - new Date()) / (1000 * 60 * 60);
  if (hoursLeft < 3) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "Não é possível aumentar o valor com menos de 3 horas para o fim do desafio",
    );
  }

  const userDoc = await db.collection("users").doc(userId).get();
  const balance = userDoc.data()?.balance || 0;
  if (balance < value) {
    throw new functions.https.HttpsError("failed-precondition", "Saldo insuficiente");
  }

  const batch = db.batch();
  batch.update(db.collection("challenges").doc(challengeId), {
    amount: admin.firestore.FieldValue.increment(value),
  });
  batch.update(db.collection("users").doc(userId), {
    balance: admin.firestore.FieldValue.increment(-value),
  });
  batch.set(db.collection("transactions").doc(), {
    userId,
    amount: value,
    type: "aporte",
    description: `Aporte: ${challenge.title}`,
    challengeId,
    createdAt: new Date().toISOString(),
  });

  await batch.commit();
  return {success: true};
});

// ─── REQUEST WITHDRAW ────────────────────────────────────────────────────────

exports.requestWithdraw = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Usuário não logado");
  }

  const userId = context.auth.uid;
  const {amount} = data;

  if (!amount || amount < 100) {
    throw new functions.https.HttpsError("invalid-argument", "Valor mínimo para saque é R$100");
  }

  const db = admin.firestore();
  const userDoc = await db.collection("users").doc(userId).get();
  const userData = userDoc.data() || {};
  const balance = userData.balance || 0;
  const pixKey = userData.pixKey || "";

  if (!pixKey) {
    throw new functions.https.HttpsError("failed-precondition", "Cadastre uma chave Pix primeiro");
  }
  if (balance < amount) {
    throw new functions.https.HttpsError("failed-precondition", "Saldo insuficiente");
  }

  const fee = Math.round(amount * 0.10 * 100) / 100;
  const netAmount = Math.round((amount - fee) * 100) / 100;
  const withdrawalRef = db.collection("withdrawals").doc();
  const batch = db.batch();

  batch.set(withdrawalRef, {
    userId,
    amount,
    fee,
    netAmount,
    pixKey,
    status: "pending",
    createdAt: new Date().toISOString(),
  });
  batch.update(db.collection("users").doc(userId), {
    balance: admin.firestore.FieldValue.increment(-amount),
    lockedBalance: admin.firestore.FieldValue.increment(amount),
  });
  batch.set(db.collection("transactions").doc(), {
    userId,
    amount,
    type: "withdraw",
    description: `Saque solicitado — taxa R$${fee.toFixed(2)} (10%)`,
    createdAt: new Date().toISOString(),
  });

  await batch.commit();
  return {withdrawalId: withdrawalRef.id};
});

// ─── SUBMIT ENTRY ────────────────────────────────────────────────────────────

exports.submitEntry = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Usuário não logado");
  }

  const userId = context.auth.uid;
  const {challengeId, contentType, contentText, contentUrl} = data;

  if (!challengeId || !contentType) {
    throw new functions.https.HttpsError(
        "invalid-argument", "challengeId e contentType são obrigatórios",
    );
  }

  const db = admin.firestore();
  const challengeDoc = await db.collection("challenges").doc(challengeId).get();

  if (!challengeDoc.exists) {
    throw new functions.https.HttpsError("not-found", "Desafio não encontrado");
  }

  const challenge = challengeDoc.data();

  if (challenge.createdBy === userId) {
    throw new functions.https.HttpsError(
        "permission-denied", "Você não pode participar do próprio desafio",
    );
  }

  if (challenge.status !== "active") {
    throw new functions.https.HttpsError("failed-precondition", "Desafio não está ativo");
  }

  const existing = await db.collection("entries")
      .where("challengeId", "==", challengeId)
      .where("userId", "==", userId)
      .get();

  if (!existing.empty) {
    throw new functions.https.HttpsError("already-exists", "Você já participou deste desafio");
  }

  const entryRef = db.collection("entries").doc();
  const challengeRef = db.collection("challenges").doc(challengeId);

  await db.runTransaction(async (tx) => {
    tx.set(entryRef, {
      challengeId,
      userId,
      contentType,
      contentText: contentText || null,
      contentUrl: contentUrl || null,
      voteCount: 0,
      isActive: true,
      createdAt: new Date().toISOString(),
    });
    tx.update(challengeRef, {entryCount: admin.firestore.FieldValue.increment(1)});
  });

  return {entryId: entryRef.id};
});

// ─── VOTE (updated: entry-level) ─────────────────────────────────────────────

exports.vote = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Usuário não logado");
  }

  const userId = context.auth.uid;
  const {challengeId, entryId} = data;

  if (!challengeId || !entryId) {
    throw new functions.https.HttpsError(
        "invalid-argument", "challengeId e entryId são obrigatórios",
    );
  }

  const db = admin.firestore();
  const challengeDoc = await db.collection("challenges").doc(challengeId).get();

  if (!challengeDoc.exists) {
    throw new functions.https.HttpsError("not-found", "Desafio não encontrado");
  }

  const challenge = challengeDoc.data();

  if (challenge.createdBy === userId) {
    throw new functions.https.HttpsError(
        "permission-denied", "Você não pode votar no próprio desafio",
    );
  }

  if (challenge.status !== "active") {
    throw new functions.https.HttpsError("failed-precondition", "Desafio não está ativo");
  }

  const voteId = `${userId}_${challengeId}`;
  const voteRef = db.collection("votes").doc(voteId);

  if ((await voteRef.get()).exists) {
    throw new functions.https.HttpsError("already-exists", "Você já votou neste desafio");
  }

  const entryRef = db.collection("entries").doc(entryId);
  const challengeRef = db.collection("challenges").doc(challengeId);
  const entryDoc = await entryRef.get();
  const entryOwnerRef = db.collection("users").doc(entryDoc.data().userId);

  await db.runTransaction(async (tx) => {
    tx.set(voteRef, {
      userId, challengeId, entryId,
      createdAt: new Date().toISOString(),
    });
    tx.update(entryRef, {voteCount: admin.firestore.FieldValue.increment(1)});
    tx.update(challengeRef, {voteCount: admin.firestore.FieldValue.increment(1)});
    tx.update(entryOwnerRef, {totalVotesReceived: admin.firestore.FieldValue.increment(1)});
  });

  return {success: true};
});

// ─── FINALIZE CHALLENGES ─────────────────────────────────────────────────────

exports.finalizeChallenges = functions.pubsub
    .schedule("every 5 minutes")
    .onRun(async () => {
      const db = admin.firestore();
      const now = new Date().toISOString();

      const snapshot = await db
          .collection("challenges")
          .where("status", "==", "active")
          .where("expiresAt", "<=", now)
          .get();

      if (snapshot.empty) return null;
      await Promise.all(snapshot.docs.map((doc) => finalizeChallenge(db, doc)));
      return null;
    });

async function finalizeChallenge(db, challengeDoc) {
  const challengeId = challengeDoc.id;
  const challenge = challengeDoc.data();
  const prizeAmount = challenge.amount || 0;
  const creatorContribution = challenge.creatorContribution || 0;

  const entriesSnapshot = await db
      .collection("entries")
      .where("challengeId", "==", challengeId)
      .where("isActive", "==", true)
      .orderBy("voteCount", "desc")
      .get();

  const challengeRef = db.collection("challenges").doc(challengeId);
  const batch = db.batch();

  const markFinished = (winnerIds = []) => batch.update(challengeRef, {
    status: "finished",
    winnerIds,
    finishedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // Always release creator's pendingBalance when challenge ends
  if (creatorContribution > 0) {
    batch.update(db.collection("users").doc(challenge.createdBy), {
      pendingBalance: admin.firestore.FieldValue.increment(-creatorContribution),
    });
  }

  if (entriesSnapshot.empty) {
    markFinished();
    return batch.commit();
  }

  const entries = entriesSnapshot.docs.map((d) => ({id: d.id, ...d.data()}));
  const maxVotes = entries[0].voteCount;

  if (maxVotes === 0) {
    markFinished();
    return batch.commit();
  }

  const winners = entries.filter((e) => e.voteCount === maxVotes);
  const winnerIds = winners.map((e) => e.userId);
  const prizeCents = Math.round(prizeAmount * 100);
  const perWinnerCents = Math.floor(prizeCents / winnerIds.length);
  const prizePerWinner = perWinnerCents / 100;

  markFinished(winnerIds);

  for (const winner of winners) {
    const userRef = db.collection("users").doc(winner.userId);
    batch.update(userRef, {
      balance: admin.firestore.FieldValue.increment(prizePerWinner),
      totalEarned: admin.firestore.FieldValue.increment(prizePerWinner),
    });
    batch.set(db.collection("transactions").doc(), {
      userId: winner.userId,
      amount: prizePerWinner,
      type: "reward",
      description: `Prêmio: ${challenge.title}`,
      challengeId,
      createdAt: new Date().toISOString(),
    });
  }

  return batch.commit();
}

// ─── CREATE PIX PAYMENT ──────────────────────────────────────────────────────
// Deploy config: firebase functions:config:set mercadopago.access_token="APP_USR-..."
// Webhook URL:   https://{region}-desafio-app-b8665.cloudfunctions.net/mercadoPagoWebhook

exports.createPixPayment = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Usuário não logado");
  }

  const {amount} = data;
  const userId = context.auth.uid;

  if (!amount || amount < 1) {
    throw new functions.https.HttpsError("invalid-argument", "Valor mínimo R$1,00");
  }

  const db = admin.firestore();
  const userDoc = await db.collection("users").doc(userId).get();
  const userEmail = userDoc.data()?.email || "payer@desafiopago.com";

  const client = mpPaymentClient();
  const mp = await client.create({
    body: {
      transaction_amount: Number(amount),
      description: "Recarga de créditos — Desafio Pago",
      payment_method_id: "pix",
      payer: {email: userEmail},
    },
  });

  const expiresAt = new Date(Date.now() + 30 * 60 * 1000).toISOString();

  await db.collection("payments").doc(String(mp.id)).set({
    userId,
    amount: Number(amount),
    mpPaymentId: mp.id,
    status: "pending",
    qrCode: mp.point_of_interaction.transaction_data.qr_code,
    qrCodeBase64: mp.point_of_interaction.transaction_data.qr_code_base64,
    expiresAt,
    createdAt: new Date().toISOString(),
  });

  return {
    paymentId: String(mp.id),
    qrCode: mp.point_of_interaction.transaction_data.qr_code,
    qrCodeBase64: mp.point_of_interaction.transaction_data.qr_code_base64,
    expiresAt,
  };
});

// ─── MERCADO PAGO WEBHOOK ────────────────────────────────────────────────────

exports.mercadoPagoWebhook = functions.https.onRequest(async (req, res) => {
  if (req.method !== "POST" || req.body.type !== "payment") {
    res.sendStatus(200);
    return;
  }

  const paymentId = String(req.body.data?.id);
  if (!paymentId) {
    res.sendStatus(400);
    return;
  }

  const db = admin.firestore();
  const paymentRef = db.collection("payments").doc(paymentId);
  const paymentDoc = await paymentRef.get();

  if (!paymentDoc.exists) {
    res.sendStatus(200);
    return;
  }

  const paymentData = paymentDoc.data();

  // Idempotency guard
  if (paymentData.status === "approved") {
    res.sendStatus(200);
    return;
  }

  // Query Mercado Pago for current status
  const mp = await mpPaymentClient().get({id: paymentId});

  if (mp.status !== "approved") {
    await paymentRef.update({status: mp.status});
    res.sendStatus(200);
    return;
  }

  // Credit user balance atomically
  const batch = db.batch();

  batch.update(paymentRef, {
    status: "approved",
    approvedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  batch.update(db.collection("users").doc(paymentData.userId), {
    balance: admin.firestore.FieldValue.increment(paymentData.amount),
  });

  batch.set(db.collection("transactions").doc(), {
    userId: paymentData.userId,
    amount: paymentData.amount,
    type: "deposit",
    description: "Recarga via Pix",
    createdAt: new Date().toISOString(),
  });

  await batch.commit();
  res.sendStatus(200);
});

// ─── ADMIN: FORCE FINISH CHALLENGE ──────────────────────────────────────────

exports.adminFinishChallenge = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Usuário não logado");
  }

  const db = admin.firestore();
  const adminDoc = await db.collection("admins").doc(context.auth.uid).get();
  if (!adminDoc.exists) {
    throw new functions.https.HttpsError("permission-denied", "Acesso negado");
  }

  const {challengeId} = data;
  if (!challengeId) {
    throw new functions.https.HttpsError("invalid-argument", "challengeId obrigatório");
  }

  const challengeDoc = await db.collection("challenges").doc(challengeId).get();
  if (!challengeDoc.exists) {
    throw new functions.https.HttpsError("not-found", "Desafio não encontrado");
  }
  if (challengeDoc.data().status === "finished") {
    throw new functions.https.HttpsError("failed-precondition", "Desafio já encerrado");
  }

  await finalizeChallenge(db, challengeDoc);
  return {success: true};
});

// ─── CHECK PAYMENT STATUS ────────────────────────────────────────────────────

exports.checkPaymentStatus = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Usuário não logado");
  }

  const {paymentId} = data;
  const db = admin.firestore();
  const doc = await db.collection("payments").doc(String(paymentId)).get();

  if (!doc.exists) {
    throw new functions.https.HttpsError("not-found", "Pagamento não encontrado");
  }
  if (doc.data().userId !== context.auth.uid) {
    throw new functions.https.HttpsError("permission-denied", "Acesso negado");
  }

  return {status: doc.data().status};
});
