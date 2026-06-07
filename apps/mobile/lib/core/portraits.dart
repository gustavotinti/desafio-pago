/// Catálogo dos retratos realistas auto-hospedados (mesmos usados pelos
/// usuários virtuais). Servidos do nosso Hosting com CORS liberado.
class PortraitLibrary {
  PortraitLibrary._();

  static const String base = 'https://desafiopago.web.app/portraits';
  static const int perGender = 100;

  static final List<String> men = List<String>.generate(
    perGender,
    (i) => '$base/men/$i.jpg',
  );

  static final List<String> women = List<String>.generate(
    perGender,
    (i) => '$base/women/$i.jpg',
  );
}
