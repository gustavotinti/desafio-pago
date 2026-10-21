// iframe com o player OFICIAL do YouTube/Instagram (Flutter Web).
//
// Cada url registra uma view uma única vez (o registro é global e não pode
// ser repetido). O iframe ocupa todo o espaço que o Flutter der a ele.
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

final _registered = <String>{};

Widget embedIframe(String src) {
  final viewType = 'dp-embed-${src.hashCode}';
  if (_registered.add(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
      final f = web.HTMLIFrameElement();
      f.src = src;
      f.style.border = '0';
      f.style.width = '100%';
      f.style.height = '100%';
      f.setAttribute(
          'allow', 'autoplay; encrypted-media; picture-in-picture; fullscreen');
      f.setAttribute('allowfullscreen', '');
      // O player do YouTube recusa embed sem origem (erro 153).
      f.setAttribute('referrerpolicy', 'strict-origin-when-cross-origin');
      return f;
    });
  }
  return HtmlElementView(viewType: viewType);
}

const bool embedSupported = true;
