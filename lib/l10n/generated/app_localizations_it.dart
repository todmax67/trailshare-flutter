// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appTitle => 'TrailShare';

  @override
  String get save => 'Salva';

  @override
  String get cancel => 'Annulla';

  @override
  String get delete => 'Elimina';

  @override
  String get confirm => 'Conferma';

  @override
  String get edit => 'Modifica';

  @override
  String get create => 'Crea';

  @override
  String get add => 'Aggiungi';

  @override
  String get send => 'Invia';

  @override
  String get search => 'Cerca';

  @override
  String get share => 'Condividi';

  @override
  String get close => 'Chiudi';

  @override
  String get back => 'Indietro';

  @override
  String get next => 'Avanti';

  @override
  String get done => 'Fatto';

  @override
  String get yes => 'Sì';

  @override
  String get no => 'No';

  @override
  String get ok => 'OK';

  @override
  String get loading => 'Caricamento...';

  @override
  String get retry => 'Riprova';

  @override
  String get error => 'Errore';

  @override
  String get success => 'Successo';

  @override
  String get warning => 'Attenzione';

  @override
  String get select => 'Seleziona';

  @override
  String get copy => 'Copia';

  @override
  String get continueAction => 'Continua';

  @override
  String get distance => 'Distanza';

  @override
  String get elevation => 'Dislivello';

  @override
  String get elevationGain => 'Dislivello+';

  @override
  String get elevationLoss => 'Dislivello-';

  @override
  String get duration => 'Durata';

  @override
  String get speed => 'Velocità';

  @override
  String get avgSpeed => 'Vel. media';

  @override
  String get maxSpeed => 'Vel. max';

  @override
  String get pace => 'Passo';

  @override
  String get altitude => 'Altitudine';

  @override
  String get maxAltitude => 'Alt. max';

  @override
  String get minAltitude => 'Alt. min';

  @override
  String get totalDistance => 'Distanza totale';

  @override
  String get totalElevation => 'Dislivello totale';

  @override
  String get activity => 'Attività';

  @override
  String activityChanged(String type) {
    return 'Attività cambiata in $type';
  }

  @override
  String get details => 'Dettagli';

  @override
  String get statistics => 'Statistiche';

  @override
  String get statsPerKm => 'Statistiche per Km';

  @override
  String get photos => 'Foto';

  @override
  String get map => 'Mappa';

  @override
  String get track => 'Traccia';

  @override
  String get tracks => 'Tracce';

  @override
  String get myTracks => 'Le mie tracce';

  @override
  String get noTracks => 'Nessuna traccia salvata';

  @override
  String get trackSaved => 'Traccia salvata!';

  @override
  String get trackDeleted => 'Traccia eliminata';

  @override
  String get saveTrack => 'Salva traccia';

  @override
  String get savingTrack => 'Salvataggio traccia...';

  @override
  String get editTrack => 'Modifica traccia';

  @override
  String get deleteTrack => 'Elimina traccia';

  @override
  String get deleteTrackConfirm =>
      'Vuoi eliminare questa traccia? L\'azione è irreversibile.';

  @override
  String get publishTrack => 'Pubblica nella community';

  @override
  String get removeFromCommunity => 'Rimuovi dalla community';

  @override
  String get published => 'Pubblica';

  @override
  String get trackName => 'Nome traccia';

  @override
  String get noName => 'Senza nome';

  @override
  String get exportGpx => 'Esporta GPX';

  @override
  String exportError(String error) {
    return 'Errore export: $error';
  }

  @override
  String get importGpx => 'Importa GPX';

  @override
  String get planRoute => 'Pianifica percorso';

  @override
  String get plannedRoutes => 'Percorsi pianificati';

  @override
  String get recording => 'Registrazione';

  @override
  String get startRecording => 'Inizia registrazione';

  @override
  String get stopRecording => 'Ferma registrazione';

  @override
  String get pauseRecording => 'Pausa';

  @override
  String get resumeRecording => 'Riprendi';

  @override
  String get criticalBattery =>
      'Batteria critica! Salvataggio traccia in corso...';

  @override
  String get gpsSignalLost => 'Segnale GPS perso';

  @override
  String get gpsSignalWeak => 'Segnale GPS debole';

  @override
  String get recordingInProgress => 'Registrazione in corso';

  @override
  String get login => 'Accedi';

  @override
  String get register => 'Registrati';

  @override
  String get logout => 'Esci';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get confirmPassword => 'Conferma password';

  @override
  String get forgotPassword => 'Password dimenticata?';

  @override
  String loginWith(String provider) {
    return 'Accedi con $provider';
  }

  @override
  String get trackYourAdventures => 'Traccia le tue avventure';

  @override
  String get or => 'oppure';

  @override
  String get alreadyHaveAccount => 'Hai già un account?';

  @override
  String get noAccount => 'Non hai un account?';

  @override
  String get registerNow => 'Registrati ora';

  @override
  String get username => 'Username';

  @override
  String get chooseUsername => 'Scegli il tuo username';

  @override
  String get usernameHint => 'Come vuoi essere chiamato?';

  @override
  String get usernameRequired => 'L\'username è obbligatorio';

  @override
  String get usernameTooShort => 'Almeno 3 caratteri';

  @override
  String get usernameAlreadyTaken => 'Username già in uso';

  @override
  String get profile => 'Profilo';

  @override
  String get editProfile => 'Modifica profilo';

  @override
  String get bio => 'Bio';

  @override
  String get level => 'Livello';

  @override
  String get followers => 'Follower';

  @override
  String get following => 'Seguiti';

  @override
  String get follow => 'Segui';

  @override
  String get unfollow => 'Non seguire più';

  @override
  String get noFollowers => 'Nessun follower';

  @override
  String get noFollowing => 'Non segui nessuno';

  @override
  String followersCount(int count) {
    return '$count follower';
  }

  @override
  String followingCount(int count) {
    return '$count seguiti';
  }

  @override
  String get shareProfile => 'Condividi le tue escursioni per farti conoscere!';

  @override
  String get discover => 'Scopri';

  @override
  String get searchTrails => 'Cerca sentieri...';

  @override
  String get noTrailsInArea => 'Nessun sentiero in questa zona';

  @override
  String get loadingFullTrack => 'Caricamento traccia completa...';

  @override
  String get trailDetails => 'Dettagli sentiero';

  @override
  String get deleteTrailAdmin => 'Elimina sentiero (Admin)';

  @override
  String get difficulty => 'Difficoltà';

  @override
  String get easy => 'Facile';

  @override
  String get moderate => 'Moderato';

  @override
  String get hard => 'Difficile';

  @override
  String get community => 'Community';

  @override
  String get communityTracks => 'Tracce community';

  @override
  String get discoverGroups => 'Scopri gruppi';

  @override
  String get suggestedUsers => 'Persone che potresti conoscere';

  @override
  String get searchUsers => 'Cerca utenti';

  @override
  String get searchUsersHint => 'Cerca utenti con la barra in alto';

  @override
  String get noSuggestions => 'Nessun suggerimento al momento';

  @override
  String get noResults => 'Nessun risultato';

  @override
  String get groups => 'Gruppi';

  @override
  String get myGroups => 'I miei gruppi';

  @override
  String get group => 'Gruppo';

  @override
  String get createGroup => 'Crea gruppo';

  @override
  String get joinGroup => 'Unisciti';

  @override
  String get leaveGroup => 'Lascia gruppo';

  @override
  String get deleteGroup => 'Elimina gruppo';

  @override
  String get deleteGroupConfirm =>
      'Vuoi eliminare questo gruppo? L\'azione è irreversibile.';

  @override
  String get groupName => 'Nome del gruppo';

  @override
  String get groupDescription => 'Descrizione del gruppo';

  @override
  String get members => 'Membri';

  @override
  String membersCount(int count) {
    return '$count membri';
  }

  @override
  String get admin => 'Admin';

  @override
  String get inviteCode => 'Codice invito';

  @override
  String get inviteCodeHint => 'Inserisci codice invito';

  @override
  String get joinWithCode => 'Unisciti con codice';

  @override
  String get visibility => 'Visibilità';

  @override
  String get public => 'Pubblico';

  @override
  String get privateGroup => 'Privato';

  @override
  String get secret => 'Segreto';

  @override
  String get publicDesc => 'Visibile a tutti, chiunque può unirsi';

  @override
  String get privateDesc => 'Visibile a tutti, accesso su richiesta';

  @override
  String get secretDesc => 'Invisibile, solo con codice invito';

  @override
  String get requestAccess => 'Richiedi accesso';

  @override
  String get requestSent => 'Richiesta inviata!';

  @override
  String get requestAlreadySent => 'Hai già inviato una richiesta';

  @override
  String get pendingRequests => 'Richieste di accesso';

  @override
  String get approveRequest => 'Approva';

  @override
  String get rejectRequest => 'Rifiuta';

  @override
  String get requestApproved => 'Richiesta approvata';

  @override
  String get requestRejected => 'Richiesta rifiutata';

  @override
  String get groupVisibility => 'Visibilità del gruppo';

  @override
  String get chat => 'Chat';

  @override
  String get messages => 'Messaggi';

  @override
  String get noMessages => 'Nessun messaggio';

  @override
  String get startConversation => 'Inizia la conversazione!';

  @override
  String get writeMessage => 'Scrivi un messaggio...';

  @override
  String get sendingImage => 'Invio immagine...';

  @override
  String get imageUploadError => 'Errore invio immagine';

  @override
  String get events => 'Eventi';

  @override
  String get createEvent => 'Crea evento';

  @override
  String get eventTitle => 'Titolo evento';

  @override
  String get eventDate => 'Data';

  @override
  String get eventTime => 'Ora';

  @override
  String get eventDescription => 'Dettagli sull\'uscita...';

  @override
  String get eventDistance => 'Distanza';

  @override
  String get eventElevation => 'Dislivello';

  @override
  String get maxParticipants => 'Max partecipanti';

  @override
  String get noLimit => 'Nessun limite';

  @override
  String get join => 'Partecipa';

  @override
  String get leave => 'Lascia';

  @override
  String get participants => 'Partecipanti';

  @override
  String get noEvents => 'Nessun evento in programma';

  @override
  String get upcomingEvents => 'Prossimi eventi';

  @override
  String get challenges => 'Sfide';

  @override
  String get createChallenge => 'Crea sfida';

  @override
  String get challengeTitle => 'Titolo sfida';

  @override
  String get noParticipants => 'Nessun partecipante ancora';

  @override
  String get leaderboard => 'Classifica';

  @override
  String get activeChallenges => 'Sfide attive';

  @override
  String get completedChallenges => 'Sfide completate';

  @override
  String get challengeType => 'Tipo sfida';

  @override
  String get distanceChallenge => 'Distanza';

  @override
  String get elevationChallenge => 'Dislivello';

  @override
  String get tracksChallenge => 'Tracce';

  @override
  String get streakChallenge => 'Costanza';

  @override
  String get settings => 'Impostazioni';

  @override
  String get generalSettings => 'Generali';

  @override
  String get mapSettings => 'Mappe';

  @override
  String get notificationSettings => 'Notifiche';

  @override
  String get account => 'Account';

  @override
  String get theme => 'Tema';

  @override
  String get darkMode => 'Modalità scura';

  @override
  String get lightMode => 'Modalità chiara';

  @override
  String get systemMode => 'Segui sistema';

  @override
  String get language => 'Lingua';

  @override
  String get offlineMaps => 'Mappe offline';

  @override
  String get downloadMap => 'Scarica mappa';

  @override
  String get deleteMap => 'Elimina mappa';

  @override
  String get mapDownloaded => 'Mappa scaricata';

  @override
  String get storageUsed => 'Spazio utilizzato';

  @override
  String get units => 'Unità di misura';

  @override
  String get metric => 'Metriche (km, m)';

  @override
  String get imperial => 'Imperiali (mi, ft)';

  @override
  String get about => 'Informazioni';

  @override
  String get version => 'Versione';

  @override
  String get privacyPolicy => 'Informativa privacy';

  @override
  String get termsOfService => 'Termini di servizio';

  @override
  String get deleteAccount => 'Elimina account';

  @override
  String get deleteAccountConfirm =>
      'Vuoi eliminare il tuo account? Tutti i dati verranno persi.';

  @override
  String get liveTracking => 'Live tracking';

  @override
  String durationLabel(String duration) {
    return 'Durata: $duration';
  }

  @override
  String get wishlistAdded => 'Salvato';

  @override
  String get wishlistRemoved => 'Rimosso';

  @override
  String get saved => 'Salvato';

  @override
  String get saving => 'Salvataggio...';

  @override
  String get errorGeneric => 'Si è verificato un errore';

  @override
  String get errorUnknown => 'Errore sconosciuto';

  @override
  String get errorNetwork => 'Errore di connessione';

  @override
  String get errorPermission => 'Permesso negato';

  @override
  String get noData => 'Nessun dato';

  @override
  String get noUser => 'Nessun utente';

  @override
  String get greatJob => 'Ottimo lavoro! 💪';

  @override
  String get greatHike => 'Grande escursione! 🏔️';

  @override
  String get fantasticTrail => 'Fantastico percorso! 🥾';

  @override
  String get whatAdventure => 'Che avventura! 🌟';

  @override
  String get trueExplorer => 'Sei un vero esploratore! 🧭';

  @override
  String get trailCompleted => 'Trail completato! 🎯';

  @override
  String get keepItUp => 'Complimenti, continua così! 🔥';

  @override
  String get today => 'Oggi';

  @override
  String get yesterday => 'Ieri';

  @override
  String get km => 'km';

  @override
  String get m => 'm';

  @override
  String get h => 'h';

  @override
  String get min => 'min';

  @override
  String get info => 'Info';

  @override
  String get sharedTracks => 'Tracce condivise';

  @override
  String get name => 'Nome';

  @override
  String get description => 'Descrizione';

  @override
  String get adminPanel => 'Pannello admin';

  @override
  String get noUsersFound => 'Nessun utente';

  @override
  String get noResultsFound => 'Nessun risultato';

  @override
  String get databaseStats => 'Statistiche database';

  @override
  String get tapKmToHighlight => 'Tocca un km per evidenziarlo sulla mappa';

  @override
  String get total => 'TOT';
}
