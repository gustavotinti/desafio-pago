// ─── MÁQUINA DE SEO ORGÂNICO ──────────────────────────────────────────────────
// Hub de conteúdo "/novidades" renderizado no SERVIDOR (o app Flutter é canvas
// e o Google não lê) + sitemap.xml + geração de artigos por IA (fila de
// tópicos) + loop de demanda via Google Search Console.
//
// Provedor de IA: usa GEMINI_API_KEY se existir; senão OPENAI_API_KEY.
// Kill-switch da publicação automática: config/seo.autoPublish == false.

const functions = require("firebase-functions");
const admin = require("firebase-admin");

const SITE = "https://desafiopago.com.br";
const BRAND = "Desafio Pago";

// ─── Utilidades ───────────────────────────────────────────────────────────────

const esc = (s) => String(s == null ? "" : s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");

// Sanitização leve do HTML vindo da IA (sem script/iframe/handlers).
const sanitizeHtml = (h) => String(h || "")
    .replace(/<\s*(script|style|iframe)[^>]*>[\s\S]*?<\s*\/\s*\1\s*>/gi, "")
    .replace(/\son\w+\s*=\s*"[^"]*"/gi, "")
    .replace(/\son\w+\s*=\s*'[^']*'/gi, "")
    .replace(/javascript:/gi, "");

const slugify = (s) => String(s || "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80);

const fmtBrl = (v) => `R$ ${(Number(v) || 0).toFixed(2).replace(".", ",")}`;

const fmtDate = (iso) => {
  try {
    const d = new Date(iso);
    const meses = ["janeiro", "fevereiro", "março", "abril", "maio", "junho",
      "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"];
    return `${d.getDate()} de ${meses[d.getMonth()]} de ${d.getFullYear()}`;
  } catch (e) {
    return "";
  }
};

// ─── IA: gera JSON (Gemini se houver chave; senão OpenAI) ────────────────────

const llmJson = async (prompt) => {
  const gemini = process.env.GEMINI_API_KEY;
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
  const openai = process.env.OPENAI_API_KEY;
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

const generateArticle = async (db, topic) => {
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

const pageShell = (opts) => `<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(opts.title)}</title>
<meta name="description" content="${esc(opts.description)}">
<link rel="canonical" href="${esc(opts.url)}">
<link rel="icon" href="/favicon.png">
<meta property="og:type" content="${opts.ogType || "article"}">
<meta property="og:site_name" content="${BRAND}">
<meta property="og:title" content="${esc(opts.title)}">
<meta property="og:description" content="${esc(opts.description)}">
<meta property="og:image" content="${SITE}/og-default.png">
<meta property="og:url" content="${esc(opts.url)}">
<meta name="twitter:card" content="summary_large_image">
${opts.jsonLd ? `<script type="application/ld+json">${opts.jsonLd}` +
    "</script>" : ""}
<style>${baseCss}</style>
</head>
<body>
<header><div class="wrap">
<a class="logo" href="${SITE}/">DESAFIO<span>PAGO</span></a>
<a class="cta-top" href="${SITE}/">Entrar nos desafios</a>
</div></header>
<main><div class="wrap">
${opts.body}
</div></main>
<footer><div class="wrap">
<a href="${SITE}/">Desafios ativos</a>
<a href="${SITE}/novidades">Novidades</a>
<div style="margin-top:8px">© ${new Date().getFullYear()} ${BRAND} —
desafios de foto valendo prêmios em dinheiro, pagos via Pix.</div>
</div></footer>
</body>
</html>`;

// Bloco de CTA com desafios reais abertos (prova de vida + link interno).
const challengesBlock = async (db) => {
  try {
    const snap = await db.collection("challenges")
        .where("status", "==", "active")
        .orderBy("amount", "desc").limit(3).get();
    if (snap.empty) return "";
    const rows = snap.docs.map((d) => {
      const c = d.data();
      return `<div class="chal">
<a href="${SITE}/challenges/${d.id}">${esc(c.title)}</a>
<span class="prize">${fmtBrl(c.amount)}</span></div>`;
    }).join("");
    return `<div class="card">
<strong>🔥 Desafios abertos agora no ${BRAND}:</strong>
${rows}
<a class="cta" href="${SITE}/">Participar e concorrer aos prêmios</a>
</div>`;
  } catch (e) {
    return "";
  }
};

const renderArticle = (a, chalBlock) => {
  const url = `${SITE}/novidades/${a.slug}`;
  const sections = (a.sections || []).map((s) =>
    `<h2>${esc(s.heading)}</h2>${s.html}`).join("\n");
  const faqHtml = (a.faq || []).length === 0 ? "" :
      `<h2>Perguntas frequentes</h2>` + a.faq.map((f) =>
        `<p class="faq-q">${esc(f.question)}</p><p>${esc(f.answer)}</p>`)
          .join("");
  const jsonLd = JSON.stringify([
    {
      "@context": "https://schema.org",
      "@type": "Article",
      "headline": a.title,
      "description": a.metaDescription,
      "datePublished": a.publishedAt,
      "dateModified": a.updatedAt || a.publishedAt,
      "mainEntityOfPage": url,
      "image": `${SITE}/og-default.png`,
      "author": {"@type": "Organization", "name": BRAND, "url": SITE},
      "publisher": {"@type": "Organization", "name": BRAND, "url": SITE},
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
        {"@type": "ListItem", "position": 1, "name": BRAND, "item": SITE},
        {"@type": "ListItem", "position": 2, "name": "Novidades",
          "item": `${SITE}/novidades`},
        {"@type": "ListItem", "position": 3, "name": a.title, "item": url},
      ],
    },
  ]);
  const body = `
<p class="meta"><a href="${SITE}/novidades">← Novidades</a></p>
<h1>${esc(a.title)}</h1>
<p class="meta">Por ${BRAND} · ${fmtDate(a.publishedAt)}</p>
${a.intro || ""}
${chalBlock}
${sections}
${faqHtml}
<a class="cta" href="${SITE}/">Criar ou participar de um desafio agora</a>`;
  return pageShell({
    title: `${a.title} | ${BRAND}`,
    description: a.metaDescription || a.title,
    url,
    jsonLd,
    body,
  });
};

const renderIndex = (articles, chalBlock) => {
  const url = `${SITE}/novidades`;
  const items = articles.map((a) => `<a class="list-item"
href="${SITE}/novidades/${a.slug}">
<h2>${esc(a.title)}</h2>
<p>${esc(a.metaDescription)}</p>
<div class="meta">${fmtDate(a.publishedAt)}</div></a>`).join("\n");
  const jsonLd = JSON.stringify({
    "@context": "https://schema.org",
    "@type": "CollectionPage",
    "name": `Novidades | ${BRAND}`,
    "url": url,
    "isPartOf": {"@type": "WebSite", "name": BRAND, "url": SITE},
  });
  const body = `
<h1>Novidades do ${BRAND}</h1>
<p class="meta">Dicas para ganhar desafios, fotografia com celular,
renda extra e tudo sobre desafios valendo prêmios em dinheiro.</p>
${chalBlock}
${items || "<p>Em breve, novos artigos por aqui.</p>"}`;
  return pageShell({
    title: `Novidades: dicas de desafios, fotos e renda extra | ${BRAND}`,
    description: "Artigos e dicas do Desafio Pago: como ganhar desafios " +
        "de foto, divulgar sua participação, receber prêmios via Pix e " +
        "fazer renda extra online.",
    url,
    ogType: "website",
    jsonLd,
    body,
  });
};

// ─── PÁGINAS SSR: /novidades e /novidades/{slug} ─────────────────────────────

exports.seoPage = functions.https.onRequest(async (req, res) => {
  try {
    const db = admin.firestore();
    const parts = (req.path || "").split("/").filter(Boolean);
    // parts: ["novidades"] ou ["novidades", "slug"]
    const slug = parts.length > 1 ? decodeURIComponent(parts[1]) : "";
    const chalBlock = await challengesBlock(db);

    if (!slug) {
      // Sem orderBy junto do where (evita índice composto) — ordena aqui.
      const snap = await db.collection("seo_articles")
          .where("status", "==", "published").limit(300).get();
      const articles = snap.docs.map((d) => d.data());
      articles.sort((a, b) =>
        String(b.publishedAt).localeCompare(String(a.publishedAt)));
      res.set("Cache-Control", "public, max-age=600, s-maxage=1800");
      return res.status(200)
          .send(renderIndex(articles.slice(0, 100), chalBlock));
    }

    const snap = await db.collection("seo_articles")
        .where("slug", "==", slug).limit(1).get();
    if (snap.empty || snap.docs[0].data().status !== "published") {
      return res.redirect(302, `${SITE}/novidades`);
    }
    res.set("Cache-Control", "public, max-age=3600, s-maxage=86400");
    return res.status(200)
        .send(renderArticle(snap.docs[0].data(), chalBlock));
  } catch (e) {
    console.error("seoPage:", e.message);
    return res.redirect(302, SITE);
  }
});

// ─── SITEMAP.XML ─────────────────────────────────────────────────────────────

exports.seoSitemap = functions.https.onRequest(async (req, res) => {
  try {
    const db = admin.firestore();
    const urls = [
      {loc: `${SITE}/`, priority: "1.0"},
      {loc: `${SITE}/novidades`, priority: "0.9"},
    ];
    const arts = await db.collection("seo_articles")
        .where("status", "==", "published").get();
    for (const d of arts.docs) {
      const a = d.data();
      urls.push({
        loc: `${SITE}/novidades/${a.slug}`,
        lastmod: (a.updatedAt || a.publishedAt || "").slice(0, 10),
        priority: "0.8",
      });
    }
    const chals = await db.collection("challenges").get();
    for (const d of chals.docs) {
      urls.push({
        loc: `${SITE}/challenges/${d.id}`,
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
