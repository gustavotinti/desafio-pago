import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../utils/open_url_stub.dart'
    if (dart.library.js_interop) '../utils/open_url_web.dart';
import 'i18n.dart';

/// Seletor de idioma com bandeiras. Aparece nos DOIS sites:
/// - No Brasil: 🇧🇷 fica selecionado; escolher outro idioma leva para o site
///   internacional (trialspaid.web.app?lang=xx) já naquele idioma.
/// - No internacional: troca o idioma na hora; 🇧🇷 volta para o desafiopago.
class LanguageSelector extends StatelessWidget {
  const LanguageSelector({super.key});

  // pt + os idiomas internacionais, cada um com bandeira e nome.
  static const _all = [
    ('pt', '🇧🇷', 'Português'),
    ('en', '🇬🇧', 'English'),
    ('es', '🇪🇸', 'Español'),
    ('fr', '🇫🇷', 'Français'),
    ('it', '🇮🇹', 'Italiano'),
    ('de', '🇩🇪', 'Deutsch'),
  ];

  void _onSelected(String code) {
    if (AppConfig.intl) {
      // No site internacional: 'pt' volta pro Brasil; resto troca na hora.
      if (code == 'pt') {
        openExternalUrl(AppConfig.brSiteUrl);
      } else {
        I18n.setLocale(code);
      }
    } else {
      // No Brasil: 'pt' fica; qualquer outro vai pro internacional já no idioma.
      if (code != 'pt') {
        openExternalUrl('${AppConfig.intlSiteUrl}/?lang=$code');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: I18n.locale,
      builder: (context, code, _) {
        final currentCode = AppConfig.intl ? code : 'pt';
        final current = _all.firstWhere(
          (l) => l.$1 == currentCode,
          orElse: () => _all.first,
        );
        return PopupMenuButton<String>(
          tooltip: I18n.tr('change_language'),
          onSelected: _onSelected,
          itemBuilder: (_) => _all
              .map((l) => PopupMenuItem<String>(
                    value: l.$1,
                    child: Row(
                      children: [
                        Text(l.$2, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        Text(l.$3),
                        if (l.$1 == currentCode) ...[
                          const Spacer(),
                          const Icon(Icons.check,
                              size: 16, color: Color(0xFF0cc0df)),
                        ],
                      ],
                    ),
                  ))
              .toList(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(current.$2, style: const TextStyle(fontSize: 20)),
                const Icon(Icons.arrow_drop_down, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }
}
