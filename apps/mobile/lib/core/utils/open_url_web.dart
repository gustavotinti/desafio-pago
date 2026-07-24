// Abrir URL externa em nova aba (web).
import 'package:web/web.dart' as web;

void openExternalUrl(String url) {
  web.window.open(url, '_blank');
}

// Navegar na MESMA aba (ex.: trocar de site BR ↔ internacional).
void navigateSameTab(String url) {
  web.window.location.href = url;
}
