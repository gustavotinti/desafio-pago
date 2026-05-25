const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

exports.vote = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
        "unauthenticated",
        "Usuário não logado",
    );
  }

  const userId = context.auth.uid;
  const challengeId = data.challengeId;

  if (!challengeId) {
    throw new functions.https.HttpsError(
        "invalid-argument",
        "challengeId obrigatório",
    );
  }

  const voteRef = admin.firestore().collection("votes");

  const existingVote = await voteRef
      .where("userId", "==", userId)
      .where("challengeId", "==", challengeId)
      .get();

  if (!existingVote.empty) {
    throw new functions.https.HttpsError(
        "already-exists",
        "Você já votou",
    );
  }

  await voteRef.add({
    userId: userId,
    challengeId: challengeId,
    createdAt: new Date().toISOString(),
  });

  await admin.firestore().collection("challenges").doc(challengeId).update({
    voteCount: admin.firestore.FieldValue.increment(1),
  });

  return {success: true};
});
