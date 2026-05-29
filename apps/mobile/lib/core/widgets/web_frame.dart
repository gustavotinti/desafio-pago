import 'package:flutter/material.dart';

/// Constrains content to [maxWidth] and centers it on wide screens (web/desktop).
/// On mobile-sized screens this widget is a transparent pass-through.
///
/// Usage — wrap the body content of any Scaffold:
///   body: WebFrame(child: SingleChildScrollView(...))
class WebFrame extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const WebFrame({
    super.key,
    required this.child,
    this.maxWidth = 680,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth <= maxWidth + 40) return child;
    final hPad = (screenWidth - maxWidth) / 2;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: child,
    );
  }
}
