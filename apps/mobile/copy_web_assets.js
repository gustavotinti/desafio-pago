// Copia pastas de assets estáticos (que o `flutter build web` não copia
// automaticamente) de web/ para build/web/ antes do deploy do Hosting.
// Acionado pelo hook "predeploy" do hosting em firebase.json.
const fs = require("fs");
const path = require("path");

const base = __dirname;
const dirs = ["avatars", "portraits", "challenge_images"];
// Arquivos avulsos que o flutter build web não copia (adicionados por nós).
const files = ["favicon.svg", "favicon.png", "apple-touch-icon.png"];

for (const d of dirs) {
  const src = path.join(base, "web", d);
  const dest = path.join(base, "build", "web", d);
  if (fs.existsSync(src)) {
    fs.cpSync(src, dest, {recursive: true});
    const count = fs.readdirSync(src, {recursive: true})
        .filter((f) => f.endsWith(".png") || f.endsWith(".jpg")).length;
    console.log(`[copy_web_assets] ${d}: ${count} arquivos -> build/web/${d}`);
  } else {
    console.log(`[copy_web_assets] aviso: web/${d} nao existe, pulando`);
  }
}

for (const f of files) {
  const src = path.join(base, "web", f);
  const dest = path.join(base, "build", "web", f);
  if (fs.existsSync(src)) {
    fs.copyFileSync(src, dest);
    console.log(`[copy_web_assets] ${f} -> build/web/${f}`);
  }
}
