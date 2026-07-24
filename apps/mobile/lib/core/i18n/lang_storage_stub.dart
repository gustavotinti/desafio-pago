// Persistência do idioma — stub para plataformas não-web (memória apenas).
String? readSavedLang() => null;

void writeSavedLang(String code) {}

String browserLanguage() => '';

bool regionSuggestDismissed() => true; // fora da web, nunca sugere

void dismissRegionSuggest() {}
