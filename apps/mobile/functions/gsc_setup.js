// ─── GOOGLE SEARCH CONSOLE — SETUP 100% POR API ─────────────────────────────
// Verifica a posse dos sites, cria as propriedades, adiciona o dono humano e
// envia os sitemaps — tudo pela conta de serviço das Cloud Functions, sem
// ninguém clicar no Search Console. Idempotente (pode rodar de novo).
//
// Fluxo (HTTP POST, secret SEED_2026_DP):
//   step=enable → habilita as APIs (Site Verification + Search Console)
//   step=token  → gera o token META de cada site (colocar no <head> e deployar)
//   step=verify → verifica posse, adiciona OWNER_EMAIL como dono, envia sitemap
//   step=status → lista propriedades verificadas + status dos sitemaps
//
// Depois disso o cron gscSyncQueries (loop de demanda) passa a funcionar, e as
// propriedades aparecem no Search Console do dono.

const functions = require("firebase-functions");
const {google} = require("googleapis");

const PROJECT = "desafio-app-b8665";
const OWNER_EMAIL = "gustavo.a.tinti3@gmail.com";

// Propriedades URL-prefix (verificação por META, sem DNS).
const SITES = [
  {url: "https://desafiopago.com.br/", sitemap: "https://desafiopago.com.br/sitemap.xml"},
  {url: "https://trialspaid.web.app/", sitemap: "https://trialspaid.web.app/sitemap.xml"},
];

const SCOPES = [
  "https://www.googleapis.com/auth/siteverification",
  "https://www.googleapis.com/auth/webmasters",
  "https://www.googleapis.com/auth/cloud-platform",
];

const authClient = () => new google.auth.GoogleAuth({scopes: SCOPES});

const stepEnable = async (auth) => {
  const su = google.serviceusage({version: "v1", auth});
  const out = [];
  for (const api of ["siteverification.googleapis.com",
    "searchconsole.googleapis.com"]) {
    try {
      await su.services.enable({name: `projects/${PROJECT}/services/${api}`});
      out.push({api, enabled: true});
    } catch (e) {
      out.push({api, enabled: false, error: e.message});
    }
  }
  return out;
};

const stepToken = async (auth) => {
  const sv = google.siteVerification({version: "v1", auth});
  const out = [];
  for (const s of SITES) {
    const r = await sv.webResource.getToken({
      requestBody: {
        site: {identifier: s.url, type: "SITE"},
        verificationMethod: "META",
      },
    });
    out.push({site: s.url, method: r.data.method, token: r.data.token});
  }
  return out;
};

const stepVerify = async (auth) => {
  const sv = google.siteVerification({version: "v1", auth});
  const wm = google.webmasters({version: "v3", auth});
  const out = [];
  for (const s of SITES) {
    const item = {site: s.url};
    // 1) Verifica a posse (Google busca a home e procura o META).
    try {
      const r = await sv.webResource.insert({
        verificationMethod: "META",
        requestBody: {site: {identifier: s.url, type: "SITE"}},
      });
      item.verified = true;
      item.resourceId = r.data.id;
      // 2) Adiciona o dono humano (aparece no Search Console dele).
      try {
        const owners = new Set(r.data.owners || []);
        owners.add(OWNER_EMAIL);
        await sv.webResource.update({
          id: r.data.id,
          requestBody: {
            id: r.data.id,
            site: r.data.site,
            owners: [...owners],
          },
        });
        item.ownerAdded = OWNER_EMAIL;
      } catch (e) {
        item.ownerError = e.message;
      }
    } catch (e) {
      item.verified = false;
      item.verifyError = e.message;
    }
    // 3) Garante a propriedade no Search Console e envia o sitemap.
    try {
      await wm.sites.add({siteUrl: s.url});
    } catch (e) {
      // já existe
    }
    try {
      await wm.sitemaps.submit({siteUrl: s.url, feedpath: s.sitemap});
      item.sitemapSubmitted = s.sitemap;
    } catch (e) {
      item.sitemapError = e.message;
    }
    out.push(item);
  }
  return out;
};

const stepStatus = async (auth) => {
  const wm = google.webmasters({version: "v3", auth});
  const sites = await wm.sites.list();
  const out = {sites: (sites.data.siteEntry || []), sitemaps: []};
  for (const s of SITES) {
    try {
      const sm = await wm.sitemaps.list({siteUrl: s.url});
      out.sitemaps.push({site: s.url, entries: sm.data.sitemap || []});
    } catch (e) {
      out.sitemaps.push({site: s.url, error: e.message});
    }
  }
  return out;
};

exports.gscSetup = functions.runWith({timeoutSeconds: 300})
    .https.onRequest(async (req, res) => {
      if (req.method !== "POST") {
        return res.status(405).json({error: "Method Not Allowed"});
      }
      if (!req.body || req.body.secret !== "SEED_2026_DP") {
        return res.status(403).json({error: "Forbidden"});
      }
      const step = String(req.body.step || "status");
      try {
        const auth = authClient();
        let result;
        if (step === "enable") result = await stepEnable(auth);
        else if (step === "token") result = await stepToken(auth);
        else if (step === "verify") result = await stepVerify(auth);
        else result = await stepStatus(auth);
        return res.json({success: true, step, result});
      } catch (e) {
        console.error("gscSetup:", e.message);
        return res.status(500).json({success: false, step, error: e.message});
      }
    });
