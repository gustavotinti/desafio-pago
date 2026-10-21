// ─── VÍDEO POR LINK (YouTube Shorts / Reels do Instagram) ───────────────────
// O vídeo continua hospedado no YouTube/Instagram — o Desafio Pago só guarda
// o link e mostra o player oficial deles (custo de armazenamento/banda zero).
//
// Lógica PURA (sem Firebase), espelhada em lib/core/utils/video_link.dart: os
// testes dos dois lados usam os mesmos vetores — se mudar aqui, mude lá.
//
// ATENÇÃO: não é espalhado no `exports` do index.js (não tem Cloud Function
// aqui) — só `require` normal.

const YT_ID = /^[A-Za-z0-9_-]{11}$/;
const IG_CODE = /^[A-Za-z0-9_-]{5,40}$/;
const IG_KINDS = ["reel", "reels", "p", "tv"];

const youtube = (id) => ({
  provider: "youtube",
  id,
  url: `https://www.youtube.com/shorts/${id}`,
  embedUrl: `https://www.youtube-nocookie.com/embed/${id}`,
  // oar2 = capa no formato ORIGINAL do vídeo (1080×1920 num Short). A
  // hqdefault é 4:3 com tarjas pretas.
  thumbUrl: `https://i.ytimg.com/vi/${id}/oar2.jpg`,
});

const instagram = (kind, code) => ({
  provider: "instagram",
  id: code,
  url: `https://www.instagram.com/${kind}/${code}/`,
  embedUrl: `https://www.instagram.com/${kind}/${code}/embed/`,
  // Capa do Instagram só com app da Meta aprovado — sem ela, o app mostra
  // um card da marca.
  thumbUrl: null,
});

/**
 * Link colado pelo participante → vídeo reconhecido, ou null.
 * Aceita: youtube.com/shorts/ID, youtube.com/watch?v=ID, youtu.be/ID,
 * youtube.com/embed/ID (www., m., music.) e instagram.com/{reel,reels,p,tv}/
 * CODE (inclusive o formato novo instagram.com/{usuario}/reel/CODE).
 * @param {string} raw
 * @return {?{provider: string, id: string, url: string, embedUrl: string,
 *   thumbUrl: ?string}}
 */
function parseVideoLink(raw) {
  let s = String(raw || "").trim();
  if (!s || /\s/.test(s)) return null;
  if (!/^https?:\/\//i.test(s)) s = "https://" + s;
  let u;
  try {
    u = new URL(s);
  } catch (e) {
    return null;
  }
  const host = u.hostname.toLowerCase().replace(/^(www\.|m\.|music\.)/, "");
  const parts = u.pathname.split("/").filter(Boolean);

  if (host === "youtube.com" || host === "youtube-nocookie.com") {
    let id = null;
    if (["shorts", "embed", "live", "v"].includes(parts[0])) id = parts[1];
    else if (parts[0] === "watch") id = u.searchParams.get("v");
    return id && YT_ID.test(id) ? youtube(id) : null;
  }
  if (host === "youtu.be") {
    const id = parts[0];
    return id && YT_ID.test(id) ? youtube(id) : null;
  }
  if (host === "instagram.com" || host === "instagr.am") {
    let i = -1;
    if (IG_KINDS.includes(parts[0])) i = 0;
    else if (IG_KINDS.includes(parts[1])) i = 1; // /{usuario}/reel/CODE
    if (i < 0) return null;
    const code = parts[i + 1];
    if (!code || !IG_CODE.test(code)) return null;
    return instagram(parts[i] === "p" ? "p" : "reel", code);
  }
  return null;
}

// Sem 0/O/1/I: o participante digita o código no título/legenda.
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

/**
 * Código de verificação do participante NESTE desafio (ex.: "DPK7M2Q").
 * Determinístico — o app mostra antes do envio e o servidor recalcula. Não é
 * segredo: ele prova que quem envia CONTROLA o vídeo (consegue editar o
 * título/legenda), não quem é a pessoa. Só aritmética inteira pequena
 * (< 2^38): dá o mesmo resultado em Node, no Dart da VM e no Dart compilado
 * para JavaScript.
 * @param {string} uid
 * @param {string} challengeId
 * @return {string}
 */
function verificationCode(uid, challengeId) {
  const s = `${uid}:${challengeId}`;
  let h = 5381;
  for (let i = 0; i < s.length; i++) {
    h = (h * 33 + s.charCodeAt(i)) % 2147483647;
  }
  let out = "";
  for (let k = 0; k < 5; k++) {
    out += CODE_ALPHABET[h % 32];
    h = Math.floor(h / 32);
  }
  return "DP" + out;
}

/**
 * O texto (título/legenda) contém o código? Ignora maiúsculas e aceita com
 * ou sem "#".
 * @param {string} text
 * @param {string} code
 * @return {boolean}
 */
function hasCode(text, code) {
  return String(text || "").toUpperCase().includes(String(code).toUpperCase());
}

/**
 * Consulta pública do YouTube (oEmbed — sem chave, sem custo). Nunca lança.
 * Confirmado ao vivo: Short responde 113×200 (vertical); vídeo comum 200×113;
 * inexistente 404; privado/incorporação desativada 401/403.
 * @param {string} id
 * @param {Object} [opts] fetchImpl (para testes) e timeoutMs.
 * @return {Promise<Object>} {status: ok | not_found | private | error,
 *   title, author, width, height}
 */
async function checkYouTube(id, {fetchImpl = fetch, timeoutMs = 8000} = {}) {
  const target = encodeURIComponent(`https://www.youtube.com/watch?v=${id}`);
  try {
    const r = await fetchImpl(
        `https://www.youtube.com/oembed?url=${target}&format=json`,
        {signal: AbortSignal.timeout(timeoutMs)});
    if (r.status === 404 || r.status === 400) return {status: "not_found"};
    if (r.status === 401 || r.status === 403) return {status: "private"};
    if (!r.ok) return {status: "error"};
    const j = await r.json();
    return {
      status: "ok",
      title: String(j.title || ""),
      author: String(j.author_name || ""),
      width: Number(j.width) || 0,
      height: Number(j.height) || 0,
    };
  } catch (e) {
    return {status: "error"};
  }
}

/**
 * Vídeo vertical (o app só aceita vertical, como as imagens 9:16/4:5).
 * @param {Object} r resposta do checkYouTube (width/height).
 * @return {boolean}
 */
const isVertical = (r) => Number(r.height) > Number(r.width);

module.exports = {
  parseVideoLink, verificationCode, hasCode, checkYouTube, isVertical,
  CODE_ALPHABET,
};
