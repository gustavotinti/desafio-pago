"use strict";

const test = require("node:test");
const assert = require("node:assert");
const {
  splitPrizeCents, withdrawalFee, withdrawalNet, xrpFromBrl,
  isSaneBrlPerUsd, normalizeRates, brlFromUsd, usdFromBrl,
} = require("../money");

test("split exato entre 2 vencedores", () => {
  assert.deepStrictEqual(
      splitPrizeCents(1000, 2), {perWinnerCents: 500, platformCents: 0});
});

test("centavo indivisível fica na plataforma (3 vencedores)", () => {
  assert.deepStrictEqual(
      splitPrizeCents(1000, 3), {perWinnerCents: 333, platformCents: 1});
});

test("split nunca distribui mais que o prêmio", () => {
  for (let cents = 1; cents <= 2000; cents += 7) {
    for (let n = 1; n <= 6; n++) {
      const r = splitPrizeCents(cents, n);
      assert.strictEqual(r.perWinnerCents * n + r.platformCents, cents);
      assert.ok(r.platformCents >= 0 && r.platformCents < n);
    }
  }
});

test("1 vencedor leva tudo", () => {
  assert.deepStrictEqual(
      splitPrizeCents(12345, 1), {perWinnerCents: 12345, platformCents: 0});
});

test("0 vencedores → tudo da plataforma", () => {
  assert.deepStrictEqual(
      splitPrizeCents(777, 0), {perWinnerCents: 0, platformCents: 777});
});

test("taxa de saque é 10% e líquido é 90%", () => {
  assert.strictEqual(withdrawalFee(100), 10);
  assert.strictEqual(withdrawalNet(100), 90);
});

test("taxa de saque arredonda a 2 casas", () => {
  assert.strictEqual(withdrawalFee(133.33), 13.33);
  assert.strictEqual(withdrawalNet(133.33), 120);
});

test("xrpFromBrl: converte e arredonda a 4 casas", () => {
  // 90 BRL / 13.5 (R$/XRP) = 6.6666... → 6.6667
  assert.strictEqual(xrpFromBrl(90, 13.5), 6.6667);
  // 100 BRL / 20 = 5 exato
  assert.strictEqual(xrpFromBrl(100, 20), 5);
});

test("xrpFromBrl: cotação inválida → 0 (nunca NaN/Infinity)", () => {
  assert.strictEqual(xrpFromBrl(100, 0), 0);
  assert.strictEqual(xrpFromBrl(100, -1), 0);
  assert.strictEqual(xrpFromBrl(100, undefined), 0);
});

// ─── Câmbio USD ↔ BRL (brlPerUsd = BRL por 1 USD) ───────────────────────────

test("brlFromUsd: US$ → R$ multiplica pela cotação BRL-por-USD", () => {
  // US$ 100 a 5,4 = R$ 540 (o bug antigo creditava R$ 18,50 com 0,185).
  assert.strictEqual(brlFromUsd(100, 5.4), 540);
  assert.strictEqual(brlFromUsd(10, 5.4), 54);
  assert.strictEqual(brlFromUsd(1.99, 5.4321), 10.81);
});

test("brlFromUsd: cotação invertida/inválida lança (nunca credita errado)", () => {
  assert.throws(() => brlFromUsd(100, 0.185));
  assert.throws(() => brlFromUsd(100, 0));
  assert.throws(() => brlFromUsd(100, undefined));
  assert.throws(() => brlFromUsd(100, 25));
});

test("usdFromBrl: R$ → US$ DIVIDE (mínimo R$100 ≈ US$ 18,52)", () => {
  assert.strictEqual(usdFromBrl(100, 5.4), 18.52);
  assert.strictEqual(usdFromBrl(540, 5.4), 100);
  assert.strictEqual(usdFromBrl(100, 5.4).toFixed(2), "18.52");
});

test("usdFromBrl: cotação inválida → 0 (só exibição, não lança)", () => {
  assert.strictEqual(usdFromBrl(100, 0.185), 0);
  assert.strictEqual(usdFromBrl(100, NaN), 0);
});

test("isSaneBrlPerUsd: só aceita entre 1 e 20", () => {
  assert.strictEqual(isSaneBrlPerUsd(5.4), true);
  assert.strictEqual(isSaneBrlPerUsd(0.185), false);
  assert.strictEqual(isSaneBrlPerUsd(1), false);
  assert.strictEqual(isSaneBrlPerUsd(20), false);
  assert.strictEqual(isSaneBrlPerUsd("5.4"), true);
  assert.strictEqual(isSaneBrlPerUsd(undefined), false);
});

const FALLBACK = {xrpUsd: 2.5, xrpBrl: 13.5, usdBrl: 13.5 / 2.5};

test("normalizeRates: cotação plausível passa intacta", () => {
  const r = normalizeRates(
      {xrpUsd: 3, xrpBrl: 16.5, usdBrl: 5.5, at: "x"}, FALLBACK);
  assert.strictEqual(r.usdBrl, 5.5);
  assert.strictEqual(r.at, "x");
});

test("normalizeRates: usdBrl invertido é recalculado de xrpBrl/xrpUsd", () => {
  const r = normalizeRates({xrpUsd: 2.5, xrpBrl: 13.5, usdBrl: 0.185}, FALLBACK);
  assert.strictEqual(r.usdBrl, 5.4);
  // E o depósito de US$ 100 credita ~R$ 540, não R$ 18,50.
  assert.strictEqual(brlFromUsd(100, r.usdBrl), 540);
});

test("normalizeRates: tudo inválido cai no fallback (5,4)", () => {
  assert.strictEqual(normalizeRates(null, FALLBACK).usdBrl, 5.4);
  assert.strictEqual(
      normalizeRates({xrpUsd: 1, xrpBrl: 0.1, usdBrl: 0.1}, FALLBACK).usdBrl,
      5.4);
});

test("normalizeRates: fallback é consistente e sem fallback inválido lança", () => {
  assert.strictEqual(normalizeRates(FALLBACK, null).usdBrl, 5.4);
  assert.throws(() => normalizeRates({xrpUsd: 0, xrpBrl: 0}, null));
});

test("mensagem de mínimo: R$100 a 5,4 ≈ US$ 18,52 (não US$ 540)", () => {
  const usd = usdFromBrl(100, normalizeRates(FALLBACK, null).usdBrl);
  assert.strictEqual(usd.toFixed(2), "18.52");
});
