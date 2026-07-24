import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../utils/open_url_stub.dart'
    if (dart.library.js_interop) '../utils/open_url_web.dart';
import 'i18n.dart';
import 'lang_storage_stub.dart'
    if (dart.library.js_interop) 'lang_storage_web.dart';

/// Banner sutil e dispensável que sugere o site certo pela região, com base
/// no idioma do navegador:
/// - No BR (desafiopago): se o navegador NÃO for português → oferece o
///   TrialsPaid (internacional).
/// - No internacional (trialspaid): se o navegador for português → oferece o
///   Desafio Pago (Brasil).
/// Aparece uma vez; ao dispensar, não incomoda de novo (localStorage).
class RegionBanner extends StatefulWidget {
  const RegionBanner({super.key});

  @override
  State<RegionBanner> createState() => _RegionBannerState();
}

class _RegionBannerState extends State<RegionBanner> {
  bool _hidden = false;

  bool get _browserIsPt =>
      browserLanguage().toLowerCase().startsWith('pt');

  /// Deve sugerir troca de site?
  bool get _suggest {
    if (regionSuggestDismissed()) return false;
    return AppConfig.intl ? _browserIsPt : !_browserIsPt;
  }

  void _dismiss() {
    dismissRegionSuggest();
    setState(() => _hidden = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden || !_suggest) return const SizedBox.shrink();
    final toBr = AppConfig.intl; // no intl, sugere o Brasil
    final url = toBr ? AppConfig.brSiteUrl : '${AppConfig.intlSiteUrl}/';
    final msg = I18n.tr(toBr ? 'region_to_br' : 'region_to_intl');
    final flag = toBr ? '🇧🇷' : '🇬🇧';
    return Material(
      color: const Color(0xFF0F172A),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(color: Colors.white, fontSize: 12.5),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => navigateSameTab(url),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF0F172A),
                backgroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(I18n.tr('region_go'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70, size: 18),
              visualDensity: VisualDensity.compact,
              tooltip: 'Fechar',
              onPressed: _dismiss,
            ),
          ],
        ),
      ),
    );
  }
}
