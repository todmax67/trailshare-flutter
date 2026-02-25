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
  String get recording => 'REGISTRAZIONE';

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
  String get createGroup => 'Crea Gruppo';

  @override
  String get joinGroup => 'Unisciti';

  @override
  String get leaveGroup => 'Lascia gruppo';

  @override
  String get deleteGroup => 'Elimina gruppo';

  @override
  String deleteGroupConfirm(String name) {
    return 'Vuoi eliminare \"$name\"?\n\nQuesta azione è irreversibile.';
  }

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
  String get offlineMaps => 'Mappe Offline';

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
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get termsOfService => 'Termini di Servizio';

  @override
  String get deleteAccount => 'Elimina Account';

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
  String get databaseStats => 'Statistiche Database';

  @override
  String get tapKmToHighlight => 'Tocca un km per evidenziarlo sulla mappa';

  @override
  String get total => 'TOT';

  @override
  String get defaultUser => 'Utente';

  @override
  String get usernameUpdated => 'Username aggiornato!';

  @override
  String get bioUpdated => 'Bio aggiornata!';

  @override
  String errorWithDetails(String error) {
    return 'Errore: $error';
  }

  @override
  String get logoutConfirm => 'Vuoi uscire dal tuo account?';

  @override
  String get loginToSeeProfile => 'Accedi per vedere il tuo profilo';

  @override
  String get loginProfileDescription =>
      'Salva le tue tracce, segui altri escursionisti e molto altro.';

  @override
  String get editNickname => 'Modifica nickname';

  @override
  String get bioHint => 'Racconta qualcosa di te...';

  @override
  String get addBio => 'Aggiungi una bio';

  @override
  String get editBio => 'Modifica bio';

  @override
  String levelNumber(int level) {
    return 'Livello $level';
  }

  @override
  String get myContacts => 'I miei contatti';

  @override
  String contactsSummary(int followers, int following) {
    return '$followers follower · $following seguiti';
  }

  @override
  String get viewDashboard => 'Vedi Dashboard';

  @override
  String get savedRoutes => 'Percorsi Salvati';

  @override
  String get weeklyLeaderboard => 'Classifica Settimanale';

  @override
  String get myBadges => 'I Miei Badge';

  @override
  String get dashboard => 'Dashboard';

  @override
  String get noStatsAvailable => 'Nessuna statistica disponibile';

  @override
  String get recordFirstTrackForStats =>
      'Registra la tua prima traccia per vedere le statistiche!';

  @override
  String get summary => 'Riepilogo';

  @override
  String get totalTracksLabel => 'Tracce Totali';

  @override
  String get totalTime => 'Tempo Totale';

  @override
  String get personalRecords => 'Record Personali';

  @override
  String get longestTrack => 'Traccia più lunga';

  @override
  String get highestElevationRecord => 'Maggior dislivello';

  @override
  String get longestDuration => 'Durata più lunga';

  @override
  String get activityDistribution => 'Distribuzione Attività';

  @override
  String get trend => 'Andamento';

  @override
  String get week => 'Settimana';

  @override
  String get month => 'Mese';

  @override
  String get year => 'Anno';

  @override
  String get noDataForPeriod => 'Nessun dato per questo periodo';

  @override
  String get thisWeek => 'Questa Settimana';

  @override
  String get previousWeek => 'Sett. Precedente';

  @override
  String get noRecord => 'Nessun record';

  @override
  String get activityCycling => 'Ciclismo';

  @override
  String get activityWalking => 'Camminata';

  @override
  String get daySun => 'Dom';

  @override
  String get dayMon => 'Lun';

  @override
  String get dayTue => 'Mar';

  @override
  String get dayWed => 'Mer';

  @override
  String get dayThu => 'Gio';

  @override
  String get dayFri => 'Ven';

  @override
  String get daySat => 'Sab';

  @override
  String get monthJanShort => 'Gen';

  @override
  String get monthFebShort => 'Feb';

  @override
  String get monthMarShort => 'Mar';

  @override
  String get monthAprShort => 'Apr';

  @override
  String get monthMayShort => 'Mag';

  @override
  String get monthJunShort => 'Giu';

  @override
  String get monthJulShort => 'Lug';

  @override
  String get monthAugShort => 'Ago';

  @override
  String get monthSepShort => 'Set';

  @override
  String get monthOctShort => 'Ott';

  @override
  String get monthNovShort => 'Nov';

  @override
  String get monthDecShort => 'Dic';

  @override
  String get monthJan => 'Gennaio';

  @override
  String get monthFeb => 'Febbraio';

  @override
  String get monthMar => 'Marzo';

  @override
  String get monthApr => 'Aprile';

  @override
  String get monthMay => 'Maggio';

  @override
  String get monthJun => 'Giugno';

  @override
  String get monthJul => 'Luglio';

  @override
  String get monthAug => 'Agosto';

  @override
  String get monthSep => 'Settembre';

  @override
  String get monthOct => 'Ottobre';

  @override
  String get monthNov => 'Novembre';

  @override
  String get monthDec => 'Dicembre';

  @override
  String activeTabCount(int count) {
    return 'Attive ($count)';
  }

  @override
  String myChallengesTabCount(int count) {
    return 'Le mie ($count)';
  }

  @override
  String get createChallengeBtn => 'Crea Sfida';

  @override
  String get noActiveChallenges => 'Nessuna sfida attiva';

  @override
  String get notInAnyChallenges => 'Non partecipi a nessuna sfida';

  @override
  String get createFirstChallenge =>
      'Crea la prima sfida e sfida la community!';

  @override
  String get joinFromActiveTab => 'Unisciti a una sfida dalla tab \"Attive\"';

  @override
  String joinChallengeTitle(String title) {
    return 'Partecipa a \"$title\"';
  }

  @override
  String get goalLabel => 'Obiettivo';

  @override
  String get deadlineLabel => 'Scadenza';

  @override
  String daysCount(int days) {
    return '$days giorni';
  }

  @override
  String get joinChallengeConfirm => 'Vuoi partecipare a questa sfida?';

  @override
  String get joinAction => 'Partecipa';

  @override
  String get joinedChallenge => '🎉 Ti sei unito alla sfida!';

  @override
  String get joinError => 'Errore durante l\'iscrizione';

  @override
  String get challengeDetail => 'Dettaglio Sfida';

  @override
  String createdBy(String name) {
    return 'Creata da $name';
  }

  @override
  String get yourProgress => 'Il tuo progresso';

  @override
  String get enrolled => '✓ Iscritto';

  @override
  String participantsCount(int count) {
    return '$count partecipanti';
  }

  @override
  String goalPrefix(String goal) {
    return 'Obiettivo: $goal';
  }

  @override
  String get createNewChallenge => 'Crea una nuova sfida';

  @override
  String get challengeHint => 'Es: 100km in una settimana';

  @override
  String get descriptionOptional => 'Descrizione (opzionale)';

  @override
  String get describeChallenge => 'Descrivi la sfida...';

  @override
  String get challengeTypeLabel => 'Tipo di sfida';

  @override
  String get enterTitle => 'Inserisci un titolo';

  @override
  String get enterGoal => 'Inserisci un obiettivo';

  @override
  String get enterValidNumber => 'Inserisci un numero valido';

  @override
  String get challengeCreated => '🎉 Sfida creata!';

  @override
  String get creationError => 'Errore durante la creazione';

  @override
  String get tracksUnit => 'tracce';

  @override
  String get newBadge => 'Nuovo Badge!';

  @override
  String get fantastic => 'Fantastico!';

  @override
  String get badges => 'Badge';

  @override
  String unlockedCount(int count) {
    return 'Sbloccati ($count)';
  }

  @override
  String allCount(int count) {
    return 'Tutti ($count)';
  }

  @override
  String get noBadgesYet => 'Nessun badge ancora';

  @override
  String get completeTracksForBadges =>
      'Completa tracce e attività per sbloccare badge!';

  @override
  String get viewAllBadges => 'Vedi tutti i badge';

  @override
  String get milestones => 'Traguardi';

  @override
  String get socialCategory => 'Social';

  @override
  String get streakCategory => 'Costanza';

  @override
  String unlockedOn(String date) {
    return 'Sbloccato il $date';
  }

  @override
  String get leaderboardLoadError => 'Errore caricamento classifica';

  @override
  String get yourPosition => 'La tua posizione';

  @override
  String get youAreLeading => '🏆 Sei in testa!';

  @override
  String positionOfTotal(int rank, int total) {
    return 'Posizione $rank di $total';
  }

  @override
  String get noActivityThisWeek => 'Nessuna attività questa settimana';

  @override
  String get completeTrackForLeaderboard =>
      'Completa una traccia per apparire in classifica.\nSegui altri utenti per competere con loro!';

  @override
  String get startHike => 'Inizia un\'escursione';

  @override
  String get loginToSeeLeaderboard => 'Accedi per vedere la classifica';

  @override
  String get competeWithFriends =>
      'Competi con gli amici e scala la classifica settimanale!';

  @override
  String get youLabel => 'TU';

  @override
  String xpThisWeek(int xp) {
    return '$xp XP questa settimana';
  }

  @override
  String get accountSection => 'Account';

  @override
  String get emailLabel => 'Email';

  @override
  String get notAvailable => 'Non disponibile';

  @override
  String get signOutTitle => 'Esci';

  @override
  String get signOutSubtitle => 'Disconnetti il tuo account';

  @override
  String get signOutConfirm => 'Vuoi uscire dal tuo account?';

  @override
  String get appearanceSection => 'Aspetto';

  @override
  String get healthConnectionSection => 'Connessione Salute';

  @override
  String get syncWithHealth => 'Sincronizza con Salute';

  @override
  String get saveToAppleHealth => 'Salva le attività su Apple Salute';

  @override
  String get saveToHealthConnect => 'Salva le attività su Health Connect';

  @override
  String get healthConnectRequired => 'Health Connect necessario';

  @override
  String get healthConnectInstallMessage =>
      'Per sincronizzare le attività è necessario installare Health Connect dal Play Store.\n\nVuoi installarlo ora?';

  @override
  String get installAction => 'Installa';

  @override
  String get permissionsNotGranted =>
      'Permessi non concessi. Riprova o abilita dalle impostazioni del dispositivo.';

  @override
  String get maxHeartRate => 'Frequenza cardiaca massima';

  @override
  String get maxHRDescription =>
      'Inserisci la tua FC max se la conosci, oppure inserisci la tua età per stimarla (220 - età).';

  @override
  String get maxHRLabel => 'FC Max (BPM)';

  @override
  String get maxHRHint => 'Es: 185';

  @override
  String get orLabel => 'oppure';

  @override
  String get ageLabel => 'Età';

  @override
  String get ageHint => 'Es: 35';

  @override
  String get setForCardioZones => 'Imposta per calcolare le zone cardio';

  @override
  String get healthDashboard => 'Dashboard Salute';

  @override
  String get healthDashboardSubtitle => 'Passi, battito, calorie settimanali';

  @override
  String get legalSection => 'Legale';

  @override
  String get privacyPolicySubtitle => 'Come gestiamo i tuoi dati';

  @override
  String get termsOfServiceSubtitle => 'Condizioni d\'uso dell\'app';

  @override
  String get openSourceLicenses => 'Licenze Open Source';

  @override
  String get openSourceLicensesSubtitle => 'Librerie utilizzate';

  @override
  String get supportSection => 'Supporto';

  @override
  String get helpCenter => 'Centro Assistenza';

  @override
  String get helpCenterSubtitle => 'FAQ e guide';

  @override
  String get contactUs => 'Contattaci';

  @override
  String get rateApp => 'Valuta l\'app';

  @override
  String get rateAppSubtitle => 'Lascia una recensione';

  @override
  String get offlineMapsSubtitle => 'Scarica mappe per uso senza connessione';

  @override
  String get infoSection => 'Informazioni';

  @override
  String get versionLabel => 'Versione';

  @override
  String get loadingEllipsis => 'Caricamento...';

  @override
  String get whatsNew => 'Novità';

  @override
  String get whatsNewSubtitle => 'Cosa c\'è di nuovo';

  @override
  String get adminSection => 'Amministrazione';

  @override
  String get importTrails => 'Import Sentieri';

  @override
  String get importTrailsSubtitle => 'Importa sentieri da Waymarked Trails';

  @override
  String get geohashMigration => 'Migrazione GeoHash';

  @override
  String get geohashMigrationSubtitle =>
      'Gestisci indici geospaziali per i sentieri';

  @override
  String get databaseStatsSubtitle => 'Visualizza metriche e utilizzo';

  @override
  String get recalculateStats => 'Ricalcola Statistiche';

  @override
  String get recalculateStatsSubtitle =>
      'Correggi dislivello e distanze dalle tracce GPS';

  @override
  String get dangerZone => 'Zona Pericolosa';

  @override
  String get deleteAccountSubtitle =>
      'Elimina permanentemente tutti i tuoi dati';

  @override
  String get accountDeleted => 'Account eliminato con successo';

  @override
  String get cannotOpenLink => 'Impossibile aprire il link';

  @override
  String get cannotOpenEmail => 'Impossibile aprire il client email';

  @override
  String get appComingSoon =>
      'Grazie! L\'app sarà presto disponibile negli store.';

  @override
  String get changelogTitle => 'Novità v1.0.0';

  @override
  String get changelogFirstRelease => '🎉 Prima release!';

  @override
  String get changelogGpsTracking => 'Registrazione tracce GPS';

  @override
  String get changelogBackground => 'Tracking in background';

  @override
  String get changelogLiveTrack => 'LiveTrack - condividi posizione';

  @override
  String get changelogSocial => 'Sistema social (follow, cheers)';

  @override
  String get changelogLeaderboard => 'Classifica settimanale';

  @override
  String get changelogWishlist => 'Wishlist percorsi';

  @override
  String get changelogDashboard => 'Dashboard statistiche';

  @override
  String get changelogGpx => 'Import/Export GPX';

  @override
  String get themeLabel => 'Tema';

  @override
  String get themeAutomatic => 'Automatico';

  @override
  String get themeLight => 'Chiaro';

  @override
  String get themeDark => 'Scuro';

  @override
  String get selectTheme => 'Seleziona tema';

  @override
  String get themeAutomaticSubtitle => 'Segue le impostazioni di sistema';

  @override
  String get themeLightSubtitle => 'Tema chiaro sempre attivo';

  @override
  String get themeDarkSubtitle => 'Tema scuro sempre attivo';

  @override
  String get stepsToday => 'Passi oggi';

  @override
  String get restingHR => 'FC riposo';

  @override
  String get goalReached => '🎉 Obiettivo raggiunto!';

  @override
  String percentOfGoal(int pct) {
    return '$pct% di 10.000';
  }

  @override
  String get stepsLast7Days => 'Passi — Ultimi 7 giorni';

  @override
  String get caloriesLast7Days => 'Calorie — Ultimi 7 giorni';

  @override
  String get noStepsData => 'Nessun dato passi disponibile';

  @override
  String get noCaloriesData => 'Nessun dato calorie disponibile';

  @override
  String get stepsUnit => 'passi';

  @override
  String get healthDataInfo =>
      'I dati provengono dal tuo smartwatch tramite Health Connect. Assicurati che il dispositivo sia sincronizzato per dati aggiornati.';

  @override
  String get faqHowCanWeHelp => 'Come possiamo aiutarti?';

  @override
  String get faqFindAnswers => 'Trova risposte alle domande più frequenti';

  @override
  String get faqCategoryGeneral => '📱 Generale';

  @override
  String get faqCategoryTracking => '🗺️ Tracking GPS';

  @override
  String get faqCategorySocial => '👥 Social';

  @override
  String get faqCategoryGamification => '🏆 Gamification';

  @override
  String get faqCategoryTechnical => '⚙️ Tecnico';

  @override
  String get faqNoAnswer => 'Non hai trovato la risposta?';

  @override
  String get faqContactPrompt => 'Contattaci e ti risponderemo al più presto';

  @override
  String get faqContactSupport => 'Contatta il supporto';

  @override
  String get faqGeneralQ1 => 'Cos\'è TrailShare?';

  @override
  String get faqGeneralA1 =>
      'TrailShare è un\'app per registrare e condividere le tue escursioni. Puoi tracciare i tuoi percorsi con GPS, scoprire nuovi sentieri, seguire altri escursionisti e partecipare a sfide settimanali.';

  @override
  String get faqGeneralQ2 => 'L\'app è gratuita?';

  @override
  String get faqGeneralA2 =>
      'Sì, TrailShare è completamente gratuita. Tutte le funzionalità sono disponibili senza costi nascosti o abbonamenti.';

  @override
  String get faqGeneralQ3 => 'Devo creare un account?';

  @override
  String get faqGeneralA3 =>
      'Sì, è necessario un account per salvare le tue tracce e accedere alle funzionalità social. Puoi registrarti con email, Google o Apple.';

  @override
  String get faqGeneralQ4 => 'I miei dati sono al sicuro?';

  @override
  String get faqGeneralA4 =>
      'Assolutamente. I tuoi dati sono protetti e criptati. Puoi consultare la nostra Privacy Policy per tutti i dettagli su come gestiamo le informazioni.';

  @override
  String get faqTrackingQ1 => 'Come registro una traccia?';

  @override
  String get faqTrackingA1 =>
      'Vai nella sezione \"Registra\", premi il pulsante verde \"Inizia\" e cammina! L\'app registrerà automaticamente il tuo percorso. Puoi mettere in pausa e riprendere in qualsiasi momento.';

  @override
  String get faqTrackingQ2 => 'Il GPS funziona in background?';

  @override
  String get faqTrackingA2 =>
      'Sì, puoi bloccare lo schermo o usare altre app mentre registri. Il tracking continua in background con notifica attiva.';

  @override
  String get faqTrackingQ3 => 'Quanto consuma la batteria?';

  @override
  String get faqTrackingA3 =>
      'Il consumo dipende dalla durata dell\'escursione. In media, aspettati un consumo del 5-10% all\'ora. Consigliamo di partire con batteria carica o portare un powerbank.';

  @override
  String get faqTrackingQ4 => 'Funziona senza connessione internet?';

  @override
  String get faqTrackingA4 =>
      'Sì! Il tracking GPS funziona completamente offline. Puoi anche scaricare le mappe in anticipo da Impostazioni > Mappe Offline. La sincronizzazione avverrà quando tornerai online.';

  @override
  String get faqTrackingQ5 => 'Come miglioro la precisione GPS?';

  @override
  String get faqTrackingA5 =>
      'Assicurati di avere una buona visuale del cielo. Evita zone con copertura fitta o canyon stretti. Attendi qualche secondo prima di iniziare per permettere al GPS di calibrarsi.';

  @override
  String get faqTrackingQ6 => 'Posso importare tracce GPX?';

  @override
  String get faqTrackingA6 =>
      'Sì, puoi importare file GPX dalla sezione \"Le mie tracce\". Tocca il pulsante + e seleziona \"Importa GPX\".';

  @override
  String get faqTrackingQ7 => 'Posso esportare le mie tracce?';

  @override
  String get faqTrackingA7 =>
      'Certamente! Apri una traccia e tocca l\'icona condividi per esportarla in formato GPX, compatibile con la maggior parte delle app e dispositivi GPS.';

  @override
  String get faqSocialQ1 => 'Come seguo altri utenti?';

  @override
  String get faqSocialA1 =>
      'Cerca un utente o visita il suo profilo da una traccia pubblica, poi tocca \"Segui\". Vedrai le sue nuove tracce nel tuo feed.';

  @override
  String get faqSocialQ2 => 'Cos\'è un \"Cheers\"?';

  @override
  String get faqSocialA2 =>
      'È il nostro modo di dire \"bella traccia!\". Puoi lasciare un cheers sulle tracce che ti piacciono. Riceverai anche XP per i cheers ricevuti.';

  @override
  String get faqSocialQ3 => 'Come pubblico una traccia?';

  @override
  String get faqSocialA3 =>
      'Dopo aver salvato una traccia, aprila e tocca \"Pubblica\". La traccia sarà visibile nella sezione Esplora e gli altri potranno vederla.';

  @override
  String get faqSocialQ4 => 'Posso rendere privata una traccia?';

  @override
  String get faqSocialA4 =>
      'Le tracce sono private di default. Solo quelle che pubblichi esplicitamente saranno visibili agli altri.';

  @override
  String get faqSocialQ5 => 'Cos\'è LiveTrack?';

  @override
  String get faqSocialA5 =>
      'LiveTrack ti permette di condividere la tua posizione in tempo reale durante un\'escursione. Genera un link che puoi inviare a familiari o amici per farti seguire sulla mappa.';

  @override
  String get faqGamificationQ1 => 'Come funzionano gli XP?';

  @override
  String get faqGamificationA1 =>
      'Guadagni XP (punti esperienza) completando tracce, ricevendo cheers, ottenendo follower e completando sfide. Più XP accumuli, più sali di livello!';

  @override
  String get faqGamificationQ2 => 'Quanti livelli ci sono?';

  @override
  String get faqGamificationA2 =>
      'Ci sono 20 livelli, da \"Principiante\" a \"Immortale\". Ogni livello richiede più XP del precedente.';

  @override
  String get faqGamificationQ3 => 'Come sblocco i badge?';

  @override
  String get faqGamificationA3 =>
      'I badge si sbloccano automaticamente raggiungendo determinati traguardi: km percorsi, dislivello accumulato, giorni consecutivi di attività e obiettivi social.';

  @override
  String get faqGamificationQ4 => 'Come funziona la classifica?';

  @override
  String get faqGamificationA4 =>
      'La classifica settimanale si basa sui km percorsi e il dislivello accumulato nella settimana. Si resetta ogni lunedì.';

  @override
  String get faqGamificationQ5 => 'Posso vedere i badge degli altri?';

  @override
  String get faqGamificationA5 =>
      'Sì, visitando il profilo di un utente puoi vedere i suoi badge sbloccati e il suo livello.';

  @override
  String get faqTechnicalQ1 => 'Come collego una fascia cardio?';

  @override
  String get faqTechnicalA1 =>
      'Durante la registrazione, tocca l\'icona del cuore in alto. L\'app cercherà automaticamente fasce cardio Bluetooth nelle vicinanze. Seleziona la tua per connetterti.';

  @override
  String get faqTechnicalQ2 => 'Quali fasce cardio sono compatibili?';

  @override
  String get faqTechnicalA2 =>
      'TrailShare supporta qualsiasi fascia cardio Bluetooth Low Energy (BLE) standard, come Polar H10, Garmin HRM-Dual, Wahoo TICKR e molte altre.';

  @override
  String get faqTechnicalQ3 => 'Come scarico le mappe offline?';

  @override
  String get faqTechnicalA3 =>
      'Vai in Impostazioni > Mappe Offline > Scarica Area. Seleziona l\'area sulla mappa, scegli il livello di dettaglio e avvia il download.';

  @override
  String get faqTechnicalQ4 => 'Quanto spazio occupano le mappe offline?';

  @override
  String get faqTechnicalA4 =>
      'Dipende dall\'area e dal livello di zoom. Un\'area di 10km con zoom medio occupa circa 30-50 MB. Puoi vedere lo spazio utilizzato nelle impostazioni.';

  @override
  String get faqTechnicalQ5 => 'Come cambio tema chiaro/scuro?';

  @override
  String get faqTechnicalA5 =>
      'Vai in Impostazioni > Aspetto > Tema. Puoi scegliere tra Chiaro, Scuro o Automatico (segue le impostazioni del sistema).';

  @override
  String get faqTechnicalQ6 => 'Come elimino il mio account?';

  @override
  String get faqTechnicalA6 =>
      'Vai in Impostazioni > Zona Pericolosa > Elimina Account. Dovrai confermare con la password. Questa azione è irreversibile e cancellerà tutti i tuoi dati.';

  @override
  String get deleteAll => 'Elimina tutto';

  @override
  String get downloadArea => 'Scarica Area';

  @override
  String areasCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count aree',
      one: '1 area',
    );
    return '$_temp0';
  }

  @override
  String get noOfflineMaps => 'Nessuna mappa offline';

  @override
  String get downloadMapsForOffline =>
      'Scarica mappe per usarle quando sei senza connessione';

  @override
  String get areaName => 'Nome area';

  @override
  String get areaNameHint => 'Es: Dolomiti, Appennino...';

  @override
  String minZoomLabel(int value) {
    return 'Zoom minimo: $value';
  }

  @override
  String maxZoomLabel(int value) {
    return 'Zoom massimo: $value';
  }

  @override
  String get tilesToDownload => 'Tile da scaricare:';

  @override
  String get estimatedSize => 'Dimensione stimata:';

  @override
  String get downloadAction => 'Scarica';

  @override
  String get deleteArea => 'Elimina area';

  @override
  String deleteAreaConfirm(String name) {
    return 'Vuoi eliminare \"$name\"?';
  }

  @override
  String get deleteLabel => 'Elimina';

  @override
  String get deleteAllMaps => 'Elimina tutte le mappe';

  @override
  String get deleteAllMapsConfirm =>
      'Vuoi eliminare tutte le mappe offline? Questa azione non può essere annullata.';

  @override
  String get deleteAllAction => 'Elimina tutto';

  @override
  String get selectArea => 'Seleziona Area';

  @override
  String get confirmAction => 'Conferma';

  @override
  String get tapMapToSelectCenter => 'Tocca la mappa per selezionare il centro';

  @override
  String get radiusLabel => 'Raggio:';

  @override
  String get downloadCompleted => '✓ Completato!';

  @override
  String get downloadInProgress => 'Download in corso...';

  @override
  String tileProgress(int downloaded, int total) {
    return '$downloaded / $total tile';
  }

  @override
  String get closeAction => 'Chiudi';

  @override
  String get privacyLastUpdated => 'Ultimo aggiornamento: Gennaio 2025';

  @override
  String get privacyIntroTitle => 'Introduzione';

  @override
  String get privacyIntroContent =>
      'TrailShare (\"noi\", \"nostro\" o \"app\") rispetta la tua privacy. Questa informativa descrive quali dati raccogliamo, come li utilizziamo e i tuoi diritti in merito.';

  @override
  String get privacyDataCollectedTitle => 'Dati che raccogliamo';

  @override
  String get privacyDataCollectedContent =>
      '• **Dati di registrazione**: email, nome utente, foto profilo (opzionale)\n• **Dati di posizione**: coordinate GPS durante la registrazione delle tracce\n• **Dati delle attività**: tracce registrate, statistiche, dislivello, distanza\n• **Dati social**: follower, following, \"cheers\" (like)\n• **Dati del dispositivo**: modello, sistema operativo, per migliorare l\'app';

  @override
  String get privacyDataUsageTitle => 'Come utilizziamo i tuoi dati';

  @override
  String get privacyDataUsageContent =>
      '• Fornire e migliorare i servizi dell\'app\n• Salvare e sincronizzare le tue tracce\n• Abilitare funzionalità social (follow, cheers, classifica)\n• Funzionalità LiveTrack per condividere la posizione in tempo reale\n• Analisi aggregate per migliorare l\'esperienza utente';

  @override
  String get privacyDataSharingTitle => 'Condivisione dei dati';

  @override
  String get privacyDataSharingContent =>
      '• **Non vendiamo** i tuoi dati personali a terzi\n• Le tracce pubblicate sono visibili ad altri utenti\n• LiveTrack condivide la posizione solo con chi ha il link\n• Utilizziamo Firebase (Google) per l\'archiviazione sicura dei dati';

  @override
  String get privacyRetentionTitle => 'Conservazione dei dati';

  @override
  String get privacyRetentionContent =>
      'I tuoi dati vengono conservati finché mantieni un account attivo. Puoi eliminare il tuo account in qualsiasi momento dalla sezione Impostazioni, e tutti i tuoi dati verranno rimossi entro 30 giorni.';

  @override
  String get privacyRightsTitle => 'I tuoi diritti';

  @override
  String get privacyRightsContent =>
      '• **Accesso**: puoi visualizzare tutti i tuoi dati nell\'app\n• **Modifica**: puoi modificare il tuo profilo in qualsiasi momento\n• **Eliminazione**: puoi eliminare il tuo account e tutti i dati associati\n• **Esportazione**: puoi esportare le tue tracce in formato GPX';

  @override
  String get privacySecurityTitle => 'Sicurezza';

  @override
  String get privacySecurityContent =>
      'Utilizziamo Firebase Authentication e Firestore con crittografia per proteggere i tuoi dati. Le connessioni sono protette tramite HTTPS.';

  @override
  String get privacyMinorsTitle => 'Minori';

  @override
  String get privacyMinorsContent =>
      'L\'app non è destinata a minori di 13 anni. Non raccogliamo consapevolmente dati di bambini sotto questa età.';

  @override
  String get privacyChangesTitle => 'Modifiche alla policy';

  @override
  String get privacyChangesContent =>
      'Potremmo aggiornare questa privacy policy. Ti notificheremo di eventuali modifiche significative tramite l\'app o email.';

  @override
  String get privacyContactTitle => 'Contatti';

  @override
  String get privacyContactContent =>
      'Per domande sulla privacy, contattaci a:\n📧 privacy@trailshare.app';

  @override
  String get viewWebVersion => 'Visualizza versione web';

  @override
  String get searchByUsername => 'Cerca per username...';

  @override
  String noUserFoundFor(String query) {
    return 'Nessun utente trovato per \"$query\"';
  }

  @override
  String get tryDifferentUsername => 'Prova con un username diverso';

  @override
  String get peopleYouMayKnow => 'Persone che potresti conoscere';

  @override
  String get noSuggestionsNow => 'Nessun suggerimento al momento';

  @override
  String get searchUsersAbove => 'Cerca utenti con la barra in alto';

  @override
  String levelLabel(int level) {
    return 'Livello $level';
  }

  @override
  String followersOf(String name) {
    return 'Follower di $name';
  }

  @override
  String followedBy(String name) {
    return 'Seguiti da $name';
  }

  @override
  String get noFollowersYet => 'Nessun follower ancora';

  @override
  String get notFollowingAnyone => 'Non segue nessuno';

  @override
  String get shareHikesToGetKnown =>
      'Condividi le tue escursioni per farti conoscere!';

  @override
  String get exploreCommunity =>
      'Esplora la community per trovare persone interessanti.';

  @override
  String get skipAction => 'Salta';

  @override
  String get startAction => 'Inizia!';

  @override
  String get nextAction => 'Avanti';

  @override
  String get onboardingWelcomeTitle => 'Benvenuto in TrailShare';

  @override
  String get onboardingWelcomeDesc =>
      'La tua app per registrare e condividere avventure outdoor. Traccia i tuoi percorsi, scopri nuovi sentieri e connettiti con altri escursionisti.';

  @override
  String get onboardingTrackTitle => 'Traccia i tuoi percorsi';

  @override
  String get onboardingTrackDesc =>
      'Registra le tue escursioni con GPS preciso. Visualizza distanza, dislivello, velocità e tempo in tempo reale anche in background.';

  @override
  String get onboardingExploreTitle => 'Scopri nuovi sentieri';

  @override
  String get onboardingExploreDesc =>
      'Esplora percorsi pubblicati dalla community. Salva i tuoi preferiti nella wishlist e pianifica la tua prossima avventura.';

  @override
  String get onboardingConnectTitle => 'Connettiti con altri';

  @override
  String get onboardingConnectDesc =>
      'Segui amici ed escursionisti, condividi i tuoi percorsi e scala la classifica settimanale. Guadagna XP e sblocca badge!';

  @override
  String get onboardingOfflineTitle => 'Funziona anche offline';

  @override
  String get onboardingOfflineDesc =>
      'Scarica le mappe per usarle senza connessione. Il tracking GPS funziona sempre, anche in modalità aereo.';

  @override
  String get chooseYourUsername => 'Scegli il tuo username';

  @override
  String get usernameVisibleToOthers =>
      'Questo nome sarà visibile agli altri utenti di TrailShare';

  @override
  String get usernameLabel => 'Username';

  @override
  String get usernameExampleHint => 'es. mario_rossi';

  @override
  String get usernameRules =>
      '3-20 caratteri • Lettere, numeri, punti e underscore';

  @override
  String get enterUsername => 'Inserisci un username';

  @override
  String get usernameMinChars => 'Minimo 3 caratteri';

  @override
  String get usernameMaxChars => 'Massimo 20 caratteri';

  @override
  String get usernameInvalidChars => 'Solo lettere, numeri, punti e underscore';

  @override
  String get usernameAlreadyTakenChooseAnother =>
      'Username già in uso, scegline un altro';

  @override
  String get continueWithApple => 'Continua con Apple';

  @override
  String get continueWithGoogle => 'Continua con Google';

  @override
  String get orDivider => 'oppure';

  @override
  String get enterYourEmail => 'Inserisci la tua email';

  @override
  String get invalidEmail => 'Email non valida';

  @override
  String get passwordLabel => 'Password';

  @override
  String get enterPassword => 'Inserisci la password';

  @override
  String get resetPassword => 'Recupera password';

  @override
  String get enterEmailForReset =>
      'Inserisci la tua email per ricevere il link di reset.';

  @override
  String get sendAction => 'Invia';

  @override
  String get resetEmailSent => 'Email di reset inviata!';

  @override
  String get genericError => 'Errore';

  @override
  String get loginAction => 'Accedi';

  @override
  String get noAccountQuestion => 'Non hai un account?';

  @override
  String get registerAction => 'Registrati';

  @override
  String get loginCancelled => 'Accesso annullato';

  @override
  String get createAccount => 'Crea account';

  @override
  String get joinTrailShare => 'Unisciti a TrailShare';

  @override
  String get createAccountToSaveTracks =>
      'Crea un account per salvare le tue tracce';

  @override
  String get orRegisterWithEmail => 'oppure registrati con email';

  @override
  String get enterAPassword => 'Inserisci una password';

  @override
  String get passwordMinSixChars => 'Minimo 6 caratteri';

  @override
  String get passwordTooShort => 'La password deve avere almeno 6 caratteri';

  @override
  String get confirmYourPassword => 'Conferma la password';

  @override
  String get passwordsDoNotMatch => 'Le password non coincidono';

  @override
  String get accountCreatedSuccess => '✅ Account creato con successo!';

  @override
  String get acceptTermsAndPrivacy =>
      'Creando un account accetti i nostri Termini di servizio e la Privacy Policy';

  @override
  String tracksTabCount(int count) {
    return 'Tracce ($count)';
  }

  @override
  String groupsTabCount(int count) {
    return 'Gruppi ($count)';
  }

  @override
  String eventsTabCount(int count) {
    return 'Eventi ($count)';
  }

  @override
  String get showList => 'Mostra lista';

  @override
  String get showMap => 'Mostra mappa';

  @override
  String get searchTracksOrUsers => 'Cerca tracce o utenti...';

  @override
  String get noSharedTracks => 'Nessuna traccia condivisa';

  @override
  String noResultsForQuery(String query) {
    return 'Nessun risultato per \"$query\"';
  }

  @override
  String get tracksLabel => 'tracce';

  @override
  String get loadMore => 'Carica altre';

  @override
  String get loadMoreTracks => 'Carica altre tracce';

  @override
  String get newGroup => 'Nuovo Gruppo';

  @override
  String myFilterCount(int count) {
    return 'I miei ($count)';
  }

  @override
  String get discoverFilter => 'Scopri';

  @override
  String get codeLabel => 'Codice';

  @override
  String get noGroups => 'Nessun gruppo';

  @override
  String get createGroupCTA =>
      'Crea un gruppo per organizzare uscite, lanciare sfide e chattare con i tuoi compagni di avventura!';

  @override
  String get noGroupsAvailable => 'Nessun gruppo disponibile';

  @override
  String get noPublicGroupsCTA =>
      'Non ci sono gruppi pubblici a cui unirti al momento. Creane uno tu!';

  @override
  String memberCountPlural(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count membri',
      one: '1 membro',
    );
    return '$_temp0';
  }

  @override
  String get publicLabel => 'Pubblico';

  @override
  String get privateLabel => 'Privato';

  @override
  String get secretLabel => 'Segreto';

  @override
  String joinedGroupSnack(String name) {
    return 'Ti sei unito a \"$name\"!';
  }

  @override
  String get joinGroupAction => 'Unisciti';

  @override
  String requestSentSnack(String name) {
    return 'Richiesta inviata a \"$name\"!';
  }

  @override
  String get requestAction => 'Richiedi';

  @override
  String get publicEventsFilter => 'Pubblici';

  @override
  String activeChallengesCount(int count) {
    return 'Sfide attive ($count)';
  }

  @override
  String get noEventsScheduled => 'Nessun evento in programma';

  @override
  String get groupEventsWillAppear =>
      'Gli eventi dei tuoi gruppi appariranno qui';

  @override
  String get noPublicEvents => 'Nessun evento pubblico';

  @override
  String get publicEventsWillAppear =>
      'Gli eventi dei gruppi pubblici appariranno qui';

  @override
  String get participating => '✓ Partecipo';

  @override
  String get clearSearch => 'Cancella ricerca';

  @override
  String get enterInviteCodeDesc =>
      'Inserisci il codice invito ricevuto per unirti a un gruppo.';

  @override
  String get codeMustBeSixChars => 'Il codice deve essere di 6 caratteri';

  @override
  String get unknownError => 'Errore sconosciuto';

  @override
  String get joinedGroupGeneric => 'Ti sei unito al gruppo!';

  @override
  String daysShort(int days) {
    return '${days}g';
  }

  @override
  String get monthShortJan => 'GEN';

  @override
  String get monthShortFeb => 'FEB';

  @override
  String get monthShortMar => 'MAR';

  @override
  String get monthShortApr => 'APR';

  @override
  String get monthShortMay => 'MAG';

  @override
  String get monthShortJun => 'GIU';

  @override
  String get monthShortJul => 'LUG';

  @override
  String get monthShortAug => 'AGO';

  @override
  String get monthShortSep => 'SET';

  @override
  String get monthShortOct => 'OTT';

  @override
  String get monthShortNov => 'NOV';

  @override
  String get monthShortDec => 'DIC';

  @override
  String leaveGroupConfirm(String name) {
    return 'Vuoi uscire da \"$name\"?';
  }

  @override
  String get exitAction => 'Esci';

  @override
  String get deleteAction => 'Elimina';

  @override
  String get membersLabel => 'Membri';

  @override
  String get chatTab => 'Chat';

  @override
  String get eventsTab => 'Eventi';

  @override
  String get challengesTab => 'Sfide';

  @override
  String get infoTab => 'Info';

  @override
  String get inviteCodeTitle => 'Codice Invito';

  @override
  String get regenerateCode => 'Rigenera codice';

  @override
  String get shareInviteCodeDesc =>
      'Condividi questo codice per invitare nuove persone al gruppo';

  @override
  String get publicVisibilityDesc => 'Visibile, chiunque può unirsi';

  @override
  String get privateVisibilityDesc => 'Visibile, richiesta accesso';

  @override
  String get secretVisibilityDesc => 'Invisibile, solo codice invito';

  @override
  String get accessRequests => 'Richieste di accesso';

  @override
  String requestedOnDate(String date) {
    return 'Richiesta il $date';
  }

  @override
  String get pendingStatus => 'In attesa';

  @override
  String userApproved(String username) {
    return '$username approvato!';
  }

  @override
  String get descriptionLabel => 'Descrizione';

  @override
  String get editAction => 'Modifica';

  @override
  String get noDescriptionHint =>
      'Nessuna descrizione. Tocca modifica per aggiungerne una.';

  @override
  String get createdOnLabel => 'Creato il';

  @override
  String get yourRole => 'Il tuo ruolo';

  @override
  String get administratorRole => 'Amministratore';

  @override
  String get memberRole => 'Membro';

  @override
  String get founderLabel => 'Fondatore';

  @override
  String get youCreatedThisGroup => 'Tu hai creato questo gruppo';

  @override
  String get editGroup => 'Modifica gruppo';

  @override
  String get groupNameLabel => 'Nome gruppo';

  @override
  String get descriptionHint => 'Descrivi il tuo gruppo...';

  @override
  String get nameMinThreeChars => 'Il nome deve avere almeno 3 caratteri';

  @override
  String get regenerateCodeTitle => 'Rigenera codice';

  @override
  String get regenerateCodeDesc =>
      'Il vecchio codice non funzionerà più. Vuoi generare un nuovo codice invito?';

  @override
  String get regenerateAction => 'Rigenera';

  @override
  String newCodeSnack(String code) {
    return 'Nuovo codice: $code';
  }

  @override
  String get codeCopied => 'Codice copiato!';

  @override
  String groupNowIs(String visibility) {
    return 'Gruppo ora è $visibility';
  }

  @override
  String inviteShareText(String name, String code) {
    return 'Unisciti al gruppo \"$name\" su TrailShare!\n\nUsa il codice invito: $code\n\nScarica TrailShare e inserisci il codice nella sezione Community > Gruppi.';
  }

  @override
  String get inviteShareSubject => 'Invito gruppo TrailShare';

  @override
  String get userLabel => 'Utente';

  @override
  String get leaveGroupTitle => 'Esci dal gruppo';

  @override
  String get deleteGroupMenu => 'Elimina gruppo';

  @override
  String get monthLowerGen => 'gen';

  @override
  String get monthLowerFeb => 'feb';

  @override
  String get monthLowerMar => 'mar';

  @override
  String get monthLowerApr => 'apr';

  @override
  String get monthLowerMag => 'mag';

  @override
  String get monthLowerGiu => 'giu';

  @override
  String get monthLowerLug => 'lug';

  @override
  String get monthLowerAgo => 'ago';

  @override
  String get monthLowerSet => 'set';

  @override
  String get monthLowerOtt => 'ott';

  @override
  String get monthLowerNov => 'nov';

  @override
  String get monthLowerDic => 'dic';

  @override
  String get groupNameHint => 'Es. Escursionisti Orobie';

  @override
  String get enterGroupName => 'Inserisci un nome per il gruppo';

  @override
  String get whatDoesYourGroupDo => 'Cosa fa il vostro gruppo?';

  @override
  String get visibilityLabel => 'Visibilità';

  @override
  String get publicVisibilityDescFull =>
      'Visibile a tutti, chiunque può unirsi';

  @override
  String get privateVisibilityDescFull =>
      'Visibile a tutti, ma serve approvazione admin';

  @override
  String get secretVisibilityDescFull =>
      'Invisibile, accessibile solo tramite codice invito';

  @override
  String get groupCreated => 'Gruppo creato!';

  @override
  String get groupCreationError => 'Errore nella creazione del gruppo';

  @override
  String get eventLabel => 'Evento';

  @override
  String get deletePost => 'Elimina post';

  @override
  String get deletePostConfirm => 'Vuoi eliminare questo post?';

  @override
  String get deleteEvent => 'Elimina evento';

  @override
  String get deleteEventConfirm =>
      'Vuoi eliminare questo evento? L\'azione è irreversibile.';

  @override
  String get changeCover => 'Cambia copertina';

  @override
  String get addCover => 'Aggiungi copertina';

  @override
  String participantsWithMax(String count, String max) {
    return 'Partecipanti ($count/$max)';
  }

  @override
  String participantsOnly(String count) {
    return 'Partecipanti ($count)';
  }

  @override
  String get noParticipantsYet => 'Nessun partecipante ancora';

  @override
  String get enrolledWithdraw => 'Sei iscritto — Ritirati';

  @override
  String get eventFull => 'Evento al completo';

  @override
  String get participate => 'Partecipa';

  @override
  String get updatesLabel => 'Aggiornamenti';

  @override
  String get writeUpdate => 'Scrivi un aggiornamento...';

  @override
  String get addPhoto => 'Aggiungi foto';

  @override
  String get publish => 'Pubblica';

  @override
  String get noUpdates => 'Nessun aggiornamento';

  @override
  String get shareEventPhotos => 'Condividi info, novità o foto dell\'evento!';

  @override
  String get justNow => 'Ora';

  @override
  String minutesAgo(int count) {
    return '$count min fa';
  }

  @override
  String hoursAgo(int count) {
    return '$count ore fa';
  }

  @override
  String daysAgo(int count) {
    return '$count giorni fa';
  }

  @override
  String get concluded => 'Concluso';

  @override
  String organizedBy(String name) {
    return 'Organizzato da $name';
  }

  @override
  String get photoEmoji => '📷 Foto';

  @override
  String get deleteEventMenu => 'Elimina evento';

  @override
  String uploadError(String error) {
    return 'Errore upload: $error';
  }

  @override
  String get monthFullJan => 'Gennaio';

  @override
  String get monthFullFeb => 'Febbraio';

  @override
  String get monthFullMar => 'Marzo';

  @override
  String get monthFullApr => 'Aprile';

  @override
  String get monthFullMay => 'Maggio';

  @override
  String get monthFullJun => 'Giugno';

  @override
  String get monthFullJul => 'Luglio';

  @override
  String get monthFullAug => 'Agosto';

  @override
  String get monthFullSep => 'Settembre';

  @override
  String get monthFullOct => 'Ottobre';

  @override
  String get monthFullNov => 'Novembre';

  @override
  String get monthFullDec => 'Dicembre';

  @override
  String sendImageError(String error) {
    return 'Errore invio immagine: $error';
  }

  @override
  String yesterdayAtTime(String time) {
    return 'Ieri $time';
  }

  @override
  String get upcomingFilter => 'Prossimi';

  @override
  String get allFilter => 'Tutti';

  @override
  String get noEventsTitle => 'Nessun evento';

  @override
  String get organizeAnOuting => 'Organizza un\'uscita!';

  @override
  String get pastLabel => 'Passato';

  @override
  String get withdraw => 'Ritirati';

  @override
  String participantsCountWithMax(String count, String max) {
    return '$count/$max partecipanti';
  }

  @override
  String participantsCountSimple(String count) {
    return '$count partecipanti';
  }

  @override
  String get createFirstGroup => 'Crea il tuo primo gruppo';

  @override
  String get myGroupsTab => 'I miei Gruppi';

  @override
  String get newChallenge => 'Nuova Sfida';

  @override
  String get challengeTitleRequired => 'Titolo sfida *';

  @override
  String get challengeTitleHint => 'Es. Chi fa più km questa settimana?';

  @override
  String get challengeTypeRequired => 'Tipo di sfida *';

  @override
  String get goalRequired => 'Obiettivo *';

  @override
  String get durationRequired => 'Durata *';

  @override
  String get enterValidGoal => 'Inserisci un obiettivo valido';

  @override
  String get launchChallenge => 'Lancia la Sfida!';

  @override
  String get distanceLabel => 'Distanza';

  @override
  String get elevationLabel => 'Dislivello';

  @override
  String get consistencyLabel => 'Costanza';

  @override
  String get distanceDesc => 'Chi percorre più km';

  @override
  String get elevationDesc => 'Chi accumula più metri';

  @override
  String get tracksDesc => 'Chi registra più uscite';

  @override
  String get consistencyDesc => 'Più giorni consecutivi';

  @override
  String get distanceHint => 'Es. 50 (km)';

  @override
  String get elevationHint => 'Es. 2000 (metri)';

  @override
  String get tracksHint => 'Es. 10 (tracce)';

  @override
  String get streakHint => 'Es. 7 (giorni)';

  @override
  String get suffixTracks => 'tracce';

  @override
  String get suffixDays => 'giorni';

  @override
  String get threeDays => '3 giorni';

  @override
  String get oneWeek => '1 settimana';

  @override
  String get twoWeeks => '2 settimane';

  @override
  String get oneMonth => '1 mese';

  @override
  String challengeInfoText(int days) {
    return 'La sfida inizia oggi e dura $days giorni. I progressi vengono calcolati automaticamente dalle tracce registrate.';
  }

  @override
  String get challengeCreatedShort => 'Sfida creata!';

  @override
  String get challengeCreationError => 'Errore nella creazione';

  @override
  String get newEvent => 'Nuovo Evento';

  @override
  String get titleRequired => 'Titolo *';

  @override
  String get eventTitleHint => 'Es. Uscita al Rifugio Vaccaro';

  @override
  String get dateAndTime => 'Data e ora *';

  @override
  String get outingDetails => 'Dettagli sull\'uscita...';

  @override
  String get meetingPoint => 'Punto di ritrovo';

  @override
  String get meetingPointHint => 'Es. Parcheggio Parre centro';

  @override
  String get routeDetails => 'Dettagli percorso';

  @override
  String get difficultyLabel => 'Difficoltà';

  @override
  String get mediumDifficulty => 'Medio';

  @override
  String get expertDifficulty => 'Esperto';

  @override
  String get maxParticipantsLabel => 'Partecipanti massimi';

  @override
  String get notesLabel => 'Note';

  @override
  String get notesHint =>
      'Es. Portare pranzo al sacco, bastoncini consigliati...';

  @override
  String get eventCreatedSnack => 'Evento creato!';

  @override
  String get distanceHintShort => 'Distanza';

  @override
  String get elevationHintShort => 'Dislivello';

  @override
  String get activeFilter => 'Attive';

  @override
  String get allChallengesFilter => 'Tutte';

  @override
  String get noChallenges => 'Nessuna sfida';

  @override
  String get launchGroupChallenge => 'Lancia una sfida al gruppo!';

  @override
  String get lastDay => 'Ultimo giorno!';

  @override
  String daysLeftCount(int count) {
    return '$count giorni';
  }

  @override
  String get concludedFemale => 'Conclusa';

  @override
  String createdByFemale(String name) {
    return 'Creata da $name';
  }

  @override
  String goalColon(String value) {
    return 'Obiettivo: $value';
  }

  @override
  String typeAndGoal(String type, String goal) {
    return '$type • Obiettivo: $goal';
  }

  @override
  String get suffixDaysShort => 'gg';

  @override
  String membersWithCount(int count) {
    return 'Membri ($count)';
  }

  @override
  String get inviteTooltip => 'Invita';

  @override
  String get removeMember => 'Rimuovi membro';

  @override
  String removeMemberConfirm(String name) {
    return 'Vuoi rimuovere $name dal gruppo?';
  }

  @override
  String get removeAction => 'Rimuovi';

  @override
  String get youSuffix => ' (tu)';

  @override
  String get adminWithCrown => '👑 Amministratore';

  @override
  String get allContactsInGroup => 'Tutti i tuoi contatti sono già nel gruppo';

  @override
  String get inviteContact => 'Invita un contatto';

  @override
  String addedToGroup(String name) {
    return '$name aggiunto al gruppo!';
  }

  @override
  String get inviteAction => 'Invita';

  @override
  String get shareTooltip => 'Condividi';

  @override
  String get publishToCommunity => 'Pubblica nella community';

  @override
  String get elevationGainLabel => 'Dislivello +';

  @override
  String photosCount(int count) {
    return '📸 $count foto';
  }

  @override
  String get publishedBadge => 'Pubblica';

  @override
  String get dateLabel => 'Data';

  @override
  String get gpsPoints => 'Punti GPS';

  @override
  String get maxElevation => 'Quota max';

  @override
  String get minElevation => 'Quota min';

  @override
  String get caloriesLabel => 'Calorie';

  @override
  String get stepsLabel => 'Passi';

  @override
  String get activityLabel => 'Attività';

  @override
  String get changeActivity => 'Cambia attività';

  @override
  String get onFoot => 'A piedi';

  @override
  String get byBicycle => 'In bicicletta';

  @override
  String get winterSports => 'Sport invernali';

  @override
  String get nameLabel => 'Nome';

  @override
  String get addDescription => 'Aggiungi una descrizione...';

  @override
  String get nameCannotBeEmpty => 'Il nome non può essere vuoto';

  @override
  String get trackUpdated => '✅ Traccia aggiornata!';

  @override
  String get publishToCommunityTitle => 'Pubblica nella community';

  @override
  String get publishCommunityDesc =>
      'La tua traccia sarà visibile a tutti gli utenti nella sezione \"Scopri\".';

  @override
  String get publishAction => 'Pubblica';

  @override
  String get heartRateTitle => 'Dati battito cardiaco';

  @override
  String get searchHRFromWatch =>
      'Tocca per cercare dati HR dal tuo smartwatch';

  @override
  String get searchingHR => '🔍 Ricerca dati battito cardiaco...';

  @override
  String hrSamplesFound(int count) {
    return '❤️ $count campioni HR trovati!';
  }

  @override
  String get noHRFound =>
      'Nessun dato HR trovato. Assicurati che il tuo smartwatch abbia sincronizzato con Health Connect.';

  @override
  String get hrRetrievalError => 'Errore nel recupero dati HR';

  @override
  String get mustBeLoggedIn => 'Devi essere loggato';

  @override
  String get trackPublished => '✅ Traccia pubblicata nella community!';

  @override
  String get publishFailed => 'Pubblicazione fallita';

  @override
  String get unpublishTitle => 'Rimuovi dalla community';

  @override
  String get unpublishDesc =>
      'La traccia non sarà più visibile nella sezione \"Scopri\". Puoi ripubblicarla in qualsiasi momento.';

  @override
  String get trackUnpublished => 'Traccia rimossa dalla community';

  @override
  String get deleteTrackTitle => 'Elimina traccia';

  @override
  String get deleteTrackIrreversible =>
      'Questa azione è irreversibile. La traccia verrà eliminata definitivamente.';

  @override
  String get downloadTooltip => 'Scarica';

  @override
  String get quotaLabel => 'Quota';

  @override
  String get positionLabel => 'Posizione';

  @override
  String get timeLabel => 'Tempo';

  @override
  String get photoInfo => 'Informazioni Foto';

  @override
  String get latitudeLabel => 'Latitudine';

  @override
  String get longitudeLabel => 'Longitudine';

  @override
  String photoFrom(String name) {
    return 'Foto da $name';
  }

  @override
  String get downloadError => 'Errore download';

  @override
  String get errorLabel => 'Errore';

  @override
  String get editMenu => 'Modifica';

  @override
  String get detailsHeader => 'Dettagli';

  @override
  String get durationStatLabel => 'Durata';

  @override
  String activityChangedTo(String name) {
    return 'Attività cambiata in $name';
  }

  @override
  String get publishDialogContent =>
      'La tua traccia sarà visibile a tutti gli utenti nella sezione \"Scopri\".';

  @override
  String get heartRateDataTitle => 'Dati battito cardiaco';

  @override
  String get tapToSearchHR => 'Tocca per cercare dati HR dal tuo smartwatch';

  @override
  String get noHRData =>
      'Nessun dato HR trovato. Assicurati che il tuo smartwatch abbia sincronizzato con Health Connect.';

  @override
  String get unpublishContent =>
      'La traccia non sarà più visibile nella sezione \"Scopri\". Puoi ripubblicarla in qualsiasi momento.';

  @override
  String get deleteTrackContent =>
      'Questa azione è irreversibile. La traccia verrà eliminata definitivamente.';

  @override
  String get elevationLossLabel => 'Dislivello -';

  @override
  String get photoInfoTitle => 'Informazioni Foto';

  @override
  String get dateInfoLabel => 'Data';

  @override
  String get timeInfoLabel => 'Ora';

  @override
  String get elevationQuotaLabel => 'Quota';

  @override
  String get captionLabel => 'Descrizione';

  @override
  String get quotaMetadata => 'Quota';

  @override
  String get positionMetadata => 'Posizione';

  @override
  String get timeMetadata => 'Ora';

  @override
  String get listTab => 'Lista';

  @override
  String get planTab => 'Pianifica';

  @override
  String get loginToSeeTracks => 'Effettua il login per vedere le tue tracce';

  @override
  String loadingErrorWithDetails(String error) {
    return 'Errore caricamento: $error';
  }

  @override
  String get noTracksSaved => 'Nessuna traccia salvata';

  @override
  String get startRecordingAdventures =>
      'Inizia a registrare le tue avventure!';

  @override
  String get loginToPlan => 'Accedi per pianificare tracce';

  @override
  String get mapAction => 'Mappa';

  @override
  String deleteTrackConfirmName(String name) {
    return 'Sei sicuro di voler eliminare \"$name\"?';
  }

  @override
  String get plannedBadge => 'PIANIFICATA';

  @override
  String todayAtTime(String time) {
    return 'Oggi $time';
  }

  @override
  String get cannotReadFile =>
      'Impossibile leggere il file. Verifica che sia un file GPX o FIT valido.';

  @override
  String get cannotReadGpx =>
      'Impossibile leggere il file GPX. Verifica che sia un file valido.';

  @override
  String get importGpxTitle => 'Importa un file GPX';

  @override
  String get selectGpxFromDevice =>
      'Seleziona un file .gpx dal tuo dispositivo';

  @override
  String get selectGpxFile => 'Seleziona file GPX';

  @override
  String get activityTypeLabel => 'Tipo di attività';

  @override
  String get changeFile => 'Cambia';

  @override
  String get trackImported => '✅ Traccia importata con successo!';

  @override
  String saveErrorWithDetails(String error) {
    return 'Errore salvataggio: $error';
  }

  @override
  String get noGpsData => 'Nessun dato GPS';

  @override
  String get elevationGainShort => 'Dislivello';

  @override
  String get cannotCalculateRoute =>
      'Impossibile calcolare il percorso. Riprova.';

  @override
  String get addAtLeast2Points => 'Aggiungi almeno 2 punti al percorso';

  @override
  String get loginToSave => 'Devi effettuare il login per salvare';

  @override
  String get routeSaved => 'Percorso salvato! 🎉';

  @override
  String get tapMapToStart => 'Tocca la mappa per iniziare';

  @override
  String waypointCount(int count) {
    return '$count punti';
  }

  @override
  String get waypointSingle => '1 punto';

  @override
  String get longPressToRemove => 'Tieni premuto per rimuovere';

  @override
  String get addPointsToCreate => 'Aggiungi punti per creare un percorso';

  @override
  String get calculatingRouteHiking => 'Calcolo percorso hiking...';

  @override
  String get calculatingRouteCycling => 'Calcolo percorso cycling...';

  @override
  String get ascentLabel => 'Salita';

  @override
  String get descentLabel => 'Discesa';

  @override
  String get timeEstLabel => 'Tempo';

  @override
  String get clearRoute => 'Cancella percorso';

  @override
  String get clearRouteConfirm => 'Vuoi cancellare tutti i punti?';

  @override
  String get clearAction => 'Cancella';

  @override
  String get saveRoute => 'Salva percorso';

  @override
  String get routeName => 'Nome percorso';

  @override
  String get enterAName => 'Inserisci un nome';

  @override
  String get hikeDefaultName => 'Escursione';

  @override
  String get bikeDefaultName => 'Giro in bici';

  @override
  String get recordLabel => 'Registra';

  @override
  String get tracksNavLabel => 'Tracce';

  @override
  String discoverWithCount(int count) {
    return 'Scopri ($count)';
  }

  @override
  String get loadingTrails => 'Caricamento sentieri...';

  @override
  String trailsUpdating(int count) {
    return '$count sentieri · Aggiornamento...';
  }

  @override
  String trailsZoomForDetails(int count) {
    return '$count sentieri (zoom per dettagli)';
  }

  @override
  String get moveMapToExplore => 'Sposta la mappa per esplorare i sentieri';

  @override
  String trailsInArea(int count) {
    return '$count sentieri in questa zona';
  }

  @override
  String get positionBtn => '📍 Posizione';

  @override
  String noResultsFor(String query) {
    return 'Nessun risultato per \"$query\"';
  }

  @override
  String get trailsLabel => 'sentieri';

  @override
  String get noTrailInArea => 'Nessun sentiero in questa zona';

  @override
  String get moveOrZoomMap =>
      'Sposta o zooma la mappa per esplorare altre aree';

  @override
  String get trailFallback => 'Sentiero';

  @override
  String get circularBadge => 'Circolare';

  @override
  String sharedOnDate(String date) {
    return 'Condiviso il $date';
  }

  @override
  String photosWithCount(int count) {
    return 'Foto ($count)';
  }

  @override
  String get detailsLabel => 'Dettagli';

  @override
  String get sourceLabel => 'Fonte';

  @override
  String get communitySource => 'Community';

  @override
  String get exporting => 'Esportazione...';

  @override
  String get downloadGpx => 'Scarica GPX';

  @override
  String get alreadyPromoted => 'Già promossa a Sentiero ✓';

  @override
  String get promotionInProgress => 'Promozione in corso...';

  @override
  String get promoteToTrail => 'Promuovi a Sentiero';

  @override
  String get promoteDialogDescription =>
      'Questa traccia verrà aggiunta ai sentieri pubblici e sarà visibile a tutti gli utenti nella sezione Scopri.';

  @override
  String get authorLabel => 'Autore';

  @override
  String get fewGpsPointsWarning =>
      'Pochi punti GPS — la traccia potrebbe essere imprecisa';

  @override
  String get promote => 'Promuovi';

  @override
  String get trackPromotedSuccess => '✅ Traccia promossa a sentiero pubblico!';

  @override
  String get promotionFailed => 'Promozione fallita';

  @override
  String get noGpsPointsToExport => 'Nessun punto GPS da esportare';

  @override
  String gpxTrackName(String name) {
    return 'Traccia GPX: $name';
  }

  @override
  String get gpxExported => '✅ GPX esportato!';

  @override
  String get cannotLoadImage => 'Impossibile caricare l\'immagine';

  @override
  String get hikePhoto => 'Foto escursione';

  @override
  String get lengthLabel => 'Lunghezza';

  @override
  String get informationLabel => 'Informazioni';

  @override
  String get trailNumber => 'Numero sentiero';

  @override
  String get managerLabel => 'Gestore';

  @override
  String get networkLabel => 'Rete';

  @override
  String get regionLabel => 'Regione';

  @override
  String get openStreetMapSource => 'OpenStreetMap';

  @override
  String get followTrail => 'Segui la traccia';

  @override
  String get navigateToStart => 'Naviga al punto di partenza';

  @override
  String get deleteTrailTitle => 'Elimina sentiero';

  @override
  String get deleteTrailConfirmIntro => 'Stai per eliminare definitivamente:';

  @override
  String get deleteTrailIrreversible =>
      'Questa azione è irreversibile e rimuoverà il sentiero dalla mappa per tutti gli utenti.';

  @override
  String trailDeletedName(String name) {
    return '✅ \"$name\" eliminato';
  }

  @override
  String deleteErrorWithDetails(String error) {
    return 'Errore eliminazione: $error';
  }

  @override
  String get loadingTrailWait => 'Caricamento traccia in corso, attendi...';

  @override
  String get loadingRetryLater =>
      'Caricamento in corso, riprova tra un momento...';

  @override
  String trailGpxName(String name) {
    return 'Sentiero GPX: $name';
  }

  @override
  String cannotOpenNavigation(String error) {
    return 'Impossibile aprire la navigazione: $error';
  }

  @override
  String get gpsDisabled => 'GPS disattivato';

  @override
  String get gpsPermDenied => 'Permesso GPS negato';

  @override
  String get gpsPermDeniedPermanently => 'Permesso GPS negato permanentemente';

  @override
  String get gpsError => 'Errore GPS';

  @override
  String get navigationActive => 'Navigazione attiva';

  @override
  String get waitingForGps => 'In attesa del GPS...';

  @override
  String get soundAlertEnabled => '🔊 Allarme sonoro attivato';

  @override
  String get soundAlertDisabled => '🔇 Allarme sonoro disattivato';

  @override
  String severeOffTrailDistance(String distance) {
    return 'Sei a ${distance}m dalla traccia!';
  }

  @override
  String offTrailDistance(String distance) {
    return 'Fuori traccia (${distance}m)';
  }

  @override
  String get arrivedAtEnd => 'Sei arrivato alla fine del sentiero! 🎉';

  @override
  String get seeFullTrail => 'Vedi tutta la traccia';

  @override
  String get centerOnMe => 'Centra su di me';

  @override
  String percentCompleted(String percent) {
    return '$percent% completato';
  }

  @override
  String get remainingLabel => 'Restante';

  @override
  String get altitudeLabel => 'Quota';

  @override
  String get fromTrailLabel => 'Dalla traccia';

  @override
  String get activeRecording => 'Registrazione attiva';

  @override
  String recordedPointsInfo(int count, String duration) {
    return 'Hai registrato $count punti in $duration.\nCosa vuoi fare?';
  }

  @override
  String get saveAndExit => 'Salva ed esci';

  @override
  String get discardAndExit => 'Scarta ed esci';

  @override
  String get stopNavigation => 'Interrompere navigazione?';

  @override
  String get stopFollowingQuestion =>
      'Vuoi smettere di seguire questa traccia?';

  @override
  String get tooFewPointsToSave => 'Troppo pochi punti per salvare';

  @override
  String get mustBeLoggedToSave => 'Devi essere loggato per salvare';

  @override
  String get discardRecording => 'Scartare registrazione?';

  @override
  String recordedPointsDiscard(int count) {
    return 'Hai registrato $count punti. Vuoi scartarli?';
  }

  @override
  String get noSave => 'No, salva';

  @override
  String get discardAction => 'Scarta';

  @override
  String trackSavedWithCount(String name, int count) {
    return '✅ Traccia \"$name\" salvata! ($count punti)';
  }

  @override
  String get saveTrackTitle => 'Salva traccia';

  @override
  String get pointsLabel => 'Punti';

  @override
  String get sessionNotFound => 'Sessione non trovata o scaduta';

  @override
  String get inLive => 'IN DIRETTA';

  @override
  String get ended => 'TERMINATA';

  @override
  String lastSignal(String time) {
    return 'Ultimo segnale: $time';
  }

  @override
  String get goBack => 'Torna indietro';

  @override
  String get recordingFound => 'Registrazione trovata';

  @override
  String get unsavedRecordingFound =>
      'È stata trovata una registrazione non salvata:';

  @override
  String get wantToRecover => 'Vuoi recuperarla?';

  @override
  String get recover => 'Recupera';

  @override
  String gpsPointsCount(int count) {
    return '📍 $count punti GPS';
  }

  @override
  String recoveredGpsPoints(int count) {
    return '✅ Recuperati $count punti GPS';
  }

  @override
  String get lowBatteryWarning =>
      '⚠️ Batteria bassa! La traccia verrà salvata automaticamente al 5%';

  @override
  String get criticalBatteryWarning =>
      '🔋 Batteria critica! Salvataggio traccia in corso...';

  @override
  String get autoSaved => '(auto-salvato)';

  @override
  String get trackAutoSaved => '✅ Traccia salvata automaticamente!';

  @override
  String uploadingPhotos(int count) {
    return 'Upload di $count foto...';
  }

  @override
  String get restoringRecording => 'Ripristino registrazione...';

  @override
  String get gpsNotAvailable => 'GPS non disponibile';

  @override
  String get photoAdded => '📸 Foto aggiunta!';

  @override
  String photosAdded(int count) {
    return '📸 $count foto aggiunte!';
  }

  @override
  String get photoDeleted => 'Foto eliminata';

  @override
  String get takePhoto => 'Scatta foto';

  @override
  String get pickFromGallery => 'Scegli dalla galleria';

  @override
  String get cancelRecording => 'Annullare registrazione?';

  @override
  String get trackDataWillBeLost =>
      'I dati della traccia corrente verranno persi.';

  @override
  String trackAndPhotosWillBeLost(int count) {
    return 'I dati della traccia e le $count foto verranno persi.';
  }

  @override
  String get noPointsRecorded => 'Nessun punto registrato';

  @override
  String get stopRecordingError => 'Errore nel fermare la registrazione';

  @override
  String photosNotUploaded(int count) {
    return '⚠️ $count foto non caricate';
  }

  @override
  String get paused => 'IN PAUSA';

  @override
  String get speedLabel => 'Vel.';

  @override
  String get avgSpeedLabel => 'Media';

  @override
  String get paceLabel => 'Passo';

  @override
  String get cancelLabel => 'Annulla';

  @override
  String get pauseLabel => 'Pausa';

  @override
  String get resumeLabel => 'Riprendi';

  @override
  String get saveLabel => 'Salva';

  @override
  String get motivational1 => 'Ottimo lavoro! 💪';

  @override
  String get motivational2 => 'Grande escursione! 🏔️';

  @override
  String get motivational3 => 'Fantastico percorso! 🥾';

  @override
  String get motivational4 => 'Che avventura! 🌟';

  @override
  String get motivational5 => 'Sei un vero esploratore! 🧭';

  @override
  String get motivational6 => 'Trail completato! 🎯';

  @override
  String get motivational7 => 'Complimenti, continua così! 🔥';

  @override
  String get metersDPlus => 'm D+';

  @override
  String get continueBtn => 'Continua';

  @override
  String get chooseActivity => 'Scegli attività';

  @override
  String get byCycle => 'In bicicletta';

  @override
  String get photosLabel => 'Foto';

  @override
  String get savedTracks => 'Percorsi Salvati';

  @override
  String get removeFromSaved => 'Rimuovi dai salvati';

  @override
  String get removeTrackQuestion =>
      'Vuoi rimuovere questo percorso dalla tua lista?';

  @override
  String get removeLabel => 'Rimuovi';

  @override
  String get trackRemovedFromSaved => 'Percorso rimosso dai salvati';

  @override
  String get loginToSeeSaved => 'Accedi per vedere i tuoi percorsi salvati';

  @override
  String get saveTracksHint =>
      'Salva i percorsi che ti interessano per ritrovarli facilmente!';

  @override
  String get loadingError => 'Errore nel caricamento';

  @override
  String get noSavedTracks => 'Nessun percorso salvato';

  @override
  String get exploreSavedHint =>
      'Esplora la sezione \"Scopri\" e salva i percorsi che ti interessano!';

  @override
  String get goToDiscover => 'Vai a Scopri';

  @override
  String get userFallback => 'Utente';

  @override
  String get gpsAccessError =>
      'Impossibile accedere al GPS. Verifica i permessi.';

  @override
  String get gpsResumeError => 'Impossibile riprendere il GPS.';

  @override
  String get locationDisclosureTitle => 'Accesso alla posizione';

  @override
  String get locationDisclosureBody =>
      'TrailShare utilizza la tua posizione per:\n\n• Registrare le tracce GPS delle tue attività outdoor (escursioni, corsa, ciclismo)\n• Mostrarti i sentieri e i punti di interesse vicini a te\n• Fornire statistiche accurate su distanza, velocità e percorso\n• Permettere il tracciamento in background durante la registrazione per garantire la continuità del percorso anche con lo schermo spento\n\nLa tua posizione non viene condivisa con terze parti, salvo quando scegli volontariamente di pubblicare una traccia nella community.';

  @override
  String get locationDisclosureDecline => 'Non ora';

  @override
  String get locationDisclosureAccept => 'Ho capito, continua';
}
