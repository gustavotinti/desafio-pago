// Fora do navegador não há iframe: o player oferece abrir no app do
// YouTube/Instagram.
import 'package:flutter/widgets.dart';

Widget embedIframe(String src) => const SizedBox.shrink();

const bool embedSupported = false;
