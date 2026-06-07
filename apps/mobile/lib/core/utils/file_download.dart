// Download de arquivo de texto. Implementação real no web (dart:html);
// no mobile cai no stub (admin é usado no web).
export 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart';
