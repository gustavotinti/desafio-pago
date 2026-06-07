/// Fallback (mobile/desktop): download direto de arquivo não suportado aqui.
void downloadTextFile(String filename, String content) {
  throw UnsupportedError(
      'Download de arquivo disponível apenas na versão web.');
}
