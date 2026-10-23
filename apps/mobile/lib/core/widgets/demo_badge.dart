import 'package:flutter/material.dart';

import '../i18n/i18n.dart';

/// Selo "Demonstração" para conteúdo virtual (perfis, desafios e
/// participações de exemplo). Transparência: quem vê sabe que não é um
/// usuário real e que não vale prêmio. Toque/hover explica.
class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key, this.compact = false});

  /// Versão pequena (ao lado de um nome).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: I18n.tr('demo_explain'),
      triggerMode: TooltipTriggerMode.tap,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 5 : 8, vertical: compact ? 1 : 3),
        decoration: BoxDecoration(
          color: const Color(0xFFEDEFF3),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFB8C0CC)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.science_outlined,
                size: compact ? 10 : 13, color: const Color(0xFF5A6474)),
            SizedBox(width: compact ? 2 : 4),
            Text(
              I18n.tr('demo_badge'),
              style: TextStyle(
                fontSize: compact ? 9 : 11,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF5A6474),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
