"use strict";

const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");
const {
  SITES, requestHost, siteForHost, siteForRequest, previewMeta,
  stripHeadMeta, rewriteHead, isAppShell, unavailableHtml,
} = require("../site_ctx");

// Espelho do <head> do web/index.html (BR) — o que o entryPreview recebe.
const BASE = `<!DOCTYPE html>
<html>
<head>
  <base href="/">
  <meta charset="UTF-8">
  <meta name="description" content="Desafios de foto valendo prêmios.">
  <link rel="canonical" href="https://desafiopago.com.br/">
  <!-- hreflang:start -->
  <link rel="alternate" hreflang="pt-BR" href="https://desafiopago.com.br/">
  <link rel="alternate" hreflang="en" href="https://trialspaid.web.app/">
  <link rel="alternate" hreflang="x-default" href="https://trialspaid.web.app/">
  <!-- hreflang:end -->
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="Desafio Pago">
  <meta property="og:title" content="Desafio Pago — desafios de foto">
  <meta property="og:description" content="Crie desafios.">
  <meta property="og:image" content="https://desafiopago.com.br/og-default.png">
  <meta property="og:url" content="https://desafiopago.com.br/">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="apple-mobile-web-app-title" content="Desafio Pago">
  <title>Desafio Pago — desafios de foto (Pix)</title>
  <link rel="manifest" href="manifest.json">
  <script type="application/ld+json">
  {"@context":"https://schema.org","@type":"WebSite","name":"Desafio Pago"}
  </script>
</head>
<body>
  <script src="flutter_bootstrap.js" async></script>
</body>
</html>`;

const count = (s, re) => (s.match(re) || []).length;

const metaFor = (site, extra = {}) => previewMeta(site, {
  challengeId: "ABC123", found: true, challengeTitle: "Pôr do sol",
  entryId: "E1", author: "Ana", ...extra,
});

test("detecta trialspaid pelo x-forwarded-host (e cai no BR sem host)", () => {
  assert.strictEqual(siteForRequest(
      {headers: {"x-forwarded-host": "trialspaid.web.app"}}), SITES.intl);
  assert.strictEqual(siteForRequest(
      {headers: {host: "TrialsPaid.web.app"}}), SITES.intl);
  assert.strictEqual(siteForRequest(
      {headers: {"x-forwarded-host": "desafiopago.com.br",
        "host": "us-central1-x.cloudfunctions.net"}}), SITES.br);
  assert.strictEqual(siteForRequest({headers: {}}), SITES.br);
  assert.strictEqual(siteForRequest({}), SITES.br);
  assert.strictEqual(siteForHost("desafiopago.web.app"), SITES.br);
  assert.strictEqual(requestHost({headers: {host: "A.B"}}), "a.b");
});

test("remove og/twitter/description/title/canonical duplicados", () => {
  const out = rewriteHead(BASE, metaFor(SITES.br));
  assert.strictEqual(count(out, /property="og:title"/g), 1);
  assert.strictEqual(count(out, /property="og:url"/g), 1);
  assert.strictEqual(count(out, /property="og:image"/g), 1);
  assert.strictEqual(count(out, /property="og:description"/g), 1);
  assert.strictEqual(count(out, /name="twitter:card"/g), 1);
  assert.strictEqual(count(out, /name="description"/g), 1);
  assert.strictEqual(count(out, /<title>/g), 1);
  assert.strictEqual(count(out, /rel="canonical"/g), 1);
  assert.ok(!out.includes("desafios de foto (Pix)</title>"));
  assert.ok(!out.includes("Desafio Pago — desafios de foto\""));
});

test("canonical self-referencial SEM ?entry=; og:url COM entry", () => {
  const out = rewriteHead(BASE, metaFor(SITES.br));
  assert.ok(out.includes(
      "<link rel=\"canonical\" href=\"https://desafiopago.com.br/challenges/ABC123\">"));
  assert.ok(!/rel="canonical"[^>]*entry=/.test(out));
  assert.ok(out.includes(
      "property=\"og:url\" content=\"https://desafiopago.com.br/challenges/ABC123?entry=E1\""));
  assert.ok(!out.includes("href=\"https://desafiopago.com.br/\">"));
});

test("não remove o JSON-LD, o manifest nem o bootstrap do app", () => {
  const out = rewriteHead(BASE, metaFor(SITES.br));
  assert.ok(out.includes("application/ld+json"));
  assert.ok(out.includes("\"@type\":\"WebSite\""));
  assert.ok(out.includes("rel=\"manifest\""));
  assert.ok(out.includes("apple-mobile-web-app-title"));
  assert.ok(out.includes("flutter_bootstrap.js"));
  assert.ok(out.includes("<base href=\"/\">"));
});

test("remove o hreflang home↔home da página de desafio", () => {
  const out = rewriteHead(BASE, metaFor(SITES.br));
  assert.strictEqual(count(out, /hreflang=/g), 0);
});

test("não muta a string de entrada (cache intacto)", () => {
  const before = String(BASE);
  rewriteHead(BASE, metaFor(SITES.br));
  stripHeadMeta(BASE);
  assert.strictEqual(BASE, before);
});

test("textos BR (pt) mantidos", () => {
  const out = rewriteHead(BASE, metaFor(SITES.br));
  assert.ok(out.includes("Ana quer o seu voto!"));
  assert.ok(out.includes("Toque e vote no Desafio Pago."));
  assert.ok(out.includes("<title>Pôr do sol · Desafio Pago</title>"));
  assert.ok(out.includes("og:site_name\" content=\"Desafio Pago\""));
});

test("intl: inglês, marca/URL/og:image do trialspaid", () => {
  const out = rewriteHead(BASE, metaFor(SITES.intl));
  assert.ok(out.includes("Ana wants your vote!"));
  assert.ok(out.includes("Tap to vote on TrialsPaid."));
  assert.ok(out.includes("og:site_name\" content=\"TrialsPaid\""));
  assert.ok(out.includes(
      "rel=\"canonical\" href=\"https://trialspaid.web.app/challenges/ABC123\""));
  assert.ok(out.includes(
      "og:image\" content=\"https://trialspaid.web.app/og-default.png\""));
  assert.ok(!out.includes("quer o seu voto"));
});

test("variações: sem autor, sem entry, desafio inexistente", () => {
  let m = metaFor(SITES.br, {author: ""});
  assert.strictEqual(m.title, "Vote nesta participação! 🗳️");
  m = metaFor(SITES.intl, {entryId: ""});
  assert.strictEqual(m.title, "Pôr do sol");
  assert.strictEqual(m.ogUrl, "https://trialspaid.web.app/challenges/ABC123");
  m = previewMeta(SITES.br, {challengeId: "NOPE", found: false});
  assert.strictEqual(m.noindex, true);
  const out = rewriteHead(BASE, m);
  assert.ok(out.includes("<meta name=\"robots\" content=\"noindex\">"));
  assert.strictEqual(count(out, /rel="canonical"/g), 0);
});

test("escapa HTML e trata $ literal no título", () => {
  const out = rewriteHead(BASE, metaFor(SITES.br,
      {author: "<b>\"x\"</b>", challengeTitle: "Ganhe $& $1 R$50"}));
  assert.ok(out.includes("&lt;b&gt;&quot;x&quot;&lt;/b&gt; quer o seu voto!"));
  assert.ok(out.includes("<title>Ganhe $&amp; $1 R$50 · Desafio Pago</title>"));
  assert.ok(!out.includes("<b>\"x\"</b>"));
});

test("id com caracteres especiais é codificado nas URLs", () => {
  const m = previewMeta(SITES.br,
      {challengeId: "a b", found: true, entryId: "e&1"});
  assert.strictEqual(m.canonical, "https://desafiopago.com.br/challenges/a%20b");
  assert.strictEqual(m.ogUrl,
      "https://desafiopago.com.br/challenges/a%20b?entry=e%261");
});

test("HTML sem </head> volta intacto; isAppShell recusa página de erro", () => {
  assert.strictEqual(rewriteHead("oops", metaFor(SITES.br)), "oops");
  assert.ok(isAppShell(BASE));
  assert.ok(!isAppShell("<html><head></head><body>503</body></html>"));
  assert.ok(!isAppShell(""));
  assert.ok(unavailableHtml(SITES.intl).includes("trialspaid.web.app/"));
});

test("web/index.html real: sai com 1 de cada tag após a reescrita", () => {
  const p = path.join(__dirname, "..", "..", "web", "index.html");
  if (!fs.existsSync(p)) return;
  const out = rewriteHead(fs.readFileSync(p, "utf8"), metaFor(SITES.br));
  for (const re of [/property="og:title"/g, /property="og:url"/g,
    /name="description"/g, /<title>/g, /rel="canonical"/g]) {
    assert.strictEqual(count(out, re), 1, String(re));
  }
  assert.ok(out.includes("application/ld+json"));
});
