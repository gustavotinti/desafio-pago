"use strict";

// Utilidades de texto puras (testáveis) usadas pela máquina de SEO.

// slug estável: minúsculas, sem acentos, só [a-z0-9-], máx 80 chars.
function slugify(s) {
  return String(s || "")
      .toLowerCase()
      .normalize("NFD")
      .replace(/[̀-ͯ]/g, "") // remove diacríticos combinantes
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 80);
}

// Sanitização leve de HTML (remove script/style/iframe, handlers on*, e
// pseudo-protocolo javascript:). Não é um sanitizador completo, mas cobre os
// vetores comuns no conteúdo gerado por IA.
function sanitizeHtml(h) {
  return String(h || "")
      .replace(/<\s*(script|style|iframe)[^>]*>[\s\S]*?<\s*\/\s*\1\s*>/gi, "")
      .replace(/\son\w+\s*=\s*"[^"]*"/gi, "")
      .replace(/\son\w+\s*=\s*'[^']*'/gi, "")
      .replace(/javascript:/gi, "");
}

module.exports = {slugify, sanitizeHtml};
