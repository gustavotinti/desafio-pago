// Lógica PURA do entryPreview (prévia de link de /challenges/**): detectar o
// site pelo host e reescrever o <head> do index.html do app. Sem triggers do
// Firebase e sem I/O — testado em test/site_ctx.test.js.
//
// O mesmo rewrite /challenges/** existe nos dois targets do hosting (app =
// desafiopago, intl = trialspaid), então a função precisa saber de qual site
// veio a requisição — mesma regra do siteCtx de seo.js (host contém
// "trialspaid" → intl).

// Contexto por site. `indexUrl` é o index.html do PRÓPRIO site (o do intl já
// vem rebrandado pelo build_sites.js); `site` é a origem canônica.
const SITES = {
  br: {
    key: "br", site: "https://desafiopago.com.br",
    indexUrl: "https://desafiopago.web.app/index.html",
    brand: "Desafio Pago", lang: "pt", locale: "pt_BR",
    t: {
      someChallenge: "um desafio",
      defaultTitle: "Desafio Pago",
      defaultDesc: "Participe de desafios e vote nas melhores participações!",
      wantsVote: (a) => `${a} quer o seu voto! 🗳️`,
      wantsVoteDesc: (c) =>
        `Participação no desafio "${c}". Toque e vote no Desafio Pago.`,
      voteEntry: "Vote nesta participação! 🗳️",
      voteEntryDesc: (c) => `Desafio "${c}" no Desafio Pago. Toque e vote.`,
      challengeDesc: "Participe e vote no Desafio Pago!",
      unavailable: "Instabilidade temporária. Tente de novo em instantes.",
      goHome: "Ir para o Desafio Pago",
    },
  },
  intl: {
    key: "intl", site: "https://trialspaid.web.app",
    indexUrl: "https://trialspaid.web.app/index.html",
    brand: "TrialsPaid", lang: "en", locale: "en_US",
    t: {
      someChallenge: "a challenge",
      defaultTitle: "TrialsPaid",
      defaultDesc: "Join challenges and vote for the best entries!",
      wantsVote: (a) => `${a} wants your vote! 🗳️`,
      wantsVoteDesc: (c) =>
        `Entry in the challenge "${c}". Tap to vote on TrialsPaid.`,
      voteEntry: "Vote for this entry! 🗳️",
      voteEntryDesc: (c) => `Challenge "${c}" on TrialsPaid. Tap to vote.`,
      challengeDesc: "Join and vote on TrialsPaid!",
      unavailable: "Temporarily unavailable. Please try again in a moment.",
      goHome: "Go to TrialsPaid",
    },
  },
};

// Host da requisição (atrás do Hosting chega em x-forwarded-host).
const requestHost = (req) => {
  const h = (req && req.headers) || {};
  return String(h["x-forwarded-host"] || h.host || "").toLowerCase();
};

const siteForHost = (host) =>
  String(host || "").toLowerCase().includes("trialspaid") ?
    SITES.intl : SITES.br;

const siteForRequest = (req) => siteForHost(requestHost(req));

const esc = (s) => String(s == null ? "" : s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");

// Textos/URLs da prévia. `found` = o desafio existe; `author` só vale com
// entryId. O canonical NUNCA leva o ?entry= (senão cada participação vira uma
// URL canônica diferente do mesmo desafio); o og:url leva, para a prévia
// compartilhada ser a da participação ("{autor} quer o seu voto").
const previewMeta = (site, {
  challengeId = "", found = false, challengeTitle = "", entryId = "",
  author = "", video = null,
} = {}) => {
  const t = site.t;
  const chTitle = challengeTitle || t.someChallenge;
  let title = t.defaultTitle;
  let desc = t.defaultDesc;
  if (found) {
    if (entryId && author) {
      title = t.wantsVote(author);
      desc = t.wantsVoteDesc(chTitle);
    } else if (entryId) {
      title = t.voteEntry;
      desc = t.voteEntryDesc(chTitle);
    } else {
      title = chTitle;
      desc = t.challengeDesc;
    }
  }
  const canonical = challengeId ?
    `${site.site}/challenges/${encodeURIComponent(challengeId)}` :
    `${site.site}/`;
  let ogUrl = canonical;
  if (found && entryId) ogUrl += `?entry=${encodeURIComponent(entryId)}`;
  // Participação em vídeo por link (YouTube): a prévia usa a capa vertical
  // do próprio vídeo e o Google recebe um VideoObject (chance de aparecer na
  // aba "Vídeos"). Sem capa (Instagram), fica a imagem padrão do site.
  const hasVideo = !!(found && entryId && video && video.thumbUrl);
  const videoLd = hasVideo ? JSON.stringify({
    "@context": "https://schema.org",
    "@type": "VideoObject",
    "name": video.name || title,
    "description": desc,
    "thumbnailUrl": [video.thumbUrl],
    "uploadDate": video.uploadDate || undefined,
    "embedUrl": video.embedUrl || undefined,
    "url": ogUrl,
  }).replace(/</g, "\\u003c") : null; // nunca fecha o <script> por engano
  return {
    title,
    desc,
    htmlTitle: found ? `${chTitle} · ${site.brand}` : site.brand,
    canonical,
    ogUrl,
    image: hasVideo ? video.thumbUrl : `${site.site}/og-default.png`,
    imageW: hasVideo ? 1080 : 1200,
    imageH: hasVideo ? 1920 : 630,
    videoLd,
    siteName: site.brand,
    locale: site.locale,
    // Desafio inexistente: não indexar (e sem canonical para a home).
    noindex: !found,
  };
};

// Tags do <head> base que a prévia substitui. O JSON-LD (<script>) fica.
const HEAD_STRIP = [
  /<link\b[^>]*\brel=["']?canonical["']?[^>]*>\s*/gi,
  // hreflang do index aponta HOME↔HOME — errado numa página de desafio.
  /<link\b[^>]*\bhreflang=[^>]*>\s*/gi,
  /<meta\b[^>]*\bproperty=["']og:[^"']*["'][^>]*>\s*/gi,
  /<meta\b[^>]*\b(?:name|property)=["']twitter:[^"']*["'][^>]*>\s*/gi,
  /<meta\b[^>]*\bname=["']description["'][^>]*>\s*/gi,
  /<meta\b[^>]*\bname=["']robots["'][^>]*>\s*/gi,
  /<title\b[^>]*>[\s\S]*?<\/title>\s*/gi,
];

const stripHeadMeta = (html) =>
  HEAD_STRIP.reduce((out, re) => out.replace(re, ""), String(html || ""));

const headTags = (m) => "\n" +
  `<title>${esc(m.htmlTitle)}</title>\n` +
  `<meta name="description" content="${esc(m.desc)}">\n` +
  (m.noindex ?
    `<meta name="robots" content="noindex">\n` :
    `<link rel="canonical" href="${esc(m.canonical)}">\n`) +
  `<meta property="og:type" content="website">\n` +
  `<meta property="og:site_name" content="${esc(m.siteName)}">\n` +
  `<meta property="og:locale" content="${esc(m.locale)}">\n` +
  `<meta property="og:title" content="${esc(m.title)}">\n` +
  `<meta property="og:description" content="${esc(m.desc)}">\n` +
  `<meta property="og:image" content="${esc(m.image)}">\n` +
  `<meta property="og:image:width" content="${m.imageW || 1200}">\n` +
  `<meta property="og:image:height" content="${m.imageH || 630}">\n` +
  `<meta property="og:url" content="${esc(m.ogUrl)}">\n` +
  `<meta name="twitter:card" content="summary_large_image">\n` +
  `<meta name="twitter:title" content="${esc(m.title)}">\n` +
  `<meta name="twitter:description" content="${esc(m.desc)}">\n` +
  `<meta name="twitter:image" content="${esc(m.image)}">\n` +
  (m.videoLd ?
    `<script type="application/ld+json">${m.videoLd}</script>\n` : "");

// Devolve uma NOVA string (strings são imutáveis — o cache do index.html
// nunca é alterado). Replacement por função: título com "$&"/"$1" entra
// literal. Sem </head> (HTML inesperado) → devolve o original sem mexer.
const rewriteHead = (html, meta) => {
  const src = String(html || "");
  if (!/<\/head>/i.test(src)) return src;
  const tags = headTags(meta);
  return stripHeadMeta(src).replace(/<\/head>/i, () => `${tags}</head>`);
};

// HTML base "bom" para cachear: o fetch do index pode devolver uma página de
// erro do Hosting (ex.: 503) — isso não pode envenenar o cache da instância.
const isAppShell = (html) => {
  const s = String(html || "");
  return /<\/head>/i.test(s) && s.includes("flutter_bootstrap.js");
};

// Página mínima de erro (503) quando nem o index.html está disponível:
// humano volta para a home do próprio site; o Google vê 503 (tenta de novo
// depois, sem trocar o índice).
const unavailableHtml = (site) => {
  const home = `${site.site}/`;
  return "<!DOCTYPE html><html><head><meta charset=\"UTF-8\">" +
    "<meta name=\"robots\" content=\"noindex\">" +
    `<title>${esc(site.brand)}</title></head><body>` +
    `<p>${esc(site.t.unavailable)}</p>` +
    `<p><a href="${esc(home)}">${esc(site.t.goHome)}</a></p>` +
    "</body></html>";
};

module.exports = {
  SITES,
  requestHost,
  siteForHost,
  siteForRequest,
  esc,
  previewMeta,
  stripHeadMeta,
  rewriteHead,
  isAppShell,
  unavailableHtml,
};
