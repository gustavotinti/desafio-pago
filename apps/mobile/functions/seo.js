// ─── MÁQUINA DE SEO ORGÂNICO ──────────────────────────────────────────────────
// Hub de conteúdo "/novidades" renderizado no SERVIDOR (o app Flutter é canvas
// e o Google não lê) + sitemap.xml + geração de artigos por IA (fila de
// tópicos) + loop de demanda via Google Search Console.
//
// Provedor de IA: usa GEMINI_API_KEY se existir; senão OPENAI_API_KEY.
// Kill-switch da publicação automática: config/seo.autoPublish == false.

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const {getSecret} = require("./secrets");
const {slugify, sanitizeHtml} = require("./text_utils");

const SITE = "https://desafiopago.com.br";
const BRAND = "Desafio Pago";
const CREATOR = "Gustavo Tinti"; // crédito do criador (aparece no rodapé)

// Contexto por site: o mesmo conjunto de funções SSR serve o hub em PT
// (desafiopago) e em EN (trialspaid) — escolhido pelo host da requisição.
const CTX = {
  pt: {
    site: SITE, brand: BRAND, lang: "pt", htmlLang: "pt-BR", region: "BR",
    logoA: "DESAFIO", logoB: "PAGO", enterCta: "Entrar nos desafios",
    footerTagline: "desafios de foto valendo prêmios em dinheiro, " +
        "pagos via Pix.",
    activeChallenges: "Desafios ativos", news: "Novidades",
    openNow: "🔥 Desafios abertos agora no",
    joinCta: "Participar e concorrer aos prêmios",
    backToNews: "← Novidades", by: "Por",
    faqTitle: "Perguntas frequentes",
    articleCta: "Criar ou participar de um desafio agora",
    readNext: "Leia também", indexH1: "Novidades do",
    indexSub: "Dicas para ganhar desafios, fotografia com celular, renda " +
        "extra e tudo sobre desafios valendo prêmios em dinheiro.",
    indexTitle: "Novidades: dicas de desafios, fotos e renda extra",
    indexDesc: "Artigos e dicas do Desafio Pago: como ganhar desafios de " +
        "foto, divulgar sua participação, receber prêmios via Pix e fazer " +
        "renda extra online.",
    soon: "Em breve, novos artigos por aqui.", createdBy: "Criado por",
  },
  en: {
    site: "https://trialspaid.web.app", brand: "TrialsPaid", lang: "en",
    htmlLang: "en", region: "INTL", logoA: "TRIALS", logoB: "PAID",
    enterCta: "Enter the challenges",
    footerTagline: "photo challenges with real cash prizes, paid in crypto.",
    activeChallenges: "Active challenges", news: "News",
    openNow: "🔥 Challenges open right now on",
    joinCta: "Join and compete for the prizes",
    backToNews: "← News", by: "By",
    faqTitle: "Frequently asked questions",
    articleCta: "Create or join a challenge now",
    readNext: "Read next", indexH1: "News from",
    indexSub: "Tips to win photo challenges, mobile photography, extra " +
        "income and everything about challenges with real cash prizes.",
    indexTitle: "News: tips on challenges, photos and extra income",
    indexDesc: "Articles and tips from TrialsPaid: how to win photo " +
        "challenges, promote your entry, get paid in crypto and make " +
        "money online.",
    soon: "New articles coming soon.", createdBy: "Created by",
  },
};

const siteCtx = (req) => {
  const host = String(
      req.headers["x-forwarded-host"] || req.headers.host || "");
  return host.includes("trialspaid") ? CTX.en : CTX.pt;
};

// ─── Utilidades ───────────────────────────────────────────────────────────────

const esc = (s) => String(s == null ? "" : s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");

const fmtBrl = (v) => `R$ ${(Number(v) || 0).toFixed(2).replace(".", ",")}`;

const fmtDate = (iso, lang) => {
  try {
    const d = new Date(iso);
    if (lang === "en") {
      const m = ["January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"];
      return `${m[d.getMonth()]} ${d.getDate()}, ${d.getFullYear()}`;
    }
    const meses = ["janeiro", "fevereiro", "março", "abril", "maio", "junho",
      "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"];
    return `${d.getDate()} de ${meses[d.getMonth()]} de ${d.getFullYear()}`;
  } catch (e) {
    return "";
  }
};

// ─── IA: gera JSON (Gemini se houver chave; senão OpenAI) ────────────────────

const llmJson = async (prompt) => {
  const gemini = await getSecret("GEMINI_API_KEY");
  if (gemini) {
    const url = "https://generativelanguage.googleapis.com/v1beta/models/" +
        `gemini-2.0-flash:generateContent?key=${gemini}`;
    const r = await fetch(url, {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({
        contents: [{parts: [{text: prompt}]}],
        generationConfig: {
          responseMimeType: "application/json",
          temperature: 0.8,
        },
      }),
    });
    const j = await r.json();
    const text = j.candidates && j.candidates[0] &&
        j.candidates[0].content.parts[0].text;
    if (!text) throw new Error("Gemini sem resposta: " + JSON.stringify(j));
    return JSON.parse(text);
  }
  const openai = await getSecret("OPENAI_API_KEY");
  if (!openai) throw new Error("Sem GEMINI_API_KEY nem OPENAI_API_KEY");
  const r = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${openai}`,
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      temperature: 0.8,
      response_format: {type: "json_object"},
      messages: [{role: "user", content: prompt}],
    }),
  });
  const j = await r.json();
  const text = j.choices && j.choices[0] && j.choices[0].message.content;
  if (!text) throw new Error("OpenAI sem resposta: " + JSON.stringify(j));
  return JSON.parse(text);
};

// ─── Geração de artigo ───────────────────────────────────────────────────────

const articlePrompt = (topic) => `
Você é o redator do blog "Novidades" do ${BRAND} (desafiopago.com.br) —
plataforma brasileira onde usuários criam desafios de FOTO com prêmio em
dinheiro; outras pessoas participam com imagens e a mais votada leva o
prêmio (pagamento por Pix; taxa de 10% só no saque; saque mínimo R$100).

Escreva um artigo ORIGINAL e genuinamente útil, em português do Brasil,
sobre o tema: "${topic}".

Regras importantes:
- 900 a 1300 palavras, tom amigável e direto, sem enrolação.
- Conteúdo prático e honesto: dicas reais e acionáveis. NUNCA invente
  estatísticas, valores de ganhos ou promessas de dinheiro fácil.
- Mencione o ${BRAND} naturalmente (1 a 2 vezes) como UMA forma de colocar
  as dicas em prática — sem exagero publicitário.
- Escreva para quem busca esse tema no Google (intenção de busca real).
- HTML permitido no corpo: <p>, <ul>, <li>, <ol>, <strong>, <em>, <h3>.

Responda APENAS com JSON válido neste formato:
{
  "title": "título chamativo com a palavra-chave (máx 60 caracteres)",
  "metaDescription": "descrição para o Google (140-155 caracteres)",
  "intro": "<p>parágrafo de abertura...</p>",
  "sections": [
    {"heading": "subtítulo H2", "html": "<p>conteúdo da seção...</p>"}
  ],
  "faq": [
    {"question": "pergunta frequente", "answer": "resposta direta"}
  ],
  "keywords": ["palavra-chave principal", "variações"]
}
Inclua 4 a 6 sections e 3 a 5 faq.`;

const generateArticle = async (db, topic, lang = "pt") => {
  const data = await llmJson(articlePrompt(topic));
  if (!data.title || !Array.isArray(data.sections)) {
    throw new Error("Artigo gerado em formato inválido");
  }
  let slug = slugify(data.title) || slugify(topic) || `artigo-${Date.now()}`;
  const dup = await db.collection("seo_articles")
      .where("slug", "==", slug).limit(1).get();
  if (!dup.empty) slug = `${slug}-${Date.now().toString(36)}`;

  const now = new Date().toISOString();
  const doc = {
    slug,
    topic,
    title: String(data.title).slice(0, 120),
    metaDescription: String(data.metaDescription || "").slice(0, 170),
    intro: sanitizeHtml(data.intro),
    sections: (data.sections || []).slice(0, 8).map((s) => ({
      heading: String(s.heading || "").slice(0, 140),
      html: sanitizeHtml(s.html),
    })),
    faq: (data.faq || []).slice(0, 6).map((f) => ({
      question: String(f.question || "").slice(0, 200),
      answer: String(f.answer || "").slice(0, 600),
    })),
    keywords: (data.keywords || []).slice(0, 8).map((k) => String(k)),
    lang,
    status: "published",
    publishedAt: now,
    updatedAt: now,
  };
  await db.collection("seo_articles").add(doc);
  return doc;
};

// ─── Template HTML (SSR) ─────────────────────────────────────────────────────

const baseCss = `
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial,
sans-serif;color:#1b2330;background:#f7f9fc;line-height:1.65}
a{color:#003b8a}
.wrap{max-width:760px;margin:0 auto;padding:0 18px}
header{background:linear-gradient(120deg,#003b8a,#0cc0df);padding:14px 0}
header .wrap{display:flex;align-items:center;justify-content:space-between}
.logo{color:#fff;font-weight:800;font-size:19px;text-decoration:none;
letter-spacing:.3px}
.logo span{opacity:.85;font-weight:600}
.cta-top{background:#fff;color:#003b8a;text-decoration:none;font-weight:700;
font-size:13px;padding:8px 14px;border-radius:20px}
main{padding:26px 0 10px}
h1{font-size:28px;line-height:1.25;margin-bottom:10px;color:#0f1c33}
h2{font-size:21px;margin:26px 0 10px;color:#0f1c33}
h3{font-size:17px;margin:18px 0 8px}
p{margin-bottom:12px}
ul,ol{margin:0 0 12px 22px}
li{margin-bottom:6px}
.meta{color:#6b7688;font-size:13px;margin-bottom:20px}
.card{background:#fff;border:1px solid #e5eaf3;border-radius:14px;
padding:18px;margin:20px 0}
.chal{display:flex;justify-content:space-between;align-items:center;gap:10px;
padding:10px 0;border-bottom:1px solid #eef1f7}
.chal:last-child{border-bottom:0}
.chal a{font-weight:600;text-decoration:none;font-size:15px}
.prize{background:linear-gradient(120deg,#00B09B,#0cc0df);color:#fff;
font-weight:800;font-size:13px;padding:5px 12px;border-radius:16px;
white-space:nowrap}
.cta{display:block;text-align:center;background:linear-gradient(120deg,
#003b8a,#0cc0df);color:#fff;font-weight:800;text-decoration:none;
padding:14px;border-radius:12px;margin:24px 0;font-size:16px}
.faq-q{font-weight:700;margin-top:14px}
.list-item{display:block;background:#fff;border:1px solid #e5eaf3;
border-radius:14px;padding:16px 18px;margin-bottom:12px;text-decoration:none}
.list-item h2{margin:0 0 6px;font-size:18px}
.list-item p{color:#4a5568;font-size:14px;margin:0}
.list-item .meta{margin:6px 0 0}
footer{border-top:1px solid #e5eaf3;margin-top:30px;padding:20px 0 40px;
color:#6b7688;font-size:13px}
footer a{margin-right:14px}
`;

const pageShell = (c, opts) => `<!DOCTYPE html>
<html lang="${c.htmlLang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(opts.title)}</title>
<meta name="description" content="${esc(opts.description)}">
<link rel="canonical" href="${esc(opts.url)}">
<link rel="icon" href="/favicon.png">
<meta property="og:type" content="${opts.ogType || "article"}">
<meta property="og:site_name" content="${c.brand}">
<meta property="og:title" content="${esc(opts.title)}">
<meta property="og:description" content="${esc(opts.description)}">
<meta property="og:image" content="${c.site}/og-default.png">
<meta property="og:url" content="${esc(opts.url)}">
<meta name="twitter:card" content="summary_large_image">
${opts.jsonLd ? `<script type="application/ld+json">${opts.jsonLd}` +
    "</script>" : ""}
<style>${baseCss}</style>
</head>
<body>
<header><div class="wrap">
<a class="logo" href="${c.site}/">${c.logoA}<span>${c.logoB}</span></a>
<a class="cta-top" href="${c.site}/">${c.enterCta}</a>
</div></header>
<main><div class="wrap">
${opts.body}
</div></main>
<footer><div class="wrap">
<a href="${c.site}/">${c.activeChallenges}</a>
<a href="${c.site}/novidades">${c.news}</a>
<div style="margin-top:8px">© ${new Date().getFullYear()} ${c.brand} —
${c.footerTagline}</div>
<div style="margin-top:4px;opacity:.7">${c.createdBy} ${CREATOR}.</div>
</div></footer>
</body>
</html>`;

// Bloco de CTA com desafios reais abertos (prova de vida + link interno).
const challengesBlock = async (db, c) => {
  try {
    const snap = await db.collection("challenges")
        .where("status", "==", "active")
        .where("region", "==", c.region)
        .orderBy("amount", "desc").limit(3).get();
    if (snap.empty) return "";
    const rows = snap.docs.map((d) => {
      const ch = d.data();
      return `<div class="chal">
<a href="${c.site}/challenges/${d.id}">${esc(ch.title)}</a>
<span class="prize">${fmtBrl(ch.amount)}</span></div>`;
    }).join("");
    return `<div class="card">
<strong>${c.openNow} ${c.brand}:</strong>
${rows}
<a class="cta" href="${c.site}/">${c.joinCta}</a>
</div>`;
  } catch (e) {
    return "";
  }
};

// Bloco de artigos relacionados (links internos — reforça o SEO).
const relatedBlock = (c, related) => {
  if (!related || related.length === 0) return "";
  const items = related.map((r) => `<a class="list-item"
href="${c.site}/novidades/${r.slug}"><h2>${esc(r.title)}</h2>
<p>${esc(r.metaDescription)}</p></a>`).join("\n");
  return `<h2>${c.readNext}</h2>${items}`;
};

const renderArticle = (c, a, chalBlock, related) => {
  const url = `${c.site}/novidades/${a.slug}`;
  const sections = (a.sections || []).map((s) =>
    `<h2>${esc(s.heading)}</h2>${s.html}`).join("\n");
  const faqHtml = (a.faq || []).length === 0 ? "" :
      `<h2>${c.faqTitle}</h2>` + a.faq.map((f) =>
        `<p class="faq-q">${esc(f.question)}</p><p>${esc(f.answer)}</p>`)
          .join("");
  const jsonLd = JSON.stringify([
    {
      "@context": "https://schema.org",
      "@type": "Article",
      "headline": a.title,
      "description": a.metaDescription,
      "inLanguage": c.lang,
      "datePublished": a.publishedAt,
      "dateModified": a.updatedAt || a.publishedAt,
      "mainEntityOfPage": url,
      "image": `${c.site}/og-default.png`,
      "author": {"@type": "Organization", "name": c.brand, "url": c.site},
      "publisher": {"@type": "Organization", "name": c.brand, "url": c.site},
    },
    ...((a.faq || []).length > 0 ? [{
      "@context": "https://schema.org",
      "@type": "FAQPage",
      "mainEntity": a.faq.map((f) => ({
        "@type": "Question",
        "name": f.question,
        "acceptedAnswer": {"@type": "Answer", "text": f.answer},
      })),
    }] : []),
    {
      "@context": "https://schema.org",
      "@type": "BreadcrumbList",
      "itemListElement": [
        {"@type": "ListItem", "position": 1, "name": c.brand, "item": c.site},
        {"@type": "ListItem", "position": 2, "name": c.news,
          "item": `${c.site}/novidades`},
        {"@type": "ListItem", "position": 3, "name": a.title, "item": url},
      ],
    },
  ]);
  const body = `
<p class="meta"><a href="${c.site}/novidades">${c.backToNews}</a></p>
<h1>${esc(a.title)}</h1>
<p class="meta">${c.by} ${c.brand} · ${fmtDate(a.publishedAt, c.lang)}</p>
${a.intro || ""}
${chalBlock}
${sections}
${faqHtml}
<a class="cta" href="${c.site}/">${c.articleCta}</a>
${relatedBlock(c, related)}`;
  return pageShell(c, {
    title: `${a.title} | ${c.brand}`,
    description: a.metaDescription || a.title,
    url,
    jsonLd,
    body,
  });
};

const renderIndex = (c, articles, chalBlock) => {
  const url = `${c.site}/novidades`;
  const items = articles.map((a) => `<a class="list-item"
href="${c.site}/novidades/${a.slug}">
<h2>${esc(a.title)}</h2>
<p>${esc(a.metaDescription)}</p>
<div class="meta">${fmtDate(a.publishedAt, c.lang)}</div></a>`).join("\n");
  const jsonLd = JSON.stringify({
    "@context": "https://schema.org",
    "@type": "CollectionPage",
    "name": `${c.news} | ${c.brand}`,
    "url": url,
    "inLanguage": c.lang,
    "isPartOf": {"@type": "WebSite", "name": c.brand, "url": c.site},
  });
  const body = `
<h1>${c.indexH1} ${c.brand}</h1>
<p class="meta">${c.indexSub}</p>
${chalBlock}
${items || `<p>${c.soon}</p>`}`;
  return pageShell(c, {
    title: `${c.indexTitle} | ${c.brand}`,
    description: c.indexDesc,
    url,
    ogType: "website",
    jsonLd,
    body,
  });
};

// ─── PÁGINAS SSR: /novidades e /novidades/{slug} ─────────────────────────────

exports.seoPage = functions.https.onRequest(async (req, res) => {
  const c = siteCtx(req);
  try {
    const db = admin.firestore();
    const parts = (req.path || "").split("/").filter(Boolean);
    // parts: ["novidades"] ou ["novidades", "slug"]
    const slug = parts.length > 1 ? decodeURIComponent(parts[1]) : "";
    const chalBlock = await challengesBlock(db, c);

    // Uma única leitura: publicados do idioma deste site (legado sem lang =
    // 'pt'), já ordenados. Serve o índice, o artigo e os relacionados.
    const langOf = (a) => (a.lang || "pt");
    const snap = await db.collection("seo_articles")
        .where("status", "==", "published").limit(300).get();
    const articles = snap.docs.map((d) => d.data())
        .filter((a) => langOf(a) === c.lang)
        .sort((a, b) =>
          String(b.publishedAt).localeCompare(String(a.publishedAt)));

    if (!slug) {
      res.set("Cache-Control", "public, max-age=600, s-maxage=1800");
      return res.status(200)
          .send(renderIndex(c, articles.slice(0, 100), chalBlock));
    }

    const article = articles.find((a) => a.slug === slug);
    if (!article) {
      return res.redirect(302, `${c.site}/novidades`);
    }
    // Relacionados: mesmo idioma, exceto o atual, 3 mais recentes.
    const related = articles.filter((a) => a.slug !== slug).slice(0, 3);
    res.set("Cache-Control", "public, max-age=3600, s-maxage=86400");
    return res.status(200)
        .send(renderArticle(c, article, chalBlock, related));
  } catch (e) {
    console.error("seoPage:", e.message);
    return res.redirect(302, c.site);
  }
});

// ─── SITEMAP.XML ─────────────────────────────────────────────────────────────

exports.seoSitemap = functions.https.onRequest(async (req, res) => {
  const c = siteCtx(req);
  try {
    const db = admin.firestore();
    const urls = [
      {loc: `${c.site}/`, priority: "1.0"},
      {loc: `${c.site}/novidades`, priority: "0.9"},
    ];
    const arts = await db.collection("seo_articles")
        .where("status", "==", "published").get();
    for (const d of arts.docs) {
      const a = d.data();
      if ((a.lang || "pt") !== c.lang) continue; // só o idioma deste site
      urls.push({
        loc: `${c.site}/novidades/${a.slug}`,
        lastmod: (a.updatedAt || a.publishedAt || "").slice(0, 10),
        priority: "0.8",
      });
    }
    const chals = await db.collection("challenges")
        .where("region", "==", c.region).get();
    for (const d of chals.docs) {
      urls.push({
        loc: `${c.site}/challenges/${d.id}`,
        lastmod: String(d.data().createdAt || "").slice(0, 10),
        priority: "0.6",
      });
    }
    const xml = `<?xml version="1.0" encoding="UTF-8"?>\n` +
        `<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n` +
        urls.map((u) => "<url>" +
            `<loc>${esc(u.loc)}</loc>` +
            (u.lastmod ? `<lastmod>${u.lastmod}</lastmod>` : "") +
            `<priority>${u.priority}</priority>` +
            "</url>").join("\n") +
        "\n</urlset>";
    res.set("Content-Type", "application/xml");
    res.set("Cache-Control", "public, max-age=3600, s-maxage=21600");
    return res.status(200).send(xml);
  } catch (e) {
    console.error("seoSitemap:", e.message);
    return res.status(500).send("erro");
  }
});

// ─── ADMIN: CONSULTOR DE SEO POR IA (tempo real) ─────────────────────────────
// Junta o estado atual (artigos pt/en, fila de temas, desafios ativos) com os
// resultados que o admin colou do Google Search Console e pede à IA um plano
// priorizado, acionável, para conseguir mais acessos AGORA. Retorna também
// temas sugeridos que podem ir direto pra fila de conteúdo.
exports.adminSeoAdvisor = functions
    .runWith({timeoutSeconds: 120})
    .https.onCall(async (data, context) => {
      if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated", "Não autenticado");
      }
      const db = admin.firestore();
      const adminDoc =
          await db.collection("admins").doc(context.auth.uid).get();
      if (!adminDoc.exists) {
        throw new functions.https.HttpsError(
            "permission-denied", "Apenas administradores.");
      }

      // Contexto atual da operação.
      const arts = await db.collection("seo_articles")
          .where("status", "==", "published").get();
      let pt = 0; let en = 0;
      arts.forEach((d) => {
        (d.data().lang || "pt") === "en" ? en++ : pt++;
      });
      const topics = await db.collection("seo_topics")
          .where("used", "==", false).get();
      let activeBr = 0; let activeIntl = 0;
      try {
        const ab = await db.collection("challenges")
            .where("status", "==", "active")
            .where("region", "==", "BR").count().get();
        activeBr = ab.data().count;
        const ai = await db.collection("challenges")
            .where("status", "==", "active")
            .where("region", "==", "INTL").count().get();
        activeIntl = ai.data().count;
      } catch (e) {
        // segue sem contagem
      }

      const pasted = String(data.pastedResults || "").slice(0, 6000);

      const prompt = `
Você é um consultor sênior de SEO orgânico. Analise a situação e dê um plano
PRÁTICO e PRIORIZADO para aumentar o tráfego de busca, em português do Brasil.

Contexto do produto:
- Duas plataformas irmãs de desafios de FOTO com prêmio em dinheiro:
  · Brasil: desafiopago.com.br (conteúdo em PT, prêmios/Pix)
  · Internacional: trialspaid.web.app (conteúdo em EN, saque em cripto/XRP)
- Cada uma tem um hub de artigos em /novidades (renderizado no servidor) e um
  sitemap.xml próprio. O app em si é um canvas (invisível ao Google), por isso
  o tráfego orgânico depende do hub de artigos + páginas de desafios.

Estado atual:
- Artigos publicados: ${pt} em PT, ${en} em EN.
- Temas na fila de conteúdo (aguardando publicação): ${topics.size}.
- Desafios ativos: ${activeBr} no BR, ${activeIntl} no internacional.

${pasted ? `Resultados que o admin colou do Google Search Console (queries,
cliques, impressões, posição — dados reais):
"""
${pasted}
"""
Priorize recomendações baseadas NESSES dados reais (queries com muitas
impressões e posição ruim = maior oportunidade).` :
    "O admin ainda não colou dados do Search Console. Dê recomendações " +
    "gerais fortes e explique quais dados do GSC colar aqui para afinar a " +
    "análise."}

Responda APENAS com JSON válido:
{
  "summary": "diagnóstico em 1-2 frases, direto",
  "priorities": [
    {"title": "ação prioritária", "why": "por que importa",
     "how": "como fazer, passo a passo curto"}
  ],
  "quickWins": ["ganho rápido acionável", "..."],
  "suggestedTopics": ["tema de artigo com alta chance de tráfego", "..."]
}
Regras: 3 a 5 priorities, 3 a 5 quickWins, 5 a 10 suggestedTopics (títulos de
artigo prontos, em PT, baseados na demanda). Nada de promessas irreais.`;

      let advice;
      try {
        advice = await llmJson(prompt);
      } catch (e) {
        throw new functions.https.HttpsError(
            "failed-precondition",
            "IA indisponível — configure a chave do Gemini em " +
            "Admin → Chaves & integrações. (" + e.message + ")");
      }
      return {
        summary: String(advice.summary || ""),
        priorities: (advice.priorities || []).slice(0, 6),
        quickWins: (advice.quickWins || []).slice(0, 8),
        suggestedTopics: (advice.suggestedTopics || []).slice(0, 12)
            .map((t) => String(t)),
        stats: {pt, en, queue: topics.size, activeBr, activeIntl},
      };
    });

// ─── ADMIN: adicionar temas sugeridos à fila ─────────────────────────────────
exports.adminAddSeoTopics = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Não autenticado");
  }
  const db = admin.firestore();
  const adminDoc = await db.collection("admins").doc(context.auth.uid).get();
  if (!adminDoc.exists) {
    throw new functions.https.HttpsError(
        "permission-denied", "Apenas administradores.");
  }
  const topics = Array.isArray(data.topics) ? data.topics : [];
  let added = 0;
  for (const raw of topics) {
    const topic = String(raw || "").trim();
    if (topic.length < 8) continue;
    const id = slugify(topic);
    if (!id) continue;
    const ref = db.collection("seo_topics").doc(id);
    if ((await ref.get()).exists) continue;
    await ref.set({
      topic,
      source: "advisor",
      used: false,
      createdAt: new Date().toISOString(),
    });
    added++;
  }
  return {success: true, added};
});

// ─── ADMIN: gerar artigo agora ───────────────────────────────────────────────

exports.adminGenerateSeoArticle = functions
    .runWith({timeoutSeconds: 180})
    .https.onCall(async (data, context) => {
      if (!context.auth) {
        throw new functions.https.HttpsError(
            "unauthenticated", "Não autenticado");
      }
      const db = admin.firestore();
      const adminDoc =
          await db.collection("admins").doc(context.auth.uid).get();
      if (!adminDoc.exists) {
        throw new functions.https.HttpsError(
            "permission-denied", "Apenas administradores.");
      }
      let topic = String(data.topic || "").trim();
      let topicRef = null;
      if (!topic) {
        const t = await db.collection("seo_topics")
            .where("used", "==", false).limit(1).get();
        if (t.empty) {
          throw new functions.https.HttpsError(
              "failed-precondition",
              "Fila de tópicos vazia — digite um tema.");
        }
        topic = t.docs[0].data().topic;
        topicRef = t.docs[0].ref;
      }
      const art = await generateArticle(db, topic);
      if (topicRef) {
        await topicRef.update({used: true, usedAt: art.publishedAt});
      }
      return {success: true, slug: art.slug, title: art.title,
        url: `${SITE}/novidades/${art.slug}`};
    });

// ─── ADMIN: liga/desliga publicação automática ───────────────────────────────

exports.adminSetSeoConfig = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Não autenticado");
  }
  const db = admin.firestore();
  const adminDoc = await db.collection("admins").doc(context.auth.uid).get();
  if (!adminDoc.exists) {
    throw new functions.https.HttpsError(
        "permission-denied", "Apenas administradores.");
  }
  const updates = {updatedAt: new Date().toISOString()};
  if (typeof data.autoPublish === "boolean") {
    updates.autoPublish = data.autoPublish;
  }
  await db.collection("config").doc("seo").set(updates, {merge: true});
  return {success: true};
});

// ─── CRON: publica 1 artigo por dia (09:00 BRT) ──────────────────────────────

exports.seoDailyPublish = functions
    .runWith({timeoutSeconds: 300})
    .pubsub.schedule("every day 09:00")
    .timeZone("America/Sao_Paulo")
    .onRun(async () => {
      const db = admin.firestore();
      const cfg = await db.collection("config").doc("seo").get();
      if (cfg.exists && cfg.data().autoPublish === false) return null;

      const t = await db.collection("seo_topics")
          .where("used", "==", false).limit(5).get();
      if (t.empty) {
        console.log("seoDailyPublish: fila de tópicos vazia");
        return null;
      }
      const pick = t.docs[Math.floor(Math.random() * t.docs.length)];
      const topic = pick.data().topic;
      try {
        const art = await generateArticle(db, topic);
        await pick.ref.update({used: true, usedAt: art.publishedAt});
        console.log(`seoDailyPublish: publicado "${art.title}" ` +
            `(/novidades/${art.slug})`);
      } catch (e) {
        console.error("seoDailyPublish:", e.message);
      }
      return null;
    });

// ─── CRON: demanda real do Google Search Console (semanal) ───────────────────
// Lê as buscas que já mostram o site (impressões) mas rendem poucos cliques
// (posição ruim) e vira cada uma em tópico de artigo — o conteúdo passa a
// seguir a DEMANDA real do Google. Requer: adicionar
// desafio-app-b8665@appspot.gserviceaccount.com como usuário na propriedade
// do Search Console (Configurações → Usuários e permissões).

exports.gscSyncQueries = functions
    .runWith({timeoutSeconds: 120})
    .pubsub.schedule("every monday 08:00")
    .timeZone("America/Sao_Paulo")
    .onRun(async () => {
      const db = admin.firestore();
      let google;
      try {
        google = require("googleapis").google;
      } catch (e) {
        console.error("gscSyncQueries: googleapis não instalado");
        return null;
      }
      const auth = new google.auth.GoogleAuth({
        scopes: ["https://www.googleapis.com/auth/webmasters.readonly"],
      });
      const sc = google.searchconsole({version: "v1", auth});
      const end = new Date().toISOString().slice(0, 10);
      const start = new Date(Date.now() - 28 * 86400000)
          .toISOString().slice(0, 10);

      const properties = [
        "sc-domain:desafiopago.com.br",
        `${SITE}/`,
      ];
      let rows = null;
      let usedProp = "";
      for (const siteUrl of properties) {
        try {
          const r = await sc.searchanalytics.query({
            siteUrl,
            requestBody: {
              startDate: start,
              endDate: end,
              dimensions: ["query"],
              rowLimit: 200,
            },
          });
          rows = r.data.rows || [];
          usedProp = siteUrl;
          break;
        } catch (e) {
          console.warn(`gscSyncQueries: sem acesso a ${siteUrl} — ` +
              e.message);
        }
      }
      if (rows == null) {
        console.warn("gscSyncQueries: sem acesso ao Search Console. " +
            "Adicione desafio-app-b8665@appspot.gserviceaccount.com " +
            "como usuário na propriedade.");
        return null;
      }

      // Guarda o snapshot (análise no admin / histórico).
      await db.collection("seo_gsc").doc(end).set({
        property: usedProp,
        start,
        end,
        rows: rows.slice(0, 200),
        syncedAt: new Date().toISOString(),
      });

      // Oportunidades: demanda existe (impressões) mas posição/cliques ruins.
      let created = 0;
      for (const r of rows) {
        const q = (r.keys && r.keys[0] || "").trim();
        if (!q || q.length < 8) continue;
        if ((r.impressions || 0) < 30) continue;
        if ((r.position || 99) <= 8) continue; // já rankeia bem
        const id = slugify(q);
        if (!id) continue;
        const ref = db.collection("seo_topics").doc(id);
        const doc = await ref.get();
        if (doc.exists) continue;
        await ref.set({
          topic: q,
          source: "gsc",
          impressions: r.impressions || 0,
          clicks: r.clicks || 0,
          position: r.position || null,
          used: false,
          createdAt: new Date().toISOString(),
        });
        created++;
      }
      console.log(`gscSyncQueries: ${rows.length} queries lidas, ` +
          `${created} tópicos novos (${usedProp})`);
      return null;
    });

// ─── SEED: fila inicial de tópicos (one-shot, re-executável) ─────────────────

const INITIAL_TOPICS = [
  "como ganhar dinheiro com fotos tiradas pelo celular",
  "desafios online valendo dinheiro: como funcionam e como participar",
  "como ganhar dinheiro na internet sem investir nada",
  "concurso de fotografia online com prêmio em dinheiro",
  "renda extra pela internet: ideias que funcionam de verdade",
  "como tirar fotos incríveis com o celular (guia para iniciantes)",
  "o que postar para ganhar votos em concursos online",
  "como receber prêmios via Pix com segurança",
  "ideias de desafios criativos para fazer entre amigos",
  "como divulgar sua participação e conseguir mais votos",
  "fotografia de comida: como fotografar pratos que dão vontade",
  "como fotografar paisagens com o celular como um profissional",
  "melhores horários de luz para tirar fotos (golden hour explicada)",
  "como editar fotos no celular de graça: apps e dicas",
  "selfie perfeita: truques de ângulo, luz e expressão",
  "como fazer dinheiro com hobby de fotografia",
  "competições online com premiação: o que verificar antes de entrar",
  "como funciona votação online em concursos e como se destacar",
  "fotos de pets que conquistam a internet: guia prático",
  "como criar um desafio viral na internet",
  "quanto custa criar um concurso cultural online",
  "regras de concursos culturais no Brasil: o básico que você deve saber",
  "como usar o WhatsApp para divulgar um link e engajar amigos",
  "estratégias para pedir votos sem ser chato",
  "composição fotográfica: regra dos terços explicada de forma simples",
  "fotografia de rua com celular: dicas para começar hoje",
  "como fotografar o céu e o pôr do sol com o celular",
  "retratos com celular: como deixar qualquer pessoa fotogênica",
  "fundo desfocado no celular: modo retrato bem usado",
  "como ganhar seguidores mostrando suas fotos",
  "transformar criatividade em renda: caminhos possíveis",
  "desafio de foto: 30 ideias de temas para se inspirar",
  "como participar de desafios pagos com segurança",
  "Pix para iniciantes: como funciona e cuidados básicos",
  "o que é prova social e por que votos importam na internet",
  "como organizar um desafio de fotos na sua comunidade",
  "erros comuns em fotos de celular (e como corrigir)",
  "iluminação caseira para fotos: soluções baratas",
  "como fotografar produtos para vender mais",
  "desafios de criatividade para sair da rotina",
  "aplicativos que pagam de verdade: como identificar os sérios",
  "como evitar golpes em promoções e sorteios online",
  "storytelling em fotos: contar histórias em uma imagem",
  "tendências de fotografia para redes sociais",
  "como montar um portfólio de fotos gratuito",
  "fotos verticais 9:16: por que dominam o celular e como aproveitar",
  "concursos de fotografia no Brasil: onde encontrar oportunidades",
  "como a votação do público funciona em concursos e como vencer",
];

// ─── SEED: artigos iniciais escritos à mão (funciona SEM chave de IA) ────────
// Garante que /novidades já nasça com conteúdo real e indexável enquanto a
// geração automática por IA não é ativada. Re-executável (pula os já criados).
const STARTER_ARTICLES = [
  {
    title: "Como ganhar dinheiro com fotos tiradas pelo celular",
    metaDescription: "Guia prático para transformar suas fotos de celular " +
      "em renda extra: desafios pagos, bancos de imagem, dicas de qualidade " +
      "e como receber via Pix com segurança.",
    keywords: ["ganhar dinheiro com fotos", "renda extra fotografia",
      "vender fotos celular"],
    intro: "<p>Você não precisa de uma câmera profissional para ganhar um " +
      "dinheiro extra com fotografia. O celular que está no seu bolso já é " +
      "suficiente para começar — o que muda o jogo é <strong>saber onde " +
      "colocar essas fotos para trabalharem por você</strong>. Neste guia, " +
      "reunimos caminhos reais (sem promessas mágicas) para monetizar suas " +
      "imagens, com foco no que dá pra fazer hoje mesmo.</p>",
    sections: [
      {heading: "1. Desafios de foto com prêmio",
        html: "<p>A forma mais direta e divertida é participar de " +
          "<strong>desafios de foto pagos</strong>: alguém coloca um prêmio " +
          "em dinheiro, você envia sua melhor imagem sobre o tema e a mais " +
          "votada leva o valor. No <strong>Desafio Pago</strong>, por " +
          "exemplo, o prêmio vai para o saldo do vencedor e pode ser sacado " +
          "via Pix. É competitivo, mas premia criatividade — não " +
          "equipamento caro.</p><p>Dica: capriche no tema pedido e divulgue " +
          "sua participação para juntar votos. Engajamento conta tanto " +
          "quanto a qualidade da foto.</p>"},
      {heading: "2. Bancos de imagem (renda passiva)",
        html: "<p>Plataformas de banco de imagens pagam royalties quando " +
          "alguém baixa sua foto. O ganho por download costuma ser pequeno, " +
          "mas é <em>renda passiva</em>: uma boa foto pode vender várias " +
          "vezes ao longo dos anos. Aposte em imagens genéricas e úteis " +
          "(pessoas trabalhando, comida, natureza, tecnologia).</p>"},
      {heading: "3. Melhore a qualidade sem gastar nada",
        html: "<ul><li><strong>Luz natural</strong> é sua melhor amiga: " +
          "fotografe perto de janelas ou na primeira/última hora do dia.</li>" +
          "<li>Use a <strong>regra dos terços</strong> (ative as linhas de " +
          "grade da câmera).</li><li>Limpe a lente — parece óbvio, mas " +
          "resolve metade das fotos borradas.</li><li>Evite zoom digital; " +
          "aproxime-se do assunto.</li></ul>"},
      {heading: "4. Como receber com segurança",
        html: "<p>Prefira plataformas que pagam via <strong>Pix</strong> e " +
          "deixam as regras claras (taxas, prazo, saque mínimo). Desconfie " +
          "de quem promete valores altos sem esforço ou pede pagamento " +
          "adiantado para 'liberar' ganhos. Ganho de verdade nunca cobra " +
          "para te pagar.</p>"},
    ],
    faq: [
      {question: "Preciso de câmera profissional?",
        answer: "Não. Celulares atuais tiram fotos ótimas. O que importa é " +
          "luz, composição e um tema bem executado."},
      {question: "Dá pra viver só disso?",
        answer: "Para a maioria é uma renda extra, não um salário. Encare " +
          "como um complemento que cresce com consistência."},
      {question: "Como recebo o dinheiro?",
        answer: "Em plataformas sérias, via Pix. No Desafio Pago o prêmio " +
          "cai no seu saldo e você saca quando quiser (saque mínimo R$100)."},
    ],
  },
  {
    title: "Desafios online valendo dinheiro: como funcionam de verdade",
    metaDescription: "Entenda como funcionam os desafios online com prêmio " +
      "em dinheiro, como participar com segurança, como são escolhidos os " +
      "vencedores e como sacar seus ganhos.",
    keywords: ["desafios online valendo dinheiro", "competição online prêmio",
      "concurso pago internet"],
    intro: "<p>Desafios online com prêmio em dinheiro viraram uma forma " +
      "popular de unir diversão e renda extra. Mas como eles funcionam por " +
      "dentro? Quem paga o prêmio? Como se garante que o vencedor recebe? " +
      "Explicamos tudo de forma simples e honesta.</p>",
    sections: [
      {heading: "O básico: tema, participação e voto",
        html: "<p>Um desafio tem um <strong>tema</strong> (ex.: 'melhor foto " +
          "de café'), um <strong>prêmio</strong> em dinheiro e um " +
          "<strong>prazo</strong>. As pessoas participam enviando conteúdo e " +
          "o público vota. Quem tiver mais votos ao fim do prazo vence e " +
          "leva o prêmio.</p>"},
      {heading: "De onde vem o prêmio",
        html: "<p>O prêmio geralmente é bancado por quem cria o desafio " +
          "(que deposita o valor) e pode crescer com aportes de outras " +
          "pessoas. Em plataformas bem feitas, esse valor fica " +
          "<strong>reservado</strong> até o fim — não some no meio do " +
          "caminho.</p>"},
      {heading: "Como se garante o pagamento",
        html: "<p>Procure plataformas com <strong>regras claras</strong>: " +
          "saldo interno, saque via Pix, taxa transparente e histórico de " +
          "transações. No Desafio Pago, cada operação de dinheiro é feita " +
          "em transação atômica — sem saldo negativo, sem prêmio pago em " +
          "dobro.</p>"},
      {heading: "Dicas para vencer",
        html: "<ul><li>Leia o tema com atenção e responda exatamente ao que " +
          "foi pedido.</li><li>Capriche na qualidade, mas invista também em " +
          "<strong>divulgação</strong>: chame amigos para votar.</li>" +
          "<li>Participe cedo — mais tempo no ar costuma render mais " +
          "votos.</li></ul>"},
    ],
    faq: [
      {question: "É seguro colocar dinheiro nesses desafios?",
        answer: "Em plataformas sérias, sim. Verifique regras, taxas e se o " +
          "saque é claro. Evite quem promete ganho fácil garantido."},
      {question: "O que acontece em caso de empate?",
        answer: "Boas plataformas dividem o prêmio entre os empatados. No " +
          "Desafio Pago, o centavo indivisível fica com a plataforma."},
      {question: "Preciso pagar para participar?",
        answer: "Depende do desafio. Muitos são gratuitos para participar; " +
          "criar um desafio é que envolve depositar o prêmio."},
    ],
  },
  {
    title: "Como conseguir mais votos e divulgar sua participação",
    metaDescription: "Estratégias práticas para conseguir votos em desafios " +
      "e concursos online: como pedir votos sem ser chato, usar o WhatsApp " +
      "a seu favor e criar prova social.",
    keywords: ["como conseguir votos", "divulgar participação",
      "ganhar votação online"],
    intro: "<p>Ter a melhor foto não basta se ninguém a vê. Em desafios " +
      "decididos por voto popular, <strong>divulgação é metade do jogo</strong>. " +
      "A boa notícia: com algumas estratégias simples você multiplica seus " +
      "votos sem incomodar ninguém.</p>",
    sections: [
      {heading: "Peça votos do jeito certo",
        html: "<p>Em vez de um genérico 'vota em mim', conte uma " +
          "<strong>história</strong>: por que você entrou, o que o prêmio " +
          "significa, por que aquela foto é especial. Pessoas votam em " +
          "pessoas, não em links.</p>"},
      {heading: "Use o link direto da sua participação",
        html: "<p>Compartilhe o <strong>link que abre direto na sua arte</strong>, " +
          "com botão de votar em destaque. Quanto menos cliques entre a " +
          "pessoa e o voto, mais votos você recebe. O Desafio Pago gera esse " +
          "link com uma prévia bonita para WhatsApp e redes.</p>"},
      {heading: "Crie prova social",
        html: "<p>Mostrar que você já tem votos incentiva mais votos " +
          "(efeito manada). Comemore marcos ('já passamos de 100 votos, " +
          "bora pra 200!') e agradeça publicamente quem apoiou.</p>"},
      {heading: "Escolha os melhores horários",
        html: "<p>Poste quando seus contatos estão online: início da manhã, " +
          "hora do almoço e início da noite costumam render mais. Evite " +
          "mandar tudo de uma vez — distribua ao longo do prazo.</p>"},
    ],
    faq: [
      {question: "Posso pedir votos em grupos de WhatsApp?",
        answer: "Sim, com bom senso. Personalize a mensagem, não repita no " +
          "mesmo grupo várias vezes e agradeça quem ajudar."},
      {question: "Vale a pena pedir voto para desconhecidos?",
        answer: "O retorno é baixo. Foque em quem já te conhece — a taxa de " +
          "conversão é muito maior."},
      {question: "Comprar votos funciona?",
        answer: "Não recomendamos: além de antiético, plataformas sérias " +
          "detectam e podem desclassificar. Votos reais valem mais."},
    ],
  },
];

// Artigos iniciais em INGLÊS para o hub internacional (trialspaid).
const EN_STARTER_ARTICLES = [
  {
    title: "How to make money with photos from your phone",
    metaDescription: "A practical guide to turning your phone photos into " +
      "extra income: paid photo challenges, stock sites, quality tips and " +
      "how to get paid safely in crypto.",
    keywords: ["make money with photos", "photo side income",
      "sell phone photos"],
    intro: "<p>You don't need a professional camera to earn extra money " +
      "with photography. The phone in your pocket is already enough — what " +
      "changes the game is <strong>knowing where to put those photos so " +
      "they work for you</strong>. In this guide we cover real paths (no " +
      "magic promises) to monetize your images, focused on what you can do " +
      "today.</p>",
    sections: [
      {heading: "1. Photo challenges with cash prizes",
        html: "<p>The most direct and fun way is joining <strong>paid photo " +
          "challenges</strong>: someone puts up a cash prize, you submit " +
          "your best image on the theme, and the most voted entry wins. On " +
          "<strong>TrialsPaid</strong>, the prize goes to the winner's " +
          "balance and can be withdrawn in crypto. It rewards creativity — " +
          "not expensive gear.</p><p>Tip: nail the requested theme and " +
          "promote your entry to gather votes. Engagement counts as much as " +
          "photo quality.</p>"},
      {heading: "2. Stock photography (passive income)",
        html: "<p>Stock platforms pay royalties whenever someone downloads " +
          "your photo. Earnings per download are small, but it's " +
          "<em>passive income</em>: a good photo can sell many times over " +
          "the years. Aim for generic, useful images (people working, " +
          "food, nature, technology).</p>"},
      {heading: "3. Improve quality without spending anything",
        html: "<ul><li><strong>Natural light</strong> is your best friend: " +
          "shoot near windows or during the first/last hour of daylight.</li>" +
          "<li>Use the <strong>rule of thirds</strong> (enable your " +
          "camera's grid).</li><li>Clean the lens — it fixes half of blurry " +
          "shots.</li><li>Avoid digital zoom; get closer instead.</li></ul>"},
      {heading: "4. How to get paid safely",
        html: "<p>Prefer platforms with clear rules (fees, timing, minimum " +
          "withdrawal). Be wary of anyone promising high returns for no " +
          "effort or asking for upfront payment to 'release' earnings. Real " +
          "earnings never charge you to get paid.</p>"},
    ],
    faq: [
      {question: "Do I need a professional camera?",
        answer: "No. Modern phones take great photos. What matters is " +
          "light, composition and a well-executed theme."},
      {question: "Can I live off this?",
        answer: "For most people it's extra income, not a salary. Treat it " +
          "as a complement that grows with consistency."},
      {question: "How do I receive the money?",
        answer: "On serious platforms, via secure methods. On TrialsPaid " +
          "the prize lands in your balance and you withdraw in crypto (XRP)."},
    ],
  },
  {
    title: "Online challenges with cash prizes: how they really work",
    metaDescription: "Understand how online challenges with cash prizes " +
      "work, how to join safely, how winners are chosen and how to withdraw " +
      "your earnings.",
    keywords: ["online challenges cash prizes", "win money online contest",
      "photo contest with prize"],
    intro: "<p>Online challenges with cash prizes have become a popular way " +
      "to mix fun and extra income. But how do they work under the hood? " +
      "Who pays the prize? How is the winner guaranteed to get paid? We " +
      "explain it simply and honestly.</p>",
    sections: [
      {heading: "The basics: theme, entry and votes",
        html: "<p>A challenge has a <strong>theme</strong> (e.g. 'best " +
          "coffee photo'), a cash <strong>prize</strong> and a " +
          "<strong>deadline</strong>. People join by submitting content and " +
          "the public votes. Whoever has the most votes at the deadline " +
          "wins the prize.</p>"},
      {heading: "Where the prize comes from",
        html: "<p>The prize is usually funded by whoever creates the " +
          "challenge (who deposits the amount) and can grow with " +
          "contributions from others. On well-built platforms, that amount " +
          "stays <strong>reserved</strong> until the end.</p>"},
      {heading: "How payment is guaranteed",
        html: "<p>Look for platforms with <strong>clear rules</strong>: " +
          "internal balance, transparent fees and a clear withdrawal flow. " +
          "On TrialsPaid every money operation is an atomic transaction — " +
          "no negative balance, no prize paid twice.</p>"},
      {heading: "Tips to win",
        html: "<ul><li>Read the theme carefully and answer exactly what was " +
          "asked.</li><li>Invest in quality, but also in " +
          "<strong>promotion</strong>: rally friends to vote.</li><li>Enter " +
          "early — more time live usually means more votes.</li></ul>"},
    ],
    faq: [
      {question: "Is it safe to put money into these challenges?",
        answer: "On serious platforms, yes. Check rules, fees and whether " +
          "withdrawal is clear. Avoid anyone promising guaranteed easy money."},
      {question: "What happens in a tie?",
        answer: "Good platforms split the prize among tied entries. On " +
          "TrialsPaid, the indivisible cent stays with the platform."},
      {question: "Do I have to pay to join?",
        answer: "It depends on the challenge. Many are free to join; " +
          "creating a challenge is what involves depositing the prize."},
    ],
  },
  {
    title: "How to get more votes and promote your entry",
    metaDescription: "Practical strategies to get votes in online challenges " +
      "and contests: how to ask for votes without being annoying, use " +
      "messaging apps and build social proof.",
    keywords: ["how to get votes", "promote your entry",
      "win online voting"],
    intro: "<p>Having the best photo isn't enough if no one sees it. In " +
      "challenges decided by popular vote, <strong>promotion is half the " +
      "game</strong>. The good news: a few simple strategies multiply your " +
      "votes without annoying anyone.</p>",
    sections: [
      {heading: "Ask for votes the right way",
        html: "<p>Instead of a generic 'vote for me', tell a " +
          "<strong>story</strong>: why you entered, what the prize means, " +
          "why that photo is special. People vote for people, not links.</p>"},
      {heading: "Use the direct link to your entry",
        html: "<p>Share the <strong>link that opens straight to your " +
          "entry</strong>, with a highlighted vote button. The fewer clicks " +
          "between a person and the vote, the more votes you get. TrialsPaid " +
          "generates that link with a rich preview for messaging apps.</p>"},
      {heading: "Build social proof",
        html: "<p>Showing that you already have votes encourages more votes " +
          "(bandwagon effect). Celebrate milestones ('we passed 100 votes, " +
          "let's hit 200!') and publicly thank supporters.</p>"},
      {heading: "Pick the best times",
        html: "<p>Post when your contacts are online: early morning, lunch " +
          "and early evening usually perform best. Don't send everything at " +
          "once — spread it across the deadline.</p>"},
    ],
    faq: [
      {question: "Can I ask for votes in group chats?",
        answer: "Yes, with good sense. Personalize the message, don't spam " +
          "the same group and thank those who help."},
      {question: "Is it worth asking strangers for votes?",
        answer: "The return is low. Focus on people who already know you — " +
          "the conversion rate is much higher."},
      {question: "Does buying votes work?",
        answer: "We don't recommend it: besides being unethical, serious " +
          "platforms detect and may disqualify. Real votes are worth more."},
    ],
  },
];

exports.seedSeoArticles = functions.runWith({timeoutSeconds: 300})
    .https.onRequest(async (req, res) => {
      if (req.method !== "POST") {
        return res.status(405).json({error: "Method Not Allowed"});
      }
      if (!req.body || req.body.secret !== "SEED_2026_DP") {
        return res.status(403).json({error: "Forbidden"});
      }
      const db = admin.firestore();
      // lang: 'pt' (padrão) ou 'en' — escolhe o conjunto de artigos.
      const lang = req.body.lang === "en" ? "en" : "pt";
      const set = lang === "en" ? EN_STARTER_ARTICLES : STARTER_ARTICLES;
      let created = 0;
      const now = new Date();
      for (let i = 0; i < set.length; i++) {
        const a = set[i];
        const slug = slugify(a.title);
        const dup = await db.collection("seo_articles")
            .where("slug", "==", slug).limit(1).get();
        if (!dup.empty) continue;
        // Datas escalonadas (não parecer tudo publicado no mesmo instante).
        const publishedAt =
          new Date(now.getTime() - i * 86400000).toISOString();
        await db.collection("seo_articles").add({
          slug,
          topic: a.title,
          title: a.title,
          metaDescription: a.metaDescription,
          intro: a.intro,
          sections: a.sections,
          faq: a.faq,
          keywords: a.keywords,
          lang,
          status: "published",
          source: "handwritten",
          publishedAt,
          updatedAt: publishedAt,
        });
        created++;
      }
      return res.json({success: true, created, lang});
    });

exports.seedSeoTopics = functions
    .runWith({timeoutSeconds: 540})
    .https.onRequest(async (req, res) => {
      if (req.method !== "POST") {
        return res.status(405).json({error: "Method Not Allowed"});
      }
      if (!req.body || req.body.secret !== "SEED_2026_DP") {
        return res.status(403).json({error: "Forbidden"});
      }
      const db = admin.firestore();
      let created = 0;
      for (const topic of INITIAL_TOPICS) {
        const id = slugify(topic);
        const ref = db.collection("seo_topics").doc(id);
        const doc = await ref.get();
        if (doc.exists) continue;
        await ref.set({
          topic,
          source: "seed",
          used: false,
          createdAt: new Date().toISOString(),
        });
        created++;
      }

      // Opcional: já gera os N primeiros artigos da fila (estreia com
      // conteúdo no ar em vez de esperar o cron diário).
      const published = [];
      const n = Math.min(Number(req.body.generate || 0), 6);
      for (let i = 0; i < n; i++) {
        const t = await db.collection("seo_topics")
            .where("used", "==", false).limit(10).get();
        if (t.empty) break;
        const pick = t.docs[Math.floor(Math.random() * t.docs.length)];
        try {
          const art = await generateArticle(db, pick.data().topic);
          await pick.ref.update({used: true, usedAt: art.publishedAt});
          published.push(art.slug);
        } catch (e) {
          console.error("seedSeoTopics generate:", e.message);
        }
      }
      return res.json({
        success: true,
        created,
        total: INITIAL_TOPICS.length,
        published,
      });
    });
