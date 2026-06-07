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
  const db = admin.firestore();
  console.log("createChallenge: invoked by userId:", userId, "data:", JSON.stringify(data));

  try {
    const {title, description, amount, durationDays} = data;

    if (!title || !description || !amount || amount <= 0 ||
        !durationDays || durationDays < 1 || durationDays > 30) {
      throw new functions.https.HttpsError("invalid-argument", "Dados inválidos");
    }

    const adminDoc = await db.collection("admins").doc(userId).get();
    const isAdmin = adminDoc.exists;

    // Daily limit
    const now = new Date();
    const startOfDay = new Date(
        now.getFullYear(), now.getMonth(), now.getDate(),
    ).toISOString();
    const existing = await db.collection("challenges")
        .where("createdBy", "==", userId)
        .where("createdAt", ">=", startOfDay)
        .get();
    if (existing.size >= 20) {
      throw new functions.https.HttpsError(
          "resource-exhausted", "Limite de 20 desafios por dia atingido",
      );
    }

    // Balance check (non-admin only)
    if (!isAdmin) {
      const userDoc = await db.collection("users").doc(userId).get();
      if (!userDoc.exists) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "Perfil de usuário não encontrado. Faça login novamente.",
        );
      }
      const balance = userDoc.data().balance ?? 0;
      if (balance < amount) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            `Saldo insuficiente. Saldo: R$${Number(balance).toFixed(2)}, necessário: R$${Number(amount).toFixed(2)}.`,
        );
      }
    }

    const expiresAt = new Date(
        now.getTime() + durationDays * 24 * 60 * 60 * 1000,
    ).toISOString();
    const challengeRef = db.collection("challenges").doc();
    const batch = db.batch();

    batch.set(challengeRef, {
      title,
      description,
      createdBy: userId,
      amount: Number(amount),
      creatorContribution: isAdmin ? 0 : Number(amount),
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
        balance: admin.firestore.FieldValue.increment(-Number(amount)),
        pendingBalance: admin.firestore.FieldValue.increment(Number(amount)),
      });
      batch.set(db.collection("transactions").doc(), {
        userId,
        amount: Number(amount),
        type: "challenge_created",
        description: `Desafio criado: ${title}`,
        challengeId: challengeRef.id,
        createdAt: now.toISOString(),
      });
    }

    await batch.commit();

    if (!isAdmin) {
      try {
        await _maybeScheduleInstagramPost(db, challengeRef.id, 0, Number(amount));
      } catch (igErr) {
        // Instagram scheduling is non-critical — log but don't fail the request
        console.error("Instagram scheduling failed (non-fatal):", igErr);
      }
    }

    return {challengeId: challengeRef.id};
  } catch (err) {
    if (err instanceof functions.https.HttpsError) throw err;
    console.error("createChallenge unhandled error:", err);
    throw new functions.https.HttpsError(
        "internal",
        `Erro interno: ${err.message || String(err)}`,
    );
  }
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

  // Admin bypass: admins can vote on any challenge (including own) multiple times
  const adminDoc = await db.collection("admins").doc(userId).get();
  const isAdmin = adminDoc.exists;

  const challengeDoc = await db.collection("challenges").doc(challengeId).get();

  if (!challengeDoc.exists) {
    throw new functions.https.HttpsError("not-found", "Desafio não encontrado");
  }

  const challenge = challengeDoc.data();

  // Creator restriction — admins bypass this for demo purposes
  if (!isAdmin && challenge.createdBy === userId) {
    throw new functions.https.HttpsError(
        "permission-denied", "Você não pode votar no próprio desafio",
    );
  }

  if (challenge.status !== "active") {
    throw new functions.https.HttpsError("failed-precondition", "Desafio não está ativo");
  }

  // Admin gets a unique vote ID per vote so they can cast multiple demo votes
  const voteId = isAdmin ?
    `admin_${userId}_${entryId}_${Date.now()}` :
    `${userId}_${challengeId}`;

  if (!isAdmin) {
    const existingVote = await db.collection("votes").doc(voteId).get();
    if (existingVote.exists) {
      throw new functions.https.HttpsError("already-exists", "Você já votou neste desafio");
    }
  }

  const voteRef = db.collection("votes").doc(voteId);
  const entryRef = db.collection("entries").doc(entryId);
  const challengeRef = db.collection("challenges").doc(challengeId);
  const entryDoc = await entryRef.get();

  await db.runTransaction(async (tx) => {
    tx.set(voteRef, {
      userId, challengeId, entryId,
      ...(isAdmin ? {isAdminVote: true} : {}),
      createdAt: new Date().toISOString(),
    });
    tx.update(entryRef, {voteCount: admin.firestore.FieldValue.increment(1)});
    tx.update(challengeRef, {voteCount: admin.firestore.FieldValue.increment(1)});
    if (!isAdmin) {
      const entryOwnerRef = db.collection("users").doc(entryDoc.data().userId);
      tx.update(entryOwnerRef, {totalVotesReceived: admin.firestore.FieldValue.increment(1)});
    }
  });

  if (!isAdmin) {
    const entryOwnerId = entryDoc.data().userId;
    if (entryOwnerId !== userId) {
      await _sendNotification(
          db, entryOwnerId,
          "🗳️ Novo voto!",
          `Alguém votou na sua entrada em "${challenge.title}"`,
          {type: "vote", challengeId, entryId},
      );
    }
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

  const {amount, purpose = "deposit"} = data;
  const userId = context.auth.uid;

  const db = admin.firestore();

  let txAmount;
  let description;
  if (purpose === "verification_priority") {
    // Fila prioritária de verificação: valor fixo, exige pedido pendente.
    const reqDoc =
        await db.collection("verificationRequests").doc(userId).get();
    if (!reqDoc.exists || reqDoc.data().status !== "pending") {
      throw new functions.https.HttpsError(
          "failed-precondition", "Envie o pedido de verificação primeiro");
    }
    if (reqDoc.data().priority === true) {
      throw new functions.https.HttpsError(
          "failed-precondition", "Você já está na fila prioritária");
    }
    txAmount = 500;
    description = "Fila prioritária de verificação — Desafio Pago";
  } else {
    if (!amount || amount < 1) {
      throw new functions.https.HttpsError(
          "invalid-argument", "Valor mínimo R$1,00");
    }
    txAmount = Number(amount);
    description = "Recarga de créditos — Desafio Pago";
  }

  const userDoc = await db.collection("users").doc(userId).get();
  const userEmail = userDoc.data()?.email || "payer@desafiopago.com";

  const client = mpPaymentClient();
  const mp = await client.create({
    body: {
      transaction_amount: txAmount,
      description,
      payment_method_id: "pix",
      payer: {email: userEmail},
    },
  });

  const expiresAt = new Date(Date.now() + 30 * 60 * 1000).toISOString();

  await db.collection("payments").doc(String(mp.id)).set({
    userId,
    amount: txAmount,
    purpose,
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

  // Fila prioritária de verificação — confirma prioridade, não credita saldo
  if (paymentData.purpose === "verification_priority") {
    const vbatch = db.batch();
    vbatch.update(paymentRef, {
      status: "approved",
      approvedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    vbatch.set(
        db.collection("verificationRequests").doc(paymentData.userId), {
          priority: true,
          paidAt: new Date().toISOString(),
          paymentId: String(paymentId),
          updatedAt: new Date().toISOString(),
        }, {merge: true});
    await vbatch.commit();
    await _sendNotification(
        db, paymentData.userId,
        "⭐ Fila prioritária confirmada!",
        "Seu pedido de verificação entrou na fila prioritária.",
        {type: "verification_priority"},
    );
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

// ─── ADMIN: SUBMIT DEMO ENTRY ────────────────────────────────────────────────
// Creates a fake participant entry on behalf of a demo user.
// Bypasses creator restriction, duplicate check, and ban check.

exports.adminSubmitDemoEntry = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Usuário não logado");
  }

  const db = admin.firestore();
  const adminDoc = await db.collection("admins").doc(context.auth.uid).get();
  if (!adminDoc.exists) {
    throw new functions.https.HttpsError("permission-denied", "Acesso negado");
  }

  const {challengeId, contentType, contentText, contentUrl, demoName} = data;

  if (!challengeId || !contentType) {
    throw new functions.https.HttpsError(
        "invalid-argument", "challengeId e contentType são obrigatórios",
    );
  }

  if (contentType === "text") {
    if (!contentText || contentText.trim().length === 0) {
      throw new functions.https.HttpsError("invalid-argument", "Conteúdo de texto é obrigatório");
    }
  } else {
    if (!contentUrl) {
      throw new functions.https.HttpsError("invalid-argument", "URL do conteúdo é obrigatória");
    }
  }

  const challengeDoc = await db.collection("challenges").doc(challengeId).get();
  if (!challengeDoc.exists) {
    throw new functions.https.HttpsError("not-found", "Desafio não encontrado");
  }
  if (challengeDoc.data().status !== "active") {
    throw new functions.https.HttpsError("failed-precondition", "Desafio não está ativo");
  }

  // Each demo entry gets a unique synthetic userId so they never conflict
  const demoUserId = `demo_${Date.now()}`;
  const entryRef = db.collection("entries").doc();
  const challengeRef = db.collection("challenges").doc(challengeId);

  await db.runTransaction(async (tx) => {
    tx.set(entryRef, {
      challengeId,
      userId: demoUserId,
      demoName: (demoName || "").trim() || "Participante Demo",
      isDemo: true,
      contentType,
      contentText: contentText || null,
      contentUrl: contentUrl || null,
      voteCount: 0,
      isActive: true,
      createdAt: new Date().toISOString(),
    });
    tx.update(challengeRef, {entryCount: admin.firestore.FieldValue.increment(1)});
  });

  await db.collection("audit_logs").add({
    type: "admin_demo_entry",
    entryId: entryRef.id,
    challengeId,
    adminId: context.auth.uid,
    demoUserId,
    createdAt: new Date().toISOString(),
  });

  return {entryId: entryRef.id};
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

// ─── SEED VIRTUAL USERS ──────────────────────────────────────────────────────

exports.seedVirtualUsers = functions.runWith({timeoutSeconds: 540}).https.onRequest(async (req, res) => {
  if (req.method !== "POST") return res.status(405).json({error: "Method Not Allowed"});
  if (!req.body || req.body.secret !== "SEED_2026_DP") {
    return res.status(403).json({error: "Forbidden"});
  }

  const db = admin.firestore();

  // Prevent double-seeding
  const check = await db.collection("users").where("isVirtual", "==", true).limit(1).get();
  if (!check.empty) {
    return res.status(409).json({error: "Already seeded. Virtual users already exist."});
  }

  // ── Name data ──────────────────────────────────────────────────────────────
  const maleFirst = [
    "João", "Pedro", "Carlos", "Lucas", "Gabriel", "Rafael", "Daniel", "Mateus", "Thiago", "Rodrigo",
    "Fernando", "Eduardo", "Bruno", "Diego", "Felipe", "Leandro", "Ricardo", "Alexandre", "Marcelo", "André",
    "Gustavo", "Paulo", "Henrique", "Roberto", "Vinícius", "Leonardo", "Caio", "Igor", "Renato", "Breno",
    "Alan", "Sérgio", "Wellington", "Murilo", "Davi", "Arthur", "Bernardo", "Enzo", "Heitor", "Samuel",
    "Victor", "William", "Yago", "Alisson", "Cláudio", "David", "Elias", "Fábio", "Kevin", "Marco",
  ];
  const femaleFirst = [
    "Maria", "Ana", "Fernanda", "Juliana", "Amanda", "Camila", "Larissa", "Mariana", "Patrícia", "Aline",
    "Bianca", "Carolina", "Daniela", "Gabriela", "Helena", "Isabela", "Jade", "Karen", "Laura", "Milena",
    "Natália", "Olivia", "Paula", "Renata", "Sabrina", "Tatiana", "Vanessa", "Yasmin", "Alice", "Beatriz",
    "Carla", "Débora", "Estela", "Flávia", "Giovanna", "Isadora", "Jéssica", "Letícia", "Manuela", "Nathalia",
    "Paola", "Sofia", "Thaís", "Valentina", "Vitória", "Eloá", "Priscila", "Mônica", "Lívia", "Bruna",
  ];
  const allFirst = [...maleFirst, ...femaleFirst];

  const lastNames = [
    "Silva", "Santos", "Oliveira", "Souza", "Rodrigues", "Ferreira", "Alves", "Pereira", "Lima", "Carvalho",
    "Gomes", "Martins", "Costa", "Ribeiro", "Cunha", "Barbosa", "Nunes", "Nascimento", "Araújo", "Moreira",
    "Almeida", "Castro", "Cardoso", "Cavalcanti", "Correia", "Dias", "Duarte", "Figueiredo", "Freitas", "Gonçalves",
    "Guimarães", "Lemos", "Lopes", "Macedo", "Machado", "Maia", "Medeiros", "Melo", "Mendes", "Miranda",
    "Monteiro", "Moraes", "Mota", "Nogueira", "Paiva", "Pinto", "Ramos", "Rocha", "Tavares", "Teixeira",
  ];

  // ── Build unique name combos ───────────────────────────────────────────────
  const allCombos = [];
  for (const fn of allFirst) {
    for (const ln of lastNames) {
      allCombos.push([fn, ln]);
    }
  }
  // Fisher-Yates shuffle
  for (let i = allCombos.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [allCombos[i], allCombos[j]] = [allCombos[j], allCombos[i]];
  }
  const selected = allCombos.slice(0, 1000);

  // ── Value distribution ─────────────────────────────────────────────────────
  // neymarjr = 734,519  → position 7  (exactly 6 regular users above him)
  // whinderssonnunes = 287,342 → position 21 (13 regular users between them)
  const MAX_VAL = 1557280;
  const NEYMAR_VAL = 734519;
  const WHINDERSSON_VAL = 287342;

  const earnedValues = [];
  earnedValues.push(MAX_VAL); // position 1 (exactly max)
  for (let i = 0; i < 5; i++) { // positions 2-6 (above neymar)
    earnedValues.push(Math.floor(NEYMAR_VAL + 1 + Math.random() * (MAX_VAL - NEYMAR_VAL - 2)));
  }
  for (let i = 0; i < 13; i++) { // positions 8-20 (between)
    earnedValues.push(Math.floor(WHINDERSSON_VAL + 1 + Math.random() * (NEYMAR_VAL - WHINDERSSON_VAL - 2)));
  }
  for (let i = 0; i < 981; i++) { // positions 22-1002 (below whindersson)
    earnedValues.push(Math.floor(100 + Math.random() * (WHINDERSSON_VAL - 101)));
  }
  // Shuffle earnings so values aren't ordered by category
  for (let i = earnedValues.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [earnedValues[i], earnedValues[j]] = [earnedValues[j], earnedValues[i]];
  }

  // ── Helper: normalize string to username-safe ──────────────────────────────
  function toUsername(str) {
    return str.toLowerCase()
        .normalize("NFD").replace(/[̀-ͯ]/g, "")
        .replace(/[^a-z0-9]/g, "").slice(0, 20);
  }

  // ── Build user objects ─────────────────────────────────────────────────────
  const now = new Date().toISOString();
  const usernameSet = new Set(["neymarjr", "whinderssonnunes"]);
  const users = [];

  for (let i = 0; i < 1000; i++) {
    const [fn, ln] = selected[i];
    const base = `${toUsername(fn)}.${toUsername(ln)}`;
    let username = base;
    let attempt = 0;
    while (usernameSet.has(username)) {
      attempt++;
      username = `${base}${attempt}`;
    }
    usernameSet.add(username);

    users.push({
      id: db.collection("users").doc().id,
      name: `${fn} ${ln}`,
      username,
      email: `${username}.demo@gmail.com`,
      photoUrl: `https://randomuser.me/api/portraits/${i % 2 === 0 ? "men" : "women"}/${Math.floor(i / 2) % 100}.jpg`,
      createdAt: now,
      balance: 0.0,
      pendingBalance: 0.0,
      lockedBalance: 0.0,
      totalEarned: earnedValues[i],
      totalVotesReceived: Math.floor(Math.random() * 50000),
      followersCount: Math.floor(Math.random() * 8000),
      followingCount: Math.floor(Math.random() * 800),
      bio: "",
      pixKey: "",
      termsAccepted: true,
      isVirtual: true,
      isVerified: false,
    });
  }

  // Special verified accounts
  users.push({
    id: db.collection("users").doc().id,
    name: "Neymar Jr",
    username: "neymarjr",
    email: "neymarjr.demo@gmail.com",
    photoUrl: "https://i.pravatar.cc/150?u=neymarjr_official",
    createdAt: now,
    balance: 0.0, pendingBalance: 0.0, lockedBalance: 0.0,
    totalEarned: NEYMAR_VAL,
    totalVotesReceived: 89432,
    followersCount: 250000,
    followingCount: 412,
    bio: "Futebol e diversão! ⚽🔥",
    pixKey: "",
    termsAccepted: true,
    isVirtual: true,
    isVerified: true,
  });

  users.push({
    id: db.collection("users").doc().id,
    name: "Whindersson Nunes",
    username: "whinderssonnunes",
    email: "whinderssonnunes.demo@gmail.com",
    photoUrl: "https://i.pravatar.cc/150?u=whinderssonnunes_official",
    createdAt: now,
    balance: 0.0, pendingBalance: 0.0, lockedBalance: 0.0,
    totalEarned: WHINDERSSON_VAL,
    totalVotesReceived: 54217,
    followersCount: 180000,
    followingCount: 387,
    bio: "Humor e entretenimento! 😂",
    pixKey: "",
    termsAccepted: true,
    isVirtual: true,
    isVerified: true,
  });

  // ── Batch write (200 users per batch = 400 ops, well under 500 limit) ──────
  const CHUNK = 200;
  let created = 0;
  for (let i = 0; i < users.length; i += CHUNK) {
    const batch = db.batch();
    const chunk = users.slice(i, i + CHUNK);
    for (const u of chunk) {
      const {id, ...data} = u;
      batch.set(db.collection("users").doc(id), data);
      batch.set(db.collection("usernames").doc(u.username), {uid: id, createdAt: now});
    }
    await batch.commit();
    created += chunk.length;
    console.log(`seedVirtualUsers: committed ${created} / ${users.length}`);
  }

  return res.json({success: true, created});
});

// ─── FIX VIRTUAL USERS (fotos self-hosted + usernames estilo gamertag) ───────

exports.fixVirtualUsers = functions.runWith({timeoutSeconds: 540})
    .https.onRequest(async (req, res) => {
      if (req.method !== "POST") {
        return res.status(405).json({error: "Method Not Allowed"});
      }
      if (!req.body || req.body.secret !== "SEED_2026_DP") {
        return res.status(403).json({error: "Forbidden"});
      }

      const db = admin.firestore();
      const HOST = "https://desafiopago.web.app";
      const MEN_COUNT = 100;
      const WOMEN_COUNT = 100;
      const CHANGE_PCT = 40; // ~40% recebem username estilo gamertag

      // Normaliza removendo acentos e caracteres não alfanuméricos.
      const norm = (s) => (s || "").toLowerCase().normalize("NFD")
          .replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9]/g, "");

      // Lista feminina (idêntica ao seed) para casar a foto com o nome.
      // Qualquer nome fora dela cai no padrão masculino.
      const femaleFirst = [
        "Maria", "Ana", "Fernanda", "Juliana", "Amanda", "Camila", "Larissa",
        "Mariana", "Patrícia", "Aline", "Bianca", "Carolina", "Daniela",
        "Gabriela", "Helena", "Isabela", "Jade", "Karen", "Laura", "Milena",
        "Natália", "Olivia", "Paula", "Renata", "Sabrina", "Tatiana", "Vanessa",
        "Yasmin", "Alice", "Beatriz", "Carla", "Débora", "Estela", "Flávia",
        "Giovanna", "Isadora", "Jéssica", "Letícia", "Manuela", "Nathalia",
        "Paola", "Sofia", "Thaís", "Valentina", "Vitória", "Eloá", "Priscila",
        "Mônica", "Lívia", "Bruna",
      ];
      const femaleSet = new Set(femaleFirst.map(norm));

      // Apelidos brasileiros para deixar os usernames mais naturais.
      const nicks = {
        joao: ["jao"], pedro: ["pedrin", "peu"], carlos: ["carlinhos"],
        lucas: ["luca", "luquinhas"], gabriel: ["biel", "gabu"],
        rafael: ["rafa"], daniel: ["dani", "dan"], mateus: ["teteu"],
        thiago: ["thi"], rodrigo: ["digo"], fernando: ["nando", "fer"],
        eduardo: ["dudu", "du"], bruno: ["bru"], felipe: ["lipe", "felps"],
        ricardo: ["ricky"], alexandre: ["xand", "ale"], marcelo: ["celo"],
        andre: ["dede"], gustavo: ["guga", "gus"], henrique: ["rique"],
        roberto: ["beto"], vinicius: ["vini"], leonardo: ["leo"],
        renato: ["nato"], sergio: ["serjao"], wellington: ["well"],
        murilo: ["muka"], arthur: ["tutu"], bernardo: ["berna"],
        heitor: ["tor"], samuel: ["samuca", "sam"], victor: ["vitao", "vic"],
        william: ["will"], alisson: ["ali"], claudio: ["cau"], elias: ["eli"],
        fabio: ["fabin"], marco: ["marquin"],
        maria: ["mah", "mari"], ana: ["aninha", "nana"],
        fernanda: ["nanda", "fe"], juliana: ["ju", "juju"],
        amanda: ["mandy"], camila: ["mila"], larissa: ["lari"],
        mariana: ["mary"], patricia: ["paty"], aline: ["line"],
        bianca: ["bibi"], carolina: ["carol"], daniela: ["dani"],
        gabriela: ["gabi", "gabs"], helena: ["lena"], isabela: ["isa", "bela"],
        karen: ["kaka"], laura: ["lala", "lau"], milena: ["mile"],
        natalia: ["nat", "tata"], olivia: ["livi", "oli"], paula: ["paulinha"],
        renata: ["naty"], sabrina: ["sah"], tatiana: ["tati"],
        vanessa: ["nessa"], yasmin: ["yas"], alice: ["lili"],
        beatriz: ["bia", "bea"], debora: ["deh", "debs"], flavia: ["fafa"],
        giovanna: ["gi", "giih"], isadora: ["dora"], jessica: ["jeh"],
        leticia: ["lele"], manuela: ["manu"], nathalia: ["naty"],
        sofia: ["sofi", "fifi"], valentina: ["tina"], vitoria: ["vivi", "vi"],
        eloa: ["loa"], priscila: ["pri"], monica: ["moni"],
        livia: ["livi"], bruna: ["bru", "bruh"],
      };
      const gamer = [
        "dark", "pro", "ninja", "sniper", "king", "lord", "zica", "fera",
        "craque", "mestre", "top", "gg", "shadow", "red", "mlk", "real",
        "cyber", "neo", "blaze", "ghost",
      ];

      const ri = (n) => Math.floor(Math.random() * n);
      const pick = (arr) => arr[ri(arr.length)];
      const numStr = () => {
        const r = Math.random();
        if (r < 0.35) return String(2007 + ri(7));
        if (r < 0.7) return String(pick([7, 10, 13, 17, 23, 69, 77, 88, 99]));
        return String(ri(1000));
      };
      const sanitize = (raw) => {
        let s = raw.toLowerCase().normalize("NFD")
            .replace(/[̀-ͯ]/g, "")
            .replace(/[^a-z0-9._]/g, "")
            .replace(/([._])\1+/g, "$1")
            .replace(/^[._]+/, "").replace(/[._]+$/, "");
        if (s.length < 3) s += numStr();
        return s.slice(0, 30).replace(/[._]+$/, "");
      };
      const makeTag = (first) => {
        const opts = nicks[first] || [first];
        const base = Math.random() < 0.6 ? pick(opts) : first;
        const templates = [
          () => `${base}${numStr()}`,
          () => `${base}.${numStr()}`,
          () => `${base}_${numStr()}`,
          () => `xx_${base}_xx`,
          () => `${base}.br`,
          () => `itz${base}`,
          () => `${base}.pro`,
          () => `${base}_${pick(gamer)}`,
          () => `${pick(gamer)}_${base}${Math.random() < 0.5 ? numStr() : ""}`,
          () => `oo${base}oo`,
          () => `${base}_oficial`,
          () => `${base}.ttv`,
          () => `${pick(gamer)}${base}`,
          () => `${base}${numStr()}`,
        ];
        return sanitize(pick(templates)());
      };

      // Carrega usernames existentes para garantir unicidade.
      const unameSnap = await db.collection("usernames").get();
      const taken = new Set(unameSnap.docs.map((d) => d.id));
      const uniqueTag = (first) => {
        let c = makeTag(first);
        let guard = 0;
        while ((taken.has(c) || c.length < 3) && guard < 60) {
          c = sanitize(c + ri(10));
          guard++;
        }
        taken.add(c);
        return c;
      };

      // Hash estável do id → seleciona ~40% de forma determinística.
      const hashId = (id) => {
        let h = 0;
        for (let i = 0; i < id.length; i++) {
          h = (h * 31 + id.charCodeAt(i)) >>> 0;
        }
        return h % 100;
      };

      const snap = await db.collection("users")
          .where("isVirtual", "==", true).get();

      let batch = db.batch();
      let ops = 0;
      let committed = 0;
      let photosFixed = 0;
      let namesChanged = 0;

      const flush = async () => {
        if (ops > 0) {
          await batch.commit();
          committed++;
          batch = db.batch();
          ops = 0;
        }
      };

      for (const docSnap of snap.docs) {
        const u = docSnap.data();
        const id = docSnap.id;
        const uname = u.username || "";
        const special = uname === "neymarjr" || uname === "whinderssonnunes";

        const first = norm((u.name || "").split(" ")[0]);
        const gender = femaleSet.has(first) ? "women" : "men";
        const count = gender === "men" ? MEN_COUNT : WOMEN_COUNT;
        const photoUrl = `${HOST}/portraits/${gender}/${ri(count)}.jpg`;

        let newUsername = null;
        if (!special && hashId(id) < CHANGE_PCT) {
          newUsername = uniqueTag(first || "user");
        }

        if (ops + 3 > 450) await flush();

        const userUpdate = {photoUrl};
        if (newUsername && newUsername !== uname) {
          userUpdate.username = newUsername;
          batch.set(db.collection("usernames").doc(newUsername),
              {uid: id, updatedAt: new Date().toISOString()});
          ops++;
          if (uname) {
            batch.delete(db.collection("usernames").doc(uname));
            ops++;
          }
          namesChanged++;
        }
        batch.update(db.collection("users").doc(id), userUpdate);
        ops++;
        photosFixed++;
      }
      await flush();

      return res.json({
        success: true,
        total: snap.size,
        photosFixed,
        namesChanged,
        batches: committed,
      });
    });

// ─── UPDATE USERNAME ──────────────────────────────────────────────────────────

exports.updateUsername = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Não autenticado");
  }

  const userId = context.auth.uid;
  const newUsername = (data.newUsername || "").trim().toLowerCase();

  if (!newUsername || !/^[a-z0-9][a-z0-9._]{2,29}$/.test(newUsername)) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "Username inválido. Use 3–30 caracteres: letras, números, ponto ou sublinhado.",
    );
  }

  const db = admin.firestore();

  // Check availability
  const existingDoc = await db.collection("usernames").doc(newUsername).get();
  if (existingDoc.exists && existingDoc.data().uid !== userId) {
    throw new functions.https.HttpsError("already-exists", "Este username já está em uso.");
  }

  // Get current username to delete old entry
  const userDoc = await db.collection("users").doc(userId).get();
  const oldUsername = userDoc.data()?.username;

  const batch = db.batch();
  batch.set(
      db.collection("usernames").doc(newUsername),
      {uid: userId, updatedAt: new Date().toISOString()},
  );
  if (oldUsername && oldUsername !== newUsername) {
    batch.delete(db.collection("usernames").doc(oldUsername));
  }
  batch.update(db.collection("users").doc(userId), {username: newUsername});
  await batch.commit();

  return {success: true, username: newUsername};
});

// ─── SET USER VERIFIED ────────────────────────────────────────────────────────

exports.setUserVerified = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Não autenticado");
  }
  const db = admin.firestore();
  const adminDoc = await db.collection("admins").doc(context.auth.uid).get();
  if (!adminDoc.exists) {
    throw new functions.https.HttpsError("permission-denied", "Apenas administradores.");
  }
  const {userId, isVerified} = data;
  if (!userId) throw new functions.https.HttpsError("invalid-argument", "userId obrigatório");
  await db.collection("users").doc(userId).update({isVerified: isVerified === true});
  return {success: true};
});

// ─── VERIFICAÇÃO: ENVIAR PEDIDO ───────────────────────────────────────────────

exports.submitVerificationRequest =
    functions.https.onCall(async (data, context) => {
      if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated", "Não autenticado");
      }
      const db = admin.firestore();
      const userId = context.auth.uid;

      const firstName = String(data.firstName || "").trim();
      const lastName = String(data.lastName || "").trim();
      const phoneDigits = String(data.phone || "").replace(/\D/g, "");
      const cpf = String(data.cpf || "").replace(/\D/g, "");

      const isValidCPF = (c) => {
        if (!/^\d{11}$/.test(c)) return false;
        if (/^(\d)\1{10}$/.test(c)) return false;
        const calc = (len) => {
          let sum = 0;
          for (let i = 0; i < len; i++) {
            sum += parseInt(c[i], 10) * (len + 1 - i);
          }
          const mod = (sum * 10) % 11;
          return mod === 10 ? 0 : mod;
        };
        return calc(9) === parseInt(c[9], 10) &&
            calc(10) === parseInt(c[10], 10);
      };

      if (firstName.length < 2 || lastName.length < 2) {
        throw new functions.https.HttpsError(
            "invalid-argument", "Informe nome e sobrenome");
      }
      if (phoneDigits.length < 10 || phoneDigits.length > 11) {
        throw new functions.https.HttpsError(
            "invalid-argument", "Telefone inválido");
      }
      if (!isValidCPF(cpf)) {
        throw new functions.https.HttpsError("invalid-argument", "CPF inválido");
      }

      const userRef = db.collection("users").doc(userId);
      const userDoc = await userRef.get();
      if (!userDoc.exists) {
        throw new functions.https.HttpsError(
            "not-found", "Usuário não encontrado");
      }
      if (userDoc.data().isVerified === true) {
        throw new functions.https.HttpsError(
            "failed-precondition", "Você já é verificado");
      }

      const reqRef = db.collection("verificationRequests").doc(userId);
      const existing = await reqRef.get();
      const now = new Date().toISOString();

      const payload = {
        userId,
        firstName,
        lastName,
        phone: phoneDigits,
        cpf,
        name: userDoc.data().name || "",
        username: userDoc.data().username || "",
        photoUrl: userDoc.data().photoUrl || "",
        status: "pending",
        updatedAt: now,
      };
      if (!existing.exists) {
        payload.priority = false;
        payload.paymentId = null;
        payload.paidAt = null;
        payload.createdAt = now;
      }

      await reqRef.set(payload, {merge: true});
      return {success: true};
    });

// ─── VERIFICAÇÃO: DECISÃO DO ADMIN ────────────────────────────────────────────

exports.decideVerificationRequest =
    functions.https.onCall(async (data, context) => {
      if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated", "Não autenticado");
      }
      const db = admin.firestore();
      const adminDoc =
          await db.collection("admins").doc(context.auth.uid).get();
      if (!adminDoc.exists) {
        throw new functions.https.HttpsError(
            "permission-denied", "Apenas administradores.");
      }

      const userId = data.userId;
      const approved = data.approved === true;
      if (!userId) {
        throw new functions.https.HttpsError(
            "invalid-argument", "userId obrigatório");
      }

      const reqRef = db.collection("verificationRequests").doc(userId);
      const reqDoc = await reqRef.get();
      if (!reqDoc.exists) {
        throw new functions.https.HttpsError(
            "not-found", "Pedido não encontrado");
      }

      const batch = db.batch();
      batch.update(reqRef, {
        status: approved ? "approved" : "rejected",
        decidedAt: new Date().toISOString(),
        decidedBy: context.auth.uid,
        updatedAt: new Date().toISOString(),
      });
      if (approved) {
        batch.update(db.collection("users").doc(userId), {isVerified: true});
      }
      await batch.commit();

      await _sendNotification(
          db, userId,
          approved ? "✅ Verificação aprovada!" : "❌ Verificação recusada",
          approved ?
            "Seu selo de verificado foi ativado." :
            "Seu pedido de verificação foi recusado.",
          {type: "verification_decision"},
      );

      return {success: true};
    });

// ─── ADMIN: EDITAR PERFIL VIRTUAL ─────────────────────────────────────────────

exports.adminUpdateVirtualUser =
    functions.https.onCall(async (data, context) => {
      if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated", "Não autenticado");
      }
      const db = admin.firestore();
      const adminDoc =
          await db.collection("admins").doc(context.auth.uid).get();
      if (!adminDoc.exists) {
        throw new functions.https.HttpsError(
            "permission-denied", "Apenas administradores.");
      }

      const userId = data.userId;
      if (!userId) {
        throw new functions.https.HttpsError(
            "invalid-argument", "userId obrigatório");
      }
      const userRef = db.collection("users").doc(userId);
      const userDoc = await userRef.get();
      if (!userDoc.exists) {
        throw new functions.https.HttpsError(
            "not-found", "Usuário não encontrado");
      }
      if (userDoc.data().isVirtual !== true) {
        throw new functions.https.HttpsError(
            "failed-precondition", "Só é permitido editar perfis virtuais.");
      }

      const updates = {};
      if (typeof data.name === "string" && data.name.trim().length > 0) {
        updates.name = data.name.trim();
      }
      if (typeof data.bio === "string") {
        updates.bio = data.bio.trim();
      }
      if (typeof data.isVerified === "boolean") {
        updates.isVerified = data.isVerified;
      }

      // Foto: upload base64 (Admin SDK) tem prioridade; senão usa URL pronta.
      if (typeof data.photoBase64 === "string" && data.photoBase64.length > 0) {
        const {randomUUID} = require("crypto");
        const bucket = admin.storage().bucket();
        const path = `virtual/${userId}.jpg`;
        const token = randomUUID();
        const buffer = Buffer.from(data.photoBase64, "base64");
        await bucket.file(path).save(buffer, {
          metadata: {
            contentType: data.photoContentType || "image/jpeg",
            metadata: {firebaseStorageDownloadTokens: token},
          },
        });
        updates.photoUrl =
            "https://firebasestorage.googleapis.com/v0/b/" + bucket.name +
            "/o/" + encodeURIComponent(path) + "?alt=media&token=" + token;
      } else if (typeof data.photoUrl === "string" &&
          data.photoUrl.length > 0) {
        updates.photoUrl = data.photoUrl;
      }

      // Username: valida formato + unicidade e troca os docs atomically.
      const newUsername = typeof data.username === "string" ?
          data.username.trim().toLowerCase() : "";
      const oldUsername = userDoc.data().username || "";

      if (newUsername && newUsername !== oldUsername) {
        if (!/^[a-z0-9][a-z0-9._]{2,29}$/.test(newUsername)) {
          throw new functions.https.HttpsError(
              "invalid-argument", "Username inválido.");
        }
        const taken = await db.collection("usernames").doc(newUsername).get();
        if (taken.exists && taken.data().uid !== userId) {
          throw new functions.https.HttpsError(
              "already-exists", "Username já está em uso.");
        }
        const batch = db.batch();
        batch.set(db.collection("usernames").doc(newUsername),
            {uid: userId, updatedAt: new Date().toISOString()});
        if (oldUsername) {
          batch.delete(db.collection("usernames").doc(oldUsername));
        }
        updates.username = newUsername;
        batch.update(userRef, updates);
        await batch.commit();
        return {success: true, photoUrl: updates.photoUrl || null};
      }

      if (Object.keys(updates).length > 0) {
        await userRef.update(updates);
      }
      return {success: true, photoUrl: updates.photoUrl || null};
    });

// ─── REGISTRAR INSTALAÇÃO DO APP ──────────────────────────────────────────────

exports.registerAppInstall =
    functions.https.onCall(async (data, context) => {
      if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated", "Não autenticado");
      }
      const db = admin.firestore();
      const ref = db.collection("users").doc(context.auth.uid);
      const doc = await ref.get();
      if (!doc.exists) return {success: false};
      const updates = {
        appInstalled: true,
        platform: String(data.platform || "mobile"),
      };
      if (!doc.data().installedAt) {
        updates.installedAt = new Date().toISOString();
      }
      await ref.update(updates);
      return {success: true};
    });

// ─── EXPORTAR PÚBLICO P/ CAMPANHAS (Google Ads / Meta) ────────────────────────

exports.exportAudience = functions.runWith({timeoutSeconds: 300})
    .https.onCall(async (data, context) => {
      if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated", "Não autenticado");
      }
      const db = admin.firestore();
      const adminDoc =
          await db.collection("admins").doc(context.auth.uid).get();
      if (!adminDoc.exists) {
        throw new functions.https.HttpsError(
            "permission-denied", "Apenas administradores.");
      }

      const segment = data.segment === "installs" ? "installs" : "signups";
      const platform = data.platform === "meta" ? "meta" : "google";

      // Telefone e nome reais vêm dos pedidos de verificação (quando houver).
      const vSnap = await db.collection("verificationRequests").get();
      const vById = {};
      vSnap.forEach((d) => {
        const x = d.data();
        vById[d.id] = {
          phone: x.phone || "",
          firstName: x.firstName || "",
          lastName: x.lastName || "",
        };
      });

      const splitName = (full) => {
        const parts =
            String(full || "").trim().split(/\s+/).filter(Boolean);
        if (parts.length === 0) return ["", ""];
        if (parts.length === 1) return [parts[0], ""];
        return [parts[0], parts.slice(1).join(" ")];
      };
      const fmtPhone = (raw) => {
        const p = String(raw || "").replace(/\D/g, "");
        if (p.length === 10 || p.length === 11) return "+55" + p;
        if (p.length === 12 || p.length === 13) return "+" + p;
        return "";
      };
      const esc = (v) => {
        const s = String(v == null ? "" : v);
        return /[",\n]/.test(s) ? "\"" + s.replace(/"/g, "\"\"") + "\"" : s;
      };

      const uSnap = await db.collection("users").get();
      const rows = [];
      uSnap.forEach((doc) => {
        const u = doc.data();
        if (u.isVirtual === true) return;
        if (u.isBanned === true) return;
        if (segment === "installs" && u.appInstalled !== true) return;
        const email = String(u.email || "").trim().toLowerCase();
        if (!email) return;

        const v = vById[doc.id];
        let fn = v && v.firstName ? v.firstName : "";
        let ln = v && v.lastName ? v.lastName : "";
        if (!fn) {
          const sp = splitName(u.name);
          fn = sp[0];
          ln = ln || sp[1];
        }
        const phone = fmtPhone(v ? v.phone : "");
        rows.push({email, phone, fn, ln});
      });

      let header;
      let lines;
      if (platform === "meta") {
        header = "email,phone,fn,ln,country";
        lines = rows.map((r) =>
          [esc(r.email), esc(r.phone), esc(r.fn), esc(r.ln), "BR"].join(","));
      } else {
        header = "Email,Phone,First Name,Last Name,Country,Zip";
        lines = rows.map((r) =>
          [esc(r.email), esc(r.phone), esc(r.fn), esc(r.ln), "BR", ""]
              .join(","));
      }
      const csv = [header, ...lines].join("\n");

      const date = new Date().toISOString().slice(0, 10);
      const filename = platform + "-" + segment + "-" + date + ".csv";

      return {csv, count: rows.length, filename, segment, platform};
    });

// ─── UPDATE VIRTUAL AVATARS ───────────────────────────────────────────────────
// One-shot migration: replaces pravatar.cc URLs with randomuser.me portraits.

exports.updateVirtualAvatars = functions.runWith({timeoutSeconds: 540}).https.onRequest(async (req, res) => {
  if (req.method !== "POST") return res.status(405).json({error: "Method Not Allowed"});
  if (!req.body || req.body.secret !== "SEED_2026_DP") {
    return res.status(403).json({error: "Forbidden"});
  }

  const db = admin.firestore();
  const snap = await db.collection("users").where("isVirtual", "==", true).get();
  const docs = snap.docs;

  const CHUNK = 490;
  let updated = 0;
  let idx = 0;

  for (let i = 0; i < docs.length; i += CHUNK) {
    const batch = db.batch();
    const chunk = docs.slice(i, i + CHUNK);
    for (const doc of chunk) {
      const d = doc.data();
      const username = d.username || "";
      // Keep special accounts' avatars as-is
      if (username === "neymarjr" || username === "whinderssonnunes") {
        idx++;
        continue;
      }
      const gender = idx % 2 === 0 ? "men" : "women";
      const num = Math.floor(idx / 2) % 100;
      batch.update(doc.ref, {photoUrl: `https://randomuser.me/api/portraits/${gender}/${num}.jpg`});
      idx++;
      updated++;
    }
    await batch.commit();
    console.log(`updateVirtualAvatars: ${updated} updated so far`);
  }

  return res.json({success: true, updated});
});
