const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

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
  const existing = await voteRef.get();

  if (existing.exists) {
    throw new functions.https.HttpsError("already-exists", "Você já votou neste desafio");
  }

  const entryRef = db.collection("entries").doc(entryId);
  const challengeRef = db.collection("challenges").doc(challengeId);

  await db.runTransaction(async (tx) => {
    tx.set(voteRef, {
      userId,
      challengeId,
      entryId,
      createdAt: new Date().toISOString(),
    });
    tx.update(entryRef, {voteCount: admin.firestore.FieldValue.increment(1)});
    tx.update(challengeRef, {voteCount: admin.firestore.FieldValue.increment(1)});
  });

  return {success: true};
});

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

  const entriesSnapshot = await db
      .collection("entries")
      .where("challengeId", "==", challengeId)
      .where("isActive", "==", true)
      .orderBy("voteCount", "desc")
      .get();

  const challengeRef = db.collection("challenges").doc(challengeId);
  const batch = db.batch();

  const noWinner = () => batch.update(challengeRef, {
    status: "finished",
    winnerIds: [],
    finishedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  if (entriesSnapshot.empty) {
    noWinner();
    return batch.commit();
  }

  const entries = entriesSnapshot.docs.map((d) => ({id: d.id, ...d.data()}));
  const maxVotes = entries[0].voteCount;

  if (maxVotes === 0) {
    noWinner();
    return batch.commit();
  }

  const winners = entries.filter((e) => e.voteCount === maxVotes);
  const winnerIds = winners.map((e) => e.userId);

  // Work in cents to avoid floating point errors
  const prizeCents = Math.round(prizeAmount * 100);
  const perWinnerCents = Math.floor(prizeCents / winnerIds.length);
  const prizePerWinner = perWinnerCents / 100;

  batch.update(challengeRef, {
    status: "finished",
    winnerIds: winnerIds,
    finishedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  for (const winner of winners) {
    const userRef = db.collection("users").doc(winner.userId);
    batch.update(userRef, {
      balance: admin.firestore.FieldValue.increment(prizePerWinner),
      totalEarned: admin.firestore.FieldValue.increment(prizePerWinner),
    });

    const txRef = db.collection("transactions").doc();
    batch.set(txRef, {
      userId: winner.userId,
      amount: prizePerWinner,
      type: "reward",
      description: `Prêmio: ${challenge.title}`,
      challengeId: challengeId,
      createdAt: new Date().toISOString(),
    });
  }

  return batch.commit();
}
