"use strict";
// Simulação dos fluxos de dinheiro do index.js REAL sobre o Firestore em
// memória (fakefire.js). Rodar: node --test money_flows.test.js
const test = require("node:test");
const assert = require("node:assert");
const F = require("../test_support/fakefire");
const fx = require("../index.js");

const HOUR = 3600 * 1000;
const iso = (ms) => new Date(Date.now() + ms).toISOString();
const ctx = (uid) => ({auth: {uid, token: {}}});
const user = (uid, extra = {}) => F.put(`users/${uid}`, {
  balance: 0, pendingBalance: 0, lockedBalance: 0, totalEarned: 0,
  totalVotesReceived: 0, ...extra});
const challenge = (id, extra = {}) => F.put(`challenges/${id}`, {
  title: "Desafio " + id, createdBy: "creator", amount: 10.01,
  creatorContribution: 10.01, status: "active", region: "BR",
  voteCount: 0, entryCount: 0, winnerIds: [], expiresAt: iso(HOUR), ...extra});
const entry = (id, chId, userId, votes, extra = {}) => F.put(`entries/${id}`, {
  challengeId: chId, userId, voteCount: votes, isActive: true,
  contentType: "image", ...extra});
const code = async (p) => {
  try {
    await p; return "ok";
  } catch (e) {
    return e.code || e.message;
  }
};

test.beforeEach(() => F.reset());
test.after(() => assert.strictEqual(F.violations(), 0,
    "houve leitura depois de escrita numa transação"));

// ── VOTE ──────────────────────────────────────────────────────────────────
test("vote: voto normal conta 1x e o segundo é recusado", async () => {
  user("creator"); user("ana"); user("bob");
  challenge("c1");
  entry("e1", "c1", "ana", 0);
  assert.strictEqual(await code(fx.vote({challengeId: "c1", entryId: "e1"}, ctx("bob"))), "ok");
  assert.strictEqual(F.read("entries/e1").voteCount, 1);
  assert.strictEqual(F.read("users/ana").totalVotesReceived, 1);
  assert.strictEqual(await code(fx.vote({challengeId: "c1", entryId: "e1"}, ctx("bob"))), "already-exists");
});

test("vote: prazo vencido (ainda 'active') não vota", async () => {
  user("creator"); user("ana"); user("bob");
  challenge("c1", {expiresAt: iso(-60 * 1000)});
  entry("e1", "c1", "ana", 0);
  assert.strictEqual(await code(fx.vote({challengeId: "c1", entryId: "e1"}, ctx("bob"))), "failed-precondition");
  assert.strictEqual(F.read("entries/e1").voteCount, 0);
});

test("vote: participação de outro desafio é recusada", async () => {
  user("creator"); user("ana"); user("bob");
  challenge("c1"); challenge("c2");
  entry("e2", "c2", "ana", 0);
  assert.strictEqual(await code(fx.vote({challengeId: "c1", entryId: "e2"}, ctx("bob"))), "invalid-argument");
});

test("vote: não gasta o voto em participação que não pode ganhar", async () => {
  user("creator"); user("bob");
  challenge("c1");
  entry("eDel", "c1", "deleted", 0);
  entry("eDemo", "c1", "demo_123", 0, {isDemo: true});
  entry("eOrf", "c1", "semdoc", 0);
  for (const id of ["eDel", "eDemo", "eOrf"]) {
    assert.strictEqual(await code(fx.vote({challengeId: "c1", entryId: id}, ctx("bob"))),
        "failed-precondition", id);
  }
  assert.strictEqual(F.read("votes/bob_c1"), undefined, "voto não pode ter sido gravado");
});

test("vote: admin ainda vota em participação demo (uso de demonstração)", async () => {
  user("creator"); user("adm"); F.put("admins/adm", {});
  challenge("c1");
  entry("eDemo", "c1", "demo_1", 0, {isDemo: true});
  assert.strictEqual(await code(fx.vote({challengeId: "c1", entryId: "eDemo"}, ctx("adm"))), "ok");
  assert.strictEqual(F.read("entries/eDemo").voteCount, 1);
});

// ── FINALIZE ──────────────────────────────────────────────────────────────
test("finalize: conta excluída na frente não trava; empate divide e o centavo fica", async () => {
  user("creator", {pendingBalance: 10.01}); user("ana"); user("bob");
  challenge("c1", {expiresAt: iso(-60 * 1000)});
  entry("eDel", "c1", "deleted", 9);
  entry("eA", "c1", "ana", 3);
  entry("eB", "c1", "bob", 3);
  await fx.finalizeChallenges();
  const c = F.read("challenges/c1");
  assert.strictEqual(c.status, "finished");
  assert.deepStrictEqual([...c.winnerIds].sort(), ["ana", "bob"]);
  assert.strictEqual(F.read("users/ana").balance, 5.00);
  assert.strictEqual(F.read("users/bob").balance, 5.00);
  assert.strictEqual(F.read("users/creator").pendingBalance, 0);
});

test("finalize: só inelegíveis → encerra sem vencedor e libera o criador", async () => {
  user("creator", {pendingBalance: 10.01});
  challenge("c1", {expiresAt: iso(-60 * 1000)});
  entry("eDel", "c1", "deleted", 5);
  entry("eDemo", "c1", "demo_1", 7, {isDemo: true});
  await fx.finalizeChallenges();
  const c = F.read("challenges/c1");
  assert.strictEqual(c.status, "finished");
  assert.deepStrictEqual(c.winnerIds, []);
  assert.strictEqual(F.read("users/creator").pendingBalance, 0);
});

test("finalize: rodar 2x não paga em dobro", async () => {
  user("creator", {pendingBalance: 10.01}); user("ana");
  challenge("c1", {expiresAt: iso(-60 * 1000), amount: 10});
  entry("eA", "c1", "ana", 2);
  await fx.finalizeChallenges();
  await fx.adminFinishChallenge({challengeId: "c1"}, ctx("adm")).catch(() => {});
  await fx.finalizeChallenges();
  assert.strictEqual(F.read("users/ana").balance, 10);
});

// ── DELETE ACCOUNT ────────────────────────────────────────────────────────
test("deleteAccount: app antigo (sem lang) com saldo recebe mensagem acionável", async () => {
  user("ana", {balance: 50, username: "ana"});
  let err;
  try {
    await fx.deleteAccount({}, ctx("ana"));
  } catch (e) {
    err = e;
  }
  assert.strictEqual(err.code, "failed-precondition");
  assert.match(err.message, /Atualize a página/);
  assert.deepStrictEqual(err.details, {reason: "balance", balance: 50});
  assert.ok(F.read("users/ana"), "conta não pode ter sido apagada");
});

test("deleteAccount: confirmou o valor certo → apaga tudo e registra o saldo perdido", async () => {
  user("ana", {balance: 50, username: "ana"});
  F.put("usernames/ana", {uid: "ana"});
  F.put("verificationRequests/ana", {cpf: "123"});
  F.put("users/ana/notifications/n1", {t: 1});
  challenge("c1", {createdBy: "x"});
  entry("eA", "c1", "ana", 1);
  await fx.deleteAccount({forfeitBalance: true, confirmedBalance: 50, lang: "pt"}, ctx("ana"));
  assert.strictEqual(F.read("users/ana"), undefined);
  assert.strictEqual(F.read("usernames/ana"), undefined);
  assert.strictEqual(F.read("verificationRequests/ana"), undefined);
  assert.strictEqual(F.read("users/ana/notifications/n1"), undefined);
  assert.strictEqual(F.read("entries/eA").userId, "deleted");
  assert.strictEqual(F.read("entries/eA").isActive, false, "desafio ativo: sai da disputa");
  const logs = [...F.store].filter(([p, d]) => p.startsWith("audit_logs/") &&
      d.type === "account_deleted_forfeit");
  assert.strictEqual(logs.length, 1);
  assert.strictEqual(logs[0][1].amount, 50);
  assert.deepStrictEqual(F.audit.authDeleted, ["ana"]);
});

test("deleteAccount: saldo maior que o confirmado (prêmio caiu) → recusa com o valor novo", async () => {
  user("ana", {balance: 300.5});
  let err;
  try {
    await fx.deleteAccount({forfeitBalance: true, confirmedBalance: 0.5, lang: "pt"}, ctx("ana"));
  } catch (e) {
    err = e;
  }
  assert.strictEqual(err.code, "failed-precondition");
  assert.deepStrictEqual(err.details, {reason: "balance", balance: 300.5});
  assert.ok(F.read("users/ana"));
  assert.deepStrictEqual(F.audit.authDeleted, []);
});

test("deleteAccount: Pix gerado e ainda válido bloqueia", async () => {
  user("ana");
  F.put("payments/p1", {userId: "ana", status: "pending", expiresAt: iso(20 * 60 * 1000)});
  assert.strictEqual(await code(fx.deleteAccount({lang: "pt"}, ctx("ana"))), "failed-precondition");
  F.put("payments/p1", {userId: "ana", status: "pending", expiresAt: iso(-60 * 1000)});
  assert.strictEqual(await code(fx.deleteAccount({lang: "pt"}, ctx("ana"))), "ok");
});

test("deleteAccount: créditos em desafio ativo continuam bloqueando", async () => {
  user("ana", {pendingBalance: 10});
  assert.strictEqual(await code(fx.deleteAccount({lang: "pt"}, ctx("ana"))), "failed-precondition");
});

// ── WEBHOOK PIX ───────────────────────────────────────────────────────────
const res = () => {
  const r = {code: null};
  r.sendStatus = (c) => {
    r.code = c; return r;
  };
  r.status = (c) => {
    r.code = c; return r;
  };
  r.send = () => r; r.json = () => r;
  return r;
};

test("webhook: Pix pago de conta excluída vira 'approved_orphan' com log e 200", async () => {
  F.setMpStatus("approved");
  F.put("payments/777", {userId: "ana", amount: 25, purpose: "deposit", status: "pending"});
  const r = res();
  await fx.mercadoPagoWebhook({method: "POST", body: {type: "payment", data: {id: "777"}},
    headers: {}, query: {}}, r);
  assert.strictEqual(r.code, 200);
  assert.strictEqual(F.read("payments/777").status, "approved_orphan");
  const logs = [...F.store].filter(([p, d]) => p.startsWith("audit_logs/") &&
      d.type === "deposit_orphan_deleted_user");
  assert.strictEqual(logs.length, 1);
  // reenvio do MP: idempotente
  const r2 = res();
  await fx.mercadoPagoWebhook({method: "POST", body: {type: "payment", data: {id: "777"}},
    headers: {}, query: {}}, r2);
  assert.strictEqual(r2.code, 200);
});

test("webhook: Pix normal credita 1x mesmo com reenvio", async () => {
  F.setMpStatus("approved");
  user("ana", {balance: 0});
  F.put("payments/888", {userId: "ana", amount: 25, purpose: "deposit", status: "pending"});
  const call = async () => {
    const r = res();
    await fx.mercadoPagoWebhook({method: "POST", body: {type: "payment", data: {id: "888"}},
      headers: {}, query: {}}, r);
    return r.code;
  };
  assert.strictEqual(await call(), 200);
  assert.strictEqual(await call(), 200);
  assert.strictEqual(F.read("users/ana").balance, 25);
  assert.strictEqual(F.read("payments/888").status, "approved");
});

// ── CENTAVOS ──────────────────────────────────────────────────────────────
test("centavos: criar desafio e aportar arredondam ao centavo", async () => {
  user("ana", {balance: 100});
  const {challengeId} = await fx.createChallenge(
      {title: "t", description: "d", amount: 10.555, durationDays: 3}, ctx("ana"));
  assert.strictEqual(F.read(`challenges/${challengeId}`).amount, 10.56);
  assert.strictEqual(F.read("users/ana").balance, 89.44);
  await fx.addAmount({challengeId, value: 0.004}, ctx("ana")).catch((e) => {
    assert.strictEqual(e.code, "invalid-argument"); // 0,004 → 0,00
  });
  await fx.addAmount({challengeId, value: 1.006}, ctx("ana")); // → 1,01
  assert.strictEqual(Math.round(F.read("users/ana").balance * 100) / 100, 88.43);
});

// ── AUTO-VOTOS ────────────────────────────────────────────────────────────
test("auto-votos: desligado por padrão (transparência)", async () => {
  user("ana");
  challenge("vivo");
  entry("e1", "vivo", "ana", 0);
  await fx.autoVoteRealEntries();
  assert.strictEqual(F.read("entries/e1").voteCount, 0);
});

test("auto-votos: desafio com prazo vencido não recebe +1", async () => {
  F.put("config/engagement", {autoVotes: true});
  user("ana"); user("bob");
  challenge("vivo"); challenge("vencido", {expiresAt: iso(-60 * 1000)});
  entry("e1", "vivo", "ana", 0);
  entry("e2", "vencido", "bob", 0);
  await fx.autoVoteRealEntries();
  assert.strictEqual(F.read("entries/e1").voteCount, 1);
  assert.strictEqual(F.read("entries/e2").voteCount, 0);
});

// ── VÍDEO POR LINK ────────────────────────────────────────────────────────
const {verificationCode} = require("../video_link");

// oEmbed falso: id → resposta. Sem entrada = 404.
const withOembed = async (map, fn) => {
  const orig = global.fetch;
  global.fetch = async (url) => {
    const id = decodeURIComponent(String(url)).match(/v=([A-Za-z0-9_-]{11})/);
    const r = id && map[id[1]];
    if (!r) return {status: 404, ok: false, json: async () => ({})};
    if (r.status) return {status: r.status, ok: false, json: async () => ({})};
    return {status: 200, ok: true, json: async () => r};
  };
  try {
    return await fn();
  } finally {
    global.fetch = orig;
  }
};
const YT = "il_MMI2MOYM";
const YT2 = "wXSbAW0B2FQ";
const submit = (uid, url, chId = "c1") => fx.submitEntry(
    {challengeId: chId, contentType: "videoLink", contentUrl: url}, ctx(uid));

test("vídeo YouTube: código no título + vertical → verificado na hora", async () => {
  user("creator"); user("ana");
  challenge("c1");
  const code = verificationCode("ana", "c1");
  const r = await withOembed({[YT]: {title: `Meu sol #${code}`, width: 113, height: 200}},
      () => submit("ana", `https://youtube.com/shorts/${YT}?si=x`));
  assert.strictEqual(r.videoCheck, "verified");
  const e = F.read(`entries/${r.entryId}`);
  assert.strictEqual(e.contentType, "videoLink");
  assert.strictEqual(e.contentUrl, `https://www.youtube.com/shorts/${YT}`);
  assert.strictEqual(e.contentText, e.contentUrl, "fallback do app antigo");
  assert.strictEqual(e.videoThumb, `https://i.ytimg.com/vi/${YT}/oar2.jpg`);
  assert.strictEqual(F.read("challenges/c1").entryCount, 1);
});

test("vídeo YouTube: sem código, horizontal, privado e inexistente são recusados", async () => {
  user("creator"); user("ana");
  challenge("c1");
  const expected = verificationCode("ana", "c1");
  const map = {
    [YT]: {title: "sem código", width: 113, height: 200},
    [YT2]: {title: `#${expected}`, width: 200, height: 113},
    AAAAAAAAAAA: {status: 401},
  };
  await withOembed(map, async () => {
    let err;
    try {
      await submit("ana", `youtu.be/${YT}`);
    } catch (e) {
      err = e;
    }
    assert.strictEqual(err.code, "failed-precondition");
    assert.deepStrictEqual(err.details, {reason: "code", code: expected});
    assert.strictEqual(await code(submit("ana", `youtu.be/${YT2}`)), "invalid-argument");
    assert.strictEqual(await code(submit("ana", "youtu.be/AAAAAAAAAAA")), "failed-precondition");
    assert.strictEqual(await code(submit("ana", "youtu.be/BBBBBBBBBBB")), "invalid-argument");
    assert.strictEqual(await code(submit("ana", "https://vimeo.com/1")), "invalid-argument");
  });
  assert.strictEqual(F.read("challenges/c1").entryCount, 0);
});

test("vídeo: o mesmo vídeo não entra 2x no mesmo desafio", async () => {
  user("creator"); user("ana"); user("bob");
  challenge("c1");
  F.put("entries/x", {challengeId: "c1", userId: "ana", contentType: "videoLink",
    videoId: YT, isActive: true, voteCount: 0});
  assert.strictEqual(await code(submit("bob", `youtu.be/${YT}`)), "already-exists");
});

test("vídeo Instagram: entra como 'pending' (admin confere a legenda)", async () => {
  user("creator"); user("ana");
  challenge("c1");
  const r = await submit("ana", "https://www.instagram.com/reel/DAz1J3gNVgI/?igsh=1");
  assert.strictEqual(r.videoCheck, "pending");
  assert.strictEqual(F.read(`entries/${r.entryId}`).videoCode, verificationCode("ana", "c1"));
});

test("imagem: só aceita arquivo do nosso Storage, do próprio usuário e desafio", async () => {
  user("creator"); user("ana");
  challenge("c1");
  const img = (url) => fx.submitEntry(
      {challengeId: "c1", contentType: "image", contentUrl: url}, ctx("ana"));
  assert.strictEqual(await code(img("https://evil.com/x.jpg")), "invalid-argument");
  const base = "https://firebasestorage.googleapis.com/v0/b/desafio-app-b8665." +
      "firebasestorage.app/o/";
  assert.strictEqual(await code(img(base + "entries%2Fc1%2Fbob_1.jpg?alt=media")),
      "invalid-argument", "arquivo de outro usuário");
  assert.strictEqual(await code(img(base + "entries%2Fc1%2Fana_1.jpg?alt=media&token=t")), "ok");
});

test("encerramento: vídeo pendente não ganha; vídeo que sumiu sai da disputa", async () => {
  user("creator", {pendingBalance: 10}); user("ana"); user("bob"); user("cris");
  challenge("c1", {expiresAt: iso(-60 * 1000), amount: 10});
  entry("eIg", "c1", "ana", 9, {contentType: "videoLink", videoProvider: "instagram",
    videoId: "DAz1J3gNVgI", videoCheck: "pending"});
  entry("eYtGone", "c1", "bob", 7, {contentType: "videoLink", videoProvider: "youtube",
    videoId: YT2, videoCheck: "verified"});
  entry("eImg", "c1", "cris", 2);
  await withOembed({}, () => fx.finalizeChallenges()); // YT2 → 404
  assert.deepStrictEqual(F.read("challenges/c1").winnerIds, ["cris"]);
  assert.strictEqual(F.read("users/cris").balance, 10);
  assert.strictEqual(F.read("entries/eYtGone").videoCheck, "unavailable");
});

test("encerramento: falha de rede NÃO desclassifica o vídeo verificado", async () => {
  user("creator", {pendingBalance: 10}); user("bob"); user("cris");
  challenge("c1", {expiresAt: iso(-60 * 1000), amount: 10});
  entry("eYt", "c1", "bob", 7, {contentType: "videoLink", videoProvider: "youtube",
    videoId: YT, videoCheck: "verified"});
  entry("eImg", "c1", "cris", 2);
  const orig = global.fetch;
  global.fetch = async () => {
    throw new Error("rede caiu");
  };
  try {
    await fx.finalizeChallenges();
  } finally {
    global.fetch = orig;
  }
  assert.deepStrictEqual(F.read("challenges/c1").winnerIds, ["bob"]);
});

test("admin aprova o vídeo do Instagram → passa a concorrer; recusar oculta", async () => {
  user("creator", {pendingBalance: 10}); user("ana"); user("bob"); user("adm");
  F.put("admins/adm", {});
  challenge("c1", {expiresAt: iso(-60 * 1000), amount: 10});
  entry("eIg", "c1", "ana", 9, {contentType: "videoLink", videoProvider: "instagram",
    videoCheck: "pending", videoCode: "DPX"});
  entry("eIg2", "c1", "bob", 5, {contentType: "videoLink", videoProvider: "instagram",
    videoCheck: "pending", videoCode: "DPY"});
  assert.strictEqual(await code(fx.adminReviewVideoEntry({entryId: "eIg", approve: true},
      ctx("ana"))), "permission-denied");
  await fx.adminReviewVideoEntry({entryId: "eIg", approve: true}, ctx("adm"));
  await fx.adminReviewVideoEntry({entryId: "eIg2", approve: false}, ctx("adm"));
  assert.strictEqual(F.read("entries/eIg").videoCheck, "verified");
  assert.strictEqual(F.read("entries/eIg2").isActive, false);
  await fx.finalizeChallenges();
  assert.deepStrictEqual(F.read("challenges/c1").winnerIds, ["ana"]);
});

test("vídeo pendente pode receber voto (só não ganha sem verificação)", async () => {
  user("creator"); user("ana"); user("bob");
  challenge("c1");
  entry("eIg", "c1", "ana", 0, {contentType: "videoLink", videoCheck: "pending"});
  assert.strictEqual(await code(fx.vote({challengeId: "c1", entryId: "eIg"}, ctx("bob"))), "ok");
});

// ── MÉTRICAS REAIS ────────────────────────────────────────────────────────
test("métricas reais: ignoram demonstração e votos de admin", async () => {
  F.put("admins/adm", {});
  F.put("publicProfiles/ana", {isVirtual: false});
  F.put("publicProfiles/v1", {isVirtual: true});
  F.put("publicProfiles/v2", {isVirtual: true});
  challenge("real", {amount: 50});
  challenge("demo", {amount: 300, isVirtual: true});
  entry("e1", "real", "ana", 0);
  entry("e2", "demo", "v1", 0, {isVirtual: true});
  F.put("votes/bob_real", {userId: "bob"});
  F.put("votes/admin_x", {isAdminVote: true});
  F.put("payments/p1", {status: "approved", amount: 25});
  F.put("payments/p2", {status: "pending", amount: 99});
  F.put("withdrawals/w1", {status: "paid", amount: 100});
  assert.strictEqual(await code(fx.adminRealMetrics({}, ctx("ana"))), "permission-denied");
  const m = await fx.adminRealMetrics({}, ctx("adm"));
  assert.deepStrictEqual(m.users, {real: 1, demo: 2});
  assert.strictEqual(m.challenges.real, 1);
  assert.strictEqual(m.challenges.realActive, 1);
  assert.strictEqual(m.challenges.realPrizeTotalBrl, 50);
  assert.strictEqual(m.challenges.userFundedPrizeBrl, 10.01); // contribuição do criador
  assert.deepStrictEqual(m.entries, {real: 1, demo: 1});
  assert.deepStrictEqual(m.votes, {byUsers: 1, byAdmins: 1});
  assert.deepStrictEqual(m.money, {depositsApproved: 1, depositsBrl: 25,
    withdrawalsPaid: 1, withdrawalsBrl: 100});
  assert.deepStrictEqual(m.onchain, {prizesRecorded: 0, resultsRecorded: 0});
});

// ── ZERAR SALDOS DE TESTE ─────────────────────────────────────────────────
test("resetTestAccounts: simula por padrão, zera só os uids pedidos e audita", async () => {
  user("g1", {balance: 48415, totalEarned: 48415});
  user("g2", {balance: 10, totalEarned: 10, lockedBalance: 5});
  user("bar", {balance: 3, totalEarned: 3});
  const call = async (body) => {
    const r = {code: 200, body: null};
    r.status = (c) => {
      r.code = c; return r;
    };
    r.json = (b) => {
      r.body = b; return r;
    };
    await fx.resetTestAccounts({method: "POST", body}, r);
    return r;
  };
  assert.strictEqual((await call({secret: "x", uids: ["g1"]})).code, 403);
  const dry = await call({secret: "SEED_2026_DP", uids: ["g1"]});
  assert.strictEqual(dry.body.report[0].result, "would_reset");
  assert.strictEqual(F.read("users/g1").balance, 48415, "dry run não mexe");
  const real = await call({secret: "SEED_2026_DP", uids: ["g1", "g2"], dryRun: false});
  assert.deepStrictEqual(real.body.report.map((x) => x.result),
      ["reset", "blocked_pending_or_locked"]);
  assert.strictEqual(F.read("users/g1").balance, 0);
  assert.strictEqual(F.read("users/g1").totalEarned, 0);
  assert.strictEqual(F.read("users/g2").balance, 10);
  assert.strictEqual(F.read("users/bar").balance, 3, "conta não pedida intacta");
  const logs = [...F.store].filter(([p, d]) => p.startsWith("audit_logs/") &&
      d.type === "test_balance_reset");
  assert.strictEqual(logs.length, 1);
  assert.strictEqual(logs[0][1].before.balance, 48415);
});
