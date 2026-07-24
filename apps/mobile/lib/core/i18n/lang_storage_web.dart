// Persistência do idioma no navegador (localStorage).
import 'package:web/web.dart' as web;

String? readSavedLang() => web.window.localStorage.getItem('tp_lang');

void writeSavedLang(String code) =>
    web.window.localStorage.setItem('tp_lang', code);

// Idioma primário do navegador (ex.: "pt-BR", "en-US"). Vazio fora da web.
String browserLanguage() => web.window.navigator.language;

// Banner de sugestão de região: lembra se o usuário já dispensou.
bool regionSuggestDismissed() =>
    web.window.localStorage.getItem('tp_region_dismissed') == '1';

void dismissRegionSuggest() =>
    web.window.localStorage.setItem('tp_region_dismissed', '1');
