import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_it.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('it'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In it, this message translates to:
  /// **'TrailShare'**
  String get appTitle;

  /// No description provided for @save.
  ///
  /// In it, this message translates to:
  /// **'Salva'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In it, this message translates to:
  /// **'Elimina'**
  String get delete;

  /// No description provided for @confirm.
  ///
  /// In it, this message translates to:
  /// **'Conferma'**
  String get confirm;

  /// No description provided for @edit.
  ///
  /// In it, this message translates to:
  /// **'Modifica'**
  String get edit;

  /// No description provided for @create.
  ///
  /// In it, this message translates to:
  /// **'Crea'**
  String get create;

  /// No description provided for @add.
  ///
  /// In it, this message translates to:
  /// **'Aggiungi'**
  String get add;

  /// No description provided for @send.
  ///
  /// In it, this message translates to:
  /// **'Invia'**
  String get send;

  /// No description provided for @search.
  ///
  /// In it, this message translates to:
  /// **'Cerca'**
  String get search;

  /// No description provided for @share.
  ///
  /// In it, this message translates to:
  /// **'Condividi'**
  String get share;

  /// No description provided for @close.
  ///
  /// In it, this message translates to:
  /// **'Chiudi'**
  String get close;

  /// No description provided for @back.
  ///
  /// In it, this message translates to:
  /// **'Indietro'**
  String get back;

  /// No description provided for @next.
  ///
  /// In it, this message translates to:
  /// **'Avanti'**
  String get next;

  /// No description provided for @done.
  ///
  /// In it, this message translates to:
  /// **'Fatto'**
  String get done;

  /// No description provided for @yes.
  ///
  /// In it, this message translates to:
  /// **'Sì'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In it, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @ok.
  ///
  /// In it, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @loading.
  ///
  /// In it, this message translates to:
  /// **'Caricamento...'**
  String get loading;

  /// No description provided for @retry.
  ///
  /// In it, this message translates to:
  /// **'Riprova'**
  String get retry;

  /// No description provided for @error.
  ///
  /// In it, this message translates to:
  /// **'Errore'**
  String get error;

  /// No description provided for @success.
  ///
  /// In it, this message translates to:
  /// **'Successo'**
  String get success;

  /// No description provided for @warning.
  ///
  /// In it, this message translates to:
  /// **'Attenzione'**
  String get warning;

  /// No description provided for @select.
  ///
  /// In it, this message translates to:
  /// **'Seleziona'**
  String get select;

  /// No description provided for @copy.
  ///
  /// In it, this message translates to:
  /// **'Copia'**
  String get copy;

  /// No description provided for @continueAction.
  ///
  /// In it, this message translates to:
  /// **'Continua'**
  String get continueAction;

  /// No description provided for @distance.
  ///
  /// In it, this message translates to:
  /// **'Distanza'**
  String get distance;

  /// No description provided for @elevation.
  ///
  /// In it, this message translates to:
  /// **'Dislivello'**
  String get elevation;

  /// No description provided for @elevationGain.
  ///
  /// In it, this message translates to:
  /// **'Dislivello+'**
  String get elevationGain;

  /// No description provided for @elevationLoss.
  ///
  /// In it, this message translates to:
  /// **'Dislivello-'**
  String get elevationLoss;

  /// No description provided for @duration.
  ///
  /// In it, this message translates to:
  /// **'Durata'**
  String get duration;

  /// No description provided for @speed.
  ///
  /// In it, this message translates to:
  /// **'Velocità'**
  String get speed;

  /// No description provided for @avgSpeed.
  ///
  /// In it, this message translates to:
  /// **'Vel. media'**
  String get avgSpeed;

  /// No description provided for @maxSpeed.
  ///
  /// In it, this message translates to:
  /// **'Vel. max'**
  String get maxSpeed;

  /// No description provided for @pace.
  ///
  /// In it, this message translates to:
  /// **'Passo'**
  String get pace;

  /// No description provided for @altitude.
  ///
  /// In it, this message translates to:
  /// **'Altitudine'**
  String get altitude;

  /// No description provided for @maxAltitude.
  ///
  /// In it, this message translates to:
  /// **'Alt. max'**
  String get maxAltitude;

  /// No description provided for @minAltitude.
  ///
  /// In it, this message translates to:
  /// **'Alt. min'**
  String get minAltitude;

  /// No description provided for @totalDistance.
  ///
  /// In it, this message translates to:
  /// **'Distanza totale'**
  String get totalDistance;

  /// No description provided for @totalElevation.
  ///
  /// In it, this message translates to:
  /// **'Dislivello totale'**
  String get totalElevation;

  /// No description provided for @activity.
  ///
  /// In it, this message translates to:
  /// **'Attività'**
  String get activity;

  /// No description provided for @activityChanged.
  ///
  /// In it, this message translates to:
  /// **'Attività cambiata in {type}'**
  String activityChanged(String type);

  /// No description provided for @details.
  ///
  /// In it, this message translates to:
  /// **'Dettagli'**
  String get details;

  /// No description provided for @statistics.
  ///
  /// In it, this message translates to:
  /// **'Statistiche'**
  String get statistics;

  /// No description provided for @statsPerKm.
  ///
  /// In it, this message translates to:
  /// **'Statistiche per Km'**
  String get statsPerKm;

  /// No description provided for @photos.
  ///
  /// In it, this message translates to:
  /// **'Foto'**
  String get photos;

  /// No description provided for @map.
  ///
  /// In it, this message translates to:
  /// **'Mappa'**
  String get map;

  /// No description provided for @track.
  ///
  /// In it, this message translates to:
  /// **'Traccia'**
  String get track;

  /// No description provided for @tracks.
  ///
  /// In it, this message translates to:
  /// **'Tracce'**
  String get tracks;

  /// No description provided for @myTracks.
  ///
  /// In it, this message translates to:
  /// **'Le mie tracce'**
  String get myTracks;

  /// No description provided for @noTracks.
  ///
  /// In it, this message translates to:
  /// **'Nessuna traccia salvata'**
  String get noTracks;

  /// No description provided for @trackSaved.
  ///
  /// In it, this message translates to:
  /// **'Traccia salvata!'**
  String get trackSaved;

  /// No description provided for @trackDeleted.
  ///
  /// In it, this message translates to:
  /// **'Traccia eliminata'**
  String get trackDeleted;

  /// No description provided for @saveTrack.
  ///
  /// In it, this message translates to:
  /// **'Salva traccia'**
  String get saveTrack;

  /// No description provided for @savingTrack.
  ///
  /// In it, this message translates to:
  /// **'Salvataggio traccia...'**
  String get savingTrack;

  /// No description provided for @editTrack.
  ///
  /// In it, this message translates to:
  /// **'Modifica traccia'**
  String get editTrack;

  /// No description provided for @deleteTrack.
  ///
  /// In it, this message translates to:
  /// **'Elimina traccia'**
  String get deleteTrack;

  /// No description provided for @deleteTrackConfirm.
  ///
  /// In it, this message translates to:
  /// **'Vuoi eliminare questa traccia? L\'azione è irreversibile.'**
  String get deleteTrackConfirm;

  /// No description provided for @publishTrack.
  ///
  /// In it, this message translates to:
  /// **'Pubblica nella community'**
  String get publishTrack;

  /// No description provided for @removeFromCommunity.
  ///
  /// In it, this message translates to:
  /// **'Rimuovi dalla community'**
  String get removeFromCommunity;

  /// No description provided for @published.
  ///
  /// In it, this message translates to:
  /// **'Pubblica'**
  String get published;

  /// No description provided for @trackName.
  ///
  /// In it, this message translates to:
  /// **'Nome traccia'**
  String get trackName;

  /// No description provided for @noName.
  ///
  /// In it, this message translates to:
  /// **'Senza nome'**
  String get noName;

  /// No description provided for @exportGpx.
  ///
  /// In it, this message translates to:
  /// **'Esporta GPX'**
  String get exportGpx;

  /// No description provided for @exportError.
  ///
  /// In it, this message translates to:
  /// **'Errore export: {error}'**
  String exportError(String error);

  /// No description provided for @importGpx.
  ///
  /// In it, this message translates to:
  /// **'Importa GPX'**
  String get importGpx;

  /// No description provided for @planRoute.
  ///
  /// In it, this message translates to:
  /// **'Pianifica percorso'**
  String get planRoute;

  /// No description provided for @plannedRoutes.
  ///
  /// In it, this message translates to:
  /// **'Percorsi pianificati'**
  String get plannedRoutes;

  /// No description provided for @recording.
  ///
  /// In it, this message translates to:
  /// **'Registrazione'**
  String get recording;

  /// No description provided for @startRecording.
  ///
  /// In it, this message translates to:
  /// **'Inizia registrazione'**
  String get startRecording;

  /// No description provided for @stopRecording.
  ///
  /// In it, this message translates to:
  /// **'Ferma registrazione'**
  String get stopRecording;

  /// No description provided for @pauseRecording.
  ///
  /// In it, this message translates to:
  /// **'Pausa'**
  String get pauseRecording;

  /// No description provided for @resumeRecording.
  ///
  /// In it, this message translates to:
  /// **'Riprendi'**
  String get resumeRecording;

  /// No description provided for @criticalBattery.
  ///
  /// In it, this message translates to:
  /// **'Batteria critica! Salvataggio traccia in corso...'**
  String get criticalBattery;

  /// No description provided for @gpsSignalLost.
  ///
  /// In it, this message translates to:
  /// **'Segnale GPS perso'**
  String get gpsSignalLost;

  /// No description provided for @gpsSignalWeak.
  ///
  /// In it, this message translates to:
  /// **'Segnale GPS debole'**
  String get gpsSignalWeak;

  /// No description provided for @recordingInProgress.
  ///
  /// In it, this message translates to:
  /// **'Registrazione in corso'**
  String get recordingInProgress;

  /// No description provided for @login.
  ///
  /// In it, this message translates to:
  /// **'Accedi'**
  String get login;

  /// No description provided for @register.
  ///
  /// In it, this message translates to:
  /// **'Registrati'**
  String get register;

  /// No description provided for @logout.
  ///
  /// In it, this message translates to:
  /// **'Esci'**
  String get logout;

  /// No description provided for @email.
  ///
  /// In it, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In it, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @confirmPassword.
  ///
  /// In it, this message translates to:
  /// **'Conferma password'**
  String get confirmPassword;

  /// No description provided for @forgotPassword.
  ///
  /// In it, this message translates to:
  /// **'Password dimenticata?'**
  String get forgotPassword;

  /// No description provided for @loginWith.
  ///
  /// In it, this message translates to:
  /// **'Accedi con {provider}'**
  String loginWith(String provider);

  /// No description provided for @trackYourAdventures.
  ///
  /// In it, this message translates to:
  /// **'Traccia le tue avventure'**
  String get trackYourAdventures;

  /// No description provided for @or.
  ///
  /// In it, this message translates to:
  /// **'oppure'**
  String get or;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In it, this message translates to:
  /// **'Hai già un account?'**
  String get alreadyHaveAccount;

  /// No description provided for @noAccount.
  ///
  /// In it, this message translates to:
  /// **'Non hai un account?'**
  String get noAccount;

  /// No description provided for @registerNow.
  ///
  /// In it, this message translates to:
  /// **'Registrati ora'**
  String get registerNow;

  /// No description provided for @username.
  ///
  /// In it, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @chooseUsername.
  ///
  /// In it, this message translates to:
  /// **'Scegli il tuo username'**
  String get chooseUsername;

  /// No description provided for @usernameHint.
  ///
  /// In it, this message translates to:
  /// **'Come vuoi essere chiamato?'**
  String get usernameHint;

  /// No description provided for @usernameRequired.
  ///
  /// In it, this message translates to:
  /// **'L\'username è obbligatorio'**
  String get usernameRequired;

  /// No description provided for @usernameTooShort.
  ///
  /// In it, this message translates to:
  /// **'Almeno 3 caratteri'**
  String get usernameTooShort;

  /// No description provided for @usernameAlreadyTaken.
  ///
  /// In it, this message translates to:
  /// **'Username già in uso'**
  String get usernameAlreadyTaken;

  /// No description provided for @profile.
  ///
  /// In it, this message translates to:
  /// **'Profilo'**
  String get profile;

  /// No description provided for @editProfile.
  ///
  /// In it, this message translates to:
  /// **'Modifica profilo'**
  String get editProfile;

  /// No description provided for @bio.
  ///
  /// In it, this message translates to:
  /// **'Bio'**
  String get bio;

  /// No description provided for @level.
  ///
  /// In it, this message translates to:
  /// **'Livello'**
  String get level;

  /// No description provided for @followers.
  ///
  /// In it, this message translates to:
  /// **'Follower'**
  String get followers;

  /// No description provided for @following.
  ///
  /// In it, this message translates to:
  /// **'Seguiti'**
  String get following;

  /// No description provided for @follow.
  ///
  /// In it, this message translates to:
  /// **'Segui'**
  String get follow;

  /// No description provided for @unfollow.
  ///
  /// In it, this message translates to:
  /// **'Non seguire più'**
  String get unfollow;

  /// No description provided for @noFollowers.
  ///
  /// In it, this message translates to:
  /// **'Nessun follower'**
  String get noFollowers;

  /// No description provided for @noFollowing.
  ///
  /// In it, this message translates to:
  /// **'Non segui nessuno'**
  String get noFollowing;

  /// No description provided for @followersCount.
  ///
  /// In it, this message translates to:
  /// **'{count} follower'**
  String followersCount(int count);

  /// No description provided for @followingCount.
  ///
  /// In it, this message translates to:
  /// **'{count} seguiti'**
  String followingCount(int count);

  /// No description provided for @shareProfile.
  ///
  /// In it, this message translates to:
  /// **'Condividi le tue escursioni per farti conoscere!'**
  String get shareProfile;

  /// No description provided for @discover.
  ///
  /// In it, this message translates to:
  /// **'Scopri'**
  String get discover;

  /// No description provided for @searchTrails.
  ///
  /// In it, this message translates to:
  /// **'Cerca sentieri...'**
  String get searchTrails;

  /// No description provided for @noTrailsInArea.
  ///
  /// In it, this message translates to:
  /// **'Nessun sentiero in questa zona'**
  String get noTrailsInArea;

  /// No description provided for @loadingFullTrack.
  ///
  /// In it, this message translates to:
  /// **'Caricamento traccia completa...'**
  String get loadingFullTrack;

  /// No description provided for @trailDetails.
  ///
  /// In it, this message translates to:
  /// **'Dettagli sentiero'**
  String get trailDetails;

  /// No description provided for @deleteTrailAdmin.
  ///
  /// In it, this message translates to:
  /// **'Elimina sentiero (Admin)'**
  String get deleteTrailAdmin;

  /// No description provided for @difficulty.
  ///
  /// In it, this message translates to:
  /// **'Difficoltà'**
  String get difficulty;

  /// No description provided for @easy.
  ///
  /// In it, this message translates to:
  /// **'Facile'**
  String get easy;

  /// No description provided for @moderate.
  ///
  /// In it, this message translates to:
  /// **'Moderato'**
  String get moderate;

  /// No description provided for @hard.
  ///
  /// In it, this message translates to:
  /// **'Difficile'**
  String get hard;

  /// No description provided for @community.
  ///
  /// In it, this message translates to:
  /// **'Community'**
  String get community;

  /// No description provided for @communityTracks.
  ///
  /// In it, this message translates to:
  /// **'Tracce community'**
  String get communityTracks;

  /// No description provided for @discoverGroups.
  ///
  /// In it, this message translates to:
  /// **'Scopri gruppi'**
  String get discoverGroups;

  /// No description provided for @suggestedUsers.
  ///
  /// In it, this message translates to:
  /// **'Persone che potresti conoscere'**
  String get suggestedUsers;

  /// No description provided for @searchUsers.
  ///
  /// In it, this message translates to:
  /// **'Cerca utenti'**
  String get searchUsers;

  /// No description provided for @searchUsersHint.
  ///
  /// In it, this message translates to:
  /// **'Cerca utenti con la barra in alto'**
  String get searchUsersHint;

  /// No description provided for @noSuggestions.
  ///
  /// In it, this message translates to:
  /// **'Nessun suggerimento al momento'**
  String get noSuggestions;

  /// No description provided for @noResults.
  ///
  /// In it, this message translates to:
  /// **'Nessun risultato'**
  String get noResults;

  /// No description provided for @groups.
  ///
  /// In it, this message translates to:
  /// **'Gruppi'**
  String get groups;

  /// No description provided for @myGroups.
  ///
  /// In it, this message translates to:
  /// **'I miei gruppi'**
  String get myGroups;

  /// No description provided for @group.
  ///
  /// In it, this message translates to:
  /// **'Gruppo'**
  String get group;

  /// No description provided for @createGroup.
  ///
  /// In it, this message translates to:
  /// **'Crea gruppo'**
  String get createGroup;

  /// No description provided for @joinGroup.
  ///
  /// In it, this message translates to:
  /// **'Unisciti'**
  String get joinGroup;

  /// No description provided for @leaveGroup.
  ///
  /// In it, this message translates to:
  /// **'Lascia gruppo'**
  String get leaveGroup;

  /// No description provided for @deleteGroup.
  ///
  /// In it, this message translates to:
  /// **'Elimina gruppo'**
  String get deleteGroup;

  /// No description provided for @deleteGroupConfirm.
  ///
  /// In it, this message translates to:
  /// **'Vuoi eliminare questo gruppo? L\'azione è irreversibile.'**
  String get deleteGroupConfirm;

  /// No description provided for @groupName.
  ///
  /// In it, this message translates to:
  /// **'Nome del gruppo'**
  String get groupName;

  /// No description provided for @groupDescription.
  ///
  /// In it, this message translates to:
  /// **'Descrizione del gruppo'**
  String get groupDescription;

  /// No description provided for @members.
  ///
  /// In it, this message translates to:
  /// **'Membri'**
  String get members;

  /// No description provided for @membersCount.
  ///
  /// In it, this message translates to:
  /// **'{count} membri'**
  String membersCount(int count);

  /// No description provided for @admin.
  ///
  /// In it, this message translates to:
  /// **'Admin'**
  String get admin;

  /// No description provided for @inviteCode.
  ///
  /// In it, this message translates to:
  /// **'Codice invito'**
  String get inviteCode;

  /// No description provided for @inviteCodeHint.
  ///
  /// In it, this message translates to:
  /// **'Inserisci codice invito'**
  String get inviteCodeHint;

  /// No description provided for @joinWithCode.
  ///
  /// In it, this message translates to:
  /// **'Unisciti con codice'**
  String get joinWithCode;

  /// No description provided for @visibility.
  ///
  /// In it, this message translates to:
  /// **'Visibilità'**
  String get visibility;

  /// No description provided for @public.
  ///
  /// In it, this message translates to:
  /// **'Pubblico'**
  String get public;

  /// No description provided for @privateGroup.
  ///
  /// In it, this message translates to:
  /// **'Privato'**
  String get privateGroup;

  /// No description provided for @secret.
  ///
  /// In it, this message translates to:
  /// **'Segreto'**
  String get secret;

  /// No description provided for @publicDesc.
  ///
  /// In it, this message translates to:
  /// **'Visibile a tutti, chiunque può unirsi'**
  String get publicDesc;

  /// No description provided for @privateDesc.
  ///
  /// In it, this message translates to:
  /// **'Visibile a tutti, accesso su richiesta'**
  String get privateDesc;

  /// No description provided for @secretDesc.
  ///
  /// In it, this message translates to:
  /// **'Invisibile, solo con codice invito'**
  String get secretDesc;

  /// No description provided for @requestAccess.
  ///
  /// In it, this message translates to:
  /// **'Richiedi accesso'**
  String get requestAccess;

  /// No description provided for @requestSent.
  ///
  /// In it, this message translates to:
  /// **'Richiesta inviata!'**
  String get requestSent;

  /// No description provided for @requestAlreadySent.
  ///
  /// In it, this message translates to:
  /// **'Hai già inviato una richiesta'**
  String get requestAlreadySent;

  /// No description provided for @pendingRequests.
  ///
  /// In it, this message translates to:
  /// **'Richieste di accesso'**
  String get pendingRequests;

  /// No description provided for @approveRequest.
  ///
  /// In it, this message translates to:
  /// **'Approva'**
  String get approveRequest;

  /// No description provided for @rejectRequest.
  ///
  /// In it, this message translates to:
  /// **'Rifiuta'**
  String get rejectRequest;

  /// No description provided for @requestApproved.
  ///
  /// In it, this message translates to:
  /// **'Richiesta approvata'**
  String get requestApproved;

  /// No description provided for @requestRejected.
  ///
  /// In it, this message translates to:
  /// **'Richiesta rifiutata'**
  String get requestRejected;

  /// No description provided for @groupVisibility.
  ///
  /// In it, this message translates to:
  /// **'Visibilità del gruppo'**
  String get groupVisibility;

  /// No description provided for @chat.
  ///
  /// In it, this message translates to:
  /// **'Chat'**
  String get chat;

  /// No description provided for @messages.
  ///
  /// In it, this message translates to:
  /// **'Messaggi'**
  String get messages;

  /// No description provided for @noMessages.
  ///
  /// In it, this message translates to:
  /// **'Nessun messaggio'**
  String get noMessages;

  /// No description provided for @startConversation.
  ///
  /// In it, this message translates to:
  /// **'Inizia la conversazione!'**
  String get startConversation;

  /// No description provided for @writeMessage.
  ///
  /// In it, this message translates to:
  /// **'Scrivi un messaggio...'**
  String get writeMessage;

  /// No description provided for @sendingImage.
  ///
  /// In it, this message translates to:
  /// **'Invio immagine...'**
  String get sendingImage;

  /// No description provided for @imageUploadError.
  ///
  /// In it, this message translates to:
  /// **'Errore invio immagine'**
  String get imageUploadError;

  /// No description provided for @events.
  ///
  /// In it, this message translates to:
  /// **'Eventi'**
  String get events;

  /// No description provided for @createEvent.
  ///
  /// In it, this message translates to:
  /// **'Crea evento'**
  String get createEvent;

  /// No description provided for @eventTitle.
  ///
  /// In it, this message translates to:
  /// **'Titolo evento'**
  String get eventTitle;

  /// No description provided for @eventDate.
  ///
  /// In it, this message translates to:
  /// **'Data'**
  String get eventDate;

  /// No description provided for @eventTime.
  ///
  /// In it, this message translates to:
  /// **'Ora'**
  String get eventTime;

  /// No description provided for @eventDescription.
  ///
  /// In it, this message translates to:
  /// **'Dettagli sull\'uscita...'**
  String get eventDescription;

  /// No description provided for @eventDistance.
  ///
  /// In it, this message translates to:
  /// **'Distanza'**
  String get eventDistance;

  /// No description provided for @eventElevation.
  ///
  /// In it, this message translates to:
  /// **'Dislivello'**
  String get eventElevation;

  /// No description provided for @maxParticipants.
  ///
  /// In it, this message translates to:
  /// **'Max partecipanti'**
  String get maxParticipants;

  /// No description provided for @noLimit.
  ///
  /// In it, this message translates to:
  /// **'Nessun limite'**
  String get noLimit;

  /// No description provided for @join.
  ///
  /// In it, this message translates to:
  /// **'Partecipa'**
  String get join;

  /// No description provided for @leave.
  ///
  /// In it, this message translates to:
  /// **'Lascia'**
  String get leave;

  /// No description provided for @participants.
  ///
  /// In it, this message translates to:
  /// **'Partecipanti'**
  String get participants;

  /// No description provided for @noEvents.
  ///
  /// In it, this message translates to:
  /// **'Nessun evento in programma'**
  String get noEvents;

  /// No description provided for @upcomingEvents.
  ///
  /// In it, this message translates to:
  /// **'Prossimi eventi'**
  String get upcomingEvents;

  /// No description provided for @challenges.
  ///
  /// In it, this message translates to:
  /// **'Sfide'**
  String get challenges;

  /// No description provided for @createChallenge.
  ///
  /// In it, this message translates to:
  /// **'Crea sfida'**
  String get createChallenge;

  /// No description provided for @challengeTitle.
  ///
  /// In it, this message translates to:
  /// **'Titolo sfida'**
  String get challengeTitle;

  /// No description provided for @noParticipants.
  ///
  /// In it, this message translates to:
  /// **'Nessun partecipante ancora'**
  String get noParticipants;

  /// No description provided for @leaderboard.
  ///
  /// In it, this message translates to:
  /// **'Classifica'**
  String get leaderboard;

  /// No description provided for @activeChallenges.
  ///
  /// In it, this message translates to:
  /// **'Sfide attive'**
  String get activeChallenges;

  /// No description provided for @completedChallenges.
  ///
  /// In it, this message translates to:
  /// **'Sfide completate'**
  String get completedChallenges;

  /// No description provided for @challengeType.
  ///
  /// In it, this message translates to:
  /// **'Tipo sfida'**
  String get challengeType;

  /// No description provided for @distanceChallenge.
  ///
  /// In it, this message translates to:
  /// **'Distanza'**
  String get distanceChallenge;

  /// No description provided for @elevationChallenge.
  ///
  /// In it, this message translates to:
  /// **'Dislivello'**
  String get elevationChallenge;

  /// No description provided for @tracksChallenge.
  ///
  /// In it, this message translates to:
  /// **'Tracce'**
  String get tracksChallenge;

  /// No description provided for @streakChallenge.
  ///
  /// In it, this message translates to:
  /// **'Costanza'**
  String get streakChallenge;

  /// No description provided for @settings.
  ///
  /// In it, this message translates to:
  /// **'Impostazioni'**
  String get settings;

  /// No description provided for @generalSettings.
  ///
  /// In it, this message translates to:
  /// **'Generali'**
  String get generalSettings;

  /// No description provided for @mapSettings.
  ///
  /// In it, this message translates to:
  /// **'Mappe'**
  String get mapSettings;

  /// No description provided for @notificationSettings.
  ///
  /// In it, this message translates to:
  /// **'Notifiche'**
  String get notificationSettings;

  /// No description provided for @account.
  ///
  /// In it, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @theme.
  ///
  /// In it, this message translates to:
  /// **'Tema'**
  String get theme;

  /// No description provided for @darkMode.
  ///
  /// In it, this message translates to:
  /// **'Modalità scura'**
  String get darkMode;

  /// No description provided for @lightMode.
  ///
  /// In it, this message translates to:
  /// **'Modalità chiara'**
  String get lightMode;

  /// No description provided for @systemMode.
  ///
  /// In it, this message translates to:
  /// **'Segui sistema'**
  String get systemMode;

  /// No description provided for @language.
  ///
  /// In it, this message translates to:
  /// **'Lingua'**
  String get language;

  /// No description provided for @offlineMaps.
  ///
  /// In it, this message translates to:
  /// **'Mappe offline'**
  String get offlineMaps;

  /// No description provided for @downloadMap.
  ///
  /// In it, this message translates to:
  /// **'Scarica mappa'**
  String get downloadMap;

  /// No description provided for @deleteMap.
  ///
  /// In it, this message translates to:
  /// **'Elimina mappa'**
  String get deleteMap;

  /// No description provided for @mapDownloaded.
  ///
  /// In it, this message translates to:
  /// **'Mappa scaricata'**
  String get mapDownloaded;

  /// No description provided for @storageUsed.
  ///
  /// In it, this message translates to:
  /// **'Spazio utilizzato'**
  String get storageUsed;

  /// No description provided for @units.
  ///
  /// In it, this message translates to:
  /// **'Unità di misura'**
  String get units;

  /// No description provided for @metric.
  ///
  /// In it, this message translates to:
  /// **'Metriche (km, m)'**
  String get metric;

  /// No description provided for @imperial.
  ///
  /// In it, this message translates to:
  /// **'Imperiali (mi, ft)'**
  String get imperial;

  /// No description provided for @about.
  ///
  /// In it, this message translates to:
  /// **'Informazioni'**
  String get about;

  /// No description provided for @version.
  ///
  /// In it, this message translates to:
  /// **'Versione'**
  String get version;

  /// No description provided for @privacyPolicy.
  ///
  /// In it, this message translates to:
  /// **'Informativa privacy'**
  String get privacyPolicy;

  /// No description provided for @termsOfService.
  ///
  /// In it, this message translates to:
  /// **'Termini di servizio'**
  String get termsOfService;

  /// No description provided for @deleteAccount.
  ///
  /// In it, this message translates to:
  /// **'Elimina account'**
  String get deleteAccount;

  /// No description provided for @deleteAccountConfirm.
  ///
  /// In it, this message translates to:
  /// **'Vuoi eliminare il tuo account? Tutti i dati verranno persi.'**
  String get deleteAccountConfirm;

  /// No description provided for @liveTracking.
  ///
  /// In it, this message translates to:
  /// **'Live tracking'**
  String get liveTracking;

  /// No description provided for @durationLabel.
  ///
  /// In it, this message translates to:
  /// **'Durata: {duration}'**
  String durationLabel(String duration);

  /// No description provided for @wishlistAdded.
  ///
  /// In it, this message translates to:
  /// **'Salvato'**
  String get wishlistAdded;

  /// No description provided for @wishlistRemoved.
  ///
  /// In it, this message translates to:
  /// **'Rimosso'**
  String get wishlistRemoved;

  /// No description provided for @saved.
  ///
  /// In it, this message translates to:
  /// **'Salvato'**
  String get saved;

  /// No description provided for @saving.
  ///
  /// In it, this message translates to:
  /// **'Salvataggio...'**
  String get saving;

  /// No description provided for @errorGeneric.
  ///
  /// In it, this message translates to:
  /// **'Si è verificato un errore'**
  String get errorGeneric;

  /// No description provided for @errorUnknown.
  ///
  /// In it, this message translates to:
  /// **'Errore sconosciuto'**
  String get errorUnknown;

  /// No description provided for @errorNetwork.
  ///
  /// In it, this message translates to:
  /// **'Errore di connessione'**
  String get errorNetwork;

  /// No description provided for @errorPermission.
  ///
  /// In it, this message translates to:
  /// **'Permesso negato'**
  String get errorPermission;

  /// No description provided for @noData.
  ///
  /// In it, this message translates to:
  /// **'Nessun dato'**
  String get noData;

  /// No description provided for @noUser.
  ///
  /// In it, this message translates to:
  /// **'Nessun utente'**
  String get noUser;

  /// No description provided for @greatJob.
  ///
  /// In it, this message translates to:
  /// **'Ottimo lavoro! 💪'**
  String get greatJob;

  /// No description provided for @greatHike.
  ///
  /// In it, this message translates to:
  /// **'Grande escursione! 🏔️'**
  String get greatHike;

  /// No description provided for @fantasticTrail.
  ///
  /// In it, this message translates to:
  /// **'Fantastico percorso! 🥾'**
  String get fantasticTrail;

  /// No description provided for @whatAdventure.
  ///
  /// In it, this message translates to:
  /// **'Che avventura! 🌟'**
  String get whatAdventure;

  /// No description provided for @trueExplorer.
  ///
  /// In it, this message translates to:
  /// **'Sei un vero esploratore! 🧭'**
  String get trueExplorer;

  /// No description provided for @trailCompleted.
  ///
  /// In it, this message translates to:
  /// **'Trail completato! 🎯'**
  String get trailCompleted;

  /// No description provided for @keepItUp.
  ///
  /// In it, this message translates to:
  /// **'Complimenti, continua così! 🔥'**
  String get keepItUp;

  /// No description provided for @today.
  ///
  /// In it, this message translates to:
  /// **'Oggi'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In it, this message translates to:
  /// **'Ieri'**
  String get yesterday;

  /// No description provided for @km.
  ///
  /// In it, this message translates to:
  /// **'km'**
  String get km;

  /// No description provided for @m.
  ///
  /// In it, this message translates to:
  /// **'m'**
  String get m;

  /// No description provided for @h.
  ///
  /// In it, this message translates to:
  /// **'h'**
  String get h;

  /// No description provided for @min.
  ///
  /// In it, this message translates to:
  /// **'min'**
  String get min;

  /// No description provided for @info.
  ///
  /// In it, this message translates to:
  /// **'Info'**
  String get info;

  /// No description provided for @sharedTracks.
  ///
  /// In it, this message translates to:
  /// **'Tracce condivise'**
  String get sharedTracks;

  /// No description provided for @name.
  ///
  /// In it, this message translates to:
  /// **'Nome'**
  String get name;

  /// No description provided for @description.
  ///
  /// In it, this message translates to:
  /// **'Descrizione'**
  String get description;

  /// No description provided for @adminPanel.
  ///
  /// In it, this message translates to:
  /// **'Pannello admin'**
  String get adminPanel;

  /// No description provided for @noUsersFound.
  ///
  /// In it, this message translates to:
  /// **'Nessun utente'**
  String get noUsersFound;

  /// No description provided for @noResultsFound.
  ///
  /// In it, this message translates to:
  /// **'Nessun risultato'**
  String get noResultsFound;

  /// No description provided for @databaseStats.
  ///
  /// In it, this message translates to:
  /// **'Statistiche database'**
  String get databaseStats;

  /// No description provided for @tapKmToHighlight.
  ///
  /// In it, this message translates to:
  /// **'Tocca un km per evidenziarlo sulla mappa'**
  String get tapKmToHighlight;

  /// No description provided for @total.
  ///
  /// In it, this message translates to:
  /// **'TOT'**
  String get total;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'it':
      return AppLocalizationsIt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
