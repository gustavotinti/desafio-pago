/// Configuração de build: Brasil (padrão) vs Internacional (trialspaid).
///
/// O build internacional é gerado com:
///   flutter build web --release --dart-define=INTL_BUILD=true
/// e deployado no site `trialspaid` (trialspaid.web.app). O build Brasil
/// permanece IDÊNTICO ao atual (desafiopago.com.br).
class AppConfig {
  AppConfig._();

  /// true no site internacional (trialspaid.web.app).
  static const bool intl =
      bool.fromEnvironment('INTL_BUILD', defaultValue: false);

  /// Nome da marca conforme o site.
  static const String brand = intl ? 'TrialsPaid' : 'Desafio Pago';

  /// URL pública do site (links compartilhados, prévias).
  static const String siteUrl =
      intl ? 'https://trialspaid.web.app' : 'https://desafiopago.com.br';

  /// Logos do topo (o internacional usa a arte em inglês).
  static const String logoStatic =
      intl ? 'assets/images/logo_intl.png' : 'assets/images/2.png';
  static const String logoAnim = intl
      ? 'assets/images/logo_anim_intl.gif'
      : 'assets/images/logo_anim_sq_dark.gif';
}
