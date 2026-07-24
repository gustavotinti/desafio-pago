const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {MercadoPagoConfig, Payment} = require("mercadopago");
const {splitPrizeCents, withdrawalFee, withdrawalNet} = require("./money");

admin.initializeApp();

const {getSecret} = require("./secrets");

// ─── helpers ─────────────────────────────────────────────────────────────────

async function mpPaymentClient() {
  // Token do cofre (painel admin) com fallback pro .env.
  const token = await getSecret("MERCADOPAGO_ACCESS_TOKEN");
  return new Payment(new MercadoPagoConfig({accessToken: token}));
}

async function _assertNotBanned(db, userId) {
  const doc = await db.collection("users").doc(userId).get();
  if (doc.data()?.isBanned === true) {
    throw new functions.https.HttpsError("permission-denied", "Sua conta está suspensa");
  }
}

async function _sendNotification(db, userId, title, body, data = {}) {
  // Histórico in-app (funciona mesmo sem push autorizado — sininho no app).
  // Subcoleção users/{uid}/notifications → sem índice composto.
  try {
    await db.collection("users").doc(userId)
        .collection("notifications").add({
          title,
          body,
          type: String(data.type || ""),
          challengeId: data.challengeId ? String(data.challengeId) : null,
          entryId: data.entryId ? String(data.entryId) : null,
          read: false,
          createdAt: new Date().toISOString(),
        });
  } catch (e) {
    console.error("Erro ao persistir notificação:", e.message);
  }
  // Push (se o usuário tiver autorizado e salvo o token).
  try {
    const userDoc = await db.collection("users").doc(userId).get();
    const token = userDoc.data()?.fcmToken;
    if (!token) return;
    await admin.messaging().send({
      token,
      notification: {title, body},
      data: Object.fromEntries(
          Object.entries(data).map(([k, v]) => [k, String(v)])),
      android: {priority: "high"},
      apns: {payload: {aps: {sound: "default"}}},
    });
  } catch (err) {
    console.error("Erro ao enviar notificação:", err.message);
  }
}

async function _maybeScheduleInstagramPost(db, challengeId, oldAmount, newAmount) {
  // Config em config/instagram (enabled + threshold). Padrão: threshold 100,
  // ligado (só não agenda se enabled === false).
  let threshold = Number(process.env.INSTAGRAM_THRESHOLD || 100);
  let enabled = true;
  try {
    const cfg = await db.collection("config").doc("instagram").get();
    if (cfg.exists) {
      const d = cfg.data();
      if (typeof d.threshold === "number" && d.threshold > 0) {
        threshold = d.threshold;
      }
      if (d.enabled === false) enabled = false;
    }
  } catch (e) {
    // usa padrão
  }
  if (!enabled) return;
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

    const expiresAt = new Date(
        now.getTime() + durationDays * 24 * 60 * 60 * 1000,
    ).toISOString();
    // Região do desafio: 'BR' (padrão) ou 'INTL' (site trialspaid). Separa os
    // feeds — o ranking continua compartilhado.
    const region = data.region === "INTL" ? "INTL" : "BR";
    const challengeRef = db.collection("challenges").doc();
    const challengeData = {
      title,
      description,
      createdBy: userId,
      amount: Number(amount),
      creatorContribution: isAdmin ? 0 : Number(amount),
      status: "active",
      region,
      voteCount: 0,
      entryCount: 0,
      winnerIds: [],
      createdAt: now.toISOString(),
      expiresAt,
    };

    if (isAdmin) {
      await challengeRef.set(challengeData);
    } else {
      // Transação: lê o saldo e debita atomicamente (evita saldo negativo).
      const userRef = db.collection("users").doc(userId);
      await db.runTransaction(async (tx) => {
        const userDoc = await tx.get(userRef);
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
              `Saldo insuficiente. Saldo: R$${Number(balance).toFixed(2)}, ` +
              `necessário: R$${Number(amount).toFixed(2)}.`,
          );
        }
        tx.set(challengeRef, challengeData);
        tx.update(userRef, {
          balance: admin.firestore.FieldValue.increment(-Number(amount)),
          pendingBalance:
              admin.firestore.FieldValue.increment(Number(amount)),
        });
        tx.set(db.collection("transactions").doc(), {
          userId,
          amount: Number(amount),
          type: "challenge_created",
          description: `Desafio criado: ${title}`,
          challengeId: challengeRef.id,
          createdAt: now.toISOString(),
        });
      });
    }

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

  const userRef = db.collection("users").doc(userId);
  const now = new Date().toISOString();

  // Transação: lê o saldo e debita atomicamente (evita saldo negativo).
  await db.runTransaction(async (tx) => {
    const userDoc = await tx.get(userRef);
    const balance = userDoc.data()?.balance || 0;
    if (balance < value) {
      throw new functions.https.HttpsError(
          "failed-precondition", "Saldo insuficiente");
    }
    tx.update(db.collection("challenges").doc(challengeId), {
      amount: admin.firestore.FieldValue.increment(value),
    });
    tx.update(userRef, {
      balance: admin.firestore.FieldValue.increment(-value),
    });
    tx.set(db.collection("transactions").doc(), {
      userId,
      amount: value,
      type: "aporte",
      description: `Aporte: ${challenge.title}`,
      challengeId,
      createdAt: now,
    });
  });

  await _maybeScheduleInstagramPost(
      db, challengeId, challenge.amount, challenge.amount + value);
  return {success: true};
});

// ─── REQUEST WITHDRAW ────────────────────────────────────────────────────────

exports.requestWithdraw = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Usuário não logado");
  }

  const userId = context.auth.uid;
  const {amount} = data;

  // Mínimo de saque configurável via env (default R$100). Para reduzir,
  // defina MIN_WITHDRAWAL em functions/.env (ex.: MIN_WITHDRAWAL=1).
  const minWithdrawal = Number(process.env.MIN_WITHDRAWAL || 100);
  if (!amount || amount < minWithdrawal) {
    throw new functions.https.HttpsError(
        "invalid-argument", `Valor mínimo para saque é R$${minWithdrawal}`);
  }

  const db = admin.firestore();
  const userRef = db.collection("users").doc(userId);
  const withdrawalRef = db.collection("withdrawals").doc();
  const fee = withdrawalFee(amount);
  const netAmount = withdrawalNet(amount);
  const now = new Date().toISOString();

  // Transação: lê o saldo e debita atomicamente (evita saldo negativo).
  await db.runTransaction(async (tx) => {
    const userDoc = await tx.get(userRef);
    const userData = userDoc.data() || {};
    const balance = userData.balance || 0;
    const pixKey = userData.pixKey || "";

    if (!pixKey) {
      throw new functions.https.HttpsError(
          "failed-precondition", "Cadastre uma chave Pix primeiro");
    }
    if (balance < amount) {
      throw new functions.https.HttpsError(
          "failed-precondition", "Saldo insuficiente");
    }

    tx.set(withdrawalRef, {
      userId,
      amount,
      fee,
      netAmount,
      pixKey,
      status: "pending",
      createdAt: now,
    });
    tx.update(userRef, {
      balance: admin.firestore.FieldValue.increment(-amount),
      lockedBalance: admin.firestore.FieldValue.increment(amount),
    });
    tx.set(db.collection("transactions").doc(), {
      userId,
      amount,
      type: "withdraw",
      description: `Saque solicitado — taxa R$${fee.toFixed(2)} (10%)`,
      createdAt: now,
    });
  });

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

// ─── AUTO-VOTOS EM PARTICIPAÇÕES DE USUÁRIOS REAIS (cron 3min) ───────────────
// A cada 3 minutos, +1 voto em CADA participação de usuário REAL (não virtual,
// não demo) em desafios ativos. Mantém os contadores consistentes: entry,
// challenge e users.totalVotesReceived (o mirror espelha pro ranking) — o
// trigger syncChallengeTopEntries atualiza as prévias do feed sozinho.
// Kill-switch: config/engagement.autoVotes == false desliga.
exports.autoVoteRealEntries = functions.pubsub
    .schedule("every 3 minutes")
    .onRun(async () => {
      const db = admin.firestore();

      const cfg = await db.collection("config").doc("engagement").get();
      if (cfg.exists && cfg.data().autoVotes === false) return null;

      const challSnap = await db.collection("challenges")
          .where("status", "==", "active").get();
      if (challSnap.empty) return null;
      const activeIds = new Set(challSnap.docs.map((d) => d.id));

      // Participações ativas de desafios ativos (filtro em memória —
      // conjunto pequeno; evita índice composto).
      const entriesSnap = await db.collection("entries")
          .where("isActive", "==", true).get();
      const candidates = entriesSnap.docs.filter((d) => {
        const e = d.data();
        return activeIds.has(e.challengeId) && e.isDemo !== true &&
            e.userId && !String(e.userId).startsWith("demo_");
      });
      if (candidates.length === 0) return null;

      // Usuário REAL = tem doc em /users e não é virtual.
      const uids = [...new Set(candidates.map((d) => d.data().userId))];
      const userDocs = await db.getAll(
          ...uids.map((id) => db.collection("users").doc(id)));
      const realIds = new Set(userDocs
          .filter((u) => u.exists && u.data().isVirtual !== true)
          .map((u) => u.id));

      const realEntries =
          candidates.filter((d) => realIds.has(d.data().userId));
      if (realEntries.length === 0) return null;

      const batch = db.batch();
      const perChallenge = {};
      const perOwner = {};
      for (const d of realEntries) {
        batch.update(d.ref,
            {voteCount: admin.firestore.FieldValue.increment(1)});
        const e = d.data();
        perChallenge[e.challengeId] = (perChallenge[e.challengeId] || 0) + 1;
        perOwner[e.userId] = (perOwner[e.userId] || 0) + 1;
      }
      for (const [cid, n] of Object.entries(perChallenge)) {
        batch.update(db.collection("challenges").doc(cid),
            {voteCount: admin.firestore.FieldValue.increment(n)});
      }
      for (const [uid, n] of Object.entries(perOwner)) {
        batch.update(db.collection("users").doc(uid),
            {totalVotesReceived: admin.firestore.FieldValue.increment(n)});
      }
      await batch.commit();
      console.log(
          `autoVoteRealEntries: +1 voto em ${realEntries.length} ` +
          "participações reais");
      return null;
    });

async function finalizeChallenge(db, challengeDoc) {
  const challengeId = challengeDoc.id;
  const challengeRef = db.collection("challenges").doc(challengeId);

  // Entradas são estáveis após o término — leitura fora da transação.
  const entriesSnapshot = await db
      .collection("entries")
      .where("challengeId", "==", challengeId)
      .where("isActive", "==", true)
      .orderBy("voteCount", "desc")
      .get();
  const entries = entriesSnapshot.docs.map((d) => ({id: d.id, ...d.data()}));

  let winnersToNotify = [];
  let prizePerWinner = 0;
  let challengeTitle = "";

  // Transação idempotente: só finaliza se ainda estiver ativo (evita pagar
  // o prêmio em dobro se o cron sobrepuser ou o admin encerrar junto).
  await db.runTransaction(async (tx) => {
    const cDoc = await tx.get(challengeRef);
    if (!cDoc.exists || cDoc.data().status !== "active") return;
    const challenge = cDoc.data();
    challengeTitle = challenge.title || "";
    const prizeAmount = challenge.amount || 0;
    const creatorContribution = challenge.creatorContribution || 0;

    if (creatorContribution > 0) {
      tx.update(db.collection("users").doc(challenge.createdBy), {
        pendingBalance:
            admin.firestore.FieldValue.increment(-creatorContribution),
      });
    }

    const maxVotes = entries.length > 0 ? entries[0].voteCount : 0;
    if (entries.length === 0 || maxVotes === 0) {
      tx.update(challengeRef, {
        status: "finished",
        winnerIds: [],
        finishedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    const winners = entries.filter((e) => e.voteCount === maxVotes);
    const winnerIds = winners.map((e) => e.userId);
    const prizeCents = Math.round(prizeAmount * 100);
    const {perWinnerCents} = splitPrizeCents(prizeCents, winnerIds.length);
    prizePerWinner = perWinnerCents / 100;

    tx.update(challengeRef, {
      status: "finished",
      winnerIds,
      finishedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    for (const winner of winners) {
      tx.update(db.collection("users").doc(winner.userId), {
        balance: admin.firestore.FieldValue.increment(prizePerWinner),
        totalEarned: admin.firestore.FieldValue.increment(prizePerWinner),
      });
      tx.set(db.collection("transactions").doc(), {
        userId: winner.userId,
        amount: prizePerWinner,
        type: "reward",
        description: `Prêmio: ${challenge.title}`,
        challengeId,
        createdAt: new Date().toISOString(),
      });
    }
    winnersToNotify = winners;
  });

  if (winnersToNotify.length > 0) {
    await Promise.all(winnersToNotify.map((w) => _sendNotification(
        db, w.userId,
        "🏆 Você ganhou!",
        `Você venceu "${challengeTitle}" e recebeu ` +
        `R$${prizePerWinner.toFixed(2)}!`,
        {type: "win", challengeId},
    )));
  }
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

  const client = await mpPaymentClient();
  const mp = await client.create({
    body: {
      transaction_amount: txAmount,
      description,
      statement_descriptor: "DESAFIOPAGO",
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

  // Validação opcional da assinatura do Mercado Pago.
  // Ativa quando MP_WEBHOOK_SECRET está definido (em functions/.env +
  // configurado no painel do MP). Sem o segredo, é ignorada — a segurança
  // já é garantida pela re-consulta do status real no MP abaixo.
  const webhookSecret = await getSecret("MP_WEBHOOK_SECRET");
  if (webhookSecret) {
    const parts = {};
    String(req.headers["x-signature"] || "").split(",").forEach((kv) => {
      const i = kv.indexOf("=");
      if (i > 0) parts[kv.slice(0, i).trim()] = kv.slice(i + 1).trim();
    });
    const reqId = req.headers["x-request-id"] || "";
    const dataId = String(req.query["data.id"] || paymentId).toLowerCase();
    const manifest = `id:${dataId};request-id:${reqId};ts:${parts.ts};`;
    const expected = require("crypto")
        .createHmac("sha256", webhookSecret)
        .update(manifest)
        .digest("hex");
    // Modo estrito: rejeita quem não tiver assinatura válida do Mercado Pago.
    if (expected !== parts.v1) {
      console.warn("mercadoPagoWebhook: assinatura inválida");
      return res.sendStatus(401);
    }
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
  const mp = await (await mpPaymentClient()).get({id: paymentId});

  if (mp.status !== "approved") {
    await paymentRef.update({status: mp.status});
    res.sendStatus(200);
    return;
  }

  // Fila prioritária de verificação — confirma prioridade, não credita saldo
  if (paymentData.purpose === "verification_priority") {
    let processed = false;
    await db.runTransaction(async (tx) => {
      const pd = await tx.get(paymentRef);
      if (pd.data().status === "approved") return; // idempotente
      tx.update(paymentRef, {
        status: "approved",
        approvedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      tx.set(
          db.collection("verificationRequests").doc(paymentData.userId), {
            priority: true,
            paidAt: new Date().toISOString(),
            paymentId: String(paymentId),
            updatedAt: new Date().toISOString(),
          }, {merge: true});
      processed = true;
    });
    if (processed) {
      await _sendNotification(
          db, paymentData.userId,
          "⭐ Fila prioritária confirmada!",
          "Seu pedido de verificação entrou na fila prioritária.",
          {type: "verification_priority"},
      );
    }
    res.sendStatus(200);
    return;
  }

  // Crédito de saldo — transação idempotente (evita crédito em dobro caso
  // o Mercado Pago reenvie a mesma notificação).
  let credited = false;
  await db.runTransaction(async (tx) => {
    const pd = await tx.get(paymentRef);
    if (pd.data().status === "approved") return; // idempotente
    tx.update(paymentRef, {
      status: "approved",
      approvedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.update(db.collection("users").doc(paymentData.userId), {
      balance: admin.firestore.FieldValue.increment(paymentData.amount),
    });
    tx.set(db.collection("transactions").doc(), {
      userId: paymentData.userId,
      amount: paymentData.amount,
      type: "deposit",
      description: "Recarga via Pix",
      createdAt: new Date().toISOString(),
    });
    credited = true;
  });

  if (credited) {
    await _sendNotification(
        db, paymentData.userId,
        "💰 Recarga confirmada!",
        `R$${paymentData.amount.toFixed(2)} adicionados aos seus créditos.`,
        {type: "deposit"},
    );
  }

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

// ─── FASE 16: AUTOMAÇÃO INSTAGRAM ────────────────────────────────────────────
// Credenciais no cofre (Admin → Chaves): INSTAGRAM_ACCESS_TOKEN (long-lived) e
// INSTAGRAM_USER_ID (id da conta Instagram Business/Creator). Config em
// config/instagram (enabled, threshold). Posta 1 imagem (melhor participação
// do desafio) por desafio, quando o prêmio cruza o threshold.

exports.processInstagramPosts = functions.pubsub
    .schedule("every 10 minutes")
    .onRun(async () => {
      const db = admin.firestore();
      const accessToken = await getSecret("INSTAGRAM_ACCESS_TOKEN");
      const igUserId = (await getSecret("INSTAGRAM_USER_ID")) ||
          (await getSecret("INSTAGRAM_PAGE_ID"));

      if (!accessToken || !igUserId) {
        console.log("Instagram não configurado — pulando");
        return null;
      }

      const snapshot = await db.collection("instagram_posts")
          .where("status", "in", ["pending", "failed"])
          .get();

      if (snapshot.empty) return null;

      const eligible = snapshot.docs
          .filter((d) => (d.data().retryCount || 0) < 3);
      // Sequencial: a Graph API do IG limita publicações concorrentes.
      for (const d of eligible) {
        await _postToInstagram(db, d, igUserId, accessToken);
      }
      return null;
    });

async function _postToInstagram(db, postDoc, igUserId, accessToken) {
  const postData = postDoc.data();
  const challengeDoc =
      await db.collection("challenges").doc(postData.challengeId).get();

  if (!challengeDoc.exists) {
    await postDoc.ref.update(
        {status: "failed", error: "desafio não encontrado"});
    return;
  }

  const challenge = challengeDoc.data();
  // Instagram exige imagem. Usa a melhor participação (imagem); senão a arte
  // padrão da marca.
  const top = Array.isArray(challenge.topEntries) ? challenge.topEntries : [];
  const firstImg = top.find(
      (e) => e && e.contentUrl && e.contentType === "image");
  const imageUrl = (firstImg && firstImg.contentUrl) ||
      "https://desafiopago.web.app/og-default.png";
  const caption =
    `🏆 ${challenge.title}\n` +
    `💰 Prêmio: R$ ${Number(challenge.amount).toFixed(2)}\n` +
    "Participe agora no Desafio Pago! 👉 link na bio\n\n" +
    "#desafiopago #desafios #premio #rendaextra #fotografia";

  const base = "https://graph.facebook.com/v21.0";
  try {
    // 1) Cria o container de mídia.
    const cr = await fetch(`${base}/${igUserId}/media`, {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify(
          {image_url: imageUrl, caption, access_token: accessToken}),
    });
    const crJson = await cr.json();
    if (!crJson.id) {
      throw new Error(
          (crJson.error && crJson.error.message) || "container falhou");
    }
    // 2) Publica o container.
    const pub = await fetch(`${base}/${igUserId}/media_publish`, {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify(
          {creation_id: crJson.id, access_token: accessToken}),
    });
    const pubJson = await pub.json();
    if (pubJson.id) {
      await postDoc.ref.update({
        status: "posted",
        postId: pubJson.id,
        postedAt: new Date().toISOString(),
      });
    } else {
      throw new Error(
          (pubJson.error && pubJson.error.message) || "publish falhou");
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

// ─── ADMIN: config do Instagram (ligar/desligar + threshold) ─────────────────
exports.adminSetInstagramConfig =
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
      const updates = {updatedAt: new Date().toISOString()};
      if (typeof data.enabled === "boolean") updates.enabled = data.enabled;
      if (data.threshold != null) {
        const t = Number(data.threshold);
        if (isFinite(t) && t > 0) updates.threshold = Math.round(t * 100) / 100;
      }
      await db.collection("config").doc("instagram").set(updates, {merge: true});
      return {success: true};
    });

// ─── ADMIN: re-enfileirar um post do Instagram que falhou ────────────────────
exports.adminRetryInstagramPost =
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
      const id = String(data.postId || "");
      if (!id) {
        throw new functions.https.HttpsError(
            "invalid-argument", "postId obrigatório");
      }
      await db.collection("instagram_posts").doc(id).update({
        status: "pending",
        retryCount: 0,
        error: admin.firestore.FieldValue.delete(),
      });
      return {success: true};
    });

// ─── MODERAÇÃO COM IA (texto via OpenAI · imagem via Gemini Vision) ──────────
// Requer chave no cofre (Admin → Chaves): OPENAI_API_KEY p/ texto,
// GEMINI_API_KEY p/ imagem. Sem chave, apenas não modera (degrada em silêncio).

async function _moderateText(text) {
  const apiKey = await getSecret("OPENAI_API_KEY");
  if (!apiKey) return null;
  const response = await fetch("https://api.openai.com/v1/moderations", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`,
    },
    body: JSON.stringify({input: text}),
  });
  const result = await response.json();
  if (result.results?.[0]?.flagged !== true) return null;
  const cats = result.results[0].categories || {};
  return Object.keys(cats).filter((k) => cats[k]).join(", ") || "conteúdo";
}

async function _moderateImage(url) {
  const gem = await getSecret("GEMINI_API_KEY");
  if (!gem || !url) return null;
  // Baixa a imagem (self-hosted no CDN) com timeout e limite de tamanho.
  const img = await fetch(url, {signal: AbortSignal.timeout(10000)});
  const buf = Buffer.from(await img.arrayBuffer());
  if (buf.length > 6 * 1024 * 1024) return null; // muito grande, ignora
  const b64 = buf.toString("base64");
  const mime = img.headers.get("content-type") || "image/jpeg";

  const endpoint =
      "https://generativelanguage.googleapis.com/v1beta/models/" +
      `gemini-2.0-flash:generateContent?key=${gem}`;
  const r = await fetch(endpoint, {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({
      contents: [{parts: [
        {text: "You are a strict content moderator for a public photo " +
            "challenge app. Flag the image if it contains sexual/nudity " +
            "content, graphic violence or gore, hate symbols, or clearly " +
            "illegal content. Normal photos (people, food, places, pets, " +
            "objects) are fine. Respond ONLY with JSON: " +
            "{\"flagged\": boolean, \"category\": string}."},
        {inline_data: {mime_type: mime, data: b64}},
      ]}],
      generationConfig: {responseMimeType: "application/json", temperature: 0},
    }),
  });
  const j = await r.json();
  const txt = j.candidates && j.candidates[0] &&
      j.candidates[0].content.parts[0].text;
  if (!txt) return null;
  let parsed;
  try {
    parsed = JSON.parse(txt);
  } catch (e) {
    return null;
  }
  return parsed.flagged === true ? (parsed.category || "conteúdo") : null;
}

exports.moderateEntry = functions.firestore
    .document("entries/{entryId}")
    .onCreate(async (snap, context) => {
      const entry = snap.data();
      // Não modera conteúdo virtual/seed nem participações de admin.
      if (entry.isVirtual === true || entry.isDemo === true) return null;

      try {
        let flaggedCats = null;
        if (entry.contentText) {
          flaggedCats = await _moderateText(entry.contentText);
        } else if (entry.contentType === "image" && entry.contentUrl) {
          flaggedCats = await _moderateImage(entry.contentUrl);
        }

        if (flaggedCats) {
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
        console.error("Erro na moderação:", err.message);
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

// ─── ADMIN: RESOLVER DENÚNCIAS DE UMA PARTICIPAÇÃO ───────────────────────────
// action: 'dismiss' (mantém no ar), 'hide' (oculta a participação),
// 'restore' (reativa) ou 'ban' (oculta + bane o autor). Resolve TODAS as
// denúncias pendentes daquela participação de uma vez.
exports.adminResolveReport = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Não autenticado");
  }
  const db = admin.firestore();
  const adminDoc = await db.collection("admins").doc(context.auth.uid).get();
  if (!adminDoc.exists) {
    throw new functions.https.HttpsError("permission-denied", "Acesso negado");
  }
  const entryId = String(data.entryId || "");
  const action = String(data.action || "");
  if (!entryId ||
      !["dismiss", "hide", "restore", "ban"].includes(action)) {
    throw new functions.https.HttpsError(
        "invalid-argument", "entryId e action válidos são obrigatórios");
  }

  const entryRef = db.collection("entries").doc(entryId);
  const entryDoc = await entryRef.get();
  const entry = entryDoc.exists ? entryDoc.data() : null;

  const now = new Date().toISOString();
  const newStatus = action === "ban" ? "resolved_banned" :
    action === "hide" ? "resolved_hidden" : "dismissed";

  const reps = await db.collection("reports")
      .where("entryId", "==", entryId)
      .where("status", "==", "pending").get();

  const batch = db.batch();
  if (entryDoc.exists && (action === "hide" || action === "ban")) {
    batch.update(entryRef, {isActive: false});
  } else if (entryDoc.exists && action === "restore") {
    batch.update(entryRef, {isActive: true});
  }
  reps.forEach((r) => batch.update(r.ref, {
    status: newStatus,
    resolvedAt: now,
    resolvedBy: context.auth.uid,
  }));
  await batch.commit();

  if (action === "ban" && entry && entry.userId) {
    await db.collection("users").doc(entry.userId).update({
      isBanned: true,
      banReason: String(data.reason || "Conteúdo denunciado"),
      bannedAt: now,
    });
  }

  await db.collection("audit_logs").add({
    type: `report_${action}`,
    entryId,
    targetUserId: entry ? entry.userId : null,
    adminId: context.auth.uid,
    resolvedReports: reps.size,
    createdAt: now,
  });

  return {success: true, resolved: reps.size};
});

// ─── ACCEPT TERMS ────────────────────────────────────────────────────────────
// Uses Admin SDK so it bypasses Firestore rules — works even if the user
// document doesn't exist yet (race between saveUser and auth-state change).

exports.acceptTerms = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Usuário não logado");
  }

  const uid = context.auth.uid;
  const phoneDigits = String(data.phone || "").replace(/\D/g, "");
  if (phoneDigits.length < 10 || phoneDigits.length > 11) {
    throw new functions.https.HttpsError(
        "invalid-argument", "Telefone inválido (informe com DDD)");
  }

  const db = admin.firestore();
  const userRef = db.collection("users").doc(uid);
  const existing = await userRef.get();
  const now = new Date().toISOString();

  if (existing.exists) {
    await userRef.update({
      termsAccepted: true,
      termsAcceptedAt: now,
      phone: phoneDigits,
    });
  } else {
    // Fallback: document was never created (saveUser failed or race condition)
    const token = context.auth.token;
    await userRef.set({
      name: token.name || "",
      email: token.email || "",
      photoUrl: token.picture || "",
      termsAccepted: true,
      termsAcceptedAt: now,
      phone: phoneDigits,
      createdAt: now,
      balance: 0,
      pendingBalance: 0,
      lockedBalance: 0,
      totalEarned: 0,
      totalVotesReceived: 0,
      followersCount: 0,
      followingCount: 0,
      bio: "",
      pixKey: "",
      isVirtual: false,
      isVerified: false,
      photoIsCustom: false,
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
  const parentId = data.parentId || "";

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
    parentId,
    userId,
    userName,
    text: text.trim(),
    likeCount: 0,
    isActive: true,
    createdAt: new Date().toISOString(),
  });

  // Notifica o dono da participação (ou o criador do desafio).
  try {
    let notifyId = null;
    if (entryId) {
      const e = await db.collection("entries").doc(entryId).get();
      notifyId = e.exists ? e.data().userId : null;
    } else {
      const c = await db.collection("challenges").doc(challengeId).get();
      notifyId = c.exists ? c.data().createdBy : null;
    }
    if (notifyId && notifyId !== userId) {
      await _sendNotification(
          db, notifyId, "Novo comentário",
          `${userName} comentou ${entryId ?
            "na sua participação" : "no seu desafio"}`,
          {type: "comment", challengeId, entryId: entryId || ""});
    }
  } catch (e) {
    console.error("notif comentário:", e.message);
  }

  return {success: true};
});

// ─── TOGGLE COMMENT LIKE ──────────────────────────────────────────────────────

exports.toggleCommentLike = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Usuário não logado");
  }
  const uid = context.auth.uid;
  const db = admin.firestore();
  await _assertNotBanned(db, uid);

  const {commentId} = data;
  if (!commentId) {
    throw new functions.https.HttpsError("invalid-argument", "commentId obrigatório");
  }

  const commentRef = db.collection("comments").doc(commentId);
  const likeRef = db.collection("commentLikes").doc(`${commentId}_${uid}`);

  let liked;
  await db.runTransaction(async (tx) => {
    const commentDoc = await tx.get(commentRef);
    if (!commentDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Comentário não encontrado");
    }
    const likeDoc = await tx.get(likeRef);
    if (likeDoc.exists) {
      tx.delete(likeRef);
      tx.update(commentRef, {
        likeCount: admin.firestore.FieldValue.increment(-1),
      });
      liked = false;
    } else {
      tx.set(likeRef, {
        commentId,
        uid,
        challengeId: commentDoc.data().challengeId || "",
        createdAt: new Date().toISOString(),
      });
      tx.update(commentRef, {
        likeCount: admin.firestore.FieldValue.increment(1),
      });
      liked = true;
    }
  });

  return {liked};
});

// ─── SEGUIR / DEIXAR DE SEGUIR ───────────────────────────────────────────────
// Contadores de seguidores ficam protegidos: só esta função (Admin SDK) os move.
exports.toggleFollow = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Usuário não logado");
  }
  const uid = context.auth.uid;
  const db = admin.firestore();
  await _assertNotBanned(db, uid);

  const targetId = data.targetUserId;
  const follow = data.follow === true;
  if (!targetId) {
    throw new functions.https.HttpsError(
        "invalid-argument", "targetUserId obrigatório");
  }
  if (targetId === uid) {
    throw new functions.https.HttpsError(
        "failed-precondition", "Você não pode seguir a si mesmo");
  }

  const followRef = db.collection("follows").doc(`${uid}_${targetId}`);
  const targetRef = db.collection("users").doc(targetId);
  const meRef = db.collection("users").doc(uid);
  const inc = admin.firestore.FieldValue.increment;

  let created = false;
  await db.runTransaction(async (tx) => {
    const existing = await tx.get(followRef);
    if (follow) {
      if (existing.exists) return;
      tx.set(followRef, {
        followerId: uid,
        followedId: targetId,
        createdAt: new Date().toISOString(),
      });
      tx.update(targetRef, {followersCount: inc(1)});
      tx.update(meRef, {followingCount: inc(1)});
      created = true;
    } else {
      if (!existing.exists) return;
      tx.delete(followRef);
      tx.update(targetRef, {followersCount: inc(-1)});
      tx.update(meRef, {followingCount: inc(-1)});
    }
  });

  if (created) {
    const me = (await db.collection("users").doc(uid).get()).data() || {};
    await _sendNotification(
        db, targetId, "Novo seguidor",
        `${me.name || "Alguém"} começou a te seguir`, {type: "follow"});
  }

  return {following: follow};
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
  const ownerId = entryDoc.data().userId;

  const batch = db.batch();
  batch.update(entryRef, {voteCount});
  if (diff !== 0) {
    batch.update(db.collection("challenges").doc(challengeId), {
      voteCount: admin.firestore.FieldValue.increment(diff),
    });
    // Mantém o ranking de votos consistente com o total exibido.
    if (ownerId) {
      batch.update(db.collection("users").doc(ownerId), {
        totalVotesReceived: admin.firestore.FieldValue.increment(diff),
      });
    }
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

// ─── ADMIN: EDITAR "AO VIVO" (pulso da plataforma) ───────────────────────────
exports.adminSetPulse = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Não autenticado");
  }
  const db = admin.firestore();
  const adminDoc = await db.collection("admins").doc(context.auth.uid).get();
  if (!adminDoc.exists) {
    throw new functions.https.HttpsError(
        "permission-denied", "Apenas administradores.");
  }
  const ref = db.collection("config").doc("platformPulse");
  if (data.clear === true) {
    await ref.delete();
    return {success: true, cleared: true};
  }
  const toInt = (v) => (v === undefined || v === null || v === "") ?
    null : Math.round(Number(v));
  const toNum = (v) => (v === undefined || v === null || v === "") ?
    null : Number(v);
  await ref.set({
    activeChallenges: toInt(data.activeChallenges),
    prizePool: toNum(data.prizePool),
    participants: toInt(data.participants),
    updatedAt: new Date().toISOString(),
  });
  return {success: true};
});

// ─── ADMIN: CONFIG DO FEED (rodapé "alta demanda" etc.) ──────────────────────
// Liga/desliga elementos do feed via config/feed (Admin SDK — ignora rules).
exports.adminSetFeedConfig = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Não autenticado");
  }
  const db = admin.firestore();
  const adminDoc = await db.collection("admins").doc(context.auth.uid).get();
  if (!adminDoc.exists) {
    throw new functions.https.HttpsError(
        "permission-denied", "Apenas administradores.");
  }
  const updates = {updatedAt: new Date().toISOString()};
  if (typeof data.highDemandFooter === "boolean") {
    updates.highDemandFooter = data.highDemandFooter;
  }
  await db.collection("config").doc("feed").set(updates, {merge: true});
  return {success: true};
});

// ─── ADMIN: EXCLUIR PARTICIPAÇÃO ─────────────────────────────────────────────
// Remove a participação + seus votos e comentários, e reverte os contadores.
exports.adminDeleteEntry = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Usuário não logado");
  }
  const db = admin.firestore();
  const adminDoc = await db.collection("admins").doc(context.auth.uid).get();
  if (!adminDoc.exists) {
    throw new functions.https.HttpsError("permission-denied", "Acesso negado");
  }

  const {entryId} = data;
  if (!entryId) {
    throw new functions.https.HttpsError("invalid-argument", "entryId obrigatório");
  }

  const entryRef = db.collection("entries").doc(entryId);
  const entryDoc = await entryRef.get();
  if (!entryDoc.exists) {
    throw new functions.https.HttpsError("not-found", "Participação não encontrada");
  }
  const entry = entryDoc.data();
  const challengeId = entry.challengeId;
  const ownerId = entry.userId;
  const entryVotes = entry.voteCount || 0;

  const votesSnap = await db.collection("votes")
      .where("entryId", "==", entryId).get();
  let nonAdminVotes = 0;
  votesSnap.forEach((d) => {
    if (d.data().isAdminVote !== true) nonAdminVotes++;
  });
  const commentsSnap = await db.collection("comments")
      .where("entryId", "==", entryId).get();

  let batch = db.batch();
  let ops = 0;
  const maybeFlush = async () => {
    if (ops >= 450) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  };
  for (const d of votesSnap.docs) {
    batch.delete(d.ref);
    ops++;
    await maybeFlush();
  }
  for (const d of commentsSnap.docs) {
    batch.delete(d.ref);
    ops++;
    await maybeFlush();
  }
  batch.delete(entryRef);
  ops++;
  if (challengeId) {
    batch.update(db.collection("challenges").doc(challengeId), {
      entryCount: admin.firestore.FieldValue.increment(-1),
      voteCount: admin.firestore.FieldValue.increment(-entryVotes),
    });
  }
  if (ownerId && nonAdminVotes > 0) {
    batch.update(db.collection("users").doc(ownerId), {
      totalVotesReceived: admin.firestore.FieldValue.increment(-nonAdminVotes),
    });
  }
  await batch.commit();

  await db.collection("audit_logs").add({
    type: "admin_entry_delete",
    entryId,
    challengeId,
    adminId: context.auth.uid,
    deletedVotes: votesSnap.size,
    deletedComments: commentsSnap.size,
    createdAt: new Date().toISOString(),
  });

  return {success: true};
});

// ─── ADMIN: EDITAR COMENTÁRIO (texto e/ou curtidas) ──────────────────────────
exports.adminUpdateComment = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Usuário não logado");
  }
  const db = admin.firestore();
  const adminDoc = await db.collection("admins").doc(context.auth.uid).get();
  if (!adminDoc.exists) {
    throw new functions.https.HttpsError("permission-denied", "Acesso negado");
  }
  const {commentId} = data;
  if (!commentId) {
    throw new functions.https.HttpsError("invalid-argument", "commentId obrigatório");
  }
  const ref = db.collection("comments").doc(commentId);
  const doc = await ref.get();
  if (!doc.exists) {
    throw new functions.https.HttpsError("not-found", "Comentário não encontrado");
  }
  const updates = {};
  if (typeof data.text === "string" && data.text.trim().length > 0) {
    if (data.text.trim().length > 500) {
      throw new functions.https.HttpsError(
          "invalid-argument", "Comentário muito longo (máx 500)");
    }
    updates.text = data.text.trim();
  }
  if (data.likeCount !== undefined && data.likeCount !== null) {
    const lc = Number(data.likeCount);
    if (!Number.isFinite(lc) || lc < 0) {
      throw new functions.https.HttpsError(
          "invalid-argument", "Curtidas inválidas");
    }
    updates.likeCount = Math.round(lc);
  }
  if (Object.keys(updates).length === 0) return {success: true, updated: 0};
  await ref.update(updates);
  return {success: true, updated: Object.keys(updates).length};
});

// ─── ADMIN: EXCLUIR COMENTÁRIO (+ respostas) ─────────────────────────────────
exports.adminDeleteComment = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Usuário não logado");
  }
  const db = admin.firestore();
  const adminDoc = await db.collection("admins").doc(context.auth.uid).get();
  if (!adminDoc.exists) {
    throw new functions.https.HttpsError("permission-denied", "Acesso negado");
  }
  const {commentId} = data;
  if (!commentId) {
    throw new functions.https.HttpsError("invalid-argument", "commentId obrigatório");
  }
  const ref = db.collection("comments").doc(commentId);
  const doc = await ref.get();
  if (!doc.exists) return {success: true};

  const batch = db.batch();
  batch.delete(ref);
  // Comentário-raiz: remove também as respostas.
  if (!doc.data().parentId) {
    const replies = await db.collection("comments")
        .where("parentId", "==", commentId).get();
    replies.forEach((r) => batch.delete(r.ref));
  }
  await batch.commit();

  await db.collection("audit_logs").add({
    type: "admin_comment_delete",
    commentId,
    adminId: context.auth.uid,
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
  const asUserId = data.userId; // usuário virtual escolhido (opcional)

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

  // Se um usuário virtual for escolhido, a participação é atribuída a ele
  // (nome/foto reais). Senão, cria um participante demo sintético.
  let entryUserId;
  let extra = {};
  if (asUserId) {
    const u = await db.collection("users").doc(asUserId).get();
    if (!u.exists || u.data().isVirtual !== true) {
      throw new functions.https.HttpsError(
          "invalid-argument", "Escolha um usuário virtual válido.");
    }
    entryUserId = asUserId;
  } else {
    entryUserId = `demo_${Date.now()}`;
    extra = {
      demoName: (demoName || "").trim() || "Participante Demo",
      isDemo: true,
    };
  }

  const entryRef = db.collection("entries").doc();
  const challengeRef = db.collection("challenges").doc(challengeId);

  await db.runTransaction(async (tx) => {
    tx.set(entryRef, {
      challengeId,
      userId: entryUserId,
      ...extra,
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
    asUserId: entryUserId,
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
      photoUrl: `https://desafiopago.web.app/portraits/${i % 2 === 0 ? "men" : "women"}/${Math.floor(i / 2) % 100}.jpg`,
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
      // Admin pode editar qualquer perfil (virtual ou real). Só mexe em
      // campos públicos (nome/@/bio/selo/foto) — nunca em saldo/PII/banimento.

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
        const bucket =
            admin.storage().bucket("desafio-app-b8665.firebasestorage.app");
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

// ─── ADMIN: EDITAR DESAFIO (título, descrição, prêmio, prazo) ─────────────────
// Edita qualquer desafio. NÃO movimenta saldo: alterar o prêmio muda apenas o
// valor exibido/distribuído no encerramento, não debita/credita ninguém.
exports.adminUpdateChallenge =
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

      const challengeId = data.challengeId;
      if (!challengeId) {
        throw new functions.https.HttpsError(
            "invalid-argument", "challengeId obrigatório");
      }
      const ref = db.collection("challenges").doc(challengeId);
      const doc = await ref.get();
      if (!doc.exists) {
        throw new functions.https.HttpsError(
            "not-found", "Desafio não encontrado");
      }

      const updates = {};
      if (typeof data.title === "string" && data.title.trim().length > 0) {
        updates.title = data.title.trim();
      }
      if (typeof data.description === "string") {
        updates.description = data.description.trim();
      }
      if (data.amount != null) {
        const amount = Number(data.amount);
        if (!isFinite(amount) || amount < 0) {
          throw new functions.https.HttpsError(
              "invalid-argument", "Prêmio inválido.");
        }
        updates.amount = Math.round(amount * 100) / 100;
      }
      if (typeof data.expiresAt === "string" && data.expiresAt.length > 0) {
        const t = Date.parse(data.expiresAt);
        if (isNaN(t)) {
          throw new functions.https.HttpsError(
              "invalid-argument", "Data inválida.");
        }
        updates.expiresAt = new Date(t).toISOString();
      }

      if (Object.keys(updates).length === 0) {
        return {success: true, updated: 0};
      }
      await ref.update(updates);
      return {success: true, updated: Object.keys(updates).length};
    });

// ─── SUPER ADMIN: FIXAR DESAFIO COMO "NOVO" (topo do feed) ────────────────────
// Recurso MANUAL e EXCLUSIVO do super admin. Nunca é acionado sozinho: não há
// trigger nem cron que fixe/desfixe — o desafio só sobe pro topo quando o super
// admin marca, e só sai quando ele desmarca. Grava `pinned` + `pinnedAt`.
exports.adminSetChallengePinned =
    functions.https.onCall(async (data, context) => {
      if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated", "Não autenticado");
      }
      const SUPER_ADMIN_EMAIL = "gustavo.a.tinti3@gmail.com";
      if (context.auth.token.email !== SUPER_ADMIN_EMAIL) {
        throw new functions.https.HttpsError(
            "permission-denied", "Apenas o super admin.");
      }
      const db = admin.firestore();
      const challengeId = data.challengeId;
      if (!challengeId) {
        throw new functions.https.HttpsError(
            "invalid-argument", "challengeId obrigatório");
      }
      const pinned = data.pinned === true;
      const ref = db.collection("challenges").doc(challengeId);
      const doc = await ref.get();
      if (!doc.exists) {
        throw new functions.https.HttpsError(
            "not-found", "Desafio não encontrado");
      }
      await ref.update({
        pinned: pinned,
        pinnedAt: pinned ? new Date().toISOString() : null,
      });
      return {success: true, pinned: pinned};
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
        const phone = fmtPhone(u.phone || (v ? v.phone : ""));
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

// ─── MIRROR PERFIL PÚBLICO (somente campos não sensíveis) ─────────────────────

const publicProfileOf = (d) => ({
  name: d.name || "",
  username: d.username || "",
  photoUrl: d.photoUrl || "",
  bio: d.bio || "",
  isVerified: d.isVerified === true,
  isVirtual: d.isVirtual === true,
  totalEarned: d.totalEarned || 0,
  totalVotesReceived: d.totalVotesReceived || 0,
  followersCount: d.followersCount || 0,
  followingCount: d.followingCount || 0,
});

exports.mirrorPublicProfile = functions.firestore
    .document("users/{uid}")
    .onWrite(async (change, context) => {
      const ref = admin.firestore()
          .collection("publicProfiles").doc(context.params.uid);
      if (!change.after.exists) {
        await ref.delete().catch(() => {});
        return null;
      }
      await ref.set(publicProfileOf(change.after.data()));
      return null;
    });

// ─── BACKFILL PERFIS PÚBLICOS (one-shot) ──────────────────────────────────────

exports.backfillPublicProfiles = functions.runWith({timeoutSeconds: 540})
    .https.onRequest(async (req, res) => {
      if (req.method !== "POST") {
        return res.status(405).json({error: "Method Not Allowed"});
      }
      if (!req.body || req.body.secret !== "SEED_2026_DP") {
        return res.status(403).json({error: "Forbidden"});
      }
      const db = admin.firestore();
      const snap = await db.collection("users").get();
      let batch = db.batch();
      let ops = 0;
      let total = 0;
      for (const doc of snap.docs) {
        batch.set(db.collection("publicProfiles").doc(doc.id),
            publicProfileOf(doc.data()));
        ops++;
        total++;
        if (ops >= 450) {
          await batch.commit();
          batch = db.batch();
          ops = 0;
        }
      }
      if (ops > 0) await batch.commit();
      return res.json({success: true, total});
    });

// ─── SEED DESAFIOS VIRTUAIS (texto + foto, ativos + encerrados) ───────────────

exports.seedVirtualChallenges = functions.runWith({timeoutSeconds: 540})
    .https.onRequest(async (req, res) => {
      if (req.method !== "POST") {
        return res.status(405).json({error: "Method Not Allowed"});
      }
      if (!req.body || req.body.secret !== "SEED_2026_DP") {
        return res.status(403).json({error: "Forbidden"});
      }

      const db = admin.firestore();

      // Evita duplicar
      const check = await db.collection("challenges")
          .where("isVirtual", "==", true).limit(1).get();
      if (!check.empty) {
        return res.status(409).json({
          error: "Desafios virtuais já existem. Limpe antes de re-seedar.",
        });
      }

      const usersSnap = await db.collection("users")
          .where("isVirtual", "==", true).limit(400).get();
      const uids = usersSnap.docs.map((d) => d.id);
      if (uids.length < 20) {
        return res.status(412).json({
          error: "Poucos usuários virtuais. Rode seedVirtualUsers primeiro.",
        });
      }

      const ri = (n) => Math.floor(Math.random() * n);
      const shuffle = (arr) => {
        const a = arr.slice();
        for (let i = a.length - 1; i > 0; i--) {
          const j = ri(i + 1);
          [a[i], a[j]] = [a[j], a[i]];
        }
        return a;
      };
      const HOST = "https://desafiopago.web.app";
      const IMG_COUNT = 40;
      let imgCursor = 0;
      const nextImg = () => {
        const n = String((imgCursor++ % IMG_COUNT) + 1).padStart(2, "0");
        return `${HOST}/challenge_images/${n}.jpg`;
      };

      const specs = [
        {
          type: "text", status: "active", amount: 150,
          title: "A melhor frase motivacional 💪",
          desc: "Mande aquela frase que te faz levantar da cama com vontade.",
          entries: [
            "Disciplina vence motivação todo santo dia.",
            "Comece onde você está, com o que você tem.",
            "Cada dia é uma nova chance de virar o jogo.",
            "Não pare quando cansar, pare quando terminar.",
            "Foco no progresso, não na perfeição.",
            "Quem quer dá um jeito, quem não quer dá uma desculpa.",
          ],
        },
        {
          type: "text", status: "active", amount: 80,
          title: "Resuma sua segunda-feira em uma palavra ☕",
          desc: "Sem textão. Uma palavra que define a sua segunda.",
          entries: [
            "Sobrevivência", "Café", "Recomeço", "Caos", "Foco", "Ânimo",
          ],
        },
        {
          type: "text", status: "active", amount: 300,
          title: "Qual é o seu sonho pra 2026? 🌟",
          desc: "Conta pra gente o que você quer muito realizar.",
          entries: [
            "Comprar minha casa própria 🏠",
            "Viajar pra fora do Brasil pela primeira vez ✈️",
            "Abrir meu próprio negócio.",
            "Quitar todas as dívidas e respirar aliviado.",
            "Passar mais tempo com quem eu amo.",
          ],
        },
        {
          type: "text", status: "finished", amount: 500,
          title: "A coisa mais engraçada que já te aconteceu 😂",
          desc: "Solta a história. A mais engraçada levou o prêmio!",
          entries: [
            "Acenei de volta pra alguém que acenava pra pessoa atrás de mim 🙈",
            "Mandei 'te amo' no grupo da firma sem querer.",
            "Escorreguei numa casca de banana DE VERDADE.",
            "Chamei a professora de 'mãe' na frente da turma toda.",
            "Fui pagar o lanche com o cartão do gás.",
          ],
        },
        {
          type: "text", status: "finished", amount: 250,
          title: "Melhor dica pra economizar dinheiro 💰",
          desc: "A dica que realmente funciona no fim do mês.",
          entries: [
            "Anote TODOS os gastos por 30 dias. Você vai se assustar.",
            "Espere 24h antes de qualquer compra por impulso.",
            "Leve marmita 3x na semana, faz milagre.",
            "Cancele as assinaturas que você não usou no mês.",
            "No Pix à vista, sempre peça desconto.",
          ],
        },
        {
          type: "text", status: "finished", amount: 120,
          title: "O melhor trocadilho que você conhece 🤪",
          desc: "Vale o mais sem-vergonha também.",
          entries: [
            "Por que o livro de matemática tava triste? Cheio de problemas.",
            "O que o tomate foi fazer no banco? Tirar extrato.",
            "Cúmulo da paciência: professor de autoescola de tartaruga.",
            "A praia terminou com o mar: ele era muito 'sal'gado.",
          ],
        },
        {
          type: "image", status: "active", amount: 400, imageN: 7,
          title: "O clique mais bonito do mês 📸",
          desc: "Aquela foto que você bateu e ficou orgulhoso. Capricha!",
        },
        {
          type: "image", status: "active", amount: 200, imageN: 6,
          title: "Foto mais criativa 🎨",
          desc: "Ângulo diferente, ideia diferente. Surpreenda a galera!",
        },
        {
          type: "image", status: "active", amount: 1000, imageN: 6,
          title: "Mostre seu cantinho favorito 🛋️",
          desc: "Seu setup, seu canto de ler, sua área. Mostra aí!",
        },
        {
          type: "image", status: "finished", amount: 1500, imageN: 7,
          title: "Melhor foto da sua viagem ✈️",
          desc: "A viagem que ficou na memória em uma única foto.",
        },
        {
          type: "image", status: "finished", amount: 700, imageN: 6,
          title: "Melhor paisagem 🌄",
          desc: "Tem cada lugar lindo por aí... mostra o seu.",
        },
      ];

      const now = Date.now();
      const day = 24 * 60 * 60 * 1000;
      const batch = db.batch();
      let cCount = 0;
      let eCount = 0;

      for (const spec of specs) {
        const pool = shuffle(uids);
        const creator = pool[0];
        const isFinished = spec.status === "finished";

        let createdMs;
        let expiresMs;
        if (isFinished) {
          createdMs = now - (20 + ri(25)) * day;
          expiresMs = createdMs + (7 + ri(9)) * day;
          if (expiresMs >= now) expiresMs = now - day;
        } else {
          createdMs = now - (1 + ri(7)) * day;
          expiresMs = now + (2 + ri(16)) * day;
        }

        const n = spec.type === "text" ? spec.entries.length : spec.imageN;
        const entrants = pool.slice(1, 1 + n);
        const challengeRef = db.collection("challenges").doc();

        const entryDocs = [];
        let totalVotes = 0;
        let maxVotes = -1;
        for (let i = 0; i < n; i++) {
          const top = isFinished ? 800 + ri(5000) : 30 + ri(700);
          const votes = 1 + ri(top);
          totalVotes += votes;
          if (votes > maxVotes) maxVotes = votes;
          entryDocs.push({
            ref: db.collection("entries").doc(),
            uid: entrants[i],
            votes,
            contentText: spec.type === "text" ? spec.entries[i] : null,
            contentUrl: spec.type === "image" ? nextImg() : null,
            createdAt: new Date(createdMs + (i + 1) * 3600 * 1000)
                .toISOString(),
          });
        }
        const winnerIds = isFinished ?
          entryDocs.filter((e) => e.votes === maxVotes).map((e) => e.uid) : [];

        batch.set(challengeRef, {
          title: spec.title,
          description: spec.desc,
          createdBy: creator,
          amount: spec.amount,
          creatorContribution: 0,
          status: spec.status,
          voteCount: totalVotes,
          entryCount: n,
          winnerIds,
          createdAt: new Date(createdMs).toISOString(),
          expiresAt: new Date(expiresMs).toISOString(),
          isVirtual: true,
        });
        cCount++;

        for (const e of entryDocs) {
          batch.set(e.ref, {
            challengeId: challengeRef.id,
            userId: e.uid,
            contentType: spec.type,
            contentText: e.contentText,
            contentUrl: e.contentUrl,
            voteCount: e.votes,
            isActive: true,
            createdAt: e.createdAt,
            isVirtual: true,
          });
          eCount++;
        }
      }

      await batch.commit();
      return res.json({success: true, challenges: cCount, entries: eCount});
    });

// ─── SEED COMENTÁRIOS VIRTUAIS ────────────────────────────────────────────────

exports.seedVirtualComments = functions.runWith({timeoutSeconds: 540})
    .https.onRequest(async (req, res) => {
      if (req.method !== "POST") {
        return res.status(405).json({error: "Method Not Allowed"});
      }
      if (!req.body || req.body.secret !== "SEED_2026_DP") {
        return res.status(403).json({error: "Forbidden"});
      }
      const db = admin.firestore();

      const check = await db.collection("comments")
          .where("isVirtual", "==", true).limit(1).get();
      if (!check.empty) {
        return res.status(409).json({error: "Comentários virtuais já existem."});
      }

      const usersSnap = await db.collection("users")
          .where("isVirtual", "==", true).limit(400).get();
      const users = usersSnap.docs
          .map((d) => ({id: d.id, name: d.data().name || "Usuário"}));
      if (users.length < 10) {
        return res.status(412).json({error: "Rode seedVirtualUsers primeiro."});
      }

      const entriesSnap = await db.collection("entries")
          .where("isVirtual", "==", true).get();
      const challSnap = await db.collection("challenges")
          .where("isVirtual", "==", true).get();

      const ri = (n) => Math.floor(Math.random() * n);
      const pick = (a) => a[ri(a.length)];

      const generic = [
        "Top demais! 🔥", "Arrasou!", "Merece ganhar 👏",
        "Simplesmente perfeito", "Tá levando essa 💪", "Que demais!",
        "Sensacional", "Muito bom mesmo", "Curti demais", "Brabo 🔥",
        "Show de bola", "Nota 10", "Meu voto é seu 🗳️", "Apoiado! 👏",
      ];
      const imageC = [
        "Que foto incrível! 📸", "Ângulo perfeito 😍", "Qualidade absurda",
        "Que clique!", "Ficou lindo demais", "Foto de capa! 🤩",
      ];
      const textC = [
        "kkkk muito boa 😂", "Concordo demais", "Verdade pura 👏",
        "Anotado!", "Essa foi forte", "Genial kkk", "Real demais",
      ];

      const now = Date.now();
      let batch = db.batch();
      let ops = 0;
      let total = 0;
      const flush = async () => {
        if (ops > 0) {
          await batch.commit();
          batch = db.batch();
          ops = 0;
        }
      };
      const add = async (challengeId, entryId, isImage) => {
        const u = pick(users);
        let pool = generic;
        if (entryId !== "") pool = (isImage ? imageC : textC).concat(generic);
        batch.set(db.collection("comments").doc(), {
          challengeId,
          entryId,
          userId: u.id,
          userName: u.name,
          text: pick(pool),
          isActive: true,
          createdAt: new Date(now - ri(8 * 86400000)).toISOString(),
          isVirtual: true,
        });
        ops++;
        total++;
        if (ops >= 450) await flush();
      };

      for (const doc of entriesSnap.docs) {
        const d = doc.data();
        const isImage = d.contentType === "image";
        const count = 1 + ri(4);
        for (let i = 0; i < count; i++) {
          await add(d.challengeId, doc.id, isImage);
        }
      }
      for (const doc of challSnap.docs) {
        const count = 1 + ri(3);
        for (let i = 0; i < count; i++) {
          await add(doc.id, "", false);
        }
      }
      await flush();
      return res.json({success: true, comments: total});
    });

// ─── SEED ENGAJAMENTO NOS DESAFIOS ATIVOS (re-executável) ─────────────────────
// Enche os desafios ATIVOS de comentários realistas (perfis virtuais, com
// curtidas e algumas respostas) e acrescenta votos às participações.
// Aditivo: pode rodar de novo para "reabastecer" o engajamento.
exports.seedActiveEngagement = functions.runWith({timeoutSeconds: 540})
    .https.onRequest(async (req, res) => {
      if (req.method !== "POST") {
        return res.status(405).json({error: "Method Not Allowed"});
      }
      if (!req.body || req.body.secret !== "SEED_2026_DP") {
        return res.status(403).json({error: "Forbidden"});
      }
      const db = admin.firestore();

      const usersSnap = await db.collection("users")
          .where("isVirtual", "==", true).limit(400).get();
      const vUsers = usersSnap.docs
          .map((d) => ({id: d.id, name: d.data().name || "Usuário"}));
      if (vUsers.length < 10) {
        return res.status(412).json({error: "Rode seedVirtualUsers primeiro."});
      }

      const challSnap = await db.collection("challenges")
          .where("status", "==", "active").get();
      if (challSnap.empty) {
        return res.json({success: true, comments: 0, votes: 0});
      }
      const activeIds = new Set(challSnap.docs.map((d) => d.id));
      const entriesSnap = await db.collection("entries")
          .where("isActive", "==", true).get();
      const entries = entriesSnap.docs
          .filter((d) => activeIds.has(d.data().challengeId));

      const ri = (n) => Math.floor(Math.random() * n);
      const pick = (a) => a[ri(a.length)];
      const now = Date.now();

      const generic = [
        "Top demais! 🔥", "Arrasou!", "Merece ganhar 👏", "Que demais!",
        "Simplesmente perfeito", "Tá levando essa 💪", "Sensacional",
        "Muito bom mesmo", "Curti demais", "Brabo 🔥", "Show de bola",
        "Nota 10", "Meu voto é seu 🗳️", "Apoiado! 👏", "mt bom isso",
        "aí sim hein 👏👏", "ganhou meu respeito", "vou votar nessa",
        "tá acirrado esse desafio 👀", "quero ver quem leva essa",
        "melhor participação até agora", "essa merece o prêmio",
        "votei! boa sorte 🍀", "capricho total", "sem palavras 👏",
        "isso vai longe", "já tá na frente por mérito", "genial",
        "criatividade em outro nível", "apostando nessa 🤞",
        "como assim isso não tá em primeiro??", "top top top",
        "kkkkk adorei", "que capricho gente", "surreal 😱",
        "o nível tá alto nesse desafio", "difícil escolher, mas essa é boa",
        "essa competição tá boa demais", "prêmio já tem dono kkk",
        "vim pelo desafio, fiquei pela qualidade", "muito estilo",
      ];
      const imageC = [
        "Que foto incrível! 📸", "Ângulo perfeito 😍", "Qualidade absurda",
        "Que clique!", "Ficou lindo demais", "Foto de capa! 🤩",
        "essa imagem tá muito boa", "parece profissional 📷",
        "que edição limpa", "cores perfeitas 😍", "enquadramento top",
      ];
      const videoC = [
        "Que vídeo bom! 🎬", "Edição muito boa 👏", "assisti 3x kkk",
        "esse vídeo merece viralizar", "produção caprichada 🎥",
        "que transição foi essa?? 🔥", "conteúdo de qualidade",
      ];
      const textC = [
        "kkkk muito boa 😂", "Concordo demais", "Verdade pura 👏",
        "Anotado!", "Essa foi forte", "Genial kkk", "Real demais",
        "escreveu tudo", "resumiu perfeitamente", "sábio demais kkk",
        "isso é muito real", "falou por todos nós",
      ];
      const replies = [
        "kkk verdade", "concordo!", "apoiadíssimo", "vote gente 🙏",
        "exatamente isso", "falou tudo", "kkkkkk", "sim!! 👏",
        "também acho", "essa é a real", "verdade demais", "certíssimo",
      ];

      let batch = db.batch();
      let ops = 0;
      let totalComments = 0;
      let totalVotes = 0;
      const flush = async () => {
        if (ops > 0) {
          await batch.commit();
          batch = db.batch();
          ops = 0;
        }
      };
      const bump = async () => {
        ops++;
        if (ops >= 450) await flush();
      };

      // Comentário (com chance de curtidas e de resposta).
      const addComment = async (challengeId, entryId, pool) => {
        const u = pick(vUsers);
        const createdAt = now - ri(36 * 3600000); // últimas 36h
        const ref = db.collection("comments").doc();
        batch.set(ref, {
          challengeId,
          entryId,
          parentId: "",
          userId: u.id,
          userName: u.name,
          text: pick(pool),
          likeCount: Math.random() < 0.35 ? 1 + ri(18) : 0,
          isActive: true,
          createdAt: new Date(createdAt).toISOString(),
          isVirtual: true,
        });
        totalComments++;
        await bump();
        if (Math.random() < 0.2) {
          const r = pick(vUsers);
          batch.set(db.collection("comments").doc(), {
            challengeId,
            entryId,
            parentId: ref.id,
            userId: r.id,
            userName: r.name,
            text: pick(replies),
            likeCount: Math.random() < 0.25 ? 1 + ri(6) : 0,
            isActive: true,
            createdAt: new Date(
                createdAt + (5 + ri(120)) * 60000).toISOString(),
            isVirtual: true,
          });
          totalComments++;
          await bump();
        }
      };

      // 1) Comentários no desafio + nas participações.
      for (const c of challSnap.docs) {
        const nCh = 3 + ri(5); // 3–7 no desafio
        for (let i = 0; i < nCh; i++) {
          await addComment(c.id, "", generic);
        }
      }
      for (const e of entries) {
        const d = e.data();
        const pool = d.contentType === "image" ?
            imageC.concat(generic) :
            (d.contentType === "video" ?
                videoC.concat(generic) : textC.concat(generic));
        const nE = 2 + ri(4); // 2–5 por participação
        for (let i = 0; i < nE; i++) {
          await addComment(d.challengeId, e.id, pool);
        }
      }

      // 2) Votos nas participações (contadores consistentes).
      const perChallenge = {};
      const perOwner = {};
      for (const e of entries) {
        const d = e.data();
        const n = 2 + ri(12); // +2..+13 votos
        batch.update(e.ref,
            {voteCount: admin.firestore.FieldValue.increment(n)});
        perChallenge[d.challengeId] = (perChallenge[d.challengeId] || 0) + n;
        if (d.userId && !String(d.userId).startsWith("demo_")) {
          perOwner[d.userId] = (perOwner[d.userId] || 0) + n;
        }
        totalVotes += n;
        await bump();
      }
      for (const [cid, n] of Object.entries(perChallenge)) {
        batch.update(db.collection("challenges").doc(cid),
            {voteCount: admin.firestore.FieldValue.increment(n)});
        await bump();
      }
      // Só incrementa donos que existem em /users (o mirror espelha).
      const ownerIds = Object.keys(perOwner);
      if (ownerIds.length > 0) {
        const ownerDocs = await db.getAll(
            ...ownerIds.map((id) => db.collection("users").doc(id)));
        for (const o of ownerDocs) {
          if (!o.exists) continue;
          batch.update(o.ref, {
            totalVotesReceived:
                admin.firestore.FieldValue.increment(perOwner[o.id]),
          });
          await bump();
        }
      }
      await flush();
      return res.json({
        success: true,
        comments: totalComments,
        votes: totalVotes,
        challenges: challSnap.size,
        entries: entries.length,
      });
    });

// ─── SEED DESAFIOS VIRTUAIS — LOTE 2 ──────────────────────────────────────────

exports.seedVirtualChallenges2 = functions.runWith({timeoutSeconds: 540})
    .https.onRequest(async (req, res) => {
      if (req.method !== "POST") {
        return res.status(405).json({error: "Method Not Allowed"});
      }
      if (!req.body || req.body.secret !== "SEED_2026_DP") {
        return res.status(403).json({error: "Forbidden"});
      }
      const db = admin.firestore();

      const check = await db.collection("challenges")
          .where("seedWave", "==", 2).limit(1).get();
      if (!check.empty) {
        return res.status(409).json({error: "Lote 2 já foi criado."});
      }

      const usersSnap = await db.collection("users")
          .where("isVirtual", "==", true).limit(400).get();
      const uids = usersSnap.docs.map((d) => d.id);
      if (uids.length < 20) {
        return res.status(412).json({error: "Rode seedVirtualUsers primeiro."});
      }

      const ri = (n) => Math.floor(Math.random() * n);
      const shuffle = (arr) => {
        const a = arr.slice();
        for (let i = a.length - 1; i > 0; i--) {
          const j = ri(i + 1);
          [a[i], a[j]] = [a[j], a[i]];
        }
        return a;
      };
      const HOST = "https://desafiopago.web.app";
      let imgCursor = 0;
      const nextImg = () => {
        const n = String((imgCursor++ % 40) + 1).padStart(2, "0");
        return `${HOST}/challenge_images/${n}.jpg`;
      };

      const specs = [
        {
          type: "text", status: "active", amount: 180,
          title: "Descreva o Brasil em 3 palavras 🇧🇷",
          desc: "Sem enrolação: três palavras que definem o nosso país.",
          entries: [
            "Futebol, samba e fé", "Calor, praia e caipirinha",
            "Resiliência, alegria e jeitinho", "Café, sol e abraço",
            "Saudade, festa e esperança",
          ],
        },
        {
          type: "text", status: "finished", amount: 350,
          title: "O melhor conselho que você já recebeu 🧠",
          desc: "Aquele conselho que mudou a sua vida.",
          entries: [
            "Guarde 10% de tudo que ganhar, sempre.",
            "Escolha a paz, não a razão.",
            "Faça hoje o que pode te livrar de um problema amanhã.",
            "Não empreste o que você não pode perder.",
            "Cerque-se de quem te puxa pra cima.",
          ],
        },
        {
          type: "text", status: "finished", amount: 200,
          title: "A maior mancada que você já pagou 🤦",
          desc: "Vai, assume aí. Todo mundo tem uma.",
          entries: [
            "Esqueci o aniversário da minha mãe 😭",
            "Mandei o print da conversa pra própria pessoa.",
            "Liguei o microfone na reunião na hora errada.",
            "Errei o nome da sogra no casamento.",
            "Estacionei na vaga do chefe sem saber.",
          ],
        },
        {
          type: "image", status: "active", amount: 600, imageN: 6,
          title: "Foto que conta uma história 📖",
          desc: "Uma imagem que vale mais que mil palavras.",
        },
        {
          type: "image", status: "active", amount: 250, imageN: 6,
          title: "A foto mais surpreendente 😮",
          desc: "Aquele clique no momento certo. Mostra!",
        },
        {
          type: "image", status: "finished", amount: 900, imageN: 7,
          title: "Seu melhor registro de 2025 🗓️",
          desc: "A foto que resume o seu ano.",
        },
      ];

      const now = Date.now();
      const day = 24 * 60 * 60 * 1000;
      const batch = db.batch();
      let cCount = 0;
      let eCount = 0;

      for (const spec of specs) {
        const pool = shuffle(uids);
        const creator = pool[0];
        const isFinished = spec.status === "finished";

        let createdMs;
        let expiresMs;
        if (isFinished) {
          createdMs = now - (20 + ri(25)) * day;
          expiresMs = createdMs + (7 + ri(9)) * day;
          if (expiresMs >= now) expiresMs = now - day;
        } else {
          createdMs = now - (1 + ri(7)) * day;
          expiresMs = now + (2 + ri(16)) * day;
        }

        const n = spec.type === "text" ? spec.entries.length : spec.imageN;
        const entrants = pool.slice(1, 1 + n);
        const challengeRef = db.collection("challenges").doc();

        const entryDocs = [];
        let totalVotes = 0;
        let maxVotes = -1;
        for (let i = 0; i < n; i++) {
          const top = isFinished ? 800 + ri(5000) : 30 + ri(700);
          const votes = 1 + ri(top);
          totalVotes += votes;
          if (votes > maxVotes) maxVotes = votes;
          entryDocs.push({
            ref: db.collection("entries").doc(),
            uid: entrants[i],
            votes,
            contentText: spec.type === "text" ? spec.entries[i] : null,
            contentUrl: spec.type === "image" ? nextImg() : null,
            createdAt: new Date(createdMs + (i + 1) * 3600 * 1000)
                .toISOString(),
          });
        }
        const winnerIds = isFinished ?
          entryDocs.filter((e) => e.votes === maxVotes).map((e) => e.uid) : [];

        batch.set(challengeRef, {
          title: spec.title,
          description: spec.desc,
          createdBy: creator,
          amount: spec.amount,
          creatorContribution: 0,
          status: spec.status,
          voteCount: totalVotes,
          entryCount: n,
          winnerIds,
          createdAt: new Date(createdMs).toISOString(),
          expiresAt: new Date(expiresMs).toISOString(),
          isVirtual: true,
          seedWave: 2,
        });
        cCount++;

        for (const e of entryDocs) {
          batch.set(e.ref, {
            challengeId: challengeRef.id,
            userId: e.uid,
            contentType: spec.type,
            contentText: e.contentText,
            contentUrl: e.contentUrl,
            voteCount: e.votes,
            isActive: true,
            createdAt: e.createdAt,
            isVirtual: true,
          });
          eCount++;
        }
      }

      await batch.commit();
      return res.json({success: true, challenges: cCount, entries: eCount});
    });

// ─── SEED INTERAÇÕES (curtidas + respostas) NOS COMENTÁRIOS VIRTUAIS ──────────

exports.seedVirtualCommentInteractions = functions.runWith({timeoutSeconds: 540})
    .https.onRequest(async (req, res) => {
      if (req.method !== "POST") {
        return res.status(405).json({error: "Method Not Allowed"});
      }
      if (!req.body || req.body.secret !== "SEED_2026_DP") {
        return res.status(403).json({error: "Forbidden"});
      }
      const db = admin.firestore();

      const sentinel = db.collection("_seedMeta").doc("commentInteractions");
      if (req.body.force !== true && (await sentinel.get()).exists) {
        return res.status(409).json({error: "Interações já foram criadas."});
      }

      const usersSnap = await db.collection("users")
          .where("isVirtual", "==", true).limit(400).get();
      const users = usersSnap.docs
          .map((d) => ({id: d.id, name: d.data().name || "Usuário"}));
      if (users.length < 10) {
        return res.status(412).json({error: "Rode seedVirtualUsers primeiro."});
      }

      const ri = (n) => Math.floor(Math.random() * n);
      const pick = (a) => a[ri(a.length)];
      const replyPool = [
        "Concordo! 🙌", "Verdade kkk", "Pensei o mesmo", "Boa!", "kkkkk",
        "Exatamente isso", "Apoiado 👏", "Também acho", "Top", "Demais!",
        "haha boa", "Isso aí 🔥",
      ];
      const likeFor = () => {
        const r = Math.random();
        if (r < 0.7) return ri(12);
        if (r < 0.95) return 10 + ri(40);
        return 50 + ri(150);
      };

      const snap = await db.collection("comments")
          .where("isVirtual", "==", true).get();

      let batch = db.batch();
      let ops = 0;
      let likesSet = 0;
      let replies = 0;
      const flush = async () => {
        if (ops > 0) {
          await batch.commit();
          batch = db.batch();
          ops = 0;
        }
      };

      for (const doc of snap.docs) {
        const d = doc.data();
        if (d.parentId) continue;
        batch.update(doc.ref, {likeCount: likeFor()});
        ops++;
        likesSet++;
        const nReplies = Math.random() < 0.5 ? 0 : 1 + ri(2);
        const baseMs = Date.parse(d.createdAt || new Date().toISOString());
        for (let i = 0; i < nReplies; i++) {
          const u = pick(users);
          batch.set(db.collection("comments").doc(), {
            challengeId: d.challengeId,
            entryId: d.entryId || "",
            parentId: doc.id,
            userId: u.id,
            userName: u.name,
            text: pick(replyPool),
            likeCount: ri(8),
            isActive: true,
            createdAt: new Date(baseMs + (i + 1) * 1800 * 1000).toISOString(),
            isVirtual: true,
          });
          ops++;
          replies++;
        }
        if (ops >= 440) await flush();
      }
      await flush();
      await sentinel.set({
        createdAt: new Date().toISOString(), likesSet, replies,
      });
      return res.json({success: true, likesSet, replies});
    });

// ─── REMOVER EMOJIS DOS TÍTULOS DOS DESAFIOS VIRTUAIS ─────────────────────────

exports.fixVirtualChallengeTitles = functions.runWith({timeoutSeconds: 300})
    .https.onRequest(async (req, res) => {
      if (req.method !== "POST") {
        return res.status(405).json({error: "Method Not Allowed"});
      }
      if (!req.body || req.body.secret !== "SEED_2026_DP") {
        return res.status(403).json({error: "Forbidden"});
      }
      const db = admin.firestore();
      const emojiRe =
          /[\u{1F1E6}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}]/gu;
      const strip = (s) => String(s || "")
          .replace(emojiRe, "")
          .replace(/‍/gu, "")
          .replace(/️/gu, "")
          .replace(/\s+/g, " ")
          .trim();

      const snap = await db.collection("challenges")
          .where("isVirtual", "==", true).get();
      let batch = db.batch();
      let ops = 0;
      let fixed = 0;
      for (const doc of snap.docs) {
        const t = doc.data().title || "";
        const nt = strip(t);
        if (nt !== t && nt.length > 0) {
          batch.update(doc.ref, {title: nt});
          ops++;
          fixed++;
          if (ops >= 450) {
            await batch.commit();
            batch = db.batch();
            ops = 0;
          }
        }
      }
      if (ops > 0) await batch.commit();
      return res.json({success: true, fixed});
    });

// ─── SEED DESAFIOS DE VALOR BAIXO (centavos a R$20, com vídeo) ─────────────────

exports.seedSmallChallenges = functions.runWith({timeoutSeconds: 540})
    .https.onRequest(async (req, res) => {
      if (req.method !== "POST") {
        return res.status(405).json({error: "Method Not Allowed"});
      }
      if (!req.body || req.body.secret !== "SEED_2026_DP") {
        return res.status(403).json({error: "Forbidden"});
      }
      const db = admin.firestore();

      const check = await db.collection("challenges")
          .where("seedWave", "==", 3).limit(1).get();
      if (!check.empty) {
        return res.status(409).json({error: "Desafios de valor baixo já existem."});
      }

      const usersSnap = await db.collection("users")
          .where("isVirtual", "==", true).limit(400).get();
      const uids = usersSnap.docs.map((d) => d.id);
      if (uids.length < 20) {
        return res.status(412).json({error: "Rode seedVirtualUsers primeiro."});
      }

      const ri = (n) => Math.floor(Math.random() * n);
      const shuffle = (arr) => {
        const a = arr.slice();
        for (let i = a.length - 1; i > 0; i--) {
          const j = ri(i + 1);
          [a[i], a[j]] = [a[j], a[i]];
        }
        return a;
      };
      const HOST = "https://desafiopago.web.app";
      let imgC = 0;
      const nextImg = () => {
        const n = String((imgC++ % 40) + 1).padStart(2, "0");
        return `${HOST}/challenge_images/${n}.jpg`;
      };
      let vidC = 0;
      const nextVid = () => {
        const n = String((vidC++ % 3) + 1).padStart(2, "0");
        return `${HOST}/challenge_videos/${n}.mp4`;
      };

      const specs = [
        {
          type: "image", status: "active", amount: 0.50, imageN: 5,
          title: "A foto do seu café da manhã",
          desc: "Mostra o que rolou no café hoje. Vale tudo!",
        },
        {
          type: "text", status: "finished", amount: 0.99,
          title: "Resuma o seu dia de ontem em uma frase",
          desc: "Sem textão. Uma frase só.",
          entries: [
            "Acordei, sobrevivi, repeti.", "Trabalho, treino e série.",
            "Dia cheio, mas produtivo.", "Só café e reunião o dia todo.",
            "Descansei e não me arrependo.",
          ],
        },
        {
          type: "text", status: "active", amount: 1.00,
          title: "Sua melhor dica de produtividade",
          desc: "O truque que te faz render mais no dia.",
          entries: [
            "Desliga as notificações por 1h e foca.",
            "Pomodoro: 25min de foco, 5 de pausa.",
            "Faça a tarefa mais difícil logo cedo.",
            "Anote tudo, não confie na memória.",
            "Uma coisa por vez, multitarefa é cilada.",
          ],
        },
        {
          type: "image", status: "active", amount: 2.50, imageN: 5,
          title: "A foto mais aleatória do seu rolo da câmera",
          desc: "Aquela foto inexplicável que tá lá. Mostra!",
        },
        {
          type: "text", status: "active", amount: 5.00,
          title: "Indique um filme pra maratonar",
          desc: "Aquele que você indicaria de olhos fechados.",
          entries: [
            "Interestelar, chora todo mundo.",
            "Cidade de Deus, clássico nacional.",
            "De Volta para o Futuro nunca erra.",
            "Parasita, vale cada minuto.",
            "Senhor dos Anéis, maratona perfeita.",
          ],
        },
        {
          type: "text", status: "finished", amount: 12.00,
          title: "Qual app você não vive sem",
          desc: "O aplicativo essencial do seu dia.",
          entries: [
            "WhatsApp, óbvio.", "Google Maps, me perco sem ele.",
            "Spotify o dia inteiro.", "Notion pra organizar tudo.",
            "iFood nos dias de preguiça.",
          ],
        },
        {
          type: "image", status: "finished", amount: 7.00, imageN: 6,
          title: "Sua foto favorita do mês",
          desc: "A melhor que você registrou nas últimas semanas.",
        },
        {
          type: "video", status: "active", amount: 20.00, videoN: 3,
          title: "Melhor vídeo de ate 15 segundos",
          desc: "Solta o vídeo mais legal que você tem. Passe o mouse!",
        },
        {
          type: "video", status: "finished", amount: 15.00, videoN: 3,
          title: "Melhor momento em video",
          desc: "Aquele clipe que vale ouro.",
        },
      ];

      const now = Date.now();
      const day = 24 * 60 * 60 * 1000;
      const batch = db.batch();
      let cCount = 0;
      let eCount = 0;

      for (const spec of specs) {
        const pool = shuffle(uids);
        const creator = pool[0];
        const isFinished = spec.status === "finished";

        let createdMs;
        let expiresMs;
        if (isFinished) {
          createdMs = now - (20 + ri(25)) * day;
          expiresMs = createdMs + (7 + ri(9)) * day;
          if (expiresMs >= now) expiresMs = now - day;
        } else {
          createdMs = now - (1 + ri(7)) * day;
          expiresMs = now + (2 + ri(16)) * day;
        }

        let n;
        if (spec.type === "text") {
          n = spec.entries.length;
        } else if (spec.type === "video") {
          n = spec.videoN;
        } else {
          n = spec.imageN;
        }
        const entrants = pool.slice(1, 1 + n);
        const challengeRef = db.collection("challenges").doc();

        const entryDocs = [];
        let totalVotes = 0;
        let maxVotes = -1;
        for (let i = 0; i < n; i++) {
          const top = isFinished ? 400 + ri(3000) : 20 + ri(500);
          const votes = 1 + ri(top);
          totalVotes += votes;
          if (votes > maxVotes) maxVotes = votes;
          let url = null;
          if (spec.type === "image") url = nextImg();
          if (spec.type === "video") url = nextVid();
          entryDocs.push({
            ref: db.collection("entries").doc(),
            uid: entrants[i],
            votes,
            contentText: spec.type === "text" ? spec.entries[i] : null,
            contentUrl: url,
            createdAt: new Date(createdMs + (i + 1) * 3600 * 1000)
                .toISOString(),
          });
        }
        const winnerIds = isFinished ?
          entryDocs.filter((e) => e.votes === maxVotes).map((e) => e.uid) : [];

        batch.set(challengeRef, {
          title: spec.title,
          description: spec.desc,
          createdBy: creator,
          amount: spec.amount,
          creatorContribution: 0,
          status: spec.status,
          voteCount: totalVotes,
          entryCount: n,
          winnerIds,
          createdAt: new Date(createdMs).toISOString(),
          expiresAt: new Date(expiresMs).toISOString(),
          isVirtual: true,
          seedWave: 3,
        });
        cCount++;

        for (const e of entryDocs) {
          batch.set(e.ref, {
            challengeId: challengeRef.id,
            userId: e.uid,
            contentType: spec.type,
            contentText: e.contentText,
            contentUrl: e.contentUrl,
            voteCount: e.votes,
            isActive: true,
            createdAt: e.createdAt,
            isVirtual: true,
          });
          eCount++;
        }
      }

      await batch.commit();
      return res.json({success: true, challenges: cCount, entries: eCount});
    });

// ─── RANDOMIZAR VALORES (desafios + ganhos do ranking) ───────────────────────

exports.randomizeVirtualValues = functions.runWith({timeoutSeconds: 540})
    .https.onRequest(async (req, res) => {
      if (req.method !== "POST") {
        return res.status(405).json({error: "Method Not Allowed"});
      }
      if (!req.body || req.body.secret !== "SEED_2026_DP") {
        return res.status(403).json({error: "Forbidden"});
      }
      const db = admin.firestore();
      const sentinel = db.collection("_seedMeta").doc("valuesRandomized");
      if ((await sentinel.get()).exists) {
        return res.status(409).json({error: "Valores já randomizados."});
      }

      const ri = (n) => Math.floor(Math.random() * n);
      const round2 = (x) => Math.round(x * 100) / 100;
      const withCents = (x) => {
        const v = round2(x);
        if (Math.round(v * 100) % 100 === 0) {
          return round2(v + (ri(98) + 1) / 100);
        }
        return v;
      };

      const cs = await db.collection("challenges")
          .where("isVirtual", "==", true).get();
      const us = await db.collection("users")
          .where("isVirtual", "==", true).get();

      let batch = db.batch();
      let ops = 0;
      let cFixed = 0;
      let uFixed = 0;
      const flush = async () => {
        if (ops > 0) {
          await batch.commit();
          batch = db.batch();
          ops = 0;
        }
      };

      // Desafios: mantém a faixa (centavos / 1-20 / maiores), mas quebra o valor.
      for (const doc of cs.docs) {
        const a = Number(doc.data().amount || 0);
        if (a <= 0) continue;
        let na;
        if (a < 1) {
          na = round2((5 + ri(94)) / 100);
        } else if (a < 25) {
          na = withCents(1 + Math.random() * 23);
        } else {
          na = withCents(a * (0.8 + Math.random() * 0.5));
        }
        batch.update(doc.ref, {amount: na});
        ops++;
        cFixed++;
        if (ops >= 440) await flush();
      }

      // Ganhos: só adiciona centavos (preserva a ordem/posições do ranking).
      for (const doc of us.docs) {
        const e = Number(doc.data().totalEarned || 0);
        const ne = round2(e + (ri(99) + 1) / 100);
        batch.update(doc.ref, {totalEarned: ne});
        ops++;
        batch.set(db.collection("publicProfiles").doc(doc.id),
            {totalEarned: ne}, {merge: true});
        ops++;
        uFixed++;
        if (ops >= 440) await flush();
      }
      await flush();
      await sentinel.set({
        createdAt: new Date().toISOString(), cFixed, uFixed,
      });
      return res.json({success: true, challenges: cFixed, users: uFixed});
    });

// ─── VALORES POR TIPO (texto < 20, imagem < 100, vídeo > 100) ─────────────────

exports.setTypedChallengeValues = functions.runWith({timeoutSeconds: 540})
    .https.onRequest(async (req, res) => {
      if (req.method !== "POST") {
        return res.status(405).json({error: "Method Not Allowed"});
      }
      if (!req.body || req.body.secret !== "SEED_2026_DP") {
        return res.status(403).json({error: "Forbidden"});
      }
      const db = admin.firestore();
      const ri = (n) => Math.floor(Math.random() * n);
      const round2 = (x) => Math.round(x * 100) / 100;
      const withCents = (x) => {
        const v = round2(x);
        if (Math.round(v * 100) % 100 === 0) {
          return round2(v + (ri(98) + 1) / 100);
        }
        return v;
      };

      // Tipo do desafio = contentType das participações virtuais.
      const entriesSnap = await db.collection("entries")
          .where("isVirtual", "==", true).get();
      const typeByChallenge = {};
      entriesSnap.forEach((d) => {
        const x = d.data();
        if (!typeByChallenge[x.challengeId]) {
          typeByChallenge[x.challengeId] = x.contentType || "text";
        }
      });

      const cs = await db.collection("challenges")
          .where("isVirtual", "==", true).get();
      let batch = db.batch();
      let ops = 0;
      const counts = {text: 0, image: 0, video: 0};
      for (const doc of cs.docs) {
        const type = typeByChallenge[doc.id] || "text";
        let amount;
        if (type === "video") {
          amount = withCents(120 + Math.random() * 2380); // > 100
        } else if (type === "image") {
          amount = withCents(20 + Math.random() * 79); // < 100
        } else {
          amount = withCents(0.5 + Math.random() * 19); // < 20
        }
        batch.update(doc.ref, {amount});
        ops++;
        counts[type] = (counts[type] || 0) + 1;
        if (ops >= 440) {
          await batch.commit();
          batch = db.batch();
          ops = 0;
        }
      }
      if (ops > 0) await batch.commit();
      return res.json({success: true, counts});
    });

// ─── RESET DOS PRAZOS DOS DESAFIOS VIRTUAIS ───────────────────────────────────
// Reativa todos os desafios virtuais e sorteia um novo término entre 20 e 30
// dias à frente. One-shot, protegido por secret. NÃO toca em desafios reais.
exports.resetVirtualChallengeDeadlines =
  functions.runWith({timeoutSeconds: 540})
      .https.onRequest(async (req, res) => {
        if (req.method !== "POST") {
          return res.status(405).json({error: "Method Not Allowed"});
        }
        if (!req.body || req.body.secret !== "SEED_2026_DP") {
          return res.status(403).json({error: "Forbidden"});
        }
        const db = admin.firestore();
        const DAY = 24 * 60 * 60 * 1000;

        const cs = await db.collection("challenges")
            .where("isVirtual", "==", true).get();

        let batch = db.batch();
        let ops = 0;
        let count = 0;
        for (const doc of cs.docs) {
          const days = 20 + Math.random() * 10; // 20..30 dias
          const expiresAt = new Date(Date.now() + days * DAY).toISOString();
          batch.update(doc.ref, {
            status: "active",
            expiresAt,
            winnerIds: [],
            finishedAt: admin.firestore.FieldValue.delete(),
          });
          ops++;
          count++;
          if (ops >= 440) {
            await batch.commit();
            batch = db.batch();
            ops = 0;
          }
        }
        if (ops > 0) await batch.commit();
        return res.json({success: true, updated: count});
      });

// ─── DESNORMALIZA TOP-3 DO DESAFIO (evita N+1 no feed) ───────────────────────
// A cada mudança numa participação (criar/votar/excluir) recalcula as 3 mais
// votadas e grava em challenges/{id}.topEntries. O feed lê isso direto.
async function _recomputeTopEntries(db, challengeId) {
  if (!challengeId) return;
  const snap = await db.collection("entries")
      .where("challengeId", "==", challengeId)
      .where("isActive", "==", true)
      .orderBy("voteCount", "desc")
      .limit(3)
      .get();
  const top = snap.docs.map((d) => {
    const x = d.data();
    return {
      entryId: d.id,
      userId: x.userId || "",
      contentType: x.contentType || "text",
      contentUrl: x.contentUrl || null,
      contentText: x.contentText || null,
      voteCount: x.voteCount || 0,
    };
  });
  await db.collection("challenges").doc(challengeId)
      .update({topEntries: top}).catch(() => {});
}

exports.syncChallengeTopEntries = functions.firestore
    .document("entries/{entryId}")
    .onWrite(async (change) => {
      const after = change.after.exists ? change.after.data() : null;
      const before = change.before.exists ? change.before.data() : null;
      const challengeId =
        (after && after.challengeId) || (before && before.challengeId);
      await _recomputeTopEntries(admin.firestore(), challengeId);
      return null;
    });

// ─── BACKFILL TOP-3 (one-shot) ───────────────────────────────────────────────
exports.backfillTopEntries = functions.runWith({timeoutSeconds: 540})
    .https.onRequest(async (req, res) => {
      if (req.method !== "POST") {
        return res.status(405).json({error: "Method Not Allowed"});
      }
      if (!req.body || req.body.secret !== "SEED_2026_DP") {
        return res.status(403).json({error: "Forbidden"});
      }
      const db = admin.firestore();
      const cs = await db.collection("challenges").get();
      let updated = 0;
      for (const c of cs.docs) {
        await _recomputeTopEntries(db, c.id);
        updated++;
      }
      return res.json({success: true, updated});
    });

// ─── LIMPAR ÓRFÃOS (entries/comments sem desafio) ────────────────────────────
exports.cleanOrphans = functions.runWith({timeoutSeconds: 540})
    .https.onRequest(async (req, res) => {
      if (req.method !== "POST") {
        return res.status(405).json({error: "Method Not Allowed"});
      }
      if (!req.body || req.body.secret !== "SEED_2026_DP") {
        return res.status(403).json({error: "Forbidden"});
      }
      const db = admin.firestore();
      const cs = await db.collection("challenges").get();
      const valid = new Set(cs.docs.map((d) => d.id));

      const sweep = async (col) => {
        const snap = await db.collection(col).get();
        let batch = db.batch();
        let ops = 0;
        let n = 0;
        for (const d of snap.docs) {
          const cid = d.data().challengeId;
          if (cid && !valid.has(cid)) {
            batch.delete(d.ref);
            ops++;
            n++;
            if (ops >= 450) {
              await batch.commit();
              batch = db.batch();
              ops = 0;
            }
          }
        }
        if (ops > 0) await batch.commit();
        return n;
      };

      const entriesDeleted = await sweep("entries");
      const commentsDeleted = await sweep("comments");
      return res.json({success: true, entriesDeleted, commentsDeleted});
    });

// ─── DIAGNÓSTICO: CONTAGENS (read-only) ──────────────────────────────────────
exports.diagCounts = functions.https.onRequest(async (req, res) => {
  if (req.method !== "POST") {
    return res.status(405).json({error: "Method Not Allowed"});
  }
  if (!req.body || req.body.secret !== "SEED_2026_DP") {
    return res.status(403).json({error: "Forbidden"});
  }
  const db = admin.firestore();
  const count = async (col, field, val) => {
    let q = db.collection(col);
    if (field) q = q.where(field, "==", val);
    const agg = await q.count().get();
    return agg.data().count;
  };
  return res.json({
    challenges_total: await count("challenges"),
    challenges_virtual: await count("challenges", "isVirtual", true),
    challenges_active: await count("challenges", "status", "active"),
    challenges_finished: await count("challenges", "status", "finished"),
    users_total: await count("users"),
    users_virtual: await count("users", "isVirtual", true),
    entries_total: await count("entries"),
  });
});

// ─── PRÉVIA DE LINK (Open Graph) PARA COMPARTILHAMENTO ────────────────────────

let _indexCache = null;
const _getIndexHtml = async () => {
  if (_indexCache) return _indexCache;
  const r = await fetch("https://desafiopago.web.app/index.html");
  _indexCache = await r.text();
  return _indexCache;
};

exports.entryPreview = functions.https.onRequest(async (req, res) => {
  try {
    const db = admin.firestore();
    const parts = (req.path || "").split("/").filter(Boolean);
    const challengeId = parts.length > 1 ? parts[1] : "";
    const entryId = req.query.entry ? String(req.query.entry) : "";

    const esc = (s) => String(s == null ? "" : s)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;");

    let title = "Desafio Pago";
    let desc = "Participe de desafios e vote nas melhores participações!";
    const image = "https://desafiopago.web.app/og-default.png";

    if (challengeId) {
      const cDoc = await db.collection("challenges").doc(challengeId).get();
      if (cDoc.exists) {
        const chTitle = cDoc.data().title || "um desafio";
        let author = "";
        if (entryId) {
          const eDoc = await db.collection("entries").doc(entryId).get();
          if (eDoc.exists) {
            const pp = await db.collection("publicProfiles")
                .doc(eDoc.data().userId).get();
            author = pp.exists ? (pp.data().name || "") : "";
          }
        }
        if (entryId && author) {
          title = `${author} quer o seu voto! 🗳️`;
          desc = `Participação no desafio "${chTitle}". ` +
              "Toque e vote no Desafio Pago.";
        } else if (entryId) {
          title = "Vote nesta participação! 🗳️";
          desc = `Desafio "${chTitle}" no Desafio Pago. Toque e vote.`;
        } else {
          title = chTitle;
          desc = "Participe e vote no Desafio Pago!";
        }
      }
    }

    let url = `https://desafiopago.com.br/challenges/${challengeId}`;
    if (entryId) url += `?entry=${encodeURIComponent(entryId)}`;

    const og = "\n" +
      `<meta property="og:type" content="website">\n` +
      `<meta property="og:site_name" content="Desafio Pago">\n` +
      `<meta property="og:title" content="${esc(title)}">\n` +
      `<meta property="og:description" content="${esc(desc)}">\n` +
      `<meta property="og:image" content="${image}">\n` +
      `<meta property="og:image:width" content="1200">\n` +
      `<meta property="og:image:height" content="630">\n` +
      `<meta property="og:url" content="${esc(url)}">\n` +
      `<meta name="twitter:card" content="summary_large_image">\n` +
      `<meta name="twitter:title" content="${esc(title)}">\n` +
      `<meta name="twitter:description" content="${esc(desc)}">\n` +
      `<meta name="twitter:image" content="${image}">\n`;

    let html = await _getIndexHtml();
    html = html.replace("</head>", `${og}</head>`);
    res.set("Cache-Control", "public, max-age=600, s-maxage=600");
    return res.status(200).send(html);
  } catch (e) {
    return res.redirect("https://desafiopago.web.app/");
  }
});

// (Removido: updateVirtualAvatars — migração obsoleta que setava URLs sem CORS.
//  Os retratos virtuais são auto-hospedados em /portraits/{men|women}/N.jpg.)

// ─── SEO ORGÂNICO (hub /novidades, sitemap, IA de conteúdo, GSC) ─────────────
// Ver functions/seo.js — páginas SSR para o Google indexar (o app Flutter é
// canvas e invisível pra busca), sitemap.xml e geração de artigos por IA.
Object.assign(exports, require("./seo"));

// ─── PAGAMENTOS INTERNACIONAIS (PayPal + XRP — trialspaid.web.app) ───────────
// Ver functions/payments_intl.js — depósito PayPal creditando o ledger e
// saque em cripto (XRP) com fluxo manual do admin (como o Pix).
Object.assign(exports, require("./payments_intl"));

// ─── COFRE DE CHAVES (painel admin) ──────────────────────────────────────────
// Só as callables entram no deploy (getSecret é helper interno, não função).
const _secrets = require("./secrets");
exports.adminSetSecret = _secrets.adminSetSecret;
exports.adminGetSecretStatus = _secrets.adminGetSecretStatus;

// ─── SEED / BACKFILL INTERNACIONAL (one-shot, re-executável) ─────────────────
// 1) Marca todos os desafios sem `region` como 'BR'. 2) Se não houver desafios
// internacionais, cria alguns (em inglês) com participações de perfis virtuais
// para o trialspaid.web.app não nascer vazio. Ranking segue compartilhado.
exports.seedInternational = functions.runWith({timeoutSeconds: 540})
    .https.onRequest(async (req, res) => {
      if (req.method !== "POST") {
        return res.status(405).json({error: "Method Not Allowed"});
      }
      if (!req.body || req.body.secret !== "SEED_2026_DP") {
        return res.status(403).json({error: "Forbidden"});
      }
      const db = admin.firestore();
      const ri = (n) => Math.floor(Math.random() * n);

      // 1) Backfill region = 'BR' onde faltar.
      const all = await db.collection("challenges").get();
      let br = 0;
      let batch = db.batch();
      let ops = 0;
      for (const d of all.docs) {
        if (d.data().region === undefined || d.data().region === null) {
          batch.update(d.ref, {region: "BR"});
          br++;
          if (++ops >= 400) {
            await batch.commit();
            batch = db.batch();
            ops = 0;
          }
        }
      }
      if (ops > 0) await batch.commit();

      // 2) Já existem desafios INTL? Então só o backfill.
      const intlExisting = await db.collection("challenges")
          .where("region", "==", "INTL").limit(1).get();
      if (!intlExisting.empty) {
        return res.json({success: true, backfilledBR: br, intlCreated: 0});
      }

      const usersSnap = await db.collection("users")
          .where("isVirtual", "==", true).limit(300).get();
      const uids = usersSnap.docs.map((d) => d.id);
      if (uids.length < 20) {
        return res.json({
          success: true, backfilledBR: br, intlCreated: 0,
          note: "Rode seedVirtualUsers primeiro para popular o intl.",
        });
      }
      const shuffle = (arr) => {
        const a = arr.slice();
        for (let i = a.length - 1; i > 0; i--) {
          const j = ri(i + 1);
          [a[i], a[j]] = [a[j], a[i]];
        }
        return a;
      };
      const HOST = "https://desafiopago.web.app";
      let imgC = ri(40);
      const nextImg = () =>
        `${HOST}/challenge_images/${String((imgC++ % 40) + 1)
            .padStart(2, "0")}.jpg`;

      // Prêmios em BRL no ledger; exibidos em USD no site (≈ /5.5).
      const specs = [
        {t: "Best sunset photo from your phone",
          d: "Golden hour, your city, your shot. Most voted wins.",
          amount: 140, status: "active", n: 5},
        {t: "Cutest pet of the week",
          d: "Show us your best friend. The internet picks the winner.",
          amount: 320, status: "active", n: 6},
        {t: "Coffee that starts your day",
          d: "Your morning cup, your way. Best framing takes the prize.",
          amount: 90, status: "active", n: 4},
        {t: "Street photography challenge",
          d: "One candid moment from your street. Make it count.",
          amount: 260, status: "active", n: 5},
        {t: "Best home-cooked plate",
          d: "Plate it, shoot it, win it. Food that makes us hungry.",
          amount: 180, status: "active", n: 5},
        {t: "Your city in one photo",
          d: "Capture where you live in a single frame.",
          amount: 210, status: "active", n: 4},
        {t: "Best travel shot of 2026",
          d: "The photo you're most proud of this year.",
          amount: 500, status: "finished", n: 6},
        {t: "Minimalist photography",
          d: "Less is more. Clean, simple, striking.",
          amount: 120, status: "finished", n: 5},
      ];
      const now = Date.now();
      const day = 86400000;
      let batch2 = db.batch();
      let ops2 = 0;
      let created = 0;
      const flush2 = async () => {
        if (ops2 > 0) {
          await batch2.commit();
          batch2 = db.batch();
          ops2 = 0;
        }
      };
      for (const spec of specs) {
        const pool = shuffle(uids);
        const creator = pool[0];
        const finished = spec.status === "finished";
        const createdMs = finished ?
          now - (20 + ri(20)) * day : now - (1 + ri(6)) * day;
        const expiresMs = finished ?
          now - (1 + ri(5)) * day : now + (2 + ri(14)) * day;
        const entrants = pool.slice(1, 1 + spec.n);
        const cRef = db.collection("challenges").doc();
        const entryDocs = [];
        let totalVotes = 0;
        let maxVotes = -1;
        for (let i = 0; i < spec.n; i++) {
          const votes = finished ? 400 + ri(3000) : 20 + ri(600);
          totalVotes += votes;
          if (votes > maxVotes) maxVotes = votes;
          entryDocs.push({
            ref: db.collection("entries").doc(),
            uid: entrants[i],
            votes,
            url: nextImg(),
            createdAt: new Date(createdMs + (i + 1) * 3600000).toISOString(),
          });
        }
        const winnerIds = finished ?
          entryDocs.filter((e) => e.votes === maxVotes).map((e) => e.uid) : [];
        batch2.set(cRef, {
          title: spec.t,
          description: spec.d,
          createdBy: creator,
          amount: spec.amount,
          creatorContribution: 0,
          status: spec.status,
          region: "INTL",
          voteCount: totalVotes,
          entryCount: spec.n,
          winnerIds,
          createdAt: new Date(createdMs).toISOString(),
          expiresAt: new Date(expiresMs).toISOString(),
          isVirtual: true,
          seedWave: "intl",
        });
        created++;
        ops2++;
        for (const e of entryDocs) {
          batch2.set(e.ref, {
            challengeId: cRef.id,
            userId: e.uid,
            contentType: "image",
            contentText: null,
            contentUrl: e.url,
            voteCount: e.votes,
            isActive: true,
            createdAt: e.createdAt,
            isVirtual: true,
          });
          if (++ops2 >= 400) await flush2();
        }
        if (ops2 >= 400) await flush2();
      }
      await flush2();
      return res.json({success: true, backfilledBR: br, intlCreated: created});
    });
