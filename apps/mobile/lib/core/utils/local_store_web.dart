// Chave-valor persistente no navegador (localStorage).
//
// Tudo em try/catch: em aba anônima, com dados do site bloqueados ou em
// prévias o acesso ao localStorage pode lançar — aí vira "sem valor".
import 'package:web/web.dart' as web;

String? localStoreRead(String key) {
  try {
    return web.window.localStorage.getItem(key);
  } catch (_) {
    return null;
  }
}

void localStoreWrite(String key, String value) {
  try {
    web.window.localStorage.setItem(key, value);
  } catch (_) {}
}

void localStoreRemove(String key) {
  try {
    web.window.localStorage.removeItem(key);
  } catch (_) {}
}
