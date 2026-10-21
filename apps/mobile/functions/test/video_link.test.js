"use strict";

const test = require("node:test");
const assert = require("node:assert");
const {
  parseVideoLink, verificationCode, hasCode, checkYouTube, isVertical,
} = require("../video_link");

// Mesmos vetores de test/video_link_test.dart (app) — os dois lados precisam
// gerar o MESMO código, senão o participante cola o código do app e o
// servidor recusa.
const CODE_VECTORS = [
  ["abc123", "c1", "DPSW36B"],
  ["uidXYZ789", "chal_42", "DP5XKBD"],
  ["Zk3mQp9TtYh2LsR8vWx1", "8hJ2kL0pQr", "DPXEEDX"],
];

test("verificationCode: vetores compartilhados com o Dart", () => {
  for (const [uid, cid, code] of CODE_VECTORS) {
    assert.strictEqual(verificationCode(uid, cid), code);
  }
});

test("verificationCode: muda com o desafio e com o usuário", () => {
  assert.notStrictEqual(verificationCode("a", "c1"), verificationCode("a", "c2"));
  assert.notStrictEqual(verificationCode("a", "c1"), verificationCode("b", "c1"));
  assert.match(verificationCode("a", "c1"), /^DP[A-HJ-NP-Z2-9]{5}$/);
});

test("parseVideoLink: formatos do YouTube viram o mesmo Short", () => {
  for (const l of [
    "https://youtube.com/shorts/il_MMI2MOYM?si=abc",
    "youtu.be/il_MMI2MOYM",
    "https://m.youtube.com/watch?v=il_MMI2MOYM&t=3",
    "https://www.youtube.com/embed/il_MMI2MOYM",
  ]) {
    const v = parseVideoLink(l);
    assert.ok(v, l);
    assert.strictEqual(v.provider, "youtube");
    assert.strictEqual(v.id, "il_MMI2MOYM");
    assert.strictEqual(v.url, "https://www.youtube.com/shorts/il_MMI2MOYM");
    assert.strictEqual(v.thumbUrl, "https://i.ytimg.com/vi/il_MMI2MOYM/oar2.jpg");
  }
});

test("parseVideoLink: Instagram (reel, p e o formato com usuário)", () => {
  const r = parseVideoLink("https://www.instagram.com/reel/DAz1J3gNVgI/?igsh=x");
  assert.deepStrictEqual(r, {
    provider: "instagram", id: "DAz1J3gNVgI",
    url: "https://www.instagram.com/reel/DAz1J3gNVgI/",
    embedUrl: "https://www.instagram.com/reel/DAz1J3gNVgI/embed/",
    thumbUrl: null,
  });
  assert.strictEqual(
      parseVideoLink("instagram.com/fulano/reel/DAz1J3gNVgI").url,
      "https://www.instagram.com/reel/DAz1J3gNVgI/");
  assert.strictEqual(parseVideoLink("https://www.instagram.com/p/DAz1J3gNVgI/").url,
      "https://www.instagram.com/p/DAz1J3gNVgI/");
});

test("parseVideoLink: recusa o que não é vídeo do YouTube/Instagram", () => {
  for (const l of [
    "", "   ", "https://vimeo.com/123", "https://youtube.com/shorts/curto",
    "javascript:alert(1)", "https://www.instagram.com/fulano/",
    "https://youtube.com.evil.com/shorts/il_MMI2MOYM",
    "https://evilyoutube.com/shorts/il_MMI2MOYM",
    "https://youtu.be/il_MMI2MOYM extra",
  ]) {
    assert.strictEqual(parseVideoLink(l), null, JSON.stringify(l));
  }
});

test("hasCode: ignora maiúsculas e aceita hashtag", () => {
  assert.ok(hasCode("Meu pôr do sol #dpsw36b 🌅", "DPSW36B"));
  assert.ok(!hasCode("Meu pôr do sol", "DPSW36B"));
});

const fakeFetch = (status, body) => async () => ({
  status, ok: status >= 200 && status < 300, json: async () => body,
});

test("checkYouTube: Short vertical com título", async () => {
  const r = await checkYouTube("x", {fetchImpl: fakeFetch(200,
      {title: "Pôr do sol DPSW36B", author_name: "Ana", width: 113, height: 200})});
  assert.strictEqual(r.status, "ok");
  assert.ok(isVertical(r));
  assert.ok(hasCode(r.title, "DPSW36B"));
});

test("checkYouTube: horizontal, inexistente, privado e falha de rede", async () => {
  const wide = await checkYouTube("x", {fetchImpl: fakeFetch(200, {width: 200, height: 113})});
  assert.ok(!isVertical(wide));
  assert.strictEqual((await checkYouTube("x", {fetchImpl: fakeFetch(404)})).status, "not_found");
  assert.strictEqual((await checkYouTube("x", {fetchImpl: fakeFetch(401)})).status, "private");
  assert.strictEqual((await checkYouTube("x", {fetchImpl: fakeFetch(500)})).status, "error");
  const boom = async () => {
    throw new Error("rede");
  };
  assert.strictEqual((await checkYouTube("x", {fetchImpl: boom})).status, "error");
});
