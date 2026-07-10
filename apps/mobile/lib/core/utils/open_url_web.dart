// Abrir URL externa em nova aba (web).
import 'package:web/web.dart' as web;

void openExternalUrl(String url) {
  web.window.open(url, '_blank');
}
