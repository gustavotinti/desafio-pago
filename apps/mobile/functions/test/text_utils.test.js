"use strict";

const test = require("node:test");
const assert = require("node:assert");
const {slugify, sanitizeHtml} = require("../text_utils");

test("slugify: minúsculas, sem acento, hifeniza", () => {
  assert.strictEqual(
      slugify("Como Ganhar DINHEIRO com Fotos"),
      "como-ganhar-dinheiro-com-fotos");
});

test("slugify: remove acentos e pontuação", () => {
  assert.strictEqual(
      slugify("Fotografia & renda extra: guia rápido!"),
      "fotografia-renda-extra-guia-rapido");
});

test("slugify: sem hífens nas pontas e sem vazio", () => {
  assert.strictEqual(slugify("  ---olá---  "), "ola");
  assert.strictEqual(slugify(""), "");
  assert.strictEqual(slugify(null), "");
});

test("slugify: limita a 80 caracteres", () => {
  const long = "palavra ".repeat(30);
  assert.ok(slugify(long).length <= 80);
});

test("sanitizeHtml: remove <script> e conteúdo", () => {
  const dirty = "<p>ok</p><script>alert(1)</script>";
  assert.strictEqual(sanitizeHtml(dirty), "<p>ok</p>");
});

test("sanitizeHtml: remove handlers on* e javascript:", () => {
  assert.ok(!sanitizeHtml("<a onclick=\"x()\">").includes("onclick"));
  assert.ok(!sanitizeHtml("<a href='javascript:x'>").includes("javascript:"));
});

test("sanitizeHtml: preserva HTML seguro", () => {
  const safe = "<p>Texto <strong>forte</strong> e <em>ênfase</em></p>";
  assert.strictEqual(sanitizeHtml(safe), safe);
});
