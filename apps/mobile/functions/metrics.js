// ─── MÉTRICAS REAIS (transparência) ──────────────────────────────────────────
// Números SÓ de uso real — sem perfis, desafios ou participações de
// demonstração (isVirtual) e sem votos de admin. São os números que podem ir
// para uma inscrição de financiamento (ex.: XRPL Grants) e que um avaliador
// consegue reproduzir lendo o banco.
//
// Exporta só a callable `adminRealMetrics` (index.js atribui explicitamente).

const functions = require("firebase-functions");
const admin = require("firebase-admin");

const countOf = async (q) => (await q.count().get()).data().count || 0;
const sumOf = async (q, field) => {
  const r = await q.aggregate({
    total: admin.firestore.AggregateField.sum(field),
  }).get();
  return Number(r.data().total) || 0;
};

/**
 * Calcula as métricas reais a partir do banco.
 * @param {FirebaseFirestore.Firestore} db
 * @return {Promise<Object>}
 */
async function computeRealMetrics(db) {
  const challenges = db.collection("challenges");
  const demoCh = challenges.where("isVirtual", "==", true);
  const activeCh = challenges.where("status", "==", "active");
  const activeDemo = activeCh.where("isVirtual", "==", true);
  const entries = db.collection("entries");
  const votes = db.collection("votes");
  const deposits = db.collection("payments").where("status", "==", "approved");
  const paidOut = db.collection("withdrawals").where("status", "==", "paid");

  const [
    usersReal, usersDemo,
    chTotal, chDemo, chActive, chActiveDemo,
    prizeTotal, prizeDemo,
    enTotal, enDemo,
    votesTotal, votesAdmin,
    depCount, depSum, wdCount, wdSum,
  ] = await Promise.all([
    countOf(db.collection("publicProfiles").where("isVirtual", "==", false)),
    countOf(db.collection("publicProfiles").where("isVirtual", "==", true)),
    countOf(challenges), countOf(demoCh),
    countOf(activeCh), countOf(activeDemo),
    sumOf(challenges, "amount"), sumOf(demoCh, "amount"),
    countOf(entries), countOf(entries.where("isVirtual", "==", true)),
    countOf(votes), countOf(votes.where("isAdminVote", "==", true)),
    countOf(deposits), sumOf(deposits, "amount"),
    countOf(paidOut), sumOf(paidOut, "amount"),
  ]);

  const round2 = (x) => Math.round(x * 100) / 100;
  return {
    users: {real: usersReal, demo: usersDemo},
    challenges: {
      real: chTotal - chDemo,
      realActive: chActive - chActiveDemo,
      demo: chDemo,
      realPrizeTotalBrl: round2(prizeTotal - prizeDemo),
    },
    entries: {real: enTotal - enDemo, demo: enDemo},
    votes: {byUsers: votesTotal - votesAdmin, byAdmins: votesAdmin},
    money: {
      depositsApproved: depCount,
      depositsBrl: round2(depSum),
      withdrawalsPaid: wdCount,
      withdrawalsBrl: round2(wdSum),
    },
    generatedAt: new Date().toISOString(),
  };
}

exports.adminRealMetrics = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Não autenticado");
  }
  const db = admin.firestore();
  const adminDoc = await db.collection("admins").doc(context.auth.uid).get();
  if (!adminDoc.exists) {
    throw new functions.https.HttpsError("permission-denied", "Acesso negado");
  }
  return computeRealMetrics(db);
});

module.exports.computeRealMetrics = computeRealMetrics;
