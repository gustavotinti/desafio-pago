import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'lang_storage_stub.dart'
    if (dart.library.js_interop) 'lang_storage_web.dart';

/// i18n leve do app. No build BRASIL o idioma é fixo em 'pt' (nada muda).
/// No build INTERNACIONAL o padrão é inglês, com seletor de bandeiras
/// (🇬🇧 🇪🇸 🇫🇷 🇮🇹 🇩🇪) persistido no navegador.
///
/// Uso: `I18n.tr('vote')` · `I18n.trp('gap_to_lead', {'n': '3'})`.
/// Toda string tem a versão pt idêntica ao texto original do app —
/// o build Brasil continua exatamente igual.
class I18n {
  I18n._();

  /// Idiomas disponíveis no seletor internacional (código → bandeira, nome).
  static const langs = [
    ('en', '🇬🇧', 'English'),
    ('es', '🇪🇸', 'Español'),
    ('fr', '🇫🇷', 'Français'),
    ('it', '🇮🇹', 'Italiano'),
    ('de', '🇩🇪', 'Deutsch'),
  ];

  /// Notifica o app inteiro quando o idioma muda (rebuild via ValueListenable).
  static final ValueNotifier<String> locale =
      ValueNotifier(AppConfig.intl ? (_validSaved() ?? 'en') : 'pt');

  static String? _validSaved() {
    final saved = readSavedLang();
    if (saved == null) return null;
    return langs.any((l) => l.$1 == saved) ? saved : null;
  }

  static void setLocale(String code) {
    if (!AppConfig.intl) return; // Brasil é sempre pt
    locale.value = code;
    writeSavedLang(code);
  }

  // Ordem das colunas nas traduções.
  static const _order = ['pt', 'en', 'es', 'fr', 'it', 'de'];

  static String tr(String key) {
    final row = _t[key];
    if (row == null) return key;
    final i = _order.indexOf(locale.value);
    if (i < 0 || i >= row.length) return row[0];
    return row[i];
  }

  /// tr com parâmetros: substitui {chave} pelos valores do mapa.
  static String trp(String key, Map<String, String> params) {
    var s = tr(key);
    params.forEach((k, v) => s = s.replaceAll('{$k}', v));
    return s;
  }

  /// Texto canônico em PT (coluna pt), independente do idioma da tela —
  /// para valores gravados no backend e lidos pelo admin (ex.: motivo de
  /// denúncia).
  static String pt(String key) => _t[key]?[0] ?? key;

  // ── Traduções: [pt, en, es, fr, it, de] ─────────────────────────────────
  static const Map<String, List<String>> _t = {
    // Abas
    'tab_challenges': [
      'Desafios', 'Challenges', 'Retos', 'Défis', 'Sfide', 'Challenges'],
    'tab_rankings': [
      'Rankings', 'Rankings', 'Rankings', 'Classements', 'Classifiche',
      'Ranglisten'],
    'tab_profile': [
      'Perfil', 'Profile', 'Perfil', 'Profil', 'Profilo', 'Profil'],

    // Genéricos
    'cancel': ['Cancelar', 'Cancel', 'Cancelar', 'Annuler', 'Annulla',
      'Abbrechen'],
    'confirm': ['Confirmar', 'Confirm', 'Confirmar', 'Confirmer', 'Conferma',
      'Bestätigen'],
    'send': ['Enviar', 'Send', 'Enviar', 'Envoyer', 'Invia', 'Senden'],
    'invalid_value': ['Valor inválido', 'Invalid amount', 'Valor no válido',
      'Montant non valide', 'Importo non valido', 'Ungültiger Betrag'],

    // Erros amigáveis (core/utils/friendly_error.dart)
    'error_try_again': [
      'Não foi possível concluir agora. Tente de novo em instantes.',
      'Something went wrong. Please try again in a moment.',
      'No se pudo completar ahora. Inténtalo de nuevo en un momento.',
      "Impossible de terminer maintenant. Réessayez dans un instant.",
      'Impossibile completare ora. Riprova tra un momento.',
      'Das hat gerade nicht geklappt. Bitte gleich noch einmal versuchen.'],
    'error_login_again': [
      'Sua sessão expirou. Entre novamente.',
      'Your session expired. Please sign in again.',
      'Tu sesión expiró. Inicia sesión de nuevo.',
      'Votre session a expiré. Reconnectez-vous.',
      'La sessione è scaduta. Accedi di nuovo.',
      'Deine Sitzung ist abgelaufen. Bitte erneut anmelden.'],
    'error_generic': [
      'Não foi possível concluir a ação.',
      "We couldn't complete that action.",
      'No se pudo completar la acción.',
      "Impossible d'effectuer cette action.",
      "Impossibile completare l'azione.",
      'Die Aktion konnte nicht abgeschlossen werden.'],
    'error_already_exists': [
      'Isso já foi feito.',
      'This was already done.',
      'Esto ya se hizo.',
      'Cela a déjà été fait.',
      'È già stato fatto.',
      'Das wurde bereits erledigt.'],
    'error_not_allowed': [
      'Você não tem permissão para isso.',
      "You're not allowed to do that.",
      'No tienes permiso para hacer esto.',
      "Vous n'êtes pas autorisé à faire cela.",
      'Non hai il permesso di farlo.',
      'Dazu bist du nicht berechtigt.'],
    'error_not_available_now': [
      'Essa ação não está disponível agora.',
      "This action isn't available right now.",
      'Esta acción no está disponible ahora.',
      "Cette action n'est pas disponible pour le moment.",
      'Questa azione non è disponibile ora.',
      'Diese Aktion ist gerade nicht verfügbar.'],
    'error_invalid_data': [
      'Confira os dados informados.',
      'Please check the information you entered.',
      'Revisa los datos ingresados.',
      'Vérifiez les informations saisies.',
      'Controlla i dati inseriti.',
      'Bitte überprüfe deine Angaben.'],
    'error_not_found': [
      'Não encontrado.',
      'Not found.',
      'No encontrado.',
      'Introuvable.',
      'Non trovato.',
      'Nicht gefunden.'],

    // Home / feed
    'create_challenge': ['Criar desafio', 'Create challenge', 'Crear reto',
      'Créer un défi', 'Crea sfida', 'Challenge erstellen'],
    'participate': ['Participar', 'Join', 'Participar', 'Participer',
      'Partecipa', 'Mitmachen'],
    'add_prize_btn': ['+ Prêmio', '+ Prize', '+ Premio', '+ Prix', '+ Premio',
      '+ Preis'],
    'view_entries': ['Ver participações', 'View entries',
      'Ver participaciones', 'Voir les participations', 'Vedi partecipazioni',
      'Beiträge ansehen'],
    'share_challenge': ['Compartilhar desafio', 'Share challenge',
      'Compartir reto', 'Partager le défi', 'Condividi sfida',
      'Challenge teilen'],
    'challenge_link_copied': ['Link do desafio copiado!',
      'Challenge link copied!', '¡Enlace del reto copiado!',
      'Lien du défi copié !', 'Link della sfida copiato!',
      'Challenge-Link kopiert!'],
    'expired': ['Expirado', 'Expired', 'Expirado', 'Expiré', 'Scaduto',
      'Abgelaufen'],
    'expires_d': ['Expira em {d}d {h}h', 'Ends in {d}d {h}h',
      'Termina en {d}d {h}h', 'Se termine dans {d}j {h}h',
      'Termina tra {d}g {h}h', 'Endet in {d}T {h}Std'],
    'expires_h': ['Expira em {h}h {m}min', 'Ends in {h}h {m}min',
      'Termina en {h}h {m}min', 'Se termine dans {h}h {m}min',
      'Termina tra {h}h {m}min', 'Endet in {h}Std {m}Min'],
    'expires_m': ['Expira em {m}min', 'Ends in {m}min', 'Termina en {m}min',
      'Se termine dans {m}min', 'Termina tra {m}min', 'Endet in {m}Min'],
    'winner_defined': ['Vencedor definido • {v}', 'Winner decided • {v}',
      'Ganador definido • {v}', 'Vainqueur désigné • {v}',
      'Vincitore deciso • {v}', 'Gewinner steht fest • {v}'],
    'winners_tie': ['{n} vencedores (empate) • {v}',
      '{n} winners (tie) • {v}', '{n} ganadores (empate) • {v}',
      '{n} vainqueurs (égalité) • {v}', '{n} vincitori (pareggio) • {v}',
      '{n} Gewinner (Gleichstand) • {v}'],
    'no_entries_short': ['Sem participações', 'No entries yet',
      'Sin participaciones', 'Aucune participation', 'Nessuna partecipazione',
      'Keine Beiträge'],
    'feed_empty': ['Nenhum desafio aqui ainda.', 'No challenges here yet.',
      'Aún no hay retos aquí.', 'Pas encore de défi ici.',
      'Ancora nessuna sfida qui.', 'Noch keine Challenges hier.'],
    'high_demand_title': ['Carregando mais desafios',
      'Loading more challenges', 'Cargando más retos',
      'Chargement de nouveaux défis', 'Caricamento di altre sfide',
      'Weitere Challenges werden geladen'],
    'high_demand_msg': [
      'Estamos com alta demanda de usuários agora — o servidor pode levar '
          'um instante para carregar mais.',
      'We are experiencing high user demand right now — the server may take '
          'a moment to load more.',
      'Tenemos alta demanda de usuarios ahora mismo: el servidor puede '
          'tardar un momento en cargar más.',
      'Forte affluence en ce moment — le serveur peut mettre un instant à '
          'charger la suite.',
      'C\'è molta richiesta in questo momento: il server potrebbe impiegare '
          'un attimo a caricare altro.',
      'Gerade sehr hohe Nachfrage — der Server braucht eventuell einen '
          'Moment, um mehr zu laden.'],
    'new_badge': ['NOVO', 'NEW', 'NUEVO', 'NOUVEAU', 'NUOVO', 'NEU'],

    // Pulso "ao vivo"
    'live_now': ['AO VIVO AGORA', 'LIVE NOW', 'EN VIVO AHORA',
      'EN DIRECT', 'IN DIRETTA', 'JETZT LIVE'],
    'stat_active': ['desafios ativos', 'active challenges', 'retos activos',
      'défis actifs', 'sfide attive', 'aktive Challenges'],
    'stat_prizes': ['em prêmios', 'in prizes', 'en premios', 'de prix',
      'in premi', 'an Preisen'],
    'stat_participants': ['participantes', 'participants', 'participantes',
      'participants', 'partecipanti', 'Teilnehmer'],

    // Ticker de vitórias ({who} {amt} {t})
    'win_tpl_0': ['{who} ganhou {amt} · "{t}"', '{who} won {amt} · "{t}"',
      '{who} ganó {amt} · "{t}"', '{who} a gagné {amt} · « {t} »',
      '{who} ha vinto {amt} · "{t}"', '{who} hat {amt} gewonnen · „{t}"'],
    'win_tpl_1': ['{who} levou {amt} no desafio "{t}"',
      '{who} took {amt} in the "{t}" challenge',
      '{who} se llevó {amt} en el reto "{t}"',
      '{who} a remporté {amt} au défi « {t} »',
      '{who} si è preso {amt} nella sfida "{t}"',
      '{who} holte sich {amt} in der Challenge „{t}"'],
    'win_tpl_2': ['{who} faturou {amt} com "{t}" 💰',
      '{who} earned {amt} with "{t}" 💰',
      '{who} facturó {amt} con "{t}" 💰',
      '{who} a empoché {amt} avec « {t} » 💰',
      '{who} ha incassato {amt} con "{t}" 💰',
      '{who} kassierte {amt} mit „{t}" 💰'],
    'win_tpl_3': ['{who} venceu "{t}" e ganhou {amt}',
      '{who} won "{t}" and earned {amt}',
      '{who} venció en "{t}" y ganó {amt}',
      '{who} a gagné « {t} » et remporté {amt}',
      '{who} ha vinto "{t}" guadagnando {amt}',
      '{who} gewann „{t}" und erhielt {amt}'],
    'win_tpl_4': ['{amt} pagos para {who} · "{t}"',
      '{amt} paid to {who} · "{t}"', '{amt} pagados a {who} · "{t}"',
      '{amt} versés à {who} · « {t} »', '{amt} pagati a {who} · "{t}"',
      '{amt} ausgezahlt an {who} · „{t}"'],
    'win_tpl_5': ['{who} acabou de ganhar {amt} em "{t}" 🎉',
      '{who} just won {amt} in "{t}" 🎉',
      '{who} acaba de ganar {amt} en "{t}" 🎉',
      '{who} vient de gagner {amt} dans « {t} » 🎉',
      '{who} ha appena vinto {amt} in "{t}" 🎉',
      '{who} hat gerade {amt} in „{t}" gewonnen 🎉'],
    'win_tpl_6': ['prêmio de {amt} foi para {who} · "{t}"',
      'the {amt} prize went to {who} · "{t}"',
      'el premio de {amt} fue para {who} · "{t}"',
      'le prix de {amt} est allé à {who} · « {t} »',
      'il premio di {amt} è andato a {who} · "{t}"',
      'der Preis von {amt} ging an {who} · „{t}"'],
    'win_tpl_7': ['{who} conquistou {amt} vencendo "{t}" 🏆',
      '{who} claimed {amt} by winning "{t}" 🏆',
      '{who} conquistó {amt} al ganar "{t}" 🏆',
      '{who} a décroché {amt} en gagnant « {t} » 🏆',
      '{who} ha conquistato {amt} vincendo "{t}" 🏆',
      '{who} sicherte sich {amt} mit dem Sieg bei „{t}" 🏆'],

    // Página de participações
    'prize_dispute': ['PRÊMIO EM DISPUTA', 'PRIZE UP FOR GRABS',
      'PREMIO EN JUEGO', 'PRIX EN JEU', 'PREMIO IN PALIO',
      'PREIS ZU GEWINNEN'],
    'prize_closed': ['PRÊMIO • ENCERRADO', 'PRIZE • CLOSED',
      'PREMIO • CERRADO', 'PRIX • TERMINÉ', 'PREMIO • CHIUSO',
      'PREIS • BEENDET'],
    'participations_n': ['{n} participações', '{n} entries',
      '{n} participaciones', '{n} participations', '{n} partecipazioni',
      '{n} Beiträge'],
    'vote_this': ['Votar nesta participação', 'Vote for this entry',
      'Votar por esta participación', 'Voter pour cette participation',
      'Vota questa partecipazione', 'Für diesen Beitrag stimmen'],
    'already_voted': ['Você já votou neste desafio ✓',
      'You already voted in this challenge ✓',
      'Ya votaste en este reto ✓', 'Vous avez déjà voté ✓',
      'Hai già votato in questa sfida ✓',
      'Du hast bereits abgestimmt ✓'],
    'vote': ['Votar', 'Vote', 'Votar', 'Voter', 'Vota', 'Abstimmen'],
    'vote_registered': ['Voto registrado!', 'Vote counted!',
      '¡Voto registrado!', 'Vote enregistré !', 'Voto registrato!',
      'Stimme gezählt!'],
    'votes_n': ['{n} voto{s}', '{n} vote{s}', '{n} voto{s}', '{n} vote{s}',
      '{n} voto/i', '{n} Stimme{s2}'],
    'comments': ['Comentários', 'Comments', 'Comentarios', 'Commentaires',
      'Commenti', 'Kommentare'],
    'challenge_comments': ['Comentários do desafio', 'Challenge comments',
      'Comentarios del reto', 'Commentaires du défi', 'Commenti della sfida',
      'Kommentare zur Challenge'],
    'like_login': ['Entre para curtir', 'Sign in to like',
      'Inicia sesión para dar me gusta', 'Connectez-vous pour aimer',
      'Accedi per mettere mi piace', 'Zum Liken anmelden'],
    'user_fallback': ['Usuário', 'User', 'Usuario', 'Utilisateur', 'Utente',
      'Nutzer'],
    'replying_to': ['Respondendo a {name}', 'Replying to {name}',
      'Respondiendo a {name}', 'Réponse à {name}', 'Rispondendo a {name}',
      'Antwort an {name}'],
    'write_reply': ['Escreva sua resposta...', 'Write your reply...',
      'Escribe tu respuesta...', 'Écrivez votre réponse...',
      'Scrivi la tua risposta...', 'Schreibe deine Antwort...'],
    'reply': ['Responder', 'Reply', 'Responder', 'Répondre', 'Rispondi',
      'Antworten'],
    // Rankings
    'rank_top_earnings': ['Maiores ganhos', 'Top earners', 'Más ganancias',
      'Meilleurs gains', 'Maggiori guadagni', 'Top-Verdiener'],
    'rank_most_voted': ['Mais votados', 'Most voted', 'Más votados',
      'Les plus votés', 'Più votati', 'Meistgewählt'],
    'no_data': ['Nenhum dado ainda', 'No data yet', 'Aún no hay datos',
      'Pas encore de données', 'Ancora nessun dato', 'Noch keine Daten'],
    'votes_suffix': ['{n} votos', '{n} votes', '{n} votos', '{n} votes',
      '{n} voti', '{n} Stimmen'],
    'your_position': ['Sua posição…', 'Your position…', 'Tu posición…',
      'Votre position…', 'La tua posizione…', 'Deine Position…'],
    'you_are_at': ['Você está em {rank}º', 'You are #{rank}',
      'Estás en el puesto {rank}', 'Vous êtes {rank}e', 'Sei {rank}º',
      'Du bist auf Platz {rank}'],
    'in_earnings': ['em ganhos · {v}', 'in earnings · {v}',
      'en ganancias · {v}', 'en gains · {v}', 'in guadagni · {v}',
      'an Einnahmen · {v}'],
    'in_votes': ['em votos · {v}', 'in votes · {v}', 'en votos · {v}',
      'en votes · {v}', 'in voti · {v}', 'an Stimmen · {v}'],

    'ago_now': ['agora', 'now', 'ahora', 'à l\'instant', 'adesso', 'jetzt'],
    'ago_min': ['{n}min atrás', '{n}m ago', 'hace {n}min', 'il y a {n} min',
      '{n} min fa', 'vor {n} Min'],
    'ago_hour': ['{n}h atrás', '{n}h ago', 'hace {n}h', 'il y a {n} h',
      '{n} h fa', 'vor {n} Std'],
    'ago_day': ['{n}d atrás', '{n}d ago', 'hace {n}d', 'il y a {n} j',
      '{n} g fa', 'vor {n} T'],
    'no_comments': ['Nenhum comentário ainda.', 'No comments yet.',
      'Aún no hay comentarios.', 'Pas encore de commentaires.',
      'Ancora nessun commento.', 'Noch keine Kommentare.'],
    'add_comment': ['Adicionar comentário...', 'Add a comment...',
      'Añadir un comentario...', 'Ajouter un commentaire...',
      'Aggiungi un commento...', 'Kommentar hinzufügen...'],
    'no_entries_yet': ['Nenhuma participação ainda', 'No entries yet',
      'Aún no hay participaciones', 'Pas encore de participation',
      'Ancora nessuna partecipazione', 'Noch keine Beiträge'],
    'vote_login': ['Entre para votar', 'Sign in to vote',
      'Inicia sesión para votar', 'Connectez-vous pour voter',
      'Accedi per votare', 'Zum Abstimmen anmelden'],
    'participate_login': ['Entre para participar do desafio',
      'Sign in to join the challenge', 'Inicia sesión para participar',
      'Connectez-vous pour participer', 'Accedi per partecipare',
      'Zum Mitmachen anmelden'],
    'share_ask': ['Vote em {who} no {brand}! 🗳️🏆\n{url}',
      'Vote for {who} on {brand}! 🗳️🏆\n{url}',
      '¡Vota por {who} en {brand}! 🗳️🏆\n{url}',
      'Votez pour {who} sur {brand} ! 🗳️🏆\n{url}',
      'Vota per {who} su {brand}! 🗳️🏆\n{url}',
      'Stimme für {who} auf {brand}! 🗳️🏆\n{url}'],
    'share_subject': ['Peça votos no Desafio Pago', 'Ask for votes',
      'Pide votos', 'Demandez des votes', 'Chiedi voti',
      'Bitte um Stimmen'],
    'link_copied_share': ['Link copiado! Cole no WhatsApp 📲',
      'Link copied! Paste it anywhere 📲',
      '¡Enlace copiado! Pégalo donde quieras 📲',
      'Lien copié ! Collez-le où vous voulez 📲',
      'Link copiato! Incollalo dove vuoi 📲',
      'Link kopiert! Überall einfügen 📲'],
    'leading': ['Você está liderando! 🏆', 'You are in the lead! 🏆',
      '¡Vas ganando! 🏆', 'Vous êtes en tête ! 🏆',
      'Sei in testa! 🏆', 'Du führst! 🏆'],
    'my_position': ['Você está em {rank}º de {total}',
      'You are #{rank} of {total}', 'Estás en el puesto {rank} de {total}',
      'Vous êtes {rank}e sur {total}', 'Sei {rank}º su {total}',
      'Du bist Platz {rank} von {total}'],
    'keep_lead': ['Continue divulgando pra manter a ponta.',
      'Keep sharing to stay on top.', 'Sigue compartiendo para mantenerte.',
      'Continuez à partager pour rester en tête.',
      'Continua a condividere per restare in testa.',
      'Teile weiter, um vorn zu bleiben.'],
    'gap_to_lead': ['Faltam {n} voto{s} pra liderar. Chame a galera!',
      '{n} vote{s} to take the lead. Rally your people!',
      'Te faltan {n} voto{s} para liderar. ¡Llama a tu gente!',
      'Il vous manque {n} vote{s} pour être en tête. Mobilisez vos amis !',
      'Ti mancano {n} voti per la vetta. Chiama i tuoi!',
      'Noch {n} Stimme{s2} bis zur Spitze. Trommle deine Leute zusammen!'],
    'promote': ['Divulgar', 'Share', 'Difundir', 'Partager', 'Condividi',
      'Teilen'],

    // Envio de participação
    'your_entry': ['Sua participação', 'Your entry', 'Tu participación',
      'Votre participation', 'La tua partecipazione', 'Dein Beitrag'],
    'choose_image': ['Escolher imagem', 'Choose image', 'Elegir imagen',
      'Choisir une image', 'Scegli immagine', 'Bild auswählen'],
    'change_image': ['Trocar imagem', 'Change image', 'Cambiar imagen',
      'Changer l\'image', 'Cambia immagine', 'Bild ändern'],
    'send_entry': ['Enviar participação', 'Submit entry',
      'Enviar participación', 'Envoyer la participation',
      'Invia partecipazione', 'Beitrag einreichen'],
    'entry_sent': ['Participação enviada!', 'Entry submitted!',
      '¡Participación enviada!', 'Participation envoyée !',
      'Partecipazione inviata!', 'Beitrag eingereicht!'],
    'select_file': ['Selecione um arquivo', 'Select a file',
      'Selecciona un archivo', 'Sélectionnez un fichier',
      'Seleziona un file', 'Datei auswählen'],
    'img_rule_title': ['Envie uma imagem — proporções aceitas:',
      'Upload an image — accepted ratios:',
      'Sube una imagen — proporciones aceptadas:',
      'Envoyez une image — formats acceptés :',
      'Carica un\'immagine — formati accettati:',
      'Lade ein Bild hoch — erlaubte Formate:'],
    'img_rule_size': ['Tamanho máximo: 10 MB', 'Max size: 10 MB',
      'Tamaño máximo: 10 MB', 'Taille max : 10 Mo', 'Dimensione max: 10 MB',
      'Max. Größe: 10 MB'],
    'img_rule_crop': ['Você recorta a imagem aqui no app — é só escolher.',
      'You crop the image right here in the app — just pick one.',
      'Recortas la imagen aquí mismo en la app: solo elige una.',
      'Vous recadrez l\'image directement dans l\'app.',
      'Ritagli l\'immagine direttamente nell\'app.',
      'Du schneidest das Bild direkt in der App zu.'],

    // Perfil / dinheiro
    'followers': ['Seguidores', 'Followers', 'Seguidores', 'Abonnés',
      'Follower', 'Follower'],
    'following': ['Seguindo', 'Following', 'Siguiendo', 'Abonnements',
      'Seguiti', 'Folgt'],
    'votes_label': ['Votos', 'Votes', 'Votos', 'Votes', 'Voti', 'Stimmen'],
    'earnings': ['Ganhos', 'Earnings', 'Ganancias', 'Gains', 'Guadagni',
      'Einnahmen'],
    'my_activity': ['Minha atividade', 'My activity', 'Mi actividad',
      'Mon activité', 'La mia attività', 'Meine Aktivität'],
    'my_activity_sub': ['Meus desafios e participações',
      'My challenges and entries', 'Mis retos y participaciones',
      'Mes défis et participations', 'Le mie sfide e partecipazioni',
      'Meine Challenges und Beiträge'],
    'credits_available': ['CRÉDITOS DISPONÍVEIS', 'AVAILABLE CREDITS',
      'CRÉDITOS DISPONIBLES', 'CRÉDITS DISPONIBLES', 'CREDITI DISPONIBILI',
      'VERFÜGBARES GUTHABEN'],
    'in_challenges': ['Em desafios', 'In challenges', 'En retos',
      'Dans des défis', 'In sfide', 'In Challenges'],
    'awaiting_withdraw': ['Aguard. saque', 'Pending payout', 'Retiro pend.',
      'Retrait en att.', 'Prelievo in att.', 'Auszahlung läuft'],
    'add_credits': ['Adicionar créditos', 'Add credits', 'Añadir créditos',
      'Ajouter des crédits', 'Aggiungi crediti', 'Guthaben aufladen'],
    'history': ['Histórico', 'History', 'Historial', 'Historique',
      'Cronologia', 'Verlauf'],
    'no_transactions': ['Nenhuma transação ainda', 'No transactions yet',
      'Aún no hay transacciones', 'Pas encore de transactions',
      'Ancora nessuna transazione', 'Noch keine Transaktionen'],
    'logout': ['Sair', 'Sign out', 'Salir', 'Déconnexion', 'Esci',
      'Abmelden'],
    'edit_profile': ['Editar perfil', 'Edit profile', 'Editar perfil',
      'Modifier le profil', 'Modifica profilo', 'Profil bearbeiten'],

    // Internacional: PayPal + XRP
    'xrp_balance_note': ['≈ {xrp} XRP', '≈ {xrp} XRP', '≈ {xrp} XRP',
      '≈ {xrp} XRP', '≈ {xrp} XRP', '≈ {xrp} XRP'],
    'deposit_paypal_title': ['Adicionar créditos (PayPal)',
      'Add credits (PayPal)', 'Añadir créditos (PayPal)',
      'Ajouter des crédits (PayPal)', 'Aggiungi crediti (PayPal)',
      'Guthaben aufladen (PayPal)'],
    'deposit_amount_usd': ['Valor (USD)', 'Amount (USD)', 'Importe (USD)',
      'Montant (USD)', 'Importo (USD)', 'Betrag (USD)'],
    'deposit_paypal_note': [
      'Pague com PayPal. Os créditos entram na sua conta assim que o '
          'pagamento for aprovado.',
      'Pay with PayPal. Credits are added to your account as soon as the '
          'payment is approved.',
      'Paga con PayPal. Los créditos se añaden en cuanto se aprueba el pago.',
      'Payez avec PayPal. Les crédits sont ajoutés dès que le paiement est '
          'approuvé.',
      'Paga con PayPal. I crediti vengono aggiunti appena il pagamento è '
          'approvato.',
      'Zahle mit PayPal. Das Guthaben wird gutgeschrieben, sobald die '
          'Zahlung bestätigt ist.'],
    'pay_with_paypal': ['Pagar com PayPal', 'Pay with PayPal',
      'Pagar con PayPal', 'Payer avec PayPal', 'Paga con PayPal',
      'Mit PayPal zahlen'],
    'paypal_opened': [
      'Abrimos o PayPal em outra aba. Depois de aprovar, volte aqui e toque '
          'em "Já paguei".',
      'PayPal opened in a new tab. After approving, come back and tap '
          '"I have paid".',
      'PayPal se abrió en otra pestaña. Tras aprobar, vuelve y toca '
          '"Ya pagué".',
      'PayPal s\'est ouvert dans un autre onglet. Après approbation, '
          'revenez et touchez « J\'ai payé ».',
      'PayPal si è aperto in un\'altra scheda. Dopo l\'approvazione torna '
          'qui e tocca "Ho pagato".',
      'PayPal wurde in einem neuen Tab geöffnet. Nach der Freigabe komm '
          'zurück und tippe auf „Ich habe bezahlt".'],
    'i_have_paid': ['Já paguei — confirmar', 'I have paid — confirm',
      'Ya pagué — confirmar', 'J\'ai payé — confirmer',
      'Ho pagato — conferma', 'Ich habe bezahlt — bestätigen'],
    'deposit_success': ['Pagamento confirmado! Créditos adicionados ✅',
      'Payment confirmed! Credits added ✅',
      '¡Pago confirmado! Créditos añadidos ✅',
      'Paiement confirmé ! Crédits ajoutés ✅',
      'Pagamento confermato! Crediti aggiunti ✅',
      'Zahlung bestätigt! Guthaben hinzugefügt ✅'],
    'deposit_not_completed': [
      'Pagamento ainda não confirmado no PayPal. Aprove na outra aba e '
          'tente de novo.',
      'Payment not confirmed by PayPal yet. Approve it in the other tab '
          'and try again.',
      'El pago aún no está confirmado en PayPal. Apruébalo y vuelve a '
          'intentar.',
      'Paiement pas encore confirmé par PayPal. Approuvez-le puis '
          'réessayez.',
      'Pagamento non ancora confermato da PayPal. Approvalo e riprova.',
      'Zahlung von PayPal noch nicht bestätigt. Bitte freigeben und erneut '
          'versuchen.'],
    'withdraw_crypto_title': ['Saque em cripto (XRP)',
      'Crypto payout (XRP)', 'Retiro en cripto (XRP)',
      'Retrait en crypto (XRP)', 'Prelievo in cripto (XRP)',
      'Krypto-Auszahlung (XRP)'],
    'withdraw_amount_usd': ['Valor do saque (USD)', 'Payout amount (USD)',
      'Importe del retiro (USD)', 'Montant du retrait (USD)',
      'Importo del prelievo (USD)', 'Auszahlungsbetrag (USD)'],
    'xrp_address': ['Endereço da carteira XRP', 'XRP wallet address',
      'Dirección de billetera XRP', 'Adresse du portefeuille XRP',
      'Indirizzo del wallet XRP', 'XRP-Wallet-Adresse'],
    'xrp_tag': ['Destination tag (se necessário)',
      'Destination tag (if required)', 'Destination tag (si es necesario)',
      'Destination tag (si nécessaire)', 'Destination tag (se richiesto)',
      'Destination Tag (falls nötig)'],
    'request_withdraw': ['Solicitar saque', 'Request payout',
      'Solicitar retiro', 'Demander le retrait', 'Richiedi prelievo',
      'Auszahlung anfordern'],
    'withdraw_requested_xrp': [
      'Saque solicitado — você receberá ≈ {xrp} XRP no endereço informado.',
      'Payout requested — you will receive ≈ {xrp} XRP at your address.',
      'Retiro solicitado: recibirás ≈ {xrp} XRP en tu dirección.',
      'Retrait demandé — vous recevrez ≈ {xrp} XRP à votre adresse.',
      'Prelievo richiesto: riceverai ≈ {xrp} XRP al tuo indirizzo.',
      'Auszahlung angefordert — du erhältst ≈ {xrp} XRP an deine Adresse.'],
    'xrp_address_required': ['Informe o endereço XRP',
      'Enter your XRP address', 'Introduce tu dirección XRP',
      'Saisissez votre adresse XRP', 'Inserisci il tuo indirizzo XRP',
      'Gib deine XRP-Adresse ein'],
    'created_by': ['Criado por', 'Created by', 'Creado por', 'Créé par',
      'Creato da', 'Erstellt von'],

    // Onboarding / termos (1º login)
    'welcome': ['Boas-vindas', 'Welcome', 'Bienvenido', 'Bienvenue',
      'Benvenuto', 'Willkommen'],
    'onboarding_sub': [
      'Falta pouco! Confirme seu telefone e aceite nossas políticas para '
          'começar.',
      'Almost there! Confirm your phone and accept our policies to get '
          'started.',
      '¡Casi listo! Confirma tu teléfono y acepta nuestras políticas para '
          'empezar.',
      'Presque fini ! Confirmez votre téléphone et acceptez nos politiques '
          'pour commencer.',
      'Ci siamo quasi! Conferma il telefono e accetta le policy per '
          'iniziare.',
      'Fast geschafft! Bestätige deine Telefonnummer und akzeptiere unsere '
          'Richtlinien.'],
    'phone_label': ['Telefone (com DDD)', 'Phone number', 'Número de teléfono',
      'Numéro de téléphone', 'Numero di telefono', 'Telefonnummer'],
    'phone_invalid': [
      'Informe um telefone válido (com DDD)',
      'Enter a valid phone number', 'Introduce un teléfono válido',
      'Entrez un numéro de téléphone valide',
      'Inserisci un numero valido', 'Gib eine gültige Nummer ein'],
    'must_accept': ['Você precisa aceitar as políticas',
      'You must accept the policies', 'Debes aceptar las políticas',
      'Vous devez accepter les politiques', 'Devi accettare le policy',
      'Du musst die Richtlinien akzeptieren'],
    'terms_title': ['Termos de Uso e Política de Privacidade',
      'Terms of Use and Privacy Policy', 'Términos de Uso y Privacidad',
      'Conditions d\'utilisation et confidentialité',
      'Termini d\'uso e Privacy', 'Nutzungsbedingungen und Datenschutz'],
    'accept_checkbox': [
      'Li e aceito os Termos de Uso e a Política de Privacidade, incluindo o '
          'uso dos meus dados para campanhas.',
      'I have read and accept the Terms of Use and Privacy Policy, including '
          'the use of my data for marketing.',
      'He leído y acepto los Términos y la Política de Privacidad, incluido '
          'el uso de mis datos para campañas.',
      'J\'ai lu et j\'accepte les Conditions et la Politique de '
          'confidentialité, y compris l\'usage de mes données marketing.',
      'Ho letto e accetto i Termini e la Privacy, incluso l\'uso dei miei '
          'dati per il marketing.',
      'Ich habe die Bedingungen und die Datenschutzerklärung gelesen und '
          'akzeptiere sie, inkl. Nutzung meiner Daten für Marketing.'],
    'finish_signup': ['Concluir cadastro', 'Finish sign-up',
      'Completar registro', 'Terminer l\'inscription', 'Completa iscrizione',
      'Registrierung abschließen'],
    'terms_updated': ['Última atualização: julho de 2026',
      'Last updated: July 2026', 'Última actualización: julio de 2026',
      'Dernière mise à jour : juillet 2026',
      'Ultimo aggiornamento: luglio 2026',
      'Zuletzt aktualisiert: Juli 2026'],
    'terms_error': ['Erro', 'Error', 'Error', 'Erreur', 'Errore', 'Fehler'],

    // Criar desafio
    'create_title': ['Criar Desafio', 'Create challenge', 'Crear reto',
      'Créer un défi', 'Crea sfida', 'Challenge erstellen'],
    'title_label': ['Título', 'Title', 'Título', 'Titre', 'Titolo', 'Titel'],
    'title_required': ['Título obrigatório', 'Title is required',
      'Título obligatorio', 'Titre obligatoire', 'Titolo obbligatorio',
      'Titel erforderlich'],
    'desc_label': ['Descrição', 'Description', 'Descripción', 'Description',
      'Descrizione', 'Beschreibung'],
    'desc_required': ['Descrição obrigatória', 'Description is required',
      'Descripción obligatoria', 'Description obligatoire',
      'Descrizione obbligatoria', 'Beschreibung erforderlich'],
    'prize_label': ['Valor do prêmio', 'Prize amount (USD)',
      'Importe del premio (USD)', 'Montant du prix (USD)',
      'Importo del premio (USD)', 'Preisbetrag (USD)'],
    'prize_invalid': ['Informe um valor válido', 'Enter a valid amount',
      'Introduce un importe válido', 'Entrez un montant valide',
      'Inserisci un importo valido', 'Gib einen gültigen Betrag ein'],
    'duration_label': ['Duração (dias, 1–30)', 'Duration (days, 1–30)',
      'Duración (días, 1–30)', 'Durée (jours, 1–30)', 'Durata (giorni, 1–30)',
      'Dauer (Tage, 1–30)'],
    'min_1_day': ['Mínimo 1 dia', 'Minimum 1 day', 'Mínimo 1 día',
      'Minimum 1 jour', 'Minimo 1 giorno', 'Mindestens 1 Tag'],
    'max_30_days': ['Máximo 30 dias', 'Maximum 30 days', 'Máximo 30 días',
      'Maximum 30 jours', 'Massimo 30 giorni', 'Maximal 30 Tage'],
    'insufficient_title': ['Créditos insuficientes', 'Insufficient credits',
      'Créditos insuficientes', 'Crédits insuffisants', 'Crediti insufficienti',
      'Nicht genug Guthaben'],
    'need_amount': ['Para criar este desafio você precisa de {v}.',
      'To create this challenge you need {v}.',
      'Para crear este reto necesitas {v}.',
      'Pour créer ce défi il vous faut {v}.',
      'Per creare questa sfida ti servono {v}.',
      'Um diese Challenge zu erstellen, brauchst du {v}.'],
    'your_balance': ['Seu saldo: {v}', 'Your balance: {v}', 'Tu saldo: {v}',
      'Votre solde : {v}', 'Il tuo saldo: {v}', 'Dein Guthaben: {v}'],
    'missing_amount': ['Faltam {v}', '{v} short', 'Faltan {v}',
      'Il manque {v}', 'Mancano {v}', 'Es fehlen {v}'],
    'add_credits_hint': [
      'Adicione créditos via Pix e volte para criar o desafio.',
      'Add credits via PayPal and come back to create the challenge.',
      'Añade créditos con PayPal y vuelve para crear el reto.',
      'Ajoutez des crédits via PayPal puis revenez créer le défi.',
      'Aggiungi crediti con PayPal e torna a creare la sfida.',
      'Lade Guthaben über PayPal auf und komm zurück.'],
    'add_via': ['Adicionar via Pix', 'Add via PayPal', 'Añadir con PayPal',
      'Ajouter via PayPal', 'Aggiungi con PayPal', 'Über PayPal aufladen'],
    'balance_updated': [
      'Saldo atualizado — toque em "Criar Desafio" novamente.',
      'Balance updated — tap "Create challenge" again.',
      'Saldo actualizado: toca "Crear reto" de nuevo.',
      'Solde mis à jour — touchez « Créer un défi » à nouveau.',
      'Saldo aggiornato: tocca di nuovo "Crea sfida".',
      'Guthaben aktualisiert — tippe erneut auf „Challenge erstellen".'],
    'balance_label': ['Saldo: {v}', 'Balance: {v}', 'Saldo: {v}',
      'Solde : {v}', 'Saldo: {v}', 'Guthaben: {v}'],
    'add_short': ['Adicionar', 'Add', 'Añadir', 'Ajouter', 'Aggiungi',
      'Aufladen'],
    'refresh_balance': ['Atualizar saldo', 'Refresh balance',
      'Actualizar saldo', 'Actualiser le solde', 'Aggiorna saldo',
      'Guthaben aktualisieren'],
    'insufficient_hint': [
      'Saldo insuficiente — você adicionará {v} via Pix',
      'Insufficient balance — you\'ll add {v} via PayPal',
      'Saldo insuficiente: añadirás {v} con PayPal',
      'Solde insuffisant — vous ajouterez {v} via PayPal',
      'Saldo insufficiente: aggiungerai {v} con PayPal',
      'Guthaben reicht nicht — du lädst {v} über PayPal auf'],
    // Sugestão de região (banner que leva ao site certo)
    'region_to_intl': [
      'Prefer English? Visit TrialsPaid — the international version.',
      'Prefer English? Visit TrialsPaid — the international version.',
      '¿Prefieres inglés? Visita TrialsPaid — la versión internacional.',
      'Vous préférez l\'anglais ? Découvrez TrialsPaid.',
      'Preferisci l\'inglese? Visita TrialsPaid.',
      'Lieber Englisch? Besuche TrialsPaid.'],
    // Só aparece para visitante com navegador em português → sempre em PT.
    'region_to_br': [
      'É do Brasil? Vá para o Desafio Pago — em português, com Pix.',
      'É do Brasil? Vá para o Desafio Pago — em português, com Pix.',
      'É do Brasil? Vá para o Desafio Pago — em português, com Pix.',
      'É do Brasil? Vá para o Desafio Pago — em português, com Pix.',
      'É do Brasil? Vá para o Desafio Pago — em português, com Pix.',
      'É do Brasil? Vá para o Desafio Pago — em português, com Pix.'],
    'region_go': ['Ir', 'Go', 'Ir', 'Aller', 'Vai', 'Los'],

    'news': ['Novidades', 'News', 'Novedades', 'Actualités', 'Novità',
      'Neuigkeiten'],
    'news_sub': ['Dicas para ganhar desafios e renda extra',
      'Tips to win challenges and earn extra income',
      'Consejos para ganar retos e ingresos extra',
      'Astuces pour gagner des défis et un revenu',
      'Consigli per vincere sfide e guadagnare',
      'Tipps zum Gewinnen und Extra-Einkommen'],
    'change_language': ['Idioma', 'Language', 'Idioma', 'Langue', 'Lingua',
      'Sprache'],

    // Perfil de visitante (sem login)
    'guest_title': ['Crie sua conta grátis', 'Create your free account',
      'Crea tu cuenta gratis', 'Créez votre compte gratuit',
      'Crea il tuo account gratis', 'Erstelle dein kostenloses Konto'],
    'guest_sub': [
      'Entre com o Google para participar dos desafios e acompanhar seus '
          'ganhos.',
      'Sign in with Google to join challenges and track your winnings.',
      'Inicia sesión con Google para participar en retos y seguir tus '
          'ganancias.',
      'Connectez-vous avec Google pour participer aux défis et suivre vos '
          'gains.',
      'Accedi con Google per partecipare alle sfide e seguire i tuoi '
          'guadagni.',
      'Melde dich mit Google an, um an Challenges teilzunehmen und deine '
          'Gewinne zu verfolgen.'],
    'guest_b1_title': ['Ganhe prêmios em dinheiro', 'Win cash prizes',
      'Gana premios en efectivo', 'Gagnez des prix en argent',
      'Vinci premi in denaro', 'Gewinne Geldpreise'],
    'guest_b1_sub': ['Participe e vença desafios pagos',
      'Join and win paid challenges', 'Participa y gana retos pagados',
      'Participez et gagnez des défis payants',
      'Partecipa e vinci sfide a premi',
      'Nimm teil und gewinne bezahlte Challenges'],
    'guest_b2_title': ['Vote nos melhores', 'Vote for the best',
      'Vota por los mejores', 'Votez pour les meilleurs',
      'Vota i migliori', 'Stimme für die Besten'],
    'guest_b2_sub': ['Ajude a escolher quem leva o prêmio',
      'Help decide who takes the prize', 'Ayuda a decidir quién gana',
      'Aidez à choisir le gagnant', 'Aiuta a decidere chi vince',
      'Hilf zu entscheiden, wer gewinnt'],
    'guest_b3_title': ['Crie seus desafios', 'Create your own challenges',
      'Crea tus retos', 'Créez vos défis', 'Crea le tue sfide',
      'Erstelle eigene Challenges'],
    'guest_b3_sub': ['Lance um prêmio e desafie a galera',
      'Put up a prize and challenge everyone',
      'Pon un premio y desafía a todos',
      'Mettez un prix en jeu et défiez tout le monde',
      'Metti in palio un premio e sfida tutti',
      'Setze einen Preis aus und fordere alle heraus'],
    'guest_b4_title': ['Saque via Pix', 'Withdraw in crypto (XRP)',
      'Retira en cripto (XRP)', 'Retrait en crypto (XRP)',
      'Preleva in cripto (XRP)', 'Auszahlung in Krypto (XRP)'],
    'guest_b4_sub': ['Receba seus ganhos quando quiser',
      'Receive your winnings anytime', 'Recibe tus ganancias cuando quieras',
      'Recevez vos gains quand vous voulez',
      'Ricevi i tuoi guadagni quando vuoi',
      'Erhalte deine Gewinne jederzeit'],
    'guest_footer': ['Apenas para usuários no Brasil · +18 anos',
      '18+ only', 'Solo mayores de 18 años', 'Réservé aux 18 ans et plus',
      'Solo maggiorenni (18+)', 'Nur ab 18 Jahren'],

    'crypto_note': [
      'O valor é convertido para XRP na hora do envio. Cotação: mercado.',
      'The amount is converted to XRP at payout time, at market rate.',
      'El importe se convierte a XRP al momento del envío, a precio de '
          'mercado.',
      'Le montant est converti en XRP au moment de l\'envoi, au cours du '
          'marché.',
      'L\'importo viene convertito in XRP al momento dell\'invio, al '
          'prezzo di mercato.',
      'Der Betrag wird bei der Auszahlung zum Marktkurs in XRP '
          'umgerechnet.'],

    // ── Frente G4: login, recorte, denúncia, exclusão de conta, PayPal ─────
    // (coluna pt = texto original do app — o build BR não muda)
    // Folha de login (auth_guard.dart)
    'sign_in_google': ['Entrar com Google', 'Sign in with Google',
      'Iniciar sesión con Google', 'Se connecter avec Google',
      'Accedi con Google', 'Mit Google anmelden'],
    'login_default': ['Entre para participar', 'Sign in to join',
      'Inicia sesión para participar', 'Connectez-vous pour participer',
      'Accedi per partecipare', 'Zum Mitmachen anmelden'],
    'login_sheet_sub': [
      'Crie sua conta com o Google para participar dos desafios, votar, '
          'comentar e acessar seu perfil.',
      'Create your account with Google to join challenges, vote, comment '
          'and access your profile.',
      'Crea tu cuenta con Google para participar en retos, votar, comentar '
          'y acceder a tu perfil.',
      'Créez votre compte avec Google pour participer aux défis, voter, '
          'commenter et accéder à votre profil.',
      'Crea il tuo account con Google per partecipare alle sfide, votare, '
          'commentare e accedere al tuo profilo.',
      'Erstelle dein Konto mit Google, um an Challenges teilzunehmen, '
          'abzustimmen, zu kommentieren und dein Profil zu nutzen.'],
    'login_error': ['Erro ao entrar: {e}', 'Sign-in error: {e}',
      'Error al iniciar sesión: {e}', 'Erreur de connexion : {e}',
      'Errore di accesso: {e}', 'Anmeldefehler: {e}'],

    // Editor de recorte (core/widgets/image_crop_page.dart)
    'crop_title': ['Recortar imagem', 'Crop image', 'Recortar imagen',
      'Recadrer l\'image', 'Ritaglia immagine', 'Bild zuschneiden'],
    'crop_failed': ['Não foi possível recortar. Tente outra imagem.',
      'Could not crop. Try another image.',
      'No se pudo recortar. Prueba con otra imagen.',
      'Recadrage impossible. Essayez une autre image.',
      'Impossibile ritagliare. Prova un\'altra immagine.',
      'Zuschneiden fehlgeschlagen. Versuche ein anderes Bild.'],
    'crop_hint_ratio': ['Arraste para enquadrar · escolha a proporção',
      'Drag to frame · choose the ratio',
      'Arrastra para encuadrar · elige la proporción',
      'Faites glisser pour cadrer · choisissez le format',
      'Trascina per inquadrare · scegli il formato',
      'Zum Ausrichten ziehen · Format wählen'],
    'crop_hint': ['Arraste para enquadrar', 'Drag to frame',
      'Arrastra para encuadrar', 'Faites glisser pour cadrer',
      'Trascina per inquadrare', 'Zum Ausrichten ziehen'],
    'cropping': ['Recortando...', 'Cropping...', 'Recortando...',
      'Recadrage...', 'Ritaglio...', 'Wird zugeschnitten...'],
    'crop_use': ['Cortar e usar', 'Crop and use', 'Recortar y usar',
      'Recadrer et utiliser', 'Ritaglia e usa', 'Zuschneiden und verwenden'],

    // Denúncia (challenge_entries_page.dart). O backend recebe SEMPRE a
    // coluna pt (I18n.pt) — o painel de denúncias do admin é PT.
    'report_reason_title': ['Motivo da denúncia', 'Reason for report',
      'Motivo de la denuncia', 'Motif du signalement',
      'Motivo della segnalazione', 'Grund der Meldung'],
    'report_offensive': ['Conteúdo ofensivo ou inadequado',
      'Offensive or inappropriate content',
      'Contenido ofensivo o inapropiado', 'Contenu offensant ou inapproprié',
      'Contenuto offensivo o inappropriato',
      'Beleidigender oder unangemessener Inhalt'],
    'report_spam': ['Spam ou propaganda', 'Spam or advertising',
      'Spam o publicidad', 'Spam ou publicité', 'Spam o pubblicità',
      'Spam oder Werbung'],
    'report_violence': ['Violência ou automutilação', 'Violence or self-harm',
      'Violencia o autolesión', 'Violence ou automutilation',
      'Violenza o autolesionismo', 'Gewalt oder Selbstverletzung'],
    'report_harassment': ['Assédio ou bullying', 'Harassment or bullying',
      'Acoso o bullying', 'Harcèlement ou intimidation',
      'Molestie o bullismo', 'Belästigung oder Mobbing'],
    'report_other': ['Outro', 'Other', 'Otro', 'Autre', 'Altro', 'Sonstiges'],
    'report_sent': ['Denúncia enviada. Obrigado!', 'Report sent. Thank you!',
      'Denuncia enviada. ¡Gracias!', 'Signalement envoyé. Merci !',
      'Segnalazione inviata. Grazie!', 'Meldung gesendet. Danke!'],
    'report': ['Denunciar', 'Report', 'Denunciar', 'Signaler', 'Segnala',
      'Melden'],
    'share_ask_votes': ['Compartilhar e pedir votos', 'Share and ask for votes',
      'Compartir y pedir votos', 'Partager et demander des votes',
      'Condividi e chiedi voti', 'Teilen und um Stimmen bitten'],

    // Exclusão de conta (profile_page.dart)
    'delete_account_title': ['Excluir conta', 'Delete account',
      'Eliminar cuenta', 'Supprimer le compte', 'Elimina account',
      'Konto löschen'],
    'delete_account_warning': [
      'Esta ação é permanente e não pode ser desfeita.\n\n'
          'Seus dados pessoais serão removidos. '
          'Suas participações em desafios serão anonimizadas.',
      'This action is permanent and cannot be undone.\n\n'
          'Your personal data will be removed. '
          'Your challenge entries will be anonymized.',
      'Esta acción es permanente y no se puede deshacer.\n\n'
          'Se eliminarán tus datos personales. '
          'Tus participaciones en retos se anonimizarán.',
      'Cette action est définitive et irréversible.\n\n'
          'Vos données personnelles seront supprimées. '
          'Vos participations aux défis seront anonymisées.',
      'Questa azione è permanente e non può essere annullata.\n\n'
          'I tuoi dati personali verranno rimossi. '
          'Le tue partecipazioni alle sfide saranno anonimizzate.',
      'Diese Aktion ist endgültig und kann nicht rückgängig gemacht '
          'werden.\n\n'
          'Deine persönlichen Daten werden gelöscht. '
          'Deine Challenge-Beiträge werden anonymisiert.'],
    'delete_account_balance': [
      'Você ainda tem {v} em créditos. Ao excluir a conta, esse saldo será '
          'PERDIDO — não há reembolso. Se preferir, saque antes (saque '
          'mínimo: {min}).',
      'You still have {v} in credits. If you delete your account, this '
          'balance will be LOST — there are no refunds. You may want to '
          'withdraw first (minimum payout: {min}).',
      'Aún tienes {v} en créditos. Si eliminas la cuenta, ese saldo se '
          'PERDERÁ — no hay reembolsos. Quizás prefieras retirarlo antes '
          '(retiro mínimo: {min}).',
      'Il vous reste {v} de crédits. Si vous supprimez le compte, ce solde '
          'sera PERDU — aucun remboursement. Vous pouvez d\'abord le retirer '
          '(retrait minimum : {min}).',
      'Hai ancora {v} di crediti. Eliminando l\'account questo saldo andrà '
          'PERSO — nessun rimborso. Puoi prelevarlo prima (prelievo minimo: '
          '{min}).',
      'Du hast noch {v} Guthaben. Wenn du dein Konto löschst, geht dieses '
          'Guthaben VERLOREN — keine Erstattung. Du kannst es vorher '
          'auszahlen lassen (Mindestauszahlung: {min}).'],
    'delete_account_confirm': ['Excluir permanentemente', 'Delete permanently',
      'Eliminar definitivamente', 'Supprimer définitivement',
      'Elimina definitivamente', 'Endgültig löschen'],
    'delete_account_btn': ['Excluir minha conta', 'Delete my account',
      'Eliminar mi cuenta', 'Supprimer mon compte', 'Elimina il mio account',
      'Mein Konto löschen'],

    // Envio de participação (entry_repository.dart)
    'not_logged_in': ['Usuário não logado', 'You are not signed in',
      'No has iniciado sesión', 'Vous n\'êtes pas connecté',
      'Non hai effettuato l\'accesso', 'Du bist nicht angemeldet'],
    'file_too_big_image': [
      'Arquivo muito grande: {mb} MB. Limite para imagens: 10 MB.',
      'File too large: {mb} MB. Image limit: 10 MB.',
      'Archivo demasiado grande: {mb} MB. Límite para imágenes: 10 MB.',
      'Fichier trop volumineux : {mb} Mo. Limite pour les images : 10 Mo.',
      'File troppo grande: {mb} MB. Limite per le immagini: 10 MB.',
      'Datei zu groß: {mb} MB. Limit für Bilder: 10 MB.'],
    'file_too_big_video': [
      'Arquivo muito grande: {mb} MB. Limite para vídeos: 50 MB.',
      'File too large: {mb} MB. Video limit: 50 MB.',
      'Archivo demasiado grande: {mb} MB. Límite para videos: 50 MB.',
      'Fichier trop volumineux : {mb} Mo. Limite pour les vidéos : 50 Mo.',
      'File troppo grande: {mb} MB. Limite per i video: 50 MB.',
      'Datei zu groß: {mb} MB. Limit für Videos: 50 MB.'],

    // PayPal: ordem aberta persistida (paypal_topup_page.dart — só intl)
    'paypal_pending_open': [
      'Você tem um pagamento em aberto — confirmar',
      'You have an open payment — confirm it',
      'Tienes un pago pendiente — confírmalo',
      'Vous avez un paiement en attente — confirmez-le',
      'Hai un pagamento in sospeso — confermalo',
      'Du hast eine offene Zahlung — jetzt bestätigen'],
    'paypal_reopen': ['Abrir o PayPal de novo', 'Open PayPal again',
      'Abrir PayPal de nuevo', 'Rouvrir PayPal', 'Riapri PayPal',
      'PayPal erneut öffnen'],
    'paypal_order_expired': [
      'Esse pagamento expirou ou foi cancelado no PayPal. Crie um novo.',
      'This payment expired or was cancelled on PayPal. Please start a new '
          'one.',
      'Este pago expiró o se canceló en PayPal. Crea uno nuevo.',
      'Ce paiement a expiré ou a été annulé sur PayPal. Créez-en un nouveau.',
      'Questo pagamento è scaduto o è stato annullato su PayPal. Creane uno '
          'nuovo.',
      'Diese Zahlung ist abgelaufen oder wurde bei PayPal storniert. Bitte '
          'neu starten.'],

    // Feed, aporte e comentarios
    'create_login': ['Entre para criar um desafio',
      'Sign in to create a challenge', 'Inicia sesión para crear un reto',
      'Connectez-vous pour créer un défi', 'Accedi per creare una sfida',
      'Melde dich an, um eine Challenge zu erstellen'],
    'add_prize_login': ['Entre para aumentar o prêmio',
      'Sign in to boost the prize', 'Inicia sesión para aumentar el premio',
      'Connectez-vous pour augmenter le prix',
      'Accedi per aumentare il premio',
      'Melde dich an, um den Preis zu erhöhen'],
    'add_prize_title': ['Aumentar prêmio', 'Boost the prize',
      'Aumentar el premio', 'Augmenter le prix', 'Aumenta il premio',
      'Preis erhöhen'],
    'add_prize_label': ['Valor a adicionar (R\$)', 'Amount to add (US\$)',
      'Monto a añadir (US\$)', 'Montant à ajouter (US\$)',
      'Importo da aggiungere (US\$)', 'Betrag zum Hinzufügen (US\$)'],
    'add_prize_done': ['{v} adicionados ao prêmio!', '{v} added to the prize!',
      '¡{v} añadidos al premio!', '{v} ajoutés au prix !',
      '{v} aggiunti al premio!', '{v} zum Preis hinzugefügt!'],

    // Prévia do feed (top 3)
    'preview_top': ['Mais votados', 'Most voted', 'Más votados',
      'Les plus votés', 'I più votati', 'Meiste Stimmen'],
    'preview_winning': ['Vencendo', 'Winning', 'Ganando', 'En tête',
      'In testa', 'Vorne'],

    // Vídeo por link (YouTube Shorts / Reels do Instagram)
    'entry_kind_image': ['Imagem', 'Image', 'Imagen', 'Image', 'Immagine',
      'Bild'],
    'entry_kind_video': ['Vídeo (link)', 'Video (link)', 'Video (enlace)',
      'Vidéo (lien)', 'Video (link)', 'Video (Link)'],
    'video_rules_title': ['Como participar com vídeo:',
      'How to enter with a video:', 'Cómo participar con video:',
      'Comment participer avec une vidéo :', 'Come partecipare con un video:',
      'So machst du mit einem Video mit:'],
    'video_rule_vertical': [
      'Vídeo VERTICAL: Shorts do YouTube ou Reels do Instagram',
      'VERTICAL video: YouTube Shorts or Instagram Reels',
      'Video VERTICAL: Shorts de YouTube o Reels de Instagram',
      'Vidéo VERTICALE : YouTube Shorts ou Reels Instagram',
      'Video VERTICALE: YouTube Shorts o Reels di Instagram',
      'HOCHKANT-Video: YouTube Shorts oder Instagram Reels'],
    'video_rule_public': ['O vídeo precisa estar PÚBLICO',
      'The video must be PUBLIC', 'El video debe ser PÚBLICO',
      'La vidéo doit être PUBLIQUE', 'Il video deve essere PUBBLICO',
      'Das Video muss ÖFFENTLICH sein'],
    'video_rule_code': [
      'Coloque o código abaixo no TÍTULO (YouTube) ou na LEGENDA (Instagram)',
      'Put the code below in the TITLE (YouTube) or CAPTION (Instagram)',
      'Pon el código de abajo en el TÍTULO (YouTube) o la DESCRIPCIÓN '
          '(Instagram)',
      'Mettez le code ci-dessous dans le TITRE (YouTube) ou la LÉGENDE '
          '(Instagram)',
      'Metti il codice qui sotto nel TITOLO (YouTube) o nella DIDASCALIA '
          '(Instagram)',
      'Setze den Code unten in den TITEL (YouTube) oder die '
          'BILDUNTERSCHRIFT (Instagram)'],
    'video_rule_why': [
      'O código prova que o vídeo é seu. Ele vale só para este desafio.',
      'The code proves the video is yours. It only works for this challenge.',
      'El código demuestra que el video es tuyo. Solo vale para este reto.',
      'Le code prouve que la vidéo est à vous. Il ne vaut que pour ce défi.',
      'Il codice dimostra che il video è tuo. Vale solo per questa sfida.',
      'Der Code beweist, dass das Video dir gehört. Er gilt nur für diese '
          'Challenge.'],
    'video_your_code': ['Seu código', 'Your code', 'Tu código', 'Votre code',
      'Il tuo codice', 'Dein Code'],
    'video_code_copied': ['Código copiado!', 'Code copied!', '¡Código copiado!',
      'Code copié !', 'Codice copiato!', 'Code kopiert!'],
    'video_link_label': ['Link do vídeo', 'Video link', 'Enlace del video',
      'Lien de la vidéo', 'Link del video', 'Video-Link'],
    'video_link_invalid': [
      'Link não reconhecido. Use um Shorts do YouTube ou um Reels do '
          'Instagram.',
      'Link not recognized. Use a YouTube Shorts or an Instagram Reels link.',
      'Enlace no reconocido. Usa un Shorts de YouTube o un Reels de '
          'Instagram.',
      'Lien non reconnu. Utilisez un YouTube Shorts ou un Reels Instagram.',
      'Link non riconosciuto. Usa uno YouTube Shorts o un Reels di Instagram.',
      'Link nicht erkannt. Nutze einen YouTube-Short oder ein Instagram-Reel.'],
    'video_detected_youtube': ['YouTube reconhecido', 'YouTube link detected',
      'Enlace de YouTube reconocido', 'Lien YouTube reconnu',
      'Link YouTube riconosciuto', 'YouTube-Link erkannt'],
    'video_detected_instagram': ['Instagram reconhecido',
      'Instagram link detected', 'Enlace de Instagram reconocido',
      'Lien Instagram reconnu', 'Link Instagram riconosciuto',
      'Instagram-Link erkannt'],
    'video_ig_review_note': [
      'Vídeos do Instagram são conferidos pela equipe antes de concorrer ao '
          'prêmio.',
      'Instagram videos are checked by our team before competing for the '
          'prize.',
      'Los videos de Instagram los revisa el equipo antes de competir por el '
          'premio.',
      "Les vidéos Instagram sont vérifiées par l'équipe avant de concourir "
          'pour le prix.',
      'I video di Instagram vengono controllati dal team prima di concorrere '
          'al premio.',
      'Instagram-Videos werden vom Team geprüft, bevor sie um den Preis '
          'antreten.'],
    'video_sent_pending': [
      'Enviado! A equipe vai conferir o código na legenda do seu vídeo.',
      'Sent! Our team will check the code in your video caption.',
      '¡Enviado! El equipo revisará el código en la descripción de tu video.',
      "Envoyé ! L'équipe vérifiera le code dans la légende de votre vidéo.",
      'Inviato! Il team controllerà il codice nella didascalia del tuo video.',
      'Gesendet! Das Team prüft den Code in deiner Bildunterschrift.'],
    'video_pending': ['Aguardando verificação', 'Awaiting verification',
      'Pendiente de verificación', 'En attente de vérification',
      'In attesa di verifica', 'Wartet auf Prüfung'],
    'video_unavailable': ['Vídeo indisponível', 'Video unavailable',
      'Video no disponible', 'Vidéo indisponible', 'Video non disponibile',
      'Video nicht verfügbar'],
    'video_open_youtube': ['Abrir no YouTube', 'Open on YouTube',
      'Abrir en YouTube', 'Ouvrir sur YouTube', 'Apri su YouTube',
      'Auf YouTube öffnen'],
    'video_open_instagram': ['Abrir no Instagram', 'Open on Instagram',
      'Abrir en Instagram', 'Ouvrir sur Instagram', 'Apri su Instagram',
      'Auf Instagram öffnen'],
    'close': ['Fechar', 'Close', 'Cerrar', 'Fermer', 'Chiudi', 'Schließen'],

    // Prova de prêmio no XRP Ledger
    'xrpl_prize_proof': ['Prêmio registrado na rede XRP',
      'Prize recorded on the XRP Ledger', 'Premio registrado en XRP Ledger',
      'Prix enregistré sur le XRP Ledger', 'Premio registrato su XRP Ledger',
      'Preis im XRP Ledger hinterlegt'],
    'xrpl_prize_proof_test': ['Prêmio registrado na rede XRP (teste)',
      'Prize recorded on the XRP Ledger (testnet)',
      'Premio registrado en XRP Ledger (testnet)',
      'Prix enregistré sur le XRP Ledger (testnet)',
      'Premio registrato su XRP Ledger (testnet)',
      'Preis im XRP Ledger hinterlegt (Testnet)'],
    'xrpl_result_proof': ['Resultado registrado na rede XRP',
      'Result recorded on the XRP Ledger', 'Resultado registrado en XRP Ledger',
      'Résultat enregistré sur le XRP Ledger',
      'Risultato registrato su XRP Ledger',
      'Ergebnis im XRP Ledger hinterlegt'],

    // Transparência: conteúdo de demonstração
    'demo_badge': ['Demonstração', 'Demo', 'Demostración', 'Démo', 'Demo',
      'Demo'],
    'demo_explain': [
      'Conteúdo de demonstração: não é de um usuário real e não vale prêmio.',
      'Demo content: not from a real user and not eligible for prizes.',
      'Contenido de demostración: no es de un usuario real y no opta a premio.',
      "Contenu de démonstration : pas d'un vrai utilisateur, sans prix.",
      'Contenuto dimostrativo: non è di un utente reale e non vale premi.',
      'Demo-Inhalt: kein echter Nutzer, nicht preisberechtigt.'],
  };
}
