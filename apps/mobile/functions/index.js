const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {MercadoPagoConfig, Payment} = require("mercadopago");

admin.initializeApp();

// ─── helpers ─────────────────────────────────────────────────────────────────

function mpPaymentClient() {
  const token = process.env.MERCADOPAGO_ACCESS_TOKEN;
  return new Payment(new MercadoPagoConfig({accessToken: token}));
}

async function _assertNotBanned(db, userId) {
  const doc = await db.collection("users").doc(userId).get();
  if (doc.data()?.isBanned === true) {
    throw new functions.https.HttpsError("permission-denied", "Sua conta está suspensa");
  }
}

async function _sendNotification(db, userId, title, body, data = {}) {
  try {
    const userDoc = await db.collection("users").doc(userId).get();
    const token = userDoc.data()?.fcmToken;
    if (!token) return;
    await admin.messaging().send({
      token,
      notification: {title, body},
      data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
      android: {priority: "high"},
      apns: {payload: {aps: {sound: "default"}}},
    });
  } catch (err) {
    console.error("Erro ao enviar notificação:", err.message);
  }
}

async function _maybeScheduleInstagramPost(db, challengeId, oldAmount, newAmount) {
  const threshold = Number(process.env.INSTAGRAM_THRESHOLD || 100);
  if (oldAmount < threshold && newAmount >= threshold) {
    const postRef = db.collection("instagram_posts").doc(challengeId);
    const existing = await postRef.get();
    if (!existing.exists) {
      await postRef.set({
        challengeId,
        status: "pending",
        retryCount: 0,
        createdAt: new Date().toISOString(),
      });
    }
  }
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

  if (!isAdmin) {
    await _maybeScheduleInstagramPost(db, challengeRef.id, 0, amount);
  }

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
  await _maybeScheduleInstagramPost(db, challengeId, challenge.amount, challenge.amount + value);
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
  const db = admin.firestore();
  await _assertNotBanned(db, userId);

  const {challengeId, contentType, contentText, contentUrl} = data;

  if (!challengeId || !contentType) {
    throw new functions.https.HttpsError(
        "invalid-argument", "challengeId e contentType são obrigatórios",
    );
  }

  // ── Validação de conteúdo ─────────────────────────────────────────────────
  if (contentType === "text") {
    if (!contentText || contentText.trim().length === 0) {
      throw new functions.https.HttpsError("invalid-argument", "Conteúdo de texto é obrigatório");
    }
    if (contentText.length > 5000) {
      throw new functions.https.HttpsError(
          "invalid-argument",
          `Texto muito longo: ${contentText.length} caracteres (máximo 5000)`,
      );
    }
  } else {
    if (!contentUrl) {
      throw new functions.https.HttpsError("invalid-argument", "URL do arquivo é obrigatória");
    }
  }

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
  await _assertNotBanned(db, userId);
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

  const entryOwnerId = entryDoc.data().userId;
  if (entryOwnerId !== userId) {
    await _sendNotification(
        db, entryOwnerId,
        "🗳️ Novo voto!",
        `Alguém votou na sua entrada em "${challenge.title}"`,
        {type: "vote", challengeId, entryId},
    );
  }

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
    await batch.commit();
    return;
  }

  const entries = entriesSnapshot.docs.map((d) => ({id: d.id, ...d.data()}));
  const maxVotes = entries[0].voteCount;

  if (maxVotes === 0) {
    markFinished();
    await batch.commit();
    return;
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

  await batch.commit();

  await Promise.all(winners.map((w) => _sendNotification(
      db, w.userId,
      "🏆 Você ganhou!",
      `Você venceu "${challenge.title}" e recebeu R$${prizePerWinner.toFixed(2)}!`,
      {type: "win", challengeId},
  )));
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

  await _sendNotification(
      db, paymentData.userId,
      "💰 Recarga confirmada!",
      `R$${paymentData.amount.toFixed(2)} adicionados aos seus créditos.`,
      {type: "deposit"},
  );

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

// ─── FASE 16: INSTAGRAM AUTOMATION ──────────────────────────────────────────
// Deploy config:
//   firebase functions:config:set instagram.access_token="EAA..."
//   firebase functions:config:set instagram.page_id="123456"
//   firebase functions:config:set instagram.threshold="100"

exports.processInstagramPosts = functions.pubsub
    .schedule("every 10 minutes")
    .onRun(async () => {
      const db = admin.firestore();
      const accessToken = process.env.INSTAGRAM_ACCESS_TOKEN;
      const pageId = process.env.INSTAGRAM_PAGE_ID;

      if (!accessToken || !pageId) {
        console.log("Instagram não configurado — pulando");
        return null;
      }

      const snapshot = await db.collection("instagram_posts")
          .where("status", "in", ["pending", "failed"])
          .get();

      if (snapshot.empty) return null;

      const eligible = snapshot.docs.filter((d) => (d.data().retryCount || 0) < 3);
      await Promise.all(eligible.map((d) => _postToInstagram(db, d, pageId, accessToken)));
      return null;
    });

async function _postToInstagram(db, postDoc, pageId, accessToken) {
  const postData = postDoc.data();
  const challengeDoc = await db.collection("challenges").doc(postData.challengeId).get();

  if (!challengeDoc.exists) {
    await postDoc.ref.update({status: "failed", error: "desafio não encontrado"});
    return;
  }

  const challenge = challengeDoc.data();
  const message =
    `🏆 ${challenge.title}\n` +
    `💰 Prêmio: R$ ${challenge.amount.toFixed(2)}\n` +
    `Participe agora no Desafio Pago!`;

  try {
    const response = await fetch(
        `https://graph.facebook.com/v18.0/${pageId}/feed`,
        {
          method: "POST",
          headers: {"Content-Type": "application/json"},
          body: JSON.stringify({message, access_token: accessToken}),
        },
    );
    const result = await response.json();

    if (result.id) {
      await postDoc.ref.update({
        status: "posted",
        postId: result.id,
        postedAt: new Date().toISOString(),
      });
    } else {
      throw new Error(result.error?.message || "Erro desconhecido");
    }
  } catch (err) {
    const retryCount = (postData.retryCount || 0) + 1;
    await postDoc.ref.update({
      status: retryCount >= 3 ? "failed" : "pending",
      retryCount,
      error: err.message,
      lastAttemptAt: new Date().toISOString(),
    });
  }
}

// ─── FASE 17: MODERAÇÃO COM IA ───────────────────────────────────────────────
// Deploy config:
//   firebase functions:config:set openai.api_key="sk-..."

exports.moderateEntry = functions.firestore
    .document("entries/{entryId}")
    .onCreate(async (snap, context) => {
      const entry = snap.data();
      if (!entry.contentText) return null;

      const apiKey = process.env.OPENAI_API_KEY;
      if (!apiKey) return null;

      try {
        const response = await fetch("https://api.openai.com/v1/moderations", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Authorization": `Bearer ${apiKey}`,
          },
          body: JSON.stringify({input: entry.contentText}),
        });

        const result = await response.json();
        const flagged = result.results?.[0]?.flagged === true;

        if (flagged) {
          const cats = result.results[0].categories || {};
          const flaggedCats = Object.keys(cats).filter((k) => cats[k]).join(", ");

          const db = admin.firestore();
          await snap.ref.update({isActive: false});
          await db.collection("audit_logs").add({
            type: "auto_moderation",
            entryId: context.params.entryId,
            userId: entry.userId,
            challengeId: entry.challengeId,
            reason: `IA sinalizou: ${flaggedCats}`,
            createdAt: new Date().toISOString(),
          });
        }
      } catch (err) {
        console.error("Erro na moderação:", err);
      }

      return null;
    });

exports.reportContent = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Usuário não logado");
  }

  const {entryId, reason} = data;
  if (!entryId || !reason) {
    throw new functions.https.HttpsError("invalid-argument", "entryId e reason são obrigatórios");
  }

  const db = admin.firestore();
  const entryDoc = await db.collection("entries").doc(entryId).get();
  if (!entryDoc.exists) {
    throw new functions.https.HttpsError("not-found", "Entrada não encontrada");
  }

  const alreadyReported = await db.collection("reports")
      .where("entryId", "==", entryId)
      .where("reporterId", "==", context.auth.uid)
      .limit(1)
      .get();

  if (!alreadyReported.empty) {
    throw new functions.https.HttpsError("already-exists", "Você já denunciou esta entrada");
  }

  const entry = entryDoc.data();
  await db.collection("reports").add({
    entryId,
    challengeId: entry.challengeId,
    reportedUserId: entry.userId,
    reporterId: context.auth.uid,
    reason,
    status: "pending",
    createdAt: new Date().toISOString(),
  });

  // Auto-ocultar após 5 denúncias pendentes
  const reportCount = await db.collection("reports")
      .where("entryId", "==", entryId)
      .where("status", "==", "pending")
      .get();

  if (reportCount.size >= 5) {
    await db.collection("entries").doc(entryId).update({isActive: false});
    await db.collection("audit_logs").add({
      type: "auto_hidden",
      entryId,
      userId: entry.userId,
      reason: `${reportCount.size} denúncias recebidas`,
      createdAt: new Date().toISOString(),
    });
  }

  return {success: true};
});

exports.adminBanUser = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Usuário não logado");
  }

  const db = admin.firestore();
  const adminDoc = await db.collection("admins").doc(context.auth.uid).get();
  if (!adminDoc.exists) {
    throw new functions.https.HttpsError("permission-denied", "Acesso negado");
  }

  const {userId, reason, unban} = data;
  if (!userId) {
    throw new functions.https.HttpsError("invalid-argument", "userId obrigatório");
  }

  const update = unban ?
    {isBanned: false, banReason: null, bannedAt: null} :
    {
      isBanned: true,
      banReason: reason || "Violação dos termos de uso",
      bannedAt: new Date().toISOString(),
    };

  await db.collection("users").doc(userId).update(update);
  await db.collection("audit_logs").add({
    type: unban ? "user_unbanned" : "user_banned",
    targetUserId: userId,
    adminId: context.auth.uid,
    reason: reason || null,
    createdAt: new Date().toISOString(),
  });

  return {success: true};
});

// ─── ACCEPT TERMS ────────────────────────────────────────────────────────────
// Uses Admin SDK so it bypasses Firestore rules — works even if the user
// document doesn't exist yet (race between saveUser and auth-state change).

exports.acceptTerms = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Usuário não logado");
  }

  const uid = context.auth.uid;
  const db = admin.firestore();
  const userRef = db.collection("users").doc(uid);
  const existing = await userRef.get();

  if (existing.exists) {
    await userRef.update({termsAccepted: true});
  } else {
    // Fallback: document was never created (saveUser failed or race condition)
    const token = context.auth.token;
    await userRef.set({
      name: token.name || "",
      email: token.email || "",
      photoUrl: token.picture || "",
      termsAccepted: true,
      createdAt: new Date().toISOString(),
      balance: 0,
      pendingBalance: 0,
      lockedBalance: 0,
      totalEarned: 0,
      totalVotesReceived: 0,
      followersCount: 0,
      followingCount: 0,
      bio: "",
      pixKey: "",
    });
  }

  return {success: true};
});

// ─── BOOTSTRAP ADMIN ─────────────────────────────────────────────────────────

exports.bootstrapAdmin = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Usuário não logado");
  }

  const SUPER_ADMIN_EMAIL = "gustavo.a.tinti3@gmail.com";
  if (context.auth.token.email !== SUPER_ADMIN_EMAIL) {
    throw new functions.https.HttpsError("permission-denied", "Acesso negado");
  }

  const db = admin.firestore();
  const adminRef = db.collection("admins").doc(context.auth.uid);
  const existing = await adminRef.get();
  if (!existing.exists) {
    await adminRef.set({
      email: SUPER_ADMIN_EMAIL,
      createdAt: new Date().toISOString(),
    });
  }
  return {success: true};
});

// ─── ADD COMMENT ─────────────────────────────────────────────────────────────

exports.addComment = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Usuário não logado");
  }

  const userId = context.auth.uid;
  const db = admin.firestore();
  await _assertNotBanned(db, userId);

  const {challengeId, text} = data;
  const entryId = data.entryId || "";

  if (!challengeId || !text || text.trim().length === 0) {
    throw new functions.https.HttpsError(
        "invalid-argument", "challengeId e text são obrigatórios",
    );
  }
  if (text.trim().length > 500) {
    throw new functions.https.HttpsError(
        "invalid-argument", "Comentário muito longo (máx 500 caracteres)",
    );
  }

  const userDoc = await db.collection("users").doc(userId).get();
  const userName = userDoc.data()?.name || "Usuário";

  await db.collection("comments").add({
    challengeId,
    entryId,
    userId,
    userName,
    text: text.trim(),
    isActive: true,
    createdAt: new Date().toISOString(),
  });

  return {success: true};
});

// ─── ADMIN: MODIFY VOTE COUNT ────────────────────────────────────────────────

exports.adminModifyVoteCount = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Usuário não logado");
  }

  const db = admin.firestore();
  const adminDoc = await db.collection("admins").doc(context.auth.uid).get();
  if (!adminDoc.exists) {
    throw new functions.https.HttpsError("permission-denied", "Acesso negado");
  }

  const {entryId, voteCount} = data;
  if (!entryId || voteCount === undefined || voteCount < 0) {
    throw new functions.https.HttpsError(
        "invalid-argument", "entryId e voteCount obrigatórios",
    );
  }

  const entryRef = db.collection("entries").doc(entryId);
  const entryDoc = await entryRef.get();
  if (!entryDoc.exists) {
    throw new functions.https.HttpsError("not-found", "Entrada não encontrada");
  }

  const oldVoteCount = entryDoc.data().voteCount || 0;
  const diff = voteCount - oldVoteCount;
  const challengeId = entryDoc.data().challengeId;

  const batch = db.batch();
  batch.update(entryRef, {voteCount});
  if (diff !== 0) {
    batch.update(db.collection("challenges").doc(challengeId), {
      voteCount: admin.firestore.FieldValue.increment(diff),
    });
  }
  await batch.commit();

  await db.collection("audit_logs").add({
    type: "admin_vote_edit",
    entryId,
    challengeId,
    adminId: context.auth.uid,
    oldVoteCount,
    newVoteCount: voteCount,
    createdAt: new Date().toISOString(),
  });

  return {success: true};
});

// ─── ADMIN: GENERATE COMMENT ─────────────────────────────────────────────────

exports.adminGenerateComment = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Usuário não logado");
  }

  const db = admin.firestore();
  const adminDoc = await db.collection("admins").doc(context.auth.uid).get();
  if (!adminDoc.exists) {
    throw new functions.https.HttpsError("permission-denied", "Acesso negado");
  }

  const {challengeId, text} = data;
  const entryId = data.entryId || "";

  if (!challengeId || !text || text.trim().length === 0) {
    throw new functions.https.HttpsError(
        "invalid-argument", "challengeId e text obrigatórios",
    );
  }

  const userDoc = await db.collection("users").doc(context.auth.uid).get();
  const userName = userDoc.data()?.name || "Admin";

  await db.collection("comments").add({
    challengeId,
    entryId,
    userId: context.auth.uid,
    userName,
    text: text.trim(),
    isActive: true,
    isAdminGenerated: true,
    createdAt: new Date().toISOString(),
  });

  return {success: true};
});

// ─── ADMIN: MARK WITHDRAWAL PAID ─────────────────────────────────────────────

exports.adminMarkWithdrawalPaid = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Usuário não logado");
  }

  const db = admin.firestore();
  const adminDoc = await db.collection("admins").doc(context.auth.uid).get();
  if (!adminDoc.exists) {
    throw new functions.https.HttpsError("permission-denied", "Acesso negado");
  }

  const {withdrawalId} = data;
  if (!withdrawalId) {
    throw new functions.https.HttpsError("invalid-argument", "withdrawalId obrigatório");
  }

  const withdrawalRef = db.collection("withdrawals").doc(withdrawalId);
  const withdrawalDoc = await withdrawalRef.get();
  if (!withdrawalDoc.exists) {
    throw new functions.https.HttpsError("not-found", "Saque não encontrado");
  }
  if (withdrawalDoc.data().status !== "approved") {
    throw new functions.https.HttpsError(
        "failed-precondition", "Saque não está com status aprovado",
    );
  }

  await withdrawalRef.update({
    status: "paid",
    paidAt: new Date().toISOString(),
    paidBy: context.auth.uid,
  });

  return {success: true};
});

// ─── ADMIN: MIGRATE USERS ────────────────────────────────────────────────────
// Backfills missing Firestore docs / fields for every Firebase Auth account.
// Safe to run multiple times — never overwrites existing financial balances.

exports.adminMigrateUsers = functions
    .runWith({timeoutSeconds: 300, memory: "256MB"})
    .https.onCall(async (data, context) => {
      if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Usuário não logado");
      }
      const db = admin.firestore();
      const adminDoc = await db.collection("admins").doc(context.auth.uid).get();
      if (!adminDoc.exists) {
        throw new functions.https.HttpsError("permission-denied", "Acesso negado");
      }

      const defaultFields = {
        name: "", email: "", photoUrl: "", bio: "", pixKey: "",
        termsAccepted: false,
        balance: 0, pendingBalance: 0, lockedBalance: 0,
        totalEarned: 0, totalVotesReceived: 0,
        followersCount: 0, followingCount: 0,
      };

      let migrated = 0;
      let pageToken;

      do {
        const list = await admin.auth().listUsers(1000, pageToken);

        for (const userRecord of list.users) {
          const uid = userRecord.uid;
          const userRef = db.collection("users").doc(uid);
          const existing = await userRef.get();

          if (!existing.exists) {
            // Doc never created — bootstrap it from Auth profile
            await userRef.set({
              ...defaultFields,
              name: userRecord.displayName || "",
              email: userRecord.email || "",
              photoUrl: userRecord.photoURL || "",
              createdAt: userRecord.metadata.creationTime || new Date().toISOString(),
            });
            migrated++;
          } else {
            // Fill any missing fields without touching existing values
            const d = existing.data();
            const updates = {};
            for (const [key, val] of Object.entries(defaultFields)) {
              if (d[key] === undefined || d[key] === null) {
                updates[key] = val;
              }
            }
            if (!d.createdAt) {
              updates.createdAt =
                userRecord.metadata.creationTime || new Date().toISOString();
            }
            if (Object.keys(updates).length > 0) {
              await userRef.update(updates);
              migrated++;
            }
          }
        }

        pageToken = list.pageToken;
      } while (pageToken);

      return {migrated};
    });

// ─── DELETE ACCOUNT ──────────────────────────────────────────────────────────

exports.deleteAccount = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Usuário não logado");
  }

  const userId = context.auth.uid;
  const db = admin.firestore();
  const userDoc = await db.collection("users").doc(userId).get();
  const userData = userDoc.data() || {};

  if ((userData.pendingBalance || 0) > 0) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "Você tem créditos em desafios ativos. Aguarde o encerramento antes de excluir a conta.",
    );
  }
  if ((userData.lockedBalance || 0) > 0) {
    throw new functions.https.HttpsError(
        "failed-precondition",
        "Você tem um saque pendente. Aguarde a conclusão antes de excluir a conta.",
    );
  }

  // Anonymiza entries para preservar integridade dos desafios
  const entries = await db.collection("entries").where("userId", "==", userId).get();
  const batch = db.batch();
  entries.docs.forEach((d) => batch.update(d.ref, {userId: "deleted", contentText: "[removido]"}));

  // Remove follows
  const following = await db.collection("follows").where("followerId", "==", userId).get();
  const followers = await db.collection("follows").where("followedId", "==", userId).get();
  following.docs.forEach((d) => batch.delete(d.ref));
  followers.docs.forEach((d) => batch.delete(d.ref));

  // Deleta documento do usuário
  batch.delete(db.collection("users").doc(userId));
  await batch.commit();

  // Deleta conta no Firebase Auth
  await admin.auth().deleteUser(userId);

  return {success: true};
});
