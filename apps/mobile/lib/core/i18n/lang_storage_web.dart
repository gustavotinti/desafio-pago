// Persistência do idioma no navegador (localStorage).
import 'package:web/web.dart' as web;

String? readSavedLang() => web.window.localStorage.getItem('tp_lang');

void writeSavedLang(String code) =>
    web.window.localStorage.setItem('tp_lang', code);
