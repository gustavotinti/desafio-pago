// ─── COFRE DE CHAVES (config sensível editável pelo admin) ───────────────────
// Guarda credenciais (Mercado Pago, PayPal, IA) num doc TRANCADO do Firestore
// (secure_config/keys — regras negam TODA leitura/escrita do client; só o
// Admin SDK acessa). O super admin grava pelo painel; o valor NUNCA é lido de
// volta pelo client (só um status mascarado). getSecret() dá prioridade ao
// cofre e cai no functions/.env como fallback.
//
// Nota de segurança: segredos no Firestore são menos protegidos que o
// Secret Manager, mas ficam fora de qualquer caminho legível pelo client e
// permitem trocar a chave sem redeploy. Bom equilíbrio p/ operação solo.

const functions = require("firebase-functions");
const admin = require("firebase-admin");

const SUPER_ADMIN_EMAIL = "gustavo.a.tinti3@gmail.com";

// Chaves que o painel pode gravar (whitelist rígida).
const ALLOWED = [
  "MERCADOPAGO_ACCESS_TOKEN",
  "MP_WEBHOOK_SECRET",
  "PAYPAL_CLIENT_ID",
  "PAYPAL_SECRET",
  "PAYPAL_MODE",
  "GEMINI_API_KEY",
  "OPENAI_API_KEY",
  "INSTAGRAM_ACCESS_TOKEN",
  "INSTAGRAM_USER_ID",
];

// Cache por instância (TTL curto) — evita ler o Firestore a cada pagamento.
let _cache = null;
let _cacheAt = 0;
const TTL_MS = 60 * 1000;

async function _load(fresh) {
  const now = Date.now();
  if (!fresh && _cache && (now - _cacheAt) < TTL_MS) return _cache;
  try {
    const doc = await admin.firestore()
        .collection("secure_config").doc("keys").get();
    _cache = doc.exists ? (doc.data() || {}) : {};
    _cacheAt = now;
  } catch (e) {
    _cache = _cache || {};
  }
  return _cache;
}

// Lê uma credencial: cofre (Firestore) tem prioridade; senão o .env.
async function getSecret(key) {
  const secrets = await _load(false);
  const v = secrets[key];
  if (v !== undefined && v !== null && String(v).length > 0) return String(v);
  return process.env[key] || "";
}

function _assertSuper(context) {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Não autenticado");
  }
  if (context.auth.token.email !== SUPER_ADMIN_EMAIL) {
    throw new functions.https.HttpsError(
        "permission-denied", "Apenas o super admin.");
  }
}

// Super admin grava uma credencial. Vazio ("") limpa o valor do cofre
// (volta a valer o .env, se houver).
exports.adminSetSecret = functions.https.onCall(async (data, context) => {
  _assertSuper(context);
  const key = String(data.key || "");
  if (!ALLOWED.includes(key)) {
    throw new functions.https.HttpsError(
        "invalid-argument", "Chave não permitida.");
  }
  const value = String(data.value == null ? "" : data.value).trim();
  await admin.firestore().collection("secure_config").doc("keys").set({
    [key]: value,
    [`${key}__updatedAt`]: new Date().toISOString(),
  }, {merge: true});
  _cache = null; // invalida o cache local desta instância
  return {success: true};
});

// Status mascarado — quais chaves estão preenchidas e de onde vêm.
// NUNCA retorna o valor completo.
exports.adminGetSecretStatus =
    functions.https.onCall(async (data, context) => {
      _assertSuper(context);
      const secrets = await _load(true);
      const out = {};
      for (const key of ALLOWED) {
        const fromVault = secrets[key];
        const hasVault = fromVault && String(fromVault).length > 0;
        const val = hasVault ? String(fromVault) : (process.env[key] || "");
        out[key] = {
          set: val.length > 0,
          source: hasVault ? "vault" : (process.env[key] ? "env" : "none"),
          masked: val.length > 4 ?
            `••••${val.slice(-4)}` : (val ? "••••" : ""),
          updatedAt: secrets[`${key}__updatedAt`] || null,
        };
      }
      return out;
    });

module.exports.getSecret = getSecret;
