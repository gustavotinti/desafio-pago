"use strict";

const test = require("node:test");
const assert = require("node:assert");
const {
  splitPrizeCents, withdrawalFee, withdrawalNet, xrpFromBrl,
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
