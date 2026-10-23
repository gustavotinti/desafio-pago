// ─── PROVA DE PRÊMIO NO XRP LEDGER ───────────────────────────────────────────
// Transparência on-chain: cada desafio REAL ganha um registro público no XRP
// Ledger.
//  1) Ao ser criado: EscrowCreate da carteira da plataforma, travado até o fim
//     do prazo (FinishAfter = expiresAt), com memo {challengeId, prêmio em BRL}.
//  2) Ao ser encerrado: EscrowFinish com memo do resultado (quantos
//     vencedores, valor por vencedor, ids de vencedor em hash — sem dado
//     pessoal).
// Qualquer pessoa confere no explorador (link na página do desafio).
//
// Hoje roda na TESTNET (XRP sem valor, custo zero): demonstra o mecanismo.
// Na mainnet o mesmo fluxo trava o valor real do prêmio (XRP/RLUSD) — marco
// do pedido de financiamento.
//
// Kill-switch: config/xrpl.enabled == false. Carteira da plataforma em
// secure_config/xrpl (doc trancado pelas rules; criada sozinha no faucet da
// testnet na primeira vez).
//
// Exporta só as functions (index.js atribui explicitamente); os helpers
// puros ficam em module.exports._pure para os testes.

const crypto = require("crypto");
const functions = require("firebase-functions");
const admin = require("firebase-admin");

const NETWORKS = {
  testnet: {
    ws: "wss://s.altnet.rippletest.net:51233",
    explorer: "https://testnet.xrpl.org/transactions/",
  },
};
const NETWORK = "testnet";
// Valor simbólico por desafio na testnet (o faucet dá 100 XRP de teste). O
// valor do prêmio em BRL vai no memo.
const ESCROW_XRP = "1";
// Se ninguém liberar o cofre, ele pode ser cancelado 30 dias após o prazo.
const CANCEL_AFTER_S = 30 * 24 * 3600;

// ── Helpers puros (testados) ────────────────────────────────────────────────
const RIPPLE_EPOCH = 946684800; // 2000-01-01T00:00:00Z em unix

/**
 * ISO → segundos desde a época Ripple (2000-01-01).
 * @param {string} iso
 * @return {number}
 */
const toRippleTime = (iso) =>
  Math.floor(Date.parse(iso) / 1000) - RIPPLE_EPOCH;

const hex = (s) => Buffer.from(String(s), "utf8").toString("hex").toUpperCase();

/**
 * Memo no formato do XRPL (MemoType/MemoData em hex).
 * @param {string} type
 * @param {Object} data
 * @return {Object}
 */
const memo = (type, data) => ({
  Memo: {MemoType: hex(type), MemoData: hex(JSON.stringify(data))},
});

/**
 * Id de vencedor sem dado pessoal: 16 hex do sha256 do uid.
 * @param {string} uid
 * @return {string}
 */
const hashUid = (uid) =>
  crypto.createHash("sha256").update(String(uid)).digest("hex").slice(0, 16);

const explorerUrl = (hash, net = NETWORK) =>
  `${NETWORKS[net].explorer}${hash}`;

/**
 * Transação de criação do cofre do prêmio.
 * @param {Object} p {account, challengeId, prizeBrl, expiresAt, region}
 * @return {Object|null} null se o prazo já passou ou é inválido
 */
function escrowCreateTx({account, challengeId, prizeBrl, expiresAt, region}) {
  const finishAfter = toRippleTime(expiresAt);
  if (!Number.isFinite(finishAfter) ||
      finishAfter <= toRippleTime(new Date().toISOString())) {
    return null;
  }
  return {
    TransactionType: "EscrowCreate",
    Account: account,
    Destination: account,
    Amount: String(Number(ESCROW_XRP) * 1e6), // drops
    FinishAfter: finishAfter,
    CancelAfter: finishAfter + CANCEL_AFTER_S,
    Memos: [memo("desafiopago/prize", {
      challengeId, prizeBrl: Number(prizeBrl) || 0, region: region || "BR",
    })],
  };
}

/**
 * Transação de liberação do cofre com o resultado.
 * @param {Object} p {account, escrowSeq, challengeId, winnerIds, prizeBrl}
 * @return {Object}
 */
function escrowFinishTx({account, escrowSeq, challengeId, winnerIds,
  prizeBrl}) {
  const n = (winnerIds || []).length;
  const per = n > 0 ? Math.floor((Number(prizeBrl) || 0) * 100 / n) / 100 : 0;
  return {
    TransactionType: "EscrowFinish",
    Account: account,
    Owner: account,
    OfferSequence: escrowSeq,
    Memos: [memo("desafiopago/result", {
      challengeId,
      winners: n,
      prizePerWinnerBrl: per,
      winnerIds: (winnerIds || []).map(hashUid),
    })],
  };
}

// ── Rede ────────────────────────────────────────────────────────────────────
// `deps` permite injetar um cliente falso nos testes.
async function _client(deps) {
  if (deps && deps.client) return deps.client;
  const xrpl = require("xrpl");
  const c = new xrpl.Client(NETWORKS[NETWORK].ws);
  await c.connect();
  return c;
}

async function _wallet(db, client, deps) {
  const xrpl = (deps && deps.xrpl) || require("xrpl");
  const ref = db.collection("secure_config").doc("xrpl");
  const doc = await ref.get();
  let wallet;
  if (doc.exists && doc.data().seed) {
    wallet = xrpl.Wallet.fromSeed(doc.data().seed);
  } else {
    // Testnet: carteira nova direto do faucet (XRP de teste, sem valor).
    const r = await client.fundWallet();
    wallet = r.wallet;
    await ref.set({
      seed: wallet.seed, address: wallet.address, network: NETWORK,
      createdAt: new Date().toISOString(),
    });
    return wallet;
  }
  // Testnet: completa o saldo quando estiver baixo (cada cofre usa reserva).
  try {
    const bal = Number(await client.getXrpBalance(wallet.address));
    if (bal < 20) await client.fundWallet(wallet);
  } catch (e) {
    // conta ainda não ativada / faucet fora: segue e deixa o envio dizer.
  }
  return wallet;
}

async function _enabled(db) {
  const c = await db.collection("config").doc("xrpl").get();
  return !(c.exists && c.data().enabled === false);
}

/**
 * Registra o prêmio de um desafio real no XRPL (EscrowCreate). Idempotente.
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} challengeId
 * @param {Object} [deps]
 * @return {Promise<string>} o que aconteceu
 */
async function recordPrizeEscrow(db, challengeId, deps) {
  if (!(await _enabled(db))) return "disabled";
  const ref = db.collection("challenges").doc(challengeId);
  const snap = await ref.get();
  if (!snap.exists) return "missing";
  const ch = snap.data();
  if (ch.isVirtual === true) return "virtual";
  if (ch.xrpl && ch.xrpl.escrowTx) return "already";
  if (ch.status !== "active") return "not_active";

  const client = await _client(deps);
  try {
    const wallet = await _wallet(db, client, deps);
    const tx = escrowCreateTx({
      account: wallet.address, challengeId, prizeBrl: ch.amount,
      expiresAt: ch.expiresAt, region: ch.region,
    });
    if (!tx) return "expired";
    const res = await client.submitAndWait(tx, {wallet, autofill: true});
    const r = res.result;
    const code = r.meta && r.meta.TransactionResult;
    if (code !== "tesSUCCESS") throw new Error(`EscrowCreate: ${code}`);
    const seq = (r.tx_json && r.tx_json.Sequence) || r.Sequence;
    await ref.update({
      xrpl: {
        network: NETWORK,
        account: wallet.address,
        escrowTx: r.hash,
        escrowSeq: seq,
        escrowXrp: ESCROW_XRP,
        prizeBrl: Number(ch.amount) || 0,
        createdAt: new Date().toISOString(),
      },
    });
    return "recorded";
  } finally {
    if (!(deps && deps.client)) await client.disconnect().catch(() => {});
  }
}

/**
 * Libera o cofre de um desafio encerrado com o resultado (EscrowFinish).
 * Idempotente. Antes do prazo (encerramento manual antecipado), marca para
 * nova tentativa (cron).
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} challengeId
 * @param {Object} [deps]
 * @return {Promise<string>}
 */
async function releasePrizeEscrow(db, challengeId, deps) {
  if (!(await _enabled(db))) return "disabled";
  const ref = db.collection("challenges").doc(challengeId);
  const snap = await ref.get();
  if (!snap.exists) return "missing";
  const ch = snap.data();
  const x = ch.xrpl || {};
  if (!x.escrowTx || x.escrowSeq == null) return "no_escrow";
  if (x.releaseTx) return "already";
  if (ch.status !== "finished") return "not_finished";
  if (Date.parse(ch.expiresAt) > Date.now()) {
    await ref.update({"xrpl.releasePending": true});
    return "too_early";
  }

  const client = await _client(deps);
  try {
    const wallet = await _wallet(db, client, deps);
    const tx = escrowFinishTx({
      account: wallet.address, escrowSeq: x.escrowSeq, challengeId,
      winnerIds: ch.winnerIds || [], prizeBrl: ch.amount,
    });
    const res = await client.submitAndWait(tx, {wallet, autofill: true});
    const code = res.result.meta && res.result.meta.TransactionResult;
    if (code !== "tesSUCCESS") throw new Error(`EscrowFinish: ${code}`);
    await ref.update({
      "xrpl.releaseTx": res.result.hash,
      "xrpl.releasedAt": new Date().toISOString(),
      "xrpl.releasePending": false,
      "xrpl.winners": (ch.winnerIds || []).length,
    });
    return "released";
  } finally {
    if (!(deps && deps.client)) await client.disconnect().catch(() => {});
  }
}

// Erro de rede nunca derruba nada do app: fica registrado no próprio desafio
// e o cron tenta de novo.
async function _safe(db, challengeId, fn, field) {
  try {
    return await fn(db, challengeId);
  } catch (e) {
    console.error(`xrpl ${field} ${challengeId}:`, e.message);
    await db.collection("challenges").doc(challengeId).update({
      [`xrpl.${field}Error`]: String(e.message).slice(0, 300),
      [`xrpl.${field}ErrorAt`]: new Date().toISOString(),
      "xrpl.retry": true,
    }).catch(() => {});
    return "error";
  }
}

exports.xrplOnChallengeCreate = functions
    .runWith({timeoutSeconds: 120})
    .firestore.document("challenges/{id}")
    .onCreate(async (snap, context) => {
      if (snap.data().isVirtual === true) return null;
      await _safe(admin.firestore(), context.params.id,
          recordPrizeEscrow, "create");
      return null;
    });

exports.xrplOnChallengeFinish = functions
    .runWith({timeoutSeconds: 120})
    .firestore.document("challenges/{id}")
    .onUpdate(async (change, context) => {
      const b = change.before.data();
      const a = change.after.data();
      if (!(b.status === "active" && a.status === "finished")) return null;
      if (!a.xrpl || !a.xrpl.escrowTx) return null;
      await _safe(admin.firestore(), context.params.id,
          releasePrizeEscrow, "release");
      return null;
    });

// Nova tentativa a cada 30 min: falhas de rede e liberações antecipadas.
exports.xrplRetry = functions
    .runWith({timeoutSeconds: 300})
    .pubsub.schedule("every 30 minutes")
    .onRun(async () => {
      const db = admin.firestore();
      const [retry, pending] = await Promise.all([
        db.collection("challenges").where("xrpl.retry", "==", true)
            .limit(20).get(),
        db.collection("challenges").where("xrpl.releasePending", "==", true)
            .limit(20).get(),
      ]);
      const ids = new Set([...retry.docs, ...pending.docs].map((d) => d.id));
      for (const id of ids) {
        const doc = await db.collection("challenges").doc(id).get();
        const x = (doc.data() || {}).xrpl || {};
        const fn = x.escrowTx ? releasePrizeEscrow : recordPrizeEscrow;
        const r = await _safe(db, id, fn, x.escrowTx ? "release" : "create");
        if (r !== "error" && r !== "too_early") {
          await doc.ref.update({"xrpl.retry": false}).catch(() => {});
        }
      }
      return null;
    });

module.exports._pure = {
  toRippleTime, memo, hashUid, explorerUrl, escrowCreateTx, escrowFinishTx,
  recordPrizeEscrow, releasePrizeEscrow, RIPPLE_EPOCH,
};
