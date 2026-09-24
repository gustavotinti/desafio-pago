// Build dos 2 sites (mesmo codebase): TrialsPaid (intl) e Desafio Pago (BR).
// Reproduz o passo a passo que antes só existia no histórico do terminal:
//   1) flutter build web --release --dart-define=INTL_BUILD=true
//   2) node copy_web_assets.js
//   3) build/web -> build/web_intl (cópia limpa)
//   4) rebrand de build/web_intl (index.html, manifest.json, robots.txt)
//   5) flutter build web --release (BR) + node copy_web_assets.js
//   6) asserções — qualquer divergência derruba o script (exit 1)
// Depois: firebase deploy --only hosting (targets app=build/web,
// intl=build/web_intl). Sem dependências — só Node.
//
// Uso (em apps/mobile): node build_sites.js
// Flutter fora do PATH: usa $FLUTTER ou, no Windows, C:\flutter\bin\flutter.bat.
const fs = require("fs");
const path = require("path");
const {spawnSync} = require("child_process");

const base = __dirname;
const isWin = process.platform === "win32";
const webDir = path.join(base, "build", "web");
const intlDir = path.join(base, "build", "web_intl");

const BR_URL = "https://desafiopago.com.br/";
const INTL_URL = "https://trialspaid.web.app/";
const HREFLANG_RE = /<!-- hreflang:start -->[\s\S]*?<!-- hreflang:end -->/;

function fail(msg) {
  console.error(`\n[build_sites] FALHOU: ${msg}`);
  process.exit(1);
}

function flutterCmd() {
  if (process.env.FLUTTER) return process.env.FLUTTER;
  const winDefault = "C:\\flutter\\bin\\flutter.bat";
  if (isWin && fs.existsSync(winDefault)) return winDefault;
  return "flutter";
}

// Roda um comando herdando o terminal; aborta se sair != 0.
// No Windows o .bat exige shell — monta a linha inteira (args são fixos).
function run(cmd, args) {
  const line = [`"${cmd}"`, ...args].join(" ");
  console.log(`\n[build_sites] $ ${line}`);
  const r = isWin ?
    spawnSync(line, {cwd: base, stdio: "inherit", shell: true}) :
    spawnSync(cmd, args, {cwd: base, stdio: "inherit"});
  if (r.error) fail(`${line}: ${r.error.message}`);
  if (r.status !== 0) fail(`${line} saiu com código ${r.status}`);
}

// Troca obrigatória: se o padrão não existir, o template mudou — falha alto
// em vez de publicar o intl com branding do BR.
function mustReplace(str, pattern, replacement, label) {
  const found = typeof pattern === "string" ?
    str.includes(pattern) : pattern.test(str);
  if (!found) fail(`rebrand: padrão não encontrado (${label})`);
  if (typeof pattern === "string") return str.split(pattern).join(replacement);
  return str.replace(pattern, replacement);
}

function hreflangBlock(html, label) {
  const m = html.match(HREFLANG_RE);
  if (!m) fail(`${label}: bloco hreflang não encontrado`);
  return m[0];
}

function rebrandIndex(html) {
  // O bloco hreflang fica intacto (idêntico nos dois sites): vira um marcador
  // durante as trocas e volta no fim.
  const block = hreflangBlock(html, "web_intl/index.html (antes do rebrand)");
  const marker = "@@HREFLANG_BLOCK@@";
  let out = html.replace(block, marker);
  out = mustReplace(out,
      /<meta name="description" content="[^"]*">/,
      "<meta name=\"description\" content=\"Photo challenges with real cash " +
      "prizes. Create a challenge, join with your best shot — the most " +
      "voted entry takes the prize. Get paid in crypto (XRP).\">",
      "meta description");
  out = mustReplace(out,
      /<meta property="og:title" content="[^"]*">/,
      "<meta property=\"og:title\" content=\"TrialsPaid — photo challenges " +
      "with cash prizes\">",
      "og:title");
  out = mustReplace(out,
      /<meta property="og:description" content="[^"]*">/,
      "<meta property=\"og:description\" content=\"Create prize challenges " +
      "or join with your best photo. Most voted wins. Paid out in crypto " +
      "(XRP).\">",
      "og:description");
  out = mustReplace(out,
      /<title>[^<]*<\/title>/,
      "<title>TrialsPaid — photo challenges with real cash prizes</title>",
      "title");
  out = mustReplace(out, "content=\"Desafio Pago\"", "content=\"TrialsPaid\"",
      "content=\"Desafio Pago\"");
  out = mustReplace(out, "\"name\":\"Desafio Pago\"", "\"name\":\"TrialsPaid\"",
      "JSON-LD name");
  out = mustReplace(out,
      /"description":"[^"]*"/,
      "\"description\":\"Photo challenges with real cash prizes, paid in " +
      "crypto.\"",
      "JSON-LD description");
  out = mustReplace(out, BR_URL, INTL_URL, "URLs desafiopago.com.br");
  // Função como replacement: o bloco é inserido literal (sem interpretar $).
  return out.replace(marker, () => block);
}

function read(p) {
  if (!fs.existsSync(p)) fail(`arquivo não existe: ${path.relative(base, p)}`);
  return fs.readFileSync(p, "utf8");
}

function write(p, content) {
  fs.writeFileSync(p, content, "utf8");
}

const flutter = flutterCmd();
const t0 = Date.now();

// 1) Build intl
run(flutter, ["build", "web", "--release", "--dart-define=INTL_BUILD=true"]);
// 2) Assets estáticos (avatars, portraits, challenge_*, favicons, og)
run(process.execPath, [path.join(base, "copy_web_assets.js")]);

// 3) build/web -> build/web_intl
fs.rmSync(intlDir, {recursive: true, force: true});
fs.cpSync(webDir, intlDir, {recursive: true});
console.log("\n[build_sites] build/web copiado para build/web_intl");

// 4) Rebrand do intl
const intlIndexPath = path.join(intlDir, "index.html");
write(intlIndexPath, rebrandIndex(read(intlIndexPath)));

const intlManifestPath = path.join(intlDir, "manifest.json");
write(intlManifestPath, mustReplace(
    mustReplace(read(intlManifestPath),
        "Desafio Pago", "TrialsPaid", "manifest.json name"),
    /"description": "[^"]*"/,
    "\"description\": \"Win photo challenges, earn real cash!\"",
    "manifest.json description"));

const intlRobotsPath = path.join(intlDir, "robots.txt");
write(intlRobotsPath, mustReplace(read(intlRobotsPath),
    `${BR_URL}sitemap.xml`, `${INTL_URL}sitemap.xml`, "robots.txt"));
console.log("[build_sites] rebrand TrialsPaid aplicado em build/web_intl");

// 5) Build BR (sobrescreve build/web) + assets
run(flutter, ["build", "web", "--release"]);
run(process.execPath, [path.join(base, "copy_web_assets.js")]);

// 6) Asserções
const intlIndex = read(intlIndexPath);
const brIndex = read(path.join(webDir, "index.html"));
const intlBlock = hreflangBlock(intlIndex, "web_intl/index.html");
const brBlock = hreflangBlock(brIndex, "web/index.html");
const outsideIntl = intlIndex.replace(HREFLANG_RE, "");

if (!intlIndex.includes("TrialsPaid")) {
  fail("web_intl/index.html não contém \"TrialsPaid\"");
}
if (intlIndex.includes("(Pix)")) {
  fail("web_intl/index.html ainda contém \"(Pix)\"");
}
if (outsideIntl.includes("Desafio Pago") || outsideIntl.includes(BR_URL)) {
  fail("web_intl/index.html ainda tem branding/URL do BR fora do hreflang");
}
if (intlBlock !== brBlock) {
  fail("bloco hreflang diferente entre web/ e web_intl/");
}
if (!brBlock.includes(BR_URL) || !brBlock.includes(INTL_URL)) {
  fail("bloco hreflang sem as URLs dos dois sites");
}
if (!brIndex.includes("Desafio Pago")) {
  fail("web/index.html não contém \"Desafio Pago\"");
}
if (brIndex.includes("TrialsPaid — photo")) {
  fail("web/index.html saiu com o rebrand do intl");
}
const intlManifest = read(path.join(intlDir, "manifest.json"));
if (intlManifest.includes("Desafio Pago") || intlManifest.includes("Vença")) {
  fail("web_intl/manifest.json ainda tem nome/descrição do BR");
}
const brRobots = read(path.join(webDir, "robots.txt"));
const intlRobots = read(intlRobotsPath);
if (!brRobots.includes(`Sitemap: ${BR_URL}sitemap.xml`)) {
  fail("web/robots.txt não aponta para o sitemap do desafiopago.com.br");
}
if (!intlRobots.includes(`Sitemap: ${INTL_URL}sitemap.xml`) ||
    intlRobots.includes(BR_URL)) {
  fail("web_intl/robots.txt não aponta (só) para o sitemap do trialspaid");
}

const secs = Math.round((Date.now() - t0) / 1000);
console.log(`
[build_sites] OK em ${secs}s
  BR   build/web       -> target "app"  (desafiopago.com.br)
  INTL build/web_intl  -> target "intl" (trialspaid.web.app)
  hreflang idêntico nos dois · robots apontando para o próprio sitemap
  Próximo: firebase deploy --only hosting --project desafio-app-b8665
`);
