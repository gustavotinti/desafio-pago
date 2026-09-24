import 'package:cloud_functions/cloud_functions.dart';

import '../config/app_config.dart';
import '../i18n/i18n.dart';

/// Erro de negócio vindo de uma Cloud Function, com o `code` preservado.
///
/// Os repositórios convertem `FirebaseFunctionsException` nisto em vez de
/// `Exception(e.message)` — que descartava o código e fazia a tela mostrar
/// "Exception: ..." cru. `toString()` devolve só a mensagem, então telas que
/// ainda fazem `Text(e.toString())` também passam a exibir texto limpo.
class AppException implements Exception {
  const AppException(this.code, this.message);

  /// Código da HttpsError (ex.: 'already-exists', 'failed-precondition').
  final String code;

  /// Mensagem do servidor (em PT-BR na maioria das functions).
  final String message;

  /// Converte a exceção do SDK preservando o código.
  factory AppException.fromFunctions(FirebaseFunctionsException e,
          [String fallback = '']) =>
      AppException(e.code, (e.message == null || e.message!.isEmpty)
          ? fallback
          : e.message!);

  @override
  String toString() => message;
}

// Falhas transitórias: não adianta mostrar a mensagem técnica — só pedir
// para tentar de novo.
const _transient = {
  'unavailable',
  'internal',
  'deadline-exceeded',
  'unknown',
  'resource-exhausted',
  'aborted',
  'cancelled',
};

// No site internacional as mensagens do servidor vêm em PT-BR; mostramos um
// texto genérico traduzido pelo código.
const _codeKey = {
  'already-exists': 'error_already_exists',
  'permission-denied': 'error_not_allowed',
  'failed-precondition': 'error_not_available_now',
  'invalid-argument': 'error_invalid_data',
  'out-of-range': 'error_invalid_data',
  'not-found': 'error_not_found',
};

/// Texto amigável e no idioma certo para exibir ao usuário final.
///
/// [serverLocalized]: a function já devolve a mensagem no idioma do usuário
/// (as de `payments_intl.js`, que recebem `lang`) — então no intl a mensagem
/// específica do servidor é preferível à genérica.
///
/// Telas de admin podem continuar mostrando o erro cru (admin é PT).
String friendlyError(Object e, {bool serverLocalized = false}) {
  String? code;
  String? msg;
  if (e is AppException) {
    code = e.code;
    msg = e.message;
  } else if (e is FirebaseFunctionsException) {
    code = e.code;
    msg = e.message;
  }

  if (code != null) {
    if (_transient.contains(code)) return I18n.tr('error_try_again');
    if (code == 'unauthenticated') return I18n.tr('error_login_again');
    if (AppConfig.intl && !serverLocalized) {
      return I18n.tr(_codeKey[code] ?? 'error_generic');
    }
    if (msg != null && msg.isNotEmpty) return msg;
    return I18n.tr('error_generic');
  }

  final s = e.toString();
  if (s.startsWith('Exception: ')) return s.substring('Exception: '.length);
  return s;
}
