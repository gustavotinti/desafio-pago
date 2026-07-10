import 'package:flutter/material.dart';

import '../config/app_config.dart';
import 'i18n.dart';

/// Seletor de idioma com bandeiras (🇬🇧 🇪🇸 🇫🇷 🇮🇹 🇩🇪) — só aparece no
/// build internacional. No Brasil não renderiza nada.
class LanguageSelector extends StatelessWidget {
  const LanguageSelector({super.key});

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.intl) return const SizedBox.shrink();
    return ValueListenableBuilder<String>(
      valueListenable: I18n.locale,
      builder: (context, code, _) {
        final current = I18n.langs.firstWhere(
          (l) => l.$1 == code,
          orElse: () => I18n.langs.first,
        );
        return PopupMenuButton<String>(
          tooltip: 'Language',
          onSelected: I18n.setLocale,
          itemBuilder: (_) => I18n.langs
              .map((l) => PopupMenuItem<String>(
                    value: l.$1,
                    child: Row(
                      children: [
                        Text(l.$2, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        Text(l.$3),
                        if (l.$1 == code) ...[
                          const Spacer(),
                          const Icon(Icons.check,
                              size: 16, color: Color(0xFF0cc0df)),
                        ],
                      ],
                    ),
                  ))
              .toList(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
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
