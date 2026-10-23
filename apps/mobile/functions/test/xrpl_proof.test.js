"use strict";
// Prova de prêmio no XRPL: helpers puros + fluxo com cliente de rede falso
// sobre o Firestore em memória (o fluxo real foi testado ao vivo na testnet).
const test = require("node:test");
const assert = require("node:assert");
const F = require("../test_support/fakefire");
const {_pure: X} = require("../xrpl_proof");

const iso = (ms) => new Date(Date.now() + ms).toISOString();
const fromHex = (h) => Buffer.from(h, "hex").toString("utf8");

const fakeNet = () => {
  const sent = [];
  return {
    sent,
    deps: {
      client: {
        fundWallet: async () => ({wallet: {address: "rPLAT", seed: "sSEED"}}),
        getXrpBalance: async () => "100",
        submitAndWait: async (tx) => {
          sent.push(tx);
          return {result: {hash: "H_" + tx.TransactionType,
            meta: {TransactionResult: "tesSUCCESS"}, tx_json: {Sequence: 77}}};
        },
      },
      xrpl: {Wallet: {fromSeed: (s) => ({address: "rPLAT", seed: s})}},
    },
  };
};

test.beforeEach(() => F.reset());

test("toRippleTime: época Ripple é 2000-01-01", () => {
  assert.strictEqual(X.toRippleTime("2000-01-01T00:00:00Z"), 0);
  assert.strictEqual(X.toRippleTime("2000-01-01T00:01:00Z"), 60);
});

test("escrowCreateTx: trava até o prazo, memo com o prêmio, recusa prazo vencido", () => {
  const exp = iso(3600 * 1000);
  const tx = X.escrowCreateTx({account: "rA", challengeId: "c1", prizeBrl: 50,
    expiresAt: exp, region: "BR"});
  assert.strictEqual(tx.TransactionType, "EscrowCreate");
  assert.strictEqual(tx.Destination, "rA");
  assert.strictEqual(tx.FinishAfter, X.toRippleTime(exp));
  assert.ok(tx.CancelAfter > tx.FinishAfter);
  assert.deepStrictEqual(JSON.parse(fromHex(tx.Memos[0].Memo.MemoData)),
      {challengeId: "c1", prizeBrl: 50, region: "BR"});
  assert.strictEqual(X.escrowCreateTx({account: "rA", challengeId: "c1",
    prizeBrl: 50, expiresAt: iso(-1000)}), null);
});

test("escrowFinishTx: resultado sem dado pessoal (uid em hash) e divisão", () => {
  const tx = X.escrowFinishTx({account: "rA", escrowSeq: 5, challengeId: "c1",
    winnerIds: ["ana", "bob"], prizeBrl: 10.01});
  const m = JSON.parse(fromHex(tx.Memos[0].Memo.MemoData));
  assert.strictEqual(tx.OfferSequence, 5);
  assert.strictEqual(m.winners, 2);
  assert.strictEqual(m.prizePerWinnerBrl, 5); // centavo indivisível fica
  assert.ok(!JSON.stringify(m).includes("ana"));
  assert.strictEqual(m.winnerIds[0], X.hashUid("ana"));
});

test("fluxo: desafio real registra e libera; virtual e repetido não", async () => {
  const net = fakeNet();
  F.put("challenges/c1", {status: "active", amount: 50, region: "BR",
    expiresAt: iso(3600 * 1000), winnerIds: []});
  F.put("challenges/v1", {status: "active", amount: 50, isVirtual: true,
    expiresAt: iso(3600 * 1000)});
  assert.strictEqual(await X.recordPrizeEscrow(F.db, "c1", net.deps), "recorded");
  assert.strictEqual(await X.recordPrizeEscrow(F.db, "c1", net.deps), "already");
  assert.strictEqual(await X.recordPrizeEscrow(F.db, "v1", net.deps), "virtual");
  const x = F.read("challenges/c1").xrpl;
  assert.strictEqual(x.escrowTx, "H_EscrowCreate");
  assert.strictEqual(x.escrowSeq, 77);
  assert.strictEqual(F.read("secure_config/xrpl").address, "rPLAT");

  // Encerrado antes do prazo (admin): fica pendente para o cron.
  F.put("challenges/c1", {...F.read("challenges/c1"), status: "finished",
    winnerIds: ["ana"]});
  assert.strictEqual(await X.releasePrizeEscrow(F.db, "c1", net.deps), "too_early");
  assert.strictEqual(F.read("challenges/c1").xrpl.releasePending, true);

  // Depois do prazo: libera com o resultado.
  F.put("challenges/c1", {...F.read("challenges/c1"), expiresAt: iso(-1000)});
  assert.strictEqual(await X.releasePrizeEscrow(F.db, "c1", net.deps), "released");
  assert.strictEqual(F.read("challenges/c1").xrpl.releaseTx, "H_EscrowFinish");
  assert.strictEqual(await X.releasePrizeEscrow(F.db, "c1", net.deps), "already");
  assert.deepStrictEqual(net.sent.map((t) => t.TransactionType),
      ["EscrowCreate", "EscrowFinish"]);
});

test("kill-switch: config/xrpl.enabled = false não envia nada", async () => {
  const net = fakeNet();
  F.put("config/xrpl", {enabled: false});
  F.put("challenges/c1", {status: "active", amount: 50, expiresAt: iso(3600 * 1000)});
  assert.strictEqual(await X.recordPrizeEscrow(F.db, "c1", net.deps), "disabled");
  assert.strictEqual(net.sent.length, 0);
});
