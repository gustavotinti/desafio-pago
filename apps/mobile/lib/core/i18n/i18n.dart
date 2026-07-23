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
  };
}
