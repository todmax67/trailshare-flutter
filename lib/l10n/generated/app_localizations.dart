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
  /// **'REGISTRAZIONE'**
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
  /// **'Crea Gruppo'**
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
  /// **'Vuoi eliminare \"{name}\"?\n\nQuesta azione è irreversibile.'**
  String deleteGroupConfirm(String name);

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
  /// **'Mappe Offline'**
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
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @termsOfService.
  ///
  /// In it, this message translates to:
  /// **'Termini di Servizio'**
  String get termsOfService;

  /// No description provided for @deleteAccount.
  ///
  /// In it, this message translates to:
  /// **'Elimina Account'**
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
  /// **'Statistiche Database'**
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

  /// No description provided for @defaultUser.
  ///
  /// In it, this message translates to:
  /// **'Utente'**
  String get defaultUser;

  /// No description provided for @usernameUpdated.
  ///
  /// In it, this message translates to:
  /// **'Username aggiornato!'**
  String get usernameUpdated;

  /// No description provided for @bioUpdated.
  ///
  /// In it, this message translates to:
  /// **'Bio aggiornata!'**
  String get bioUpdated;

  /// No description provided for @errorWithDetails.
  ///
  /// In it, this message translates to:
  /// **'Errore: {error}'**
  String errorWithDetails(String error);

  /// No description provided for @logoutConfirm.
  ///
  /// In it, this message translates to:
  /// **'Vuoi uscire dal tuo account?'**
  String get logoutConfirm;

  /// No description provided for @loginToSeeProfile.
  ///
  /// In it, this message translates to:
  /// **'Accedi per vedere il tuo profilo'**
  String get loginToSeeProfile;

  /// No description provided for @loginProfileDescription.
  ///
  /// In it, this message translates to:
  /// **'Salva le tue tracce, segui altri escursionisti e molto altro.'**
  String get loginProfileDescription;

  /// No description provided for @editNickname.
  ///
  /// In it, this message translates to:
  /// **'Modifica nickname'**
  String get editNickname;

  /// No description provided for @bioHint.
  ///
  /// In it, this message translates to:
  /// **'Racconta qualcosa di te...'**
  String get bioHint;

  /// No description provided for @addBio.
  ///
  /// In it, this message translates to:
  /// **'Aggiungi una bio'**
  String get addBio;

  /// No description provided for @editBio.
  ///
  /// In it, this message translates to:
  /// **'Modifica bio'**
  String get editBio;

  /// No description provided for @levelNumber.
  ///
  /// In it, this message translates to:
  /// **'Livello {level}'**
  String levelNumber(int level);

  /// No description provided for @myContacts.
  ///
  /// In it, this message translates to:
  /// **'I miei contatti'**
  String get myContacts;

  /// No description provided for @contactsSummary.
  ///
  /// In it, this message translates to:
  /// **'{followers} follower · {following} seguiti'**
  String contactsSummary(int followers, int following);

  /// No description provided for @viewDashboard.
  ///
  /// In it, this message translates to:
  /// **'Vedi Dashboard'**
  String get viewDashboard;

  /// No description provided for @savedRoutes.
  ///
  /// In it, this message translates to:
  /// **'Percorsi Salvati'**
  String get savedRoutes;

  /// No description provided for @weeklyLeaderboard.
  ///
  /// In it, this message translates to:
  /// **'Classifica Settimanale'**
  String get weeklyLeaderboard;

  /// No description provided for @myBadges.
  ///
  /// In it, this message translates to:
  /// **'I Miei Badge'**
  String get myBadges;

  /// No description provided for @dashboard.
  ///
  /// In it, this message translates to:
  /// **'Dashboard'**
  String get dashboard;

  /// No description provided for @noStatsAvailable.
  ///
  /// In it, this message translates to:
  /// **'Nessuna statistica disponibile'**
  String get noStatsAvailable;

  /// No description provided for @recordFirstTrackForStats.
  ///
  /// In it, this message translates to:
  /// **'Registra la tua prima traccia per vedere le statistiche!'**
  String get recordFirstTrackForStats;

  /// No description provided for @summary.
  ///
  /// In it, this message translates to:
  /// **'Riepilogo'**
  String get summary;

  /// No description provided for @totalTracksLabel.
  ///
  /// In it, this message translates to:
  /// **'Tracce Totali'**
  String get totalTracksLabel;

  /// No description provided for @totalTime.
  ///
  /// In it, this message translates to:
  /// **'Tempo Totale'**
  String get totalTime;

  /// No description provided for @personalRecords.
  ///
  /// In it, this message translates to:
  /// **'Record Personali'**
  String get personalRecords;

  /// No description provided for @longestTrack.
  ///
  /// In it, this message translates to:
  /// **'Traccia più lunga'**
  String get longestTrack;

  /// No description provided for @highestElevationRecord.
  ///
  /// In it, this message translates to:
  /// **'Maggior dislivello'**
  String get highestElevationRecord;

  /// No description provided for @longestDuration.
  ///
  /// In it, this message translates to:
  /// **'Durata più lunga'**
  String get longestDuration;

  /// No description provided for @activityDistribution.
  ///
  /// In it, this message translates to:
  /// **'Distribuzione Attività'**
  String get activityDistribution;

  /// No description provided for @trend.
  ///
  /// In it, this message translates to:
  /// **'Andamento'**
  String get trend;

  /// No description provided for @week.
  ///
  /// In it, this message translates to:
  /// **'Settimana'**
  String get week;

  /// No description provided for @month.
  ///
  /// In it, this message translates to:
  /// **'Mese'**
  String get month;

  /// No description provided for @year.
  ///
  /// In it, this message translates to:
  /// **'Anno'**
  String get year;

  /// No description provided for @noDataForPeriod.
  ///
  /// In it, this message translates to:
  /// **'Nessun dato per questo periodo'**
  String get noDataForPeriod;

  /// No description provided for @thisWeek.
  ///
  /// In it, this message translates to:
  /// **'Questa Settimana'**
  String get thisWeek;

  /// No description provided for @previousWeek.
  ///
  /// In it, this message translates to:
  /// **'Sett. Precedente'**
  String get previousWeek;

  /// No description provided for @noRecord.
  ///
  /// In it, this message translates to:
  /// **'Nessun record'**
  String get noRecord;

  /// No description provided for @activityCycling.
  ///
  /// In it, this message translates to:
  /// **'Ciclismo'**
  String get activityCycling;

  /// No description provided for @activityWalking.
  ///
  /// In it, this message translates to:
  /// **'Camminata'**
  String get activityWalking;

  /// No description provided for @daySun.
  ///
  /// In it, this message translates to:
  /// **'Dom'**
  String get daySun;

  /// No description provided for @dayMon.
  ///
  /// In it, this message translates to:
  /// **'Lun'**
  String get dayMon;

  /// No description provided for @dayTue.
  ///
  /// In it, this message translates to:
  /// **'Mar'**
  String get dayTue;

  /// No description provided for @dayWed.
  ///
  /// In it, this message translates to:
  /// **'Mer'**
  String get dayWed;

  /// No description provided for @dayThu.
  ///
  /// In it, this message translates to:
  /// **'Gio'**
  String get dayThu;

  /// No description provided for @dayFri.
  ///
  /// In it, this message translates to:
  /// **'Ven'**
  String get dayFri;

  /// No description provided for @daySat.
  ///
  /// In it, this message translates to:
  /// **'Sab'**
  String get daySat;

  /// No description provided for @monthJanShort.
  ///
  /// In it, this message translates to:
  /// **'Gen'**
  String get monthJanShort;

  /// No description provided for @monthFebShort.
  ///
  /// In it, this message translates to:
  /// **'Feb'**
  String get monthFebShort;

  /// No description provided for @monthMarShort.
  ///
  /// In it, this message translates to:
  /// **'Mar'**
  String get monthMarShort;

  /// No description provided for @monthAprShort.
  ///
  /// In it, this message translates to:
  /// **'Apr'**
  String get monthAprShort;

  /// No description provided for @monthMayShort.
  ///
  /// In it, this message translates to:
  /// **'Mag'**
  String get monthMayShort;

  /// No description provided for @monthJunShort.
  ///
  /// In it, this message translates to:
  /// **'Giu'**
  String get monthJunShort;

  /// No description provided for @monthJulShort.
  ///
  /// In it, this message translates to:
  /// **'Lug'**
  String get monthJulShort;

  /// No description provided for @monthAugShort.
  ///
  /// In it, this message translates to:
  /// **'Ago'**
  String get monthAugShort;

  /// No description provided for @monthSepShort.
  ///
  /// In it, this message translates to:
  /// **'Set'**
  String get monthSepShort;

  /// No description provided for @monthOctShort.
  ///
  /// In it, this message translates to:
  /// **'Ott'**
  String get monthOctShort;

  /// No description provided for @monthNovShort.
  ///
  /// In it, this message translates to:
  /// **'Nov'**
  String get monthNovShort;

  /// No description provided for @monthDecShort.
  ///
  /// In it, this message translates to:
  /// **'Dic'**
  String get monthDecShort;

  /// No description provided for @monthJan.
  ///
  /// In it, this message translates to:
  /// **'Gennaio'**
  String get monthJan;

  /// No description provided for @monthFeb.
  ///
  /// In it, this message translates to:
  /// **'Febbraio'**
  String get monthFeb;

  /// No description provided for @monthMar.
  ///
  /// In it, this message translates to:
  /// **'Marzo'**
  String get monthMar;

  /// No description provided for @monthApr.
  ///
  /// In it, this message translates to:
  /// **'Aprile'**
  String get monthApr;

  /// No description provided for @monthMay.
  ///
  /// In it, this message translates to:
  /// **'Maggio'**
  String get monthMay;

  /// No description provided for @monthJun.
  ///
  /// In it, this message translates to:
  /// **'Giugno'**
  String get monthJun;

  /// No description provided for @monthJul.
  ///
  /// In it, this message translates to:
  /// **'Luglio'**
  String get monthJul;

  /// No description provided for @monthAug.
  ///
  /// In it, this message translates to:
  /// **'Agosto'**
  String get monthAug;

  /// No description provided for @monthSep.
  ///
  /// In it, this message translates to:
  /// **'Settembre'**
  String get monthSep;

  /// No description provided for @monthOct.
  ///
  /// In it, this message translates to:
  /// **'Ottobre'**
  String get monthOct;

  /// No description provided for @monthNov.
  ///
  /// In it, this message translates to:
  /// **'Novembre'**
  String get monthNov;

  /// No description provided for @monthDec.
  ///
  /// In it, this message translates to:
  /// **'Dicembre'**
  String get monthDec;

  /// No description provided for @activeTabCount.
  ///
  /// In it, this message translates to:
  /// **'Attive ({count})'**
  String activeTabCount(int count);

  /// No description provided for @myChallengesTabCount.
  ///
  /// In it, this message translates to:
  /// **'Le mie ({count})'**
  String myChallengesTabCount(int count);

  /// No description provided for @createChallengeBtn.
  ///
  /// In it, this message translates to:
  /// **'Crea Sfida'**
  String get createChallengeBtn;

  /// No description provided for @noActiveChallenges.
  ///
  /// In it, this message translates to:
  /// **'Nessuna sfida attiva'**
  String get noActiveChallenges;

  /// No description provided for @notInAnyChallenges.
  ///
  /// In it, this message translates to:
  /// **'Non partecipi a nessuna sfida'**
  String get notInAnyChallenges;

  /// No description provided for @createFirstChallenge.
  ///
  /// In it, this message translates to:
  /// **'Crea la prima sfida e sfida la community!'**
  String get createFirstChallenge;

  /// No description provided for @joinFromActiveTab.
  ///
  /// In it, this message translates to:
  /// **'Unisciti a una sfida dalla tab \"Attive\"'**
  String get joinFromActiveTab;

  /// No description provided for @joinChallengeTitle.
  ///
  /// In it, this message translates to:
  /// **'Partecipa a \"{title}\"'**
  String joinChallengeTitle(String title);

  /// No description provided for @goalLabel.
  ///
  /// In it, this message translates to:
  /// **'Obiettivo'**
  String get goalLabel;

  /// No description provided for @deadlineLabel.
  ///
  /// In it, this message translates to:
  /// **'Scadenza'**
  String get deadlineLabel;

  /// No description provided for @daysCount.
  ///
  /// In it, this message translates to:
  /// **'{days} giorni'**
  String daysCount(int days);

  /// No description provided for @joinChallengeConfirm.
  ///
  /// In it, this message translates to:
  /// **'Vuoi partecipare a questa sfida?'**
  String get joinChallengeConfirm;

  /// No description provided for @joinAction.
  ///
  /// In it, this message translates to:
  /// **'Partecipa'**
  String get joinAction;

  /// No description provided for @joinedChallenge.
  ///
  /// In it, this message translates to:
  /// **'🎉 Ti sei unito alla sfida!'**
  String get joinedChallenge;

  /// No description provided for @joinError.
  ///
  /// In it, this message translates to:
  /// **'Errore durante l\'iscrizione'**
  String get joinError;

  /// No description provided for @challengeDetail.
  ///
  /// In it, this message translates to:
  /// **'Dettaglio Sfida'**
  String get challengeDetail;

  /// No description provided for @createdBy.
  ///
  /// In it, this message translates to:
  /// **'Creata da {name}'**
  String createdBy(String name);

  /// No description provided for @yourProgress.
  ///
  /// In it, this message translates to:
  /// **'Il tuo progresso'**
  String get yourProgress;

  /// No description provided for @enrolled.
  ///
  /// In it, this message translates to:
  /// **'✓ Iscritto'**
  String get enrolled;

  /// No description provided for @participantsCount.
  ///
  /// In it, this message translates to:
  /// **'{count} partecipanti'**
  String participantsCount(int count);

  /// No description provided for @goalPrefix.
  ///
  /// In it, this message translates to:
  /// **'Obiettivo: {goal}'**
  String goalPrefix(String goal);

  /// No description provided for @createNewChallenge.
  ///
  /// In it, this message translates to:
  /// **'Crea una nuova sfida'**
  String get createNewChallenge;

  /// No description provided for @challengeHint.
  ///
  /// In it, this message translates to:
  /// **'Es: 100km in una settimana'**
  String get challengeHint;

  /// No description provided for @descriptionOptional.
  ///
  /// In it, this message translates to:
  /// **'Descrizione (opzionale)'**
  String get descriptionOptional;

  /// No description provided for @describeChallenge.
  ///
  /// In it, this message translates to:
  /// **'Descrivi la sfida...'**
  String get describeChallenge;

  /// No description provided for @challengeTypeLabel.
  ///
  /// In it, this message translates to:
  /// **'Tipo di sfida'**
  String get challengeTypeLabel;

  /// No description provided for @enterTitle.
  ///
  /// In it, this message translates to:
  /// **'Inserisci un titolo'**
  String get enterTitle;

  /// No description provided for @enterGoal.
  ///
  /// In it, this message translates to:
  /// **'Inserisci un obiettivo'**
  String get enterGoal;

  /// No description provided for @enterValidNumber.
  ///
  /// In it, this message translates to:
  /// **'Inserisci un numero valido'**
  String get enterValidNumber;

  /// No description provided for @challengeCreated.
  ///
  /// In it, this message translates to:
  /// **'🎉 Sfida creata!'**
  String get challengeCreated;

  /// No description provided for @creationError.
  ///
  /// In it, this message translates to:
  /// **'Errore durante la creazione'**
  String get creationError;

  /// No description provided for @tracksUnit.
  ///
  /// In it, this message translates to:
  /// **'tracce'**
  String get tracksUnit;

  /// No description provided for @newBadge.
  ///
  /// In it, this message translates to:
  /// **'Nuovo Badge!'**
  String get newBadge;

  /// No description provided for @fantastic.
  ///
  /// In it, this message translates to:
  /// **'Fantastico!'**
  String get fantastic;

  /// No description provided for @badges.
  ///
  /// In it, this message translates to:
  /// **'Badge'**
  String get badges;

  /// No description provided for @unlockedCount.
  ///
  /// In it, this message translates to:
  /// **'Sbloccati ({count})'**
  String unlockedCount(int count);

  /// No description provided for @allCount.
  ///
  /// In it, this message translates to:
  /// **'Tutti ({count})'**
  String allCount(int count);

  /// No description provided for @noBadgesYet.
  ///
  /// In it, this message translates to:
  /// **'Nessun badge ancora'**
  String get noBadgesYet;

  /// No description provided for @completeTracksForBadges.
  ///
  /// In it, this message translates to:
  /// **'Completa tracce e attività per sbloccare badge!'**
  String get completeTracksForBadges;

  /// No description provided for @viewAllBadges.
  ///
  /// In it, this message translates to:
  /// **'Vedi tutti i badge'**
  String get viewAllBadges;

  /// No description provided for @milestones.
  ///
  /// In it, this message translates to:
  /// **'Traguardi'**
  String get milestones;

  /// No description provided for @socialCategory.
  ///
  /// In it, this message translates to:
  /// **'Social'**
  String get socialCategory;

  /// No description provided for @streakCategory.
  ///
  /// In it, this message translates to:
  /// **'Costanza'**
  String get streakCategory;

  /// No description provided for @unlockedOn.
  ///
  /// In it, this message translates to:
  /// **'Sbloccato il {date}'**
  String unlockedOn(String date);

  /// No description provided for @leaderboardLoadError.
  ///
  /// In it, this message translates to:
  /// **'Errore caricamento classifica'**
  String get leaderboardLoadError;

  /// No description provided for @yourPosition.
  ///
  /// In it, this message translates to:
  /// **'La tua posizione'**
  String get yourPosition;

  /// No description provided for @youAreLeading.
  ///
  /// In it, this message translates to:
  /// **'🏆 Sei in testa!'**
  String get youAreLeading;

  /// No description provided for @positionOfTotal.
  ///
  /// In it, this message translates to:
  /// **'Posizione {rank} di {total}'**
  String positionOfTotal(int rank, int total);

  /// No description provided for @noActivityThisWeek.
  ///
  /// In it, this message translates to:
  /// **'Nessuna attività questa settimana'**
  String get noActivityThisWeek;

  /// No description provided for @completeTrackForLeaderboard.
  ///
  /// In it, this message translates to:
  /// **'Completa una traccia per apparire in classifica.\nSegui altri utenti per competere con loro!'**
  String get completeTrackForLeaderboard;

  /// No description provided for @startHike.
  ///
  /// In it, this message translates to:
  /// **'Inizia un\'escursione'**
  String get startHike;

  /// No description provided for @loginToSeeLeaderboard.
  ///
  /// In it, this message translates to:
  /// **'Accedi per vedere la classifica'**
  String get loginToSeeLeaderboard;

  /// No description provided for @competeWithFriends.
  ///
  /// In it, this message translates to:
  /// **'Competi con gli amici e scala la classifica settimanale!'**
  String get competeWithFriends;

  /// No description provided for @youLabel.
  ///
  /// In it, this message translates to:
  /// **'TU'**
  String get youLabel;

  /// No description provided for @xpThisWeek.
  ///
  /// In it, this message translates to:
  /// **'{xp} XP questa settimana'**
  String xpThisWeek(int xp);

  /// No description provided for @accountSection.
  ///
  /// In it, this message translates to:
  /// **'Account'**
  String get accountSection;

  /// No description provided for @emailLabel.
  ///
  /// In it, this message translates to:
  /// **'Email'**
  String get emailLabel;

  /// No description provided for @notAvailable.
  ///
  /// In it, this message translates to:
  /// **'Non disponibile'**
  String get notAvailable;

  /// No description provided for @signOutTitle.
  ///
  /// In it, this message translates to:
  /// **'Esci'**
  String get signOutTitle;

  /// No description provided for @signOutSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Disconnetti il tuo account'**
  String get signOutSubtitle;

  /// No description provided for @signOutConfirm.
  ///
  /// In it, this message translates to:
  /// **'Vuoi uscire dal tuo account?'**
  String get signOutConfirm;

  /// No description provided for @appearanceSection.
  ///
  /// In it, this message translates to:
  /// **'Aspetto'**
  String get appearanceSection;

  /// No description provided for @healthConnectionSection.
  ///
  /// In it, this message translates to:
  /// **'Connessione Salute'**
  String get healthConnectionSection;

  /// No description provided for @syncWithHealth.
  ///
  /// In it, this message translates to:
  /// **'Sincronizza con Salute'**
  String get syncWithHealth;

  /// No description provided for @saveToAppleHealth.
  ///
  /// In it, this message translates to:
  /// **'Salva le attività su Apple Salute'**
  String get saveToAppleHealth;

  /// No description provided for @saveToHealthConnect.
  ///
  /// In it, this message translates to:
  /// **'Salva le attività su Health Connect'**
  String get saveToHealthConnect;

  /// No description provided for @healthConnectRequired.
  ///
  /// In it, this message translates to:
  /// **'Health Connect necessario'**
  String get healthConnectRequired;

  /// No description provided for @healthConnectInstallMessage.
  ///
  /// In it, this message translates to:
  /// **'Per sincronizzare le attività è necessario installare Health Connect dal Play Store.\n\nVuoi installarlo ora?'**
  String get healthConnectInstallMessage;

  /// No description provided for @installAction.
  ///
  /// In it, this message translates to:
  /// **'Installa'**
  String get installAction;

  /// No description provided for @permissionsNotGranted.
  ///
  /// In it, this message translates to:
  /// **'Permessi non concessi. Riprova o abilita dalle impostazioni del dispositivo.'**
  String get permissionsNotGranted;

  /// No description provided for @maxHeartRate.
  ///
  /// In it, this message translates to:
  /// **'Frequenza cardiaca massima'**
  String get maxHeartRate;

  /// No description provided for @maxHRDescription.
  ///
  /// In it, this message translates to:
  /// **'Inserisci la tua FC max se la conosci, oppure inserisci la tua età per stimarla (220 - età).'**
  String get maxHRDescription;

  /// No description provided for @maxHRLabel.
  ///
  /// In it, this message translates to:
  /// **'FC Max (BPM)'**
  String get maxHRLabel;

  /// No description provided for @maxHRHint.
  ///
  /// In it, this message translates to:
  /// **'Es: 185'**
  String get maxHRHint;

  /// No description provided for @orLabel.
  ///
  /// In it, this message translates to:
  /// **'oppure'**
  String get orLabel;

  /// No description provided for @ageLabel.
  ///
  /// In it, this message translates to:
  /// **'Età'**
  String get ageLabel;

  /// No description provided for @ageHint.
  ///
  /// In it, this message translates to:
  /// **'Es: 35'**
  String get ageHint;

  /// No description provided for @setForCardioZones.
  ///
  /// In it, this message translates to:
  /// **'Imposta per calcolare le zone cardio'**
  String get setForCardioZones;

  /// No description provided for @healthDashboard.
  ///
  /// In it, this message translates to:
  /// **'Dashboard Salute'**
  String get healthDashboard;

  /// No description provided for @healthDashboardSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Passi, battito, calorie settimanali'**
  String get healthDashboardSubtitle;

  /// No description provided for @legalSection.
  ///
  /// In it, this message translates to:
  /// **'Legale'**
  String get legalSection;

  /// No description provided for @privacyPolicySubtitle.
  ///
  /// In it, this message translates to:
  /// **'Come gestiamo i tuoi dati'**
  String get privacyPolicySubtitle;

  /// No description provided for @termsOfServiceSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Condizioni d\'uso dell\'app'**
  String get termsOfServiceSubtitle;

  /// No description provided for @openSourceLicenses.
  ///
  /// In it, this message translates to:
  /// **'Licenze Open Source'**
  String get openSourceLicenses;

  /// No description provided for @openSourceLicensesSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Librerie utilizzate'**
  String get openSourceLicensesSubtitle;

  /// No description provided for @supportSection.
  ///
  /// In it, this message translates to:
  /// **'Supporto'**
  String get supportSection;

  /// No description provided for @helpCenter.
  ///
  /// In it, this message translates to:
  /// **'Centro Assistenza'**
  String get helpCenter;

  /// No description provided for @helpCenterSubtitle.
  ///
  /// In it, this message translates to:
  /// **'FAQ e guide'**
  String get helpCenterSubtitle;

  /// No description provided for @contactUs.
  ///
  /// In it, this message translates to:
  /// **'Contattaci'**
  String get contactUs;

  /// No description provided for @rateApp.
  ///
  /// In it, this message translates to:
  /// **'Valuta l\'app'**
  String get rateApp;

  /// No description provided for @rateAppSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Lascia una recensione'**
  String get rateAppSubtitle;

  /// No description provided for @offlineMapsSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Scarica mappe per uso senza connessione'**
  String get offlineMapsSubtitle;

  /// No description provided for @infoSection.
  ///
  /// In it, this message translates to:
  /// **'Informazioni'**
  String get infoSection;

  /// No description provided for @versionLabel.
  ///
  /// In it, this message translates to:
  /// **'Versione'**
  String get versionLabel;

  /// No description provided for @loadingEllipsis.
  ///
  /// In it, this message translates to:
  /// **'Caricamento...'**
  String get loadingEllipsis;

  /// No description provided for @whatsNew.
  ///
  /// In it, this message translates to:
  /// **'Novità'**
  String get whatsNew;

  /// No description provided for @whatsNewSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Cosa c\'è di nuovo'**
  String get whatsNewSubtitle;

  /// No description provided for @adminSection.
  ///
  /// In it, this message translates to:
  /// **'Amministrazione'**
  String get adminSection;

  /// No description provided for @importTrails.
  ///
  /// In it, this message translates to:
  /// **'Import Sentieri'**
  String get importTrails;

  /// No description provided for @importTrailsSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Importa sentieri da Waymarked Trails'**
  String get importTrailsSubtitle;

  /// No description provided for @geohashMigration.
  ///
  /// In it, this message translates to:
  /// **'Migrazione GeoHash'**
  String get geohashMigration;

  /// No description provided for @geohashMigrationSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Gestisci indici geospaziali per i sentieri'**
  String get geohashMigrationSubtitle;

  /// No description provided for @databaseStatsSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Visualizza metriche e utilizzo'**
  String get databaseStatsSubtitle;

  /// No description provided for @recalculateStats.
  ///
  /// In it, this message translates to:
  /// **'Ricalcola Statistiche'**
  String get recalculateStats;

  /// No description provided for @recalculateStatsSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Correggi dislivello e distanze dalle tracce GPS'**
  String get recalculateStatsSubtitle;

  /// No description provided for @dangerZone.
  ///
  /// In it, this message translates to:
  /// **'Zona Pericolosa'**
  String get dangerZone;

  /// No description provided for @deleteAccountSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Elimina permanentemente tutti i tuoi dati'**
  String get deleteAccountSubtitle;

  /// No description provided for @accountDeleted.
  ///
  /// In it, this message translates to:
  /// **'Account eliminato con successo'**
  String get accountDeleted;

  /// No description provided for @cannotOpenLink.
  ///
  /// In it, this message translates to:
  /// **'Impossibile aprire il link'**
  String get cannotOpenLink;

  /// No description provided for @cannotOpenEmail.
  ///
  /// In it, this message translates to:
  /// **'Impossibile aprire il client email'**
  String get cannotOpenEmail;

  /// No description provided for @appComingSoon.
  ///
  /// In it, this message translates to:
  /// **'Grazie! L\'app sarà presto disponibile negli store.'**
  String get appComingSoon;

  /// No description provided for @changelogTitle.
  ///
  /// In it, this message translates to:
  /// **'Novità v1.0.0'**
  String get changelogTitle;

  /// No description provided for @changelogFirstRelease.
  ///
  /// In it, this message translates to:
  /// **'🎉 Prima release!'**
  String get changelogFirstRelease;

  /// No description provided for @changelogGpsTracking.
  ///
  /// In it, this message translates to:
  /// **'Registrazione tracce GPS'**
  String get changelogGpsTracking;

  /// No description provided for @changelogBackground.
  ///
  /// In it, this message translates to:
  /// **'Tracking in background'**
  String get changelogBackground;

  /// No description provided for @changelogLiveTrack.
  ///
  /// In it, this message translates to:
  /// **'LiveTrack - condividi posizione'**
  String get changelogLiveTrack;

  /// No description provided for @changelogSocial.
  ///
  /// In it, this message translates to:
  /// **'Sistema social (follow, cheers)'**
  String get changelogSocial;

  /// No description provided for @changelogLeaderboard.
  ///
  /// In it, this message translates to:
  /// **'Classifica settimanale'**
  String get changelogLeaderboard;

  /// No description provided for @changelogWishlist.
  ///
  /// In it, this message translates to:
  /// **'Wishlist percorsi'**
  String get changelogWishlist;

  /// No description provided for @changelogDashboard.
  ///
  /// In it, this message translates to:
  /// **'Dashboard statistiche'**
  String get changelogDashboard;

  /// No description provided for @changelogGpx.
  ///
  /// In it, this message translates to:
  /// **'Import/Export GPX'**
  String get changelogGpx;

  /// No description provided for @themeLabel.
  ///
  /// In it, this message translates to:
  /// **'Tema'**
  String get themeLabel;

  /// No description provided for @themeAutomatic.
  ///
  /// In it, this message translates to:
  /// **'Automatico'**
  String get themeAutomatic;

  /// No description provided for @themeLight.
  ///
  /// In it, this message translates to:
  /// **'Chiaro'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In it, this message translates to:
  /// **'Scuro'**
  String get themeDark;

  /// No description provided for @selectTheme.
  ///
  /// In it, this message translates to:
  /// **'Seleziona tema'**
  String get selectTheme;

  /// No description provided for @themeAutomaticSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Segue le impostazioni di sistema'**
  String get themeAutomaticSubtitle;

  /// No description provided for @themeLightSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Tema chiaro sempre attivo'**
  String get themeLightSubtitle;

  /// No description provided for @themeDarkSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Tema scuro sempre attivo'**
  String get themeDarkSubtitle;

  /// No description provided for @stepsToday.
  ///
  /// In it, this message translates to:
  /// **'Passi oggi'**
  String get stepsToday;

  /// No description provided for @restingHR.
  ///
  /// In it, this message translates to:
  /// **'FC riposo'**
  String get restingHR;

  /// No description provided for @goalReached.
  ///
  /// In it, this message translates to:
  /// **'🎉 Obiettivo raggiunto!'**
  String get goalReached;

  /// No description provided for @percentOfGoal.
  ///
  /// In it, this message translates to:
  /// **'{pct}% di 10.000'**
  String percentOfGoal(int pct);

  /// No description provided for @stepsLast7Days.
  ///
  /// In it, this message translates to:
  /// **'Passi — Ultimi 7 giorni'**
  String get stepsLast7Days;

  /// No description provided for @caloriesLast7Days.
  ///
  /// In it, this message translates to:
  /// **'Calorie — Ultimi 7 giorni'**
  String get caloriesLast7Days;

  /// No description provided for @noStepsData.
  ///
  /// In it, this message translates to:
  /// **'Nessun dato passi disponibile'**
  String get noStepsData;

  /// No description provided for @noCaloriesData.
  ///
  /// In it, this message translates to:
  /// **'Nessun dato calorie disponibile'**
  String get noCaloriesData;

  /// No description provided for @stepsUnit.
  ///
  /// In it, this message translates to:
  /// **'passi'**
  String get stepsUnit;

  /// No description provided for @healthDataInfo.
  ///
  /// In it, this message translates to:
  /// **'I dati provengono dal tuo smartwatch tramite Health Connect. Assicurati che il dispositivo sia sincronizzato per dati aggiornati.'**
  String get healthDataInfo;

  /// No description provided for @faqHowCanWeHelp.
  ///
  /// In it, this message translates to:
  /// **'Come possiamo aiutarti?'**
  String get faqHowCanWeHelp;

  /// No description provided for @faqFindAnswers.
  ///
  /// In it, this message translates to:
  /// **'Trova risposte alle domande più frequenti'**
  String get faqFindAnswers;

  /// No description provided for @faqCategoryGeneral.
  ///
  /// In it, this message translates to:
  /// **'📱 Generale'**
  String get faqCategoryGeneral;

  /// No description provided for @faqCategoryTracking.
  ///
  /// In it, this message translates to:
  /// **'🗺️ Tracking GPS'**
  String get faqCategoryTracking;

  /// No description provided for @faqCategorySocial.
  ///
  /// In it, this message translates to:
  /// **'👥 Social'**
  String get faqCategorySocial;

  /// No description provided for @faqCategoryGamification.
  ///
  /// In it, this message translates to:
  /// **'🏆 Gamification'**
  String get faqCategoryGamification;

  /// No description provided for @faqCategoryTechnical.
  ///
  /// In it, this message translates to:
  /// **'⚙️ Tecnico'**
  String get faqCategoryTechnical;

  /// No description provided for @faqNoAnswer.
  ///
  /// In it, this message translates to:
  /// **'Non hai trovato la risposta?'**
  String get faqNoAnswer;

  /// No description provided for @faqContactPrompt.
  ///
  /// In it, this message translates to:
  /// **'Contattaci e ti risponderemo al più presto'**
  String get faqContactPrompt;

  /// No description provided for @faqContactSupport.
  ///
  /// In it, this message translates to:
  /// **'Contatta il supporto'**
  String get faqContactSupport;

  /// No description provided for @faqGeneralQ1.
  ///
  /// In it, this message translates to:
  /// **'Cos\'è TrailShare?'**
  String get faqGeneralQ1;

  /// No description provided for @faqGeneralA1.
  ///
  /// In it, this message translates to:
  /// **'TrailShare è un\'app per registrare e condividere le tue escursioni. Puoi tracciare i tuoi percorsi con GPS, scoprire nuovi sentieri, seguire altri escursionisti e partecipare a sfide settimanali.'**
  String get faqGeneralA1;

  /// No description provided for @faqGeneralQ2.
  ///
  /// In it, this message translates to:
  /// **'L\'app è gratuita?'**
  String get faqGeneralQ2;

  /// No description provided for @faqGeneralA2.
  ///
  /// In it, this message translates to:
  /// **'Sì, TrailShare è completamente gratuita. Tutte le funzionalità sono disponibili senza costi nascosti o abbonamenti.'**
  String get faqGeneralA2;

  /// No description provided for @faqGeneralQ3.
  ///
  /// In it, this message translates to:
  /// **'Devo creare un account?'**
  String get faqGeneralQ3;

  /// No description provided for @faqGeneralA3.
  ///
  /// In it, this message translates to:
  /// **'Sì, è necessario un account per salvare le tue tracce e accedere alle funzionalità social. Puoi registrarti con email, Google o Apple.'**
  String get faqGeneralA3;

  /// No description provided for @faqGeneralQ4.
  ///
  /// In it, this message translates to:
  /// **'I miei dati sono al sicuro?'**
  String get faqGeneralQ4;

  /// No description provided for @faqGeneralA4.
  ///
  /// In it, this message translates to:
  /// **'Assolutamente. I tuoi dati sono protetti e criptati. Puoi consultare la nostra Privacy Policy per tutti i dettagli su come gestiamo le informazioni.'**
  String get faqGeneralA4;

  /// No description provided for @faqTrackingQ1.
  ///
  /// In it, this message translates to:
  /// **'Come registro una traccia?'**
  String get faqTrackingQ1;

  /// No description provided for @faqTrackingA1.
  ///
  /// In it, this message translates to:
  /// **'Vai nella sezione \"Registra\", premi il pulsante verde \"Inizia\" e cammina! L\'app registrerà automaticamente il tuo percorso. Puoi mettere in pausa e riprendere in qualsiasi momento.'**
  String get faqTrackingA1;

  /// No description provided for @faqTrackingQ2.
  ///
  /// In it, this message translates to:
  /// **'Il GPS funziona in background?'**
  String get faqTrackingQ2;

  /// No description provided for @faqTrackingA2.
  ///
  /// In it, this message translates to:
  /// **'Sì, puoi bloccare lo schermo o usare altre app mentre registri. Il tracking continua in background con notifica attiva.'**
  String get faqTrackingA2;

  /// No description provided for @faqTrackingQ3.
  ///
  /// In it, this message translates to:
  /// **'Quanto consuma la batteria?'**
  String get faqTrackingQ3;

  /// No description provided for @faqTrackingA3.
  ///
  /// In it, this message translates to:
  /// **'Il consumo dipende dalla durata dell\'escursione. In media, aspettati un consumo del 5-10% all\'ora. Consigliamo di partire con batteria carica o portare un powerbank.'**
  String get faqTrackingA3;

  /// No description provided for @faqTrackingQ4.
  ///
  /// In it, this message translates to:
  /// **'Funziona senza connessione internet?'**
  String get faqTrackingQ4;

  /// No description provided for @faqTrackingA4.
  ///
  /// In it, this message translates to:
  /// **'Sì! Il tracking GPS funziona completamente offline. Puoi anche scaricare le mappe in anticipo da Impostazioni > Mappe Offline. La sincronizzazione avverrà quando tornerai online.'**
  String get faqTrackingA4;

  /// No description provided for @faqTrackingQ5.
  ///
  /// In it, this message translates to:
  /// **'Come miglioro la precisione GPS?'**
  String get faqTrackingQ5;

  /// No description provided for @faqTrackingA5.
  ///
  /// In it, this message translates to:
  /// **'Assicurati di avere una buona visuale del cielo. Evita zone con copertura fitta o canyon stretti. Attendi qualche secondo prima di iniziare per permettere al GPS di calibrarsi.'**
  String get faqTrackingA5;

  /// No description provided for @faqTrackingQ6.
  ///
  /// In it, this message translates to:
  /// **'Posso importare tracce GPX?'**
  String get faqTrackingQ6;

  /// No description provided for @faqTrackingA6.
  ///
  /// In it, this message translates to:
  /// **'Sì, puoi importare file GPX dalla sezione \"Le mie tracce\". Tocca il pulsante + e seleziona \"Importa GPX\".'**
  String get faqTrackingA6;

  /// No description provided for @faqTrackingQ7.
  ///
  /// In it, this message translates to:
  /// **'Posso esportare le mie tracce?'**
  String get faqTrackingQ7;

  /// No description provided for @faqTrackingA7.
  ///
  /// In it, this message translates to:
  /// **'Certamente! Apri una traccia e tocca l\'icona condividi per esportarla in formato GPX, compatibile con la maggior parte delle app e dispositivi GPS.'**
  String get faqTrackingA7;

  /// No description provided for @faqSocialQ1.
  ///
  /// In it, this message translates to:
  /// **'Come seguo altri utenti?'**
  String get faqSocialQ1;

  /// No description provided for @faqSocialA1.
  ///
  /// In it, this message translates to:
  /// **'Cerca un utente o visita il suo profilo da una traccia pubblica, poi tocca \"Segui\". Vedrai le sue nuove tracce nel tuo feed.'**
  String get faqSocialA1;

  /// No description provided for @faqSocialQ2.
  ///
  /// In it, this message translates to:
  /// **'Cos\'è un \"Cheers\"?'**
  String get faqSocialQ2;

  /// No description provided for @faqSocialA2.
  ///
  /// In it, this message translates to:
  /// **'È il nostro modo di dire \"bella traccia!\". Puoi lasciare un cheers sulle tracce che ti piacciono. Riceverai anche XP per i cheers ricevuti.'**
  String get faqSocialA2;

  /// No description provided for @faqSocialQ3.
  ///
  /// In it, this message translates to:
  /// **'Come pubblico una traccia?'**
  String get faqSocialQ3;

  /// No description provided for @faqSocialA3.
  ///
  /// In it, this message translates to:
  /// **'Dopo aver salvato una traccia, aprila e tocca \"Pubblica\". La traccia sarà visibile nella sezione Esplora e gli altri potranno vederla.'**
  String get faqSocialA3;

  /// No description provided for @faqSocialQ4.
  ///
  /// In it, this message translates to:
  /// **'Posso rendere privata una traccia?'**
  String get faqSocialQ4;

  /// No description provided for @faqSocialA4.
  ///
  /// In it, this message translates to:
  /// **'Le tracce sono private di default. Solo quelle che pubblichi esplicitamente saranno visibili agli altri.'**
  String get faqSocialA4;

  /// No description provided for @faqSocialQ5.
  ///
  /// In it, this message translates to:
  /// **'Cos\'è LiveTrack?'**
  String get faqSocialQ5;

  /// No description provided for @faqSocialA5.
  ///
  /// In it, this message translates to:
  /// **'LiveTrack ti permette di condividere la tua posizione in tempo reale durante un\'escursione. Genera un link che puoi inviare a familiari o amici per farti seguire sulla mappa.'**
  String get faqSocialA5;

  /// No description provided for @faqGamificationQ1.
  ///
  /// In it, this message translates to:
  /// **'Come funzionano gli XP?'**
  String get faqGamificationQ1;

  /// No description provided for @faqGamificationA1.
  ///
  /// In it, this message translates to:
  /// **'Guadagni XP (punti esperienza) completando tracce, ricevendo cheers, ottenendo follower e completando sfide. Più XP accumuli, più sali di livello!'**
  String get faqGamificationA1;

  /// No description provided for @faqGamificationQ2.
  ///
  /// In it, this message translates to:
  /// **'Quanti livelli ci sono?'**
  String get faqGamificationQ2;

  /// No description provided for @faqGamificationA2.
  ///
  /// In it, this message translates to:
  /// **'Ci sono 20 livelli, da \"Principiante\" a \"Immortale\". Ogni livello richiede più XP del precedente.'**
  String get faqGamificationA2;

  /// No description provided for @faqGamificationQ3.
  ///
  /// In it, this message translates to:
  /// **'Come sblocco i badge?'**
  String get faqGamificationQ3;

  /// No description provided for @faqGamificationA3.
  ///
  /// In it, this message translates to:
  /// **'I badge si sbloccano automaticamente raggiungendo determinati traguardi: km percorsi, dislivello accumulato, giorni consecutivi di attività e obiettivi social.'**
  String get faqGamificationA3;

  /// No description provided for @faqGamificationQ4.
  ///
  /// In it, this message translates to:
  /// **'Come funziona la classifica?'**
  String get faqGamificationQ4;

  /// No description provided for @faqGamificationA4.
  ///
  /// In it, this message translates to:
  /// **'La classifica settimanale si basa sui km percorsi e il dislivello accumulato nella settimana. Si resetta ogni lunedì.'**
  String get faqGamificationA4;

  /// No description provided for @faqGamificationQ5.
  ///
  /// In it, this message translates to:
  /// **'Posso vedere i badge degli altri?'**
  String get faqGamificationQ5;

  /// No description provided for @faqGamificationA5.
  ///
  /// In it, this message translates to:
  /// **'Sì, visitando il profilo di un utente puoi vedere i suoi badge sbloccati e il suo livello.'**
  String get faqGamificationA5;

  /// No description provided for @faqTechnicalQ1.
  ///
  /// In it, this message translates to:
  /// **'Come collego una fascia cardio?'**
  String get faqTechnicalQ1;

  /// No description provided for @faqTechnicalA1.
  ///
  /// In it, this message translates to:
  /// **'Durante la registrazione, tocca l\'icona del cuore in alto. L\'app cercherà automaticamente fasce cardio Bluetooth nelle vicinanze. Seleziona la tua per connetterti.'**
  String get faqTechnicalA1;

  /// No description provided for @faqTechnicalQ2.
  ///
  /// In it, this message translates to:
  /// **'Quali fasce cardio sono compatibili?'**
  String get faqTechnicalQ2;

  /// No description provided for @faqTechnicalA2.
  ///
  /// In it, this message translates to:
  /// **'TrailShare supporta qualsiasi fascia cardio Bluetooth Low Energy (BLE) standard, come Polar H10, Garmin HRM-Dual, Wahoo TICKR e molte altre.'**
  String get faqTechnicalA2;

  /// No description provided for @faqTechnicalQ3.
  ///
  /// In it, this message translates to:
  /// **'Come scarico le mappe offline?'**
  String get faqTechnicalQ3;

  /// No description provided for @faqTechnicalA3.
  ///
  /// In it, this message translates to:
  /// **'Vai in Impostazioni > Mappe Offline > Scarica Area. Seleziona l\'area sulla mappa, scegli il livello di dettaglio e avvia il download.'**
  String get faqTechnicalA3;

  /// No description provided for @faqTechnicalQ4.
  ///
  /// In it, this message translates to:
  /// **'Quanto spazio occupano le mappe offline?'**
  String get faqTechnicalQ4;

  /// No description provided for @faqTechnicalA4.
  ///
  /// In it, this message translates to:
  /// **'Dipende dall\'area e dal livello di zoom. Un\'area di 10km con zoom medio occupa circa 30-50 MB. Puoi vedere lo spazio utilizzato nelle impostazioni.'**
  String get faqTechnicalA4;

  /// No description provided for @faqTechnicalQ5.
  ///
  /// In it, this message translates to:
  /// **'Come cambio tema chiaro/scuro?'**
  String get faqTechnicalQ5;

  /// No description provided for @faqTechnicalA5.
  ///
  /// In it, this message translates to:
  /// **'Vai in Impostazioni > Aspetto > Tema. Puoi scegliere tra Chiaro, Scuro o Automatico (segue le impostazioni del sistema).'**
  String get faqTechnicalA5;

  /// No description provided for @faqTechnicalQ6.
  ///
  /// In it, this message translates to:
  /// **'Come elimino il mio account?'**
  String get faqTechnicalQ6;

  /// No description provided for @faqTechnicalA6.
  ///
  /// In it, this message translates to:
  /// **'Vai in Impostazioni > Zona Pericolosa > Elimina Account. Dovrai confermare con la password. Questa azione è irreversibile e cancellerà tutti i tuoi dati.'**
  String get faqTechnicalA6;

  /// No description provided for @deleteAll.
  ///
  /// In it, this message translates to:
  /// **'Elimina tutto'**
  String get deleteAll;

  /// No description provided for @downloadArea.
  ///
  /// In it, this message translates to:
  /// **'Scarica Area'**
  String get downloadArea;

  /// No description provided for @areasCount.
  ///
  /// In it, this message translates to:
  /// **'{count, plural, =1{1 area} other{{count} aree}}'**
  String areasCount(int count);

  /// No description provided for @noOfflineMaps.
  ///
  /// In it, this message translates to:
  /// **'Nessuna mappa offline'**
  String get noOfflineMaps;

  /// No description provided for @downloadMapsForOffline.
  ///
  /// In it, this message translates to:
  /// **'Scarica mappe per usarle quando sei senza connessione'**
  String get downloadMapsForOffline;

  /// No description provided for @areaName.
  ///
  /// In it, this message translates to:
  /// **'Nome area'**
  String get areaName;

  /// No description provided for @areaNameHint.
  ///
  /// In it, this message translates to:
  /// **'Es: Dolomiti, Appennino...'**
  String get areaNameHint;

  /// No description provided for @minZoomLabel.
  ///
  /// In it, this message translates to:
  /// **'Zoom minimo: {value}'**
  String minZoomLabel(int value);

  /// No description provided for @maxZoomLabel.
  ///
  /// In it, this message translates to:
  /// **'Zoom massimo: {value}'**
  String maxZoomLabel(int value);

  /// No description provided for @tilesToDownload.
  ///
  /// In it, this message translates to:
  /// **'Tile da scaricare:'**
  String get tilesToDownload;

  /// No description provided for @estimatedSize.
  ///
  /// In it, this message translates to:
  /// **'Dimensione stimata:'**
  String get estimatedSize;

  /// No description provided for @downloadAction.
  ///
  /// In it, this message translates to:
  /// **'Scarica'**
  String get downloadAction;

  /// No description provided for @deleteArea.
  ///
  /// In it, this message translates to:
  /// **'Elimina area'**
  String get deleteArea;

  /// No description provided for @deleteAreaConfirm.
  ///
  /// In it, this message translates to:
  /// **'Vuoi eliminare \"{name}\"?'**
  String deleteAreaConfirm(String name);

  /// No description provided for @deleteLabel.
  ///
  /// In it, this message translates to:
  /// **'Elimina'**
  String get deleteLabel;

  /// No description provided for @deleteAllMaps.
  ///
  /// In it, this message translates to:
  /// **'Elimina tutte le mappe'**
  String get deleteAllMaps;

  /// No description provided for @deleteAllMapsConfirm.
  ///
  /// In it, this message translates to:
  /// **'Vuoi eliminare tutte le mappe offline? Questa azione non può essere annullata.'**
  String get deleteAllMapsConfirm;

  /// No description provided for @deleteAllAction.
  ///
  /// In it, this message translates to:
  /// **'Elimina tutto'**
  String get deleteAllAction;

  /// No description provided for @selectArea.
  ///
  /// In it, this message translates to:
  /// **'Seleziona Area'**
  String get selectArea;

  /// No description provided for @confirmAction.
  ///
  /// In it, this message translates to:
  /// **'Conferma'**
  String get confirmAction;

  /// No description provided for @tapMapToSelectCenter.
  ///
  /// In it, this message translates to:
  /// **'Tocca la mappa per selezionare il centro'**
  String get tapMapToSelectCenter;

  /// No description provided for @radiusLabel.
  ///
  /// In it, this message translates to:
  /// **'Raggio:'**
  String get radiusLabel;

  /// No description provided for @downloadCompleted.
  ///
  /// In it, this message translates to:
  /// **'✓ Completato!'**
  String get downloadCompleted;

  /// No description provided for @downloadInProgress.
  ///
  /// In it, this message translates to:
  /// **'Download in corso...'**
  String get downloadInProgress;

  /// No description provided for @tileProgress.
  ///
  /// In it, this message translates to:
  /// **'{downloaded} / {total} tile'**
  String tileProgress(int downloaded, int total);

  /// No description provided for @closeAction.
  ///
  /// In it, this message translates to:
  /// **'Chiudi'**
  String get closeAction;

  /// No description provided for @privacyLastUpdated.
  ///
  /// In it, this message translates to:
  /// **'Ultimo aggiornamento: Gennaio 2025'**
  String get privacyLastUpdated;

  /// No description provided for @privacyIntroTitle.
  ///
  /// In it, this message translates to:
  /// **'Introduzione'**
  String get privacyIntroTitle;

  /// No description provided for @privacyIntroContent.
  ///
  /// In it, this message translates to:
  /// **'TrailShare (\"noi\", \"nostro\" o \"app\") rispetta la tua privacy. Questa informativa descrive quali dati raccogliamo, come li utilizziamo e i tuoi diritti in merito.'**
  String get privacyIntroContent;

  /// No description provided for @privacyDataCollectedTitle.
  ///
  /// In it, this message translates to:
  /// **'Dati che raccogliamo'**
  String get privacyDataCollectedTitle;

  /// No description provided for @privacyDataCollectedContent.
  ///
  /// In it, this message translates to:
  /// **'• **Dati di registrazione**: email, nome utente, foto profilo (opzionale)\n• **Dati di posizione**: coordinate GPS durante la registrazione delle tracce\n• **Dati delle attività**: tracce registrate, statistiche, dislivello, distanza\n• **Dati social**: follower, following, \"cheers\" (like)\n• **Dati del dispositivo**: modello, sistema operativo, per migliorare l\'app'**
  String get privacyDataCollectedContent;

  /// No description provided for @privacyDataUsageTitle.
  ///
  /// In it, this message translates to:
  /// **'Come utilizziamo i tuoi dati'**
  String get privacyDataUsageTitle;

  /// No description provided for @privacyDataUsageContent.
  ///
  /// In it, this message translates to:
  /// **'• Fornire e migliorare i servizi dell\'app\n• Salvare e sincronizzare le tue tracce\n• Abilitare funzionalità social (follow, cheers, classifica)\n• Funzionalità LiveTrack per condividere la posizione in tempo reale\n• Analisi aggregate per migliorare l\'esperienza utente'**
  String get privacyDataUsageContent;

  /// No description provided for @privacyDataSharingTitle.
  ///
  /// In it, this message translates to:
  /// **'Condivisione dei dati'**
  String get privacyDataSharingTitle;

  /// No description provided for @privacyDataSharingContent.
  ///
  /// In it, this message translates to:
  /// **'• **Non vendiamo** i tuoi dati personali a terzi\n• Le tracce pubblicate sono visibili ad altri utenti\n• LiveTrack condivide la posizione solo con chi ha il link\n• Utilizziamo Firebase (Google) per l\'archiviazione sicura dei dati'**
  String get privacyDataSharingContent;

  /// No description provided for @privacyRetentionTitle.
  ///
  /// In it, this message translates to:
  /// **'Conservazione dei dati'**
  String get privacyRetentionTitle;

  /// No description provided for @privacyRetentionContent.
  ///
  /// In it, this message translates to:
  /// **'I tuoi dati vengono conservati finché mantieni un account attivo. Puoi eliminare il tuo account in qualsiasi momento dalla sezione Impostazioni, e tutti i tuoi dati verranno rimossi entro 30 giorni.'**
  String get privacyRetentionContent;

  /// No description provided for @privacyRightsTitle.
  ///
  /// In it, this message translates to:
  /// **'I tuoi diritti'**
  String get privacyRightsTitle;

  /// No description provided for @privacyRightsContent.
  ///
  /// In it, this message translates to:
  /// **'• **Accesso**: puoi visualizzare tutti i tuoi dati nell\'app\n• **Modifica**: puoi modificare il tuo profilo in qualsiasi momento\n• **Eliminazione**: puoi eliminare il tuo account e tutti i dati associati\n• **Esportazione**: puoi esportare le tue tracce in formato GPX'**
  String get privacyRightsContent;

  /// No description provided for @privacySecurityTitle.
  ///
  /// In it, this message translates to:
  /// **'Sicurezza'**
  String get privacySecurityTitle;

  /// No description provided for @privacySecurityContent.
  ///
  /// In it, this message translates to:
  /// **'Utilizziamo Firebase Authentication e Firestore con crittografia per proteggere i tuoi dati. Le connessioni sono protette tramite HTTPS.'**
  String get privacySecurityContent;

  /// No description provided for @privacyMinorsTitle.
  ///
  /// In it, this message translates to:
  /// **'Minori'**
  String get privacyMinorsTitle;

  /// No description provided for @privacyMinorsContent.
  ///
  /// In it, this message translates to:
  /// **'L\'app non è destinata a minori di 13 anni. Non raccogliamo consapevolmente dati di bambini sotto questa età.'**
  String get privacyMinorsContent;

  /// No description provided for @privacyChangesTitle.
  ///
  /// In it, this message translates to:
  /// **'Modifiche alla policy'**
  String get privacyChangesTitle;

  /// No description provided for @privacyChangesContent.
  ///
  /// In it, this message translates to:
  /// **'Potremmo aggiornare questa privacy policy. Ti notificheremo di eventuali modifiche significative tramite l\'app o email.'**
  String get privacyChangesContent;

  /// No description provided for @privacyContactTitle.
  ///
  /// In it, this message translates to:
  /// **'Contatti'**
  String get privacyContactTitle;

  /// No description provided for @privacyContactContent.
  ///
  /// In it, this message translates to:
  /// **'Per domande sulla privacy, contattaci a:\n📧 privacy@trailshare.app'**
  String get privacyContactContent;

  /// No description provided for @viewWebVersion.
  ///
  /// In it, this message translates to:
  /// **'Visualizza versione web'**
  String get viewWebVersion;

  /// No description provided for @searchByUsername.
  ///
  /// In it, this message translates to:
  /// **'Cerca per username...'**
  String get searchByUsername;

  /// No description provided for @noUserFoundFor.
  ///
  /// In it, this message translates to:
  /// **'Nessun utente trovato per \"{query}\"'**
  String noUserFoundFor(String query);

  /// No description provided for @tryDifferentUsername.
  ///
  /// In it, this message translates to:
  /// **'Prova con un username diverso'**
  String get tryDifferentUsername;

  /// No description provided for @peopleYouMayKnow.
  ///
  /// In it, this message translates to:
  /// **'Persone che potresti conoscere'**
  String get peopleYouMayKnow;

  /// No description provided for @noSuggestionsNow.
  ///
  /// In it, this message translates to:
  /// **'Nessun suggerimento al momento'**
  String get noSuggestionsNow;

  /// No description provided for @searchUsersAbove.
  ///
  /// In it, this message translates to:
  /// **'Cerca utenti con la barra in alto'**
  String get searchUsersAbove;

  /// No description provided for @levelLabel.
  ///
  /// In it, this message translates to:
  /// **'Livello {level}'**
  String levelLabel(int level);

  /// No description provided for @followersOf.
  ///
  /// In it, this message translates to:
  /// **'Follower di {name}'**
  String followersOf(String name);

  /// No description provided for @followedBy.
  ///
  /// In it, this message translates to:
  /// **'Seguiti da {name}'**
  String followedBy(String name);

  /// No description provided for @noFollowersYet.
  ///
  /// In it, this message translates to:
  /// **'Nessun follower ancora'**
  String get noFollowersYet;

  /// No description provided for @notFollowingAnyone.
  ///
  /// In it, this message translates to:
  /// **'Non segue nessuno'**
  String get notFollowingAnyone;

  /// No description provided for @shareHikesToGetKnown.
  ///
  /// In it, this message translates to:
  /// **'Condividi le tue escursioni per farti conoscere!'**
  String get shareHikesToGetKnown;

  /// No description provided for @exploreCommunity.
  ///
  /// In it, this message translates to:
  /// **'Esplora la community per trovare persone interessanti.'**
  String get exploreCommunity;

  /// No description provided for @skipAction.
  ///
  /// In it, this message translates to:
  /// **'Salta'**
  String get skipAction;

  /// No description provided for @startAction.
  ///
  /// In it, this message translates to:
  /// **'Inizia!'**
  String get startAction;

  /// No description provided for @nextAction.
  ///
  /// In it, this message translates to:
  /// **'Avanti'**
  String get nextAction;

  /// No description provided for @onboardingWelcomeTitle.
  ///
  /// In it, this message translates to:
  /// **'Benvenuto in TrailShare'**
  String get onboardingWelcomeTitle;

  /// No description provided for @onboardingWelcomeDesc.
  ///
  /// In it, this message translates to:
  /// **'La tua app per registrare e condividere avventure outdoor. Traccia i tuoi percorsi, scopri nuovi sentieri e connettiti con altri escursionisti.'**
  String get onboardingWelcomeDesc;

  /// No description provided for @onboardingTrackTitle.
  ///
  /// In it, this message translates to:
  /// **'Traccia i tuoi percorsi'**
  String get onboardingTrackTitle;

  /// No description provided for @onboardingTrackDesc.
  ///
  /// In it, this message translates to:
  /// **'Registra le tue escursioni con GPS preciso. Visualizza distanza, dislivello, velocità e tempo in tempo reale anche in background.'**
  String get onboardingTrackDesc;

  /// No description provided for @onboardingExploreTitle.
  ///
  /// In it, this message translates to:
  /// **'Scopri nuovi sentieri'**
  String get onboardingExploreTitle;

  /// No description provided for @onboardingExploreDesc.
  ///
  /// In it, this message translates to:
  /// **'Esplora percorsi pubblicati dalla community. Salva i tuoi preferiti nella wishlist e pianifica la tua prossima avventura.'**
  String get onboardingExploreDesc;

  /// No description provided for @onboardingConnectTitle.
  ///
  /// In it, this message translates to:
  /// **'Connettiti con altri'**
  String get onboardingConnectTitle;

  /// No description provided for @onboardingConnectDesc.
  ///
  /// In it, this message translates to:
  /// **'Segui amici ed escursionisti, condividi i tuoi percorsi e scala la classifica settimanale. Guadagna XP e sblocca badge!'**
  String get onboardingConnectDesc;

  /// No description provided for @onboardingOfflineTitle.
  ///
  /// In it, this message translates to:
  /// **'Funziona anche offline'**
  String get onboardingOfflineTitle;

  /// No description provided for @onboardingOfflineDesc.
  ///
  /// In it, this message translates to:
  /// **'Scarica le mappe per usarle senza connessione. Il tracking GPS funziona sempre, anche in modalità aereo.'**
  String get onboardingOfflineDesc;

  /// No description provided for @chooseYourUsername.
  ///
  /// In it, this message translates to:
  /// **'Scegli il tuo username'**
  String get chooseYourUsername;

  /// No description provided for @usernameVisibleToOthers.
  ///
  /// In it, this message translates to:
  /// **'Questo nome sarà visibile agli altri utenti di TrailShare'**
  String get usernameVisibleToOthers;

  /// No description provided for @usernameLabel.
  ///
  /// In it, this message translates to:
  /// **'Username'**
  String get usernameLabel;

  /// No description provided for @usernameExampleHint.
  ///
  /// In it, this message translates to:
  /// **'es. mario_rossi'**
  String get usernameExampleHint;

  /// No description provided for @usernameRules.
  ///
  /// In it, this message translates to:
  /// **'3-20 caratteri • Lettere, numeri, punti e underscore'**
  String get usernameRules;

  /// No description provided for @enterUsername.
  ///
  /// In it, this message translates to:
  /// **'Inserisci un username'**
  String get enterUsername;

  /// No description provided for @usernameMinChars.
  ///
  /// In it, this message translates to:
  /// **'Minimo 3 caratteri'**
  String get usernameMinChars;

  /// No description provided for @usernameMaxChars.
  ///
  /// In it, this message translates to:
  /// **'Massimo 20 caratteri'**
  String get usernameMaxChars;

  /// No description provided for @usernameInvalidChars.
  ///
  /// In it, this message translates to:
  /// **'Solo lettere, numeri, punti e underscore'**
  String get usernameInvalidChars;

  /// No description provided for @usernameAlreadyTakenChooseAnother.
  ///
  /// In it, this message translates to:
  /// **'Username già in uso, scegline un altro'**
  String get usernameAlreadyTakenChooseAnother;

  /// No description provided for @continueWithApple.
  ///
  /// In it, this message translates to:
  /// **'Continua con Apple'**
  String get continueWithApple;

  /// No description provided for @continueWithGoogle.
  ///
  /// In it, this message translates to:
  /// **'Continua con Google'**
  String get continueWithGoogle;

  /// No description provided for @orDivider.
  ///
  /// In it, this message translates to:
  /// **'oppure'**
  String get orDivider;

  /// No description provided for @enterYourEmail.
  ///
  /// In it, this message translates to:
  /// **'Inserisci la tua email'**
  String get enterYourEmail;

  /// No description provided for @invalidEmail.
  ///
  /// In it, this message translates to:
  /// **'Email non valida'**
  String get invalidEmail;

  /// No description provided for @passwordLabel.
  ///
  /// In it, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @enterPassword.
  ///
  /// In it, this message translates to:
  /// **'Inserisci la password'**
  String get enterPassword;

  /// No description provided for @resetPassword.
  ///
  /// In it, this message translates to:
  /// **'Recupera password'**
  String get resetPassword;

  /// No description provided for @enterEmailForReset.
  ///
  /// In it, this message translates to:
  /// **'Inserisci la tua email per ricevere il link di reset.'**
  String get enterEmailForReset;

  /// No description provided for @sendAction.
  ///
  /// In it, this message translates to:
  /// **'Invia'**
  String get sendAction;

  /// No description provided for @resetEmailSent.
  ///
  /// In it, this message translates to:
  /// **'Email di reset inviata!'**
  String get resetEmailSent;

  /// No description provided for @genericError.
  ///
  /// In it, this message translates to:
  /// **'Errore'**
  String get genericError;

  /// No description provided for @loginAction.
  ///
  /// In it, this message translates to:
  /// **'Accedi'**
  String get loginAction;

  /// No description provided for @noAccountQuestion.
  ///
  /// In it, this message translates to:
  /// **'Non hai un account?'**
  String get noAccountQuestion;

  /// No description provided for @registerAction.
  ///
  /// In it, this message translates to:
  /// **'Registrati'**
  String get registerAction;

  /// No description provided for @loginCancelled.
  ///
  /// In it, this message translates to:
  /// **'Accesso annullato'**
  String get loginCancelled;

  /// No description provided for @createAccount.
  ///
  /// In it, this message translates to:
  /// **'Crea account'**
  String get createAccount;

  /// No description provided for @joinTrailShare.
  ///
  /// In it, this message translates to:
  /// **'Unisciti a TrailShare'**
  String get joinTrailShare;

  /// No description provided for @createAccountToSaveTracks.
  ///
  /// In it, this message translates to:
  /// **'Crea un account per salvare le tue tracce'**
  String get createAccountToSaveTracks;

  /// No description provided for @orRegisterWithEmail.
  ///
  /// In it, this message translates to:
  /// **'oppure registrati con email'**
  String get orRegisterWithEmail;

  /// No description provided for @enterAPassword.
  ///
  /// In it, this message translates to:
  /// **'Inserisci una password'**
  String get enterAPassword;

  /// No description provided for @passwordMinSixChars.
  ///
  /// In it, this message translates to:
  /// **'Minimo 6 caratteri'**
  String get passwordMinSixChars;

  /// No description provided for @passwordTooShort.
  ///
  /// In it, this message translates to:
  /// **'La password deve avere almeno 6 caratteri'**
  String get passwordTooShort;

  /// No description provided for @confirmYourPassword.
  ///
  /// In it, this message translates to:
  /// **'Conferma la password'**
  String get confirmYourPassword;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In it, this message translates to:
  /// **'Le password non coincidono'**
  String get passwordsDoNotMatch;

  /// No description provided for @accountCreatedSuccess.
  ///
  /// In it, this message translates to:
  /// **'✅ Account creato con successo!'**
  String get accountCreatedSuccess;

  /// No description provided for @acceptTermsAndPrivacy.
  ///
  /// In it, this message translates to:
  /// **'Creando un account accetti i nostri Termini di servizio e la Privacy Policy'**
  String get acceptTermsAndPrivacy;

  /// No description provided for @tracksTabCount.
  ///
  /// In it, this message translates to:
  /// **'Tracce ({count})'**
  String tracksTabCount(int count);

  /// No description provided for @groupsTabCount.
  ///
  /// In it, this message translates to:
  /// **'Gruppi ({count})'**
  String groupsTabCount(int count);

  /// No description provided for @eventsTabCount.
  ///
  /// In it, this message translates to:
  /// **'Eventi ({count})'**
  String eventsTabCount(int count);

  /// No description provided for @showList.
  ///
  /// In it, this message translates to:
  /// **'Mostra lista'**
  String get showList;

  /// No description provided for @showMap.
  ///
  /// In it, this message translates to:
  /// **'Mostra mappa'**
  String get showMap;

  /// No description provided for @searchTracksOrUsers.
  ///
  /// In it, this message translates to:
  /// **'Cerca tracce o utenti...'**
  String get searchTracksOrUsers;

  /// No description provided for @noSharedTracks.
  ///
  /// In it, this message translates to:
  /// **'Nessuna traccia condivisa'**
  String get noSharedTracks;

  /// No description provided for @noResultsForQuery.
  ///
  /// In it, this message translates to:
  /// **'Nessun risultato per \"{query}\"'**
  String noResultsForQuery(String query);

  /// No description provided for @tracksLabel.
  ///
  /// In it, this message translates to:
  /// **'tracce'**
  String get tracksLabel;

  /// No description provided for @loadMore.
  ///
  /// In it, this message translates to:
  /// **'Carica altre'**
  String get loadMore;

  /// No description provided for @loadMoreTracks.
  ///
  /// In it, this message translates to:
  /// **'Carica altre tracce'**
  String get loadMoreTracks;

  /// No description provided for @newGroup.
  ///
  /// In it, this message translates to:
  /// **'Nuovo Gruppo'**
  String get newGroup;

  /// No description provided for @myFilterCount.
  ///
  /// In it, this message translates to:
  /// **'I miei ({count})'**
  String myFilterCount(int count);

  /// No description provided for @discoverFilter.
  ///
  /// In it, this message translates to:
  /// **'Scopri'**
  String get discoverFilter;

  /// No description provided for @codeLabel.
  ///
  /// In it, this message translates to:
  /// **'Codice'**
  String get codeLabel;

  /// No description provided for @noGroups.
  ///
  /// In it, this message translates to:
  /// **'Nessun gruppo'**
  String get noGroups;

  /// No description provided for @createGroupCTA.
  ///
  /// In it, this message translates to:
  /// **'Crea un gruppo per organizzare uscite, lanciare sfide e chattare con i tuoi compagni di avventura!'**
  String get createGroupCTA;

  /// No description provided for @noGroupsAvailable.
  ///
  /// In it, this message translates to:
  /// **'Nessun gruppo disponibile'**
  String get noGroupsAvailable;

  /// No description provided for @noPublicGroupsCTA.
  ///
  /// In it, this message translates to:
  /// **'Non ci sono gruppi pubblici a cui unirti al momento. Creane uno tu!'**
  String get noPublicGroupsCTA;

  /// No description provided for @memberCountPlural.
  ///
  /// In it, this message translates to:
  /// **'{count, plural, =1{1 membro} other{{count} membri}}'**
  String memberCountPlural(int count);

  /// No description provided for @publicLabel.
  ///
  /// In it, this message translates to:
  /// **'Pubblico'**
  String get publicLabel;

  /// No description provided for @privateLabel.
  ///
  /// In it, this message translates to:
  /// **'Privato'**
  String get privateLabel;

  /// No description provided for @secretLabel.
  ///
  /// In it, this message translates to:
  /// **'Segreto'**
  String get secretLabel;

  /// No description provided for @joinedGroupSnack.
  ///
  /// In it, this message translates to:
  /// **'Ti sei unito a \"{name}\"!'**
  String joinedGroupSnack(String name);

  /// No description provided for @joinGroupAction.
  ///
  /// In it, this message translates to:
  /// **'Unisciti'**
  String get joinGroupAction;

  /// No description provided for @requestSentSnack.
  ///
  /// In it, this message translates to:
  /// **'Richiesta inviata a \"{name}\"!'**
  String requestSentSnack(String name);

  /// No description provided for @requestAction.
  ///
  /// In it, this message translates to:
  /// **'Richiedi'**
  String get requestAction;

  /// No description provided for @publicEventsFilter.
  ///
  /// In it, this message translates to:
  /// **'Pubblici'**
  String get publicEventsFilter;

  /// No description provided for @activeChallengesCount.
  ///
  /// In it, this message translates to:
  /// **'Sfide attive ({count})'**
  String activeChallengesCount(int count);

  /// No description provided for @noEventsScheduled.
  ///
  /// In it, this message translates to:
  /// **'Nessun evento in programma'**
  String get noEventsScheduled;

  /// No description provided for @groupEventsWillAppear.
  ///
  /// In it, this message translates to:
  /// **'Gli eventi dei tuoi gruppi appariranno qui'**
  String get groupEventsWillAppear;

  /// No description provided for @noPublicEvents.
  ///
  /// In it, this message translates to:
  /// **'Nessun evento pubblico'**
  String get noPublicEvents;

  /// No description provided for @publicEventsWillAppear.
  ///
  /// In it, this message translates to:
  /// **'Gli eventi dei gruppi pubblici appariranno qui'**
  String get publicEventsWillAppear;

  /// No description provided for @participating.
  ///
  /// In it, this message translates to:
  /// **'✓ Partecipo'**
  String get participating;

  /// No description provided for @clearSearch.
  ///
  /// In it, this message translates to:
  /// **'Cancella ricerca'**
  String get clearSearch;

  /// No description provided for @enterInviteCodeDesc.
  ///
  /// In it, this message translates to:
  /// **'Inserisci il codice invito ricevuto per unirti a un gruppo.'**
  String get enterInviteCodeDesc;

  /// No description provided for @codeMustBeSixChars.
  ///
  /// In it, this message translates to:
  /// **'Il codice deve essere di 6 caratteri'**
  String get codeMustBeSixChars;

  /// No description provided for @unknownError.
  ///
  /// In it, this message translates to:
  /// **'Errore sconosciuto'**
  String get unknownError;

  /// No description provided for @joinedGroupGeneric.
  ///
  /// In it, this message translates to:
  /// **'Ti sei unito al gruppo!'**
  String get joinedGroupGeneric;

  /// No description provided for @daysShort.
  ///
  /// In it, this message translates to:
  /// **'{days}g'**
  String daysShort(int days);

  /// No description provided for @monthShortJan.
  ///
  /// In it, this message translates to:
  /// **'GEN'**
  String get monthShortJan;

  /// No description provided for @monthShortFeb.
  ///
  /// In it, this message translates to:
  /// **'FEB'**
  String get monthShortFeb;

  /// No description provided for @monthShortMar.
  ///
  /// In it, this message translates to:
  /// **'MAR'**
  String get monthShortMar;

  /// No description provided for @monthShortApr.
  ///
  /// In it, this message translates to:
  /// **'APR'**
  String get monthShortApr;

  /// No description provided for @monthShortMay.
  ///
  /// In it, this message translates to:
  /// **'MAG'**
  String get monthShortMay;

  /// No description provided for @monthShortJun.
  ///
  /// In it, this message translates to:
  /// **'GIU'**
  String get monthShortJun;

  /// No description provided for @monthShortJul.
  ///
  /// In it, this message translates to:
  /// **'LUG'**
  String get monthShortJul;

  /// No description provided for @monthShortAug.
  ///
  /// In it, this message translates to:
  /// **'AGO'**
  String get monthShortAug;

  /// No description provided for @monthShortSep.
  ///
  /// In it, this message translates to:
  /// **'SET'**
  String get monthShortSep;

  /// No description provided for @monthShortOct.
  ///
  /// In it, this message translates to:
  /// **'OTT'**
  String get monthShortOct;

  /// No description provided for @monthShortNov.
  ///
  /// In it, this message translates to:
  /// **'NOV'**
  String get monthShortNov;

  /// No description provided for @monthShortDec.
  ///
  /// In it, this message translates to:
  /// **'DIC'**
  String get monthShortDec;

  /// No description provided for @leaveGroupConfirm.
  ///
  /// In it, this message translates to:
  /// **'Vuoi uscire da \"{name}\"?'**
  String leaveGroupConfirm(String name);

  /// No description provided for @exitAction.
  ///
  /// In it, this message translates to:
  /// **'Esci'**
  String get exitAction;

  /// No description provided for @deleteAction.
  ///
  /// In it, this message translates to:
  /// **'Elimina'**
  String get deleteAction;

  /// No description provided for @membersLabel.
  ///
  /// In it, this message translates to:
  /// **'Membri'**
  String get membersLabel;

  /// No description provided for @chatTab.
  ///
  /// In it, this message translates to:
  /// **'Chat'**
  String get chatTab;

  /// No description provided for @eventsTab.
  ///
  /// In it, this message translates to:
  /// **'Eventi'**
  String get eventsTab;

  /// No description provided for @challengesTab.
  ///
  /// In it, this message translates to:
  /// **'Sfide'**
  String get challengesTab;

  /// No description provided for @infoTab.
  ///
  /// In it, this message translates to:
  /// **'Info'**
  String get infoTab;

  /// No description provided for @inviteCodeTitle.
  ///
  /// In it, this message translates to:
  /// **'Codice Invito'**
  String get inviteCodeTitle;

  /// No description provided for @regenerateCode.
  ///
  /// In it, this message translates to:
  /// **'Rigenera codice'**
  String get regenerateCode;

  /// No description provided for @shareInviteCodeDesc.
  ///
  /// In it, this message translates to:
  /// **'Condividi questo codice per invitare nuove persone al gruppo'**
  String get shareInviteCodeDesc;

  /// No description provided for @publicVisibilityDesc.
  ///
  /// In it, this message translates to:
  /// **'Visibile, chiunque può unirsi'**
  String get publicVisibilityDesc;

  /// No description provided for @privateVisibilityDesc.
  ///
  /// In it, this message translates to:
  /// **'Visibile, richiesta accesso'**
  String get privateVisibilityDesc;

  /// No description provided for @secretVisibilityDesc.
  ///
  /// In it, this message translates to:
  /// **'Invisibile, solo codice invito'**
  String get secretVisibilityDesc;

  /// No description provided for @accessRequests.
  ///
  /// In it, this message translates to:
  /// **'Richieste di accesso'**
  String get accessRequests;

  /// No description provided for @requestedOnDate.
  ///
  /// In it, this message translates to:
  /// **'Richiesta il {date}'**
  String requestedOnDate(String date);

  /// No description provided for @pendingStatus.
  ///
  /// In it, this message translates to:
  /// **'In attesa'**
  String get pendingStatus;

  /// No description provided for @userApproved.
  ///
  /// In it, this message translates to:
  /// **'{username} approvato!'**
  String userApproved(String username);

  /// No description provided for @descriptionLabel.
  ///
  /// In it, this message translates to:
  /// **'Descrizione'**
  String get descriptionLabel;

  /// No description provided for @editAction.
  ///
  /// In it, this message translates to:
  /// **'Modifica'**
  String get editAction;

  /// No description provided for @noDescriptionHint.
  ///
  /// In it, this message translates to:
  /// **'Nessuna descrizione. Tocca modifica per aggiungerne una.'**
  String get noDescriptionHint;

  /// No description provided for @createdOnLabel.
  ///
  /// In it, this message translates to:
  /// **'Creato il'**
  String get createdOnLabel;

  /// No description provided for @yourRole.
  ///
  /// In it, this message translates to:
  /// **'Il tuo ruolo'**
  String get yourRole;

  /// No description provided for @administratorRole.
  ///
  /// In it, this message translates to:
  /// **'Amministratore'**
  String get administratorRole;

  /// No description provided for @memberRole.
  ///
  /// In it, this message translates to:
  /// **'Membro'**
  String get memberRole;

  /// No description provided for @founderLabel.
  ///
  /// In it, this message translates to:
  /// **'Fondatore'**
  String get founderLabel;

  /// No description provided for @youCreatedThisGroup.
  ///
  /// In it, this message translates to:
  /// **'Tu hai creato questo gruppo'**
  String get youCreatedThisGroup;

  /// No description provided for @editGroup.
  ///
  /// In it, this message translates to:
  /// **'Modifica gruppo'**
  String get editGroup;

  /// No description provided for @groupNameLabel.
  ///
  /// In it, this message translates to:
  /// **'Nome gruppo'**
  String get groupNameLabel;

  /// No description provided for @descriptionHint.
  ///
  /// In it, this message translates to:
  /// **'Descrivi il tuo gruppo...'**
  String get descriptionHint;

  /// No description provided for @nameMinThreeChars.
  ///
  /// In it, this message translates to:
  /// **'Il nome deve avere almeno 3 caratteri'**
  String get nameMinThreeChars;

  /// No description provided for @regenerateCodeTitle.
  ///
  /// In it, this message translates to:
  /// **'Rigenera codice'**
  String get regenerateCodeTitle;

  /// No description provided for @regenerateCodeDesc.
  ///
  /// In it, this message translates to:
  /// **'Il vecchio codice non funzionerà più. Vuoi generare un nuovo codice invito?'**
  String get regenerateCodeDesc;

  /// No description provided for @regenerateAction.
  ///
  /// In it, this message translates to:
  /// **'Rigenera'**
  String get regenerateAction;

  /// No description provided for @newCodeSnack.
  ///
  /// In it, this message translates to:
  /// **'Nuovo codice: {code}'**
  String newCodeSnack(String code);

  /// No description provided for @codeCopied.
  ///
  /// In it, this message translates to:
  /// **'Codice copiato!'**
  String get codeCopied;

  /// No description provided for @groupNowIs.
  ///
  /// In it, this message translates to:
  /// **'Gruppo ora è {visibility}'**
  String groupNowIs(String visibility);

  /// No description provided for @inviteShareText.
  ///
  /// In it, this message translates to:
  /// **'Unisciti al gruppo \"{name}\" su TrailShare!\n\nUsa il codice invito: {code}\n\nScarica TrailShare e inserisci il codice nella sezione Community > Gruppi.'**
  String inviteShareText(String name, String code);

  /// No description provided for @inviteShareSubject.
  ///
  /// In it, this message translates to:
  /// **'Invito gruppo TrailShare'**
  String get inviteShareSubject;

  /// No description provided for @userLabel.
  ///
  /// In it, this message translates to:
  /// **'Utente'**
  String get userLabel;

  /// No description provided for @leaveGroupTitle.
  ///
  /// In it, this message translates to:
  /// **'Esci dal gruppo'**
  String get leaveGroupTitle;

  /// No description provided for @deleteGroupMenu.
  ///
  /// In it, this message translates to:
  /// **'Elimina gruppo'**
  String get deleteGroupMenu;

  /// No description provided for @monthLowerGen.
  ///
  /// In it, this message translates to:
  /// **'gen'**
  String get monthLowerGen;

  /// No description provided for @monthLowerFeb.
  ///
  /// In it, this message translates to:
  /// **'feb'**
  String get monthLowerFeb;

  /// No description provided for @monthLowerMar.
  ///
  /// In it, this message translates to:
  /// **'mar'**
  String get monthLowerMar;

  /// No description provided for @monthLowerApr.
  ///
  /// In it, this message translates to:
  /// **'apr'**
  String get monthLowerApr;

  /// No description provided for @monthLowerMag.
  ///
  /// In it, this message translates to:
  /// **'mag'**
  String get monthLowerMag;

  /// No description provided for @monthLowerGiu.
  ///
  /// In it, this message translates to:
  /// **'giu'**
  String get monthLowerGiu;

  /// No description provided for @monthLowerLug.
  ///
  /// In it, this message translates to:
  /// **'lug'**
  String get monthLowerLug;

  /// No description provided for @monthLowerAgo.
  ///
  /// In it, this message translates to:
  /// **'ago'**
  String get monthLowerAgo;

  /// No description provided for @monthLowerSet.
  ///
  /// In it, this message translates to:
  /// **'set'**
  String get monthLowerSet;

  /// No description provided for @monthLowerOtt.
  ///
  /// In it, this message translates to:
  /// **'ott'**
  String get monthLowerOtt;

  /// No description provided for @monthLowerNov.
  ///
  /// In it, this message translates to:
  /// **'nov'**
  String get monthLowerNov;

  /// No description provided for @monthLowerDic.
  ///
  /// In it, this message translates to:
  /// **'dic'**
  String get monthLowerDic;

  /// No description provided for @groupNameHint.
  ///
  /// In it, this message translates to:
  /// **'Es. Escursionisti Orobie'**
  String get groupNameHint;

  /// No description provided for @enterGroupName.
  ///
  /// In it, this message translates to:
  /// **'Inserisci un nome per il gruppo'**
  String get enterGroupName;

  /// No description provided for @whatDoesYourGroupDo.
  ///
  /// In it, this message translates to:
  /// **'Cosa fa il vostro gruppo?'**
  String get whatDoesYourGroupDo;

  /// No description provided for @visibilityLabel.
  ///
  /// In it, this message translates to:
  /// **'Visibilità'**
  String get visibilityLabel;

  /// No description provided for @publicVisibilityDescFull.
  ///
  /// In it, this message translates to:
  /// **'Visibile a tutti, chiunque può unirsi'**
  String get publicVisibilityDescFull;

  /// No description provided for @privateVisibilityDescFull.
  ///
  /// In it, this message translates to:
  /// **'Visibile a tutti, ma serve approvazione admin'**
  String get privateVisibilityDescFull;

  /// No description provided for @secretVisibilityDescFull.
  ///
  /// In it, this message translates to:
  /// **'Invisibile, accessibile solo tramite codice invito'**
  String get secretVisibilityDescFull;

  /// No description provided for @groupCreated.
  ///
  /// In it, this message translates to:
  /// **'Gruppo creato!'**
  String get groupCreated;

  /// No description provided for @groupCreationError.
  ///
  /// In it, this message translates to:
  /// **'Errore nella creazione del gruppo'**
  String get groupCreationError;

  /// No description provided for @eventLabel.
  ///
  /// In it, this message translates to:
  /// **'Evento'**
  String get eventLabel;

  /// No description provided for @deletePost.
  ///
  /// In it, this message translates to:
  /// **'Elimina post'**
  String get deletePost;

  /// No description provided for @deletePostConfirm.
  ///
  /// In it, this message translates to:
  /// **'Vuoi eliminare questo post?'**
  String get deletePostConfirm;

  /// No description provided for @deleteEvent.
  ///
  /// In it, this message translates to:
  /// **'Elimina evento'**
  String get deleteEvent;

  /// No description provided for @deleteEventConfirm.
  ///
  /// In it, this message translates to:
  /// **'Vuoi eliminare questo evento? L\'azione è irreversibile.'**
  String get deleteEventConfirm;

  /// No description provided for @changeCover.
  ///
  /// In it, this message translates to:
  /// **'Cambia copertina'**
  String get changeCover;

  /// No description provided for @addCover.
  ///
  /// In it, this message translates to:
  /// **'Aggiungi copertina'**
  String get addCover;

  /// No description provided for @participantsWithMax.
  ///
  /// In it, this message translates to:
  /// **'Partecipanti ({count}/{max})'**
  String participantsWithMax(String count, String max);

  /// No description provided for @participantsOnly.
  ///
  /// In it, this message translates to:
  /// **'Partecipanti ({count})'**
  String participantsOnly(String count);

  /// No description provided for @noParticipantsYet.
  ///
  /// In it, this message translates to:
  /// **'Nessun partecipante ancora'**
  String get noParticipantsYet;

  /// No description provided for @enrolledWithdraw.
  ///
  /// In it, this message translates to:
  /// **'Sei iscritto — Ritirati'**
  String get enrolledWithdraw;

  /// No description provided for @eventFull.
  ///
  /// In it, this message translates to:
  /// **'Evento al completo'**
  String get eventFull;

  /// No description provided for @participate.
  ///
  /// In it, this message translates to:
  /// **'Partecipa'**
  String get participate;

  /// No description provided for @updatesLabel.
  ///
  /// In it, this message translates to:
  /// **'Aggiornamenti'**
  String get updatesLabel;

  /// No description provided for @writeUpdate.
  ///
  /// In it, this message translates to:
  /// **'Scrivi un aggiornamento...'**
  String get writeUpdate;

  /// No description provided for @addPhoto.
  ///
  /// In it, this message translates to:
  /// **'Aggiungi foto'**
  String get addPhoto;

  /// No description provided for @publish.
  ///
  /// In it, this message translates to:
  /// **'Pubblica'**
  String get publish;

  /// No description provided for @noUpdates.
  ///
  /// In it, this message translates to:
  /// **'Nessun aggiornamento'**
  String get noUpdates;

  /// No description provided for @shareEventPhotos.
  ///
  /// In it, this message translates to:
  /// **'Condividi info, novità o foto dell\'evento!'**
  String get shareEventPhotos;

  /// No description provided for @justNow.
  ///
  /// In it, this message translates to:
  /// **'Ora'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In it, this message translates to:
  /// **'{count} min fa'**
  String minutesAgo(int count);

  /// No description provided for @hoursAgo.
  ///
  /// In it, this message translates to:
  /// **'{count} ore fa'**
  String hoursAgo(int count);

  /// No description provided for @daysAgo.
  ///
  /// In it, this message translates to:
  /// **'{count} giorni fa'**
  String daysAgo(int count);

  /// No description provided for @concluded.
  ///
  /// In it, this message translates to:
  /// **'Concluso'**
  String get concluded;

  /// No description provided for @organizedBy.
  ///
  /// In it, this message translates to:
  /// **'Organizzato da {name}'**
  String organizedBy(String name);

  /// No description provided for @photoEmoji.
  ///
  /// In it, this message translates to:
  /// **'📷 Foto'**
  String get photoEmoji;

  /// No description provided for @deleteEventMenu.
  ///
  /// In it, this message translates to:
  /// **'Elimina evento'**
  String get deleteEventMenu;

  /// No description provided for @uploadError.
  ///
  /// In it, this message translates to:
  /// **'Errore upload: {error}'**
  String uploadError(String error);

  /// No description provided for @monthFullJan.
  ///
  /// In it, this message translates to:
  /// **'Gennaio'**
  String get monthFullJan;

  /// No description provided for @monthFullFeb.
  ///
  /// In it, this message translates to:
  /// **'Febbraio'**
  String get monthFullFeb;

  /// No description provided for @monthFullMar.
  ///
  /// In it, this message translates to:
  /// **'Marzo'**
  String get monthFullMar;

  /// No description provided for @monthFullApr.
  ///
  /// In it, this message translates to:
  /// **'Aprile'**
  String get monthFullApr;

  /// No description provided for @monthFullMay.
  ///
  /// In it, this message translates to:
  /// **'Maggio'**
  String get monthFullMay;

  /// No description provided for @monthFullJun.
  ///
  /// In it, this message translates to:
  /// **'Giugno'**
  String get monthFullJun;

  /// No description provided for @monthFullJul.
  ///
  /// In it, this message translates to:
  /// **'Luglio'**
  String get monthFullJul;

  /// No description provided for @monthFullAug.
  ///
  /// In it, this message translates to:
  /// **'Agosto'**
  String get monthFullAug;

  /// No description provided for @monthFullSep.
  ///
  /// In it, this message translates to:
  /// **'Settembre'**
  String get monthFullSep;

  /// No description provided for @monthFullOct.
  ///
  /// In it, this message translates to:
  /// **'Ottobre'**
  String get monthFullOct;

  /// No description provided for @monthFullNov.
  ///
  /// In it, this message translates to:
  /// **'Novembre'**
  String get monthFullNov;

  /// No description provided for @monthFullDec.
  ///
  /// In it, this message translates to:
  /// **'Dicembre'**
  String get monthFullDec;

  /// No description provided for @sendImageError.
  ///
  /// In it, this message translates to:
  /// **'Errore invio immagine: {error}'**
  String sendImageError(String error);

  /// No description provided for @yesterdayAtTime.
  ///
  /// In it, this message translates to:
  /// **'Ieri {time}'**
  String yesterdayAtTime(String time);

  /// No description provided for @upcomingFilter.
  ///
  /// In it, this message translates to:
  /// **'Prossimi'**
  String get upcomingFilter;

  /// No description provided for @allFilter.
  ///
  /// In it, this message translates to:
  /// **'Tutti'**
  String get allFilter;

  /// No description provided for @noEventsTitle.
  ///
  /// In it, this message translates to:
  /// **'Nessun evento'**
  String get noEventsTitle;

  /// No description provided for @organizeAnOuting.
  ///
  /// In it, this message translates to:
  /// **'Organizza un\'uscita!'**
  String get organizeAnOuting;

  /// No description provided for @pastLabel.
  ///
  /// In it, this message translates to:
  /// **'Passato'**
  String get pastLabel;

  /// No description provided for @withdraw.
  ///
  /// In it, this message translates to:
  /// **'Ritirati'**
  String get withdraw;

  /// No description provided for @participantsCountWithMax.
  ///
  /// In it, this message translates to:
  /// **'{count}/{max} partecipanti'**
  String participantsCountWithMax(String count, String max);

  /// No description provided for @participantsCountSimple.
  ///
  /// In it, this message translates to:
  /// **'{count} partecipanti'**
  String participantsCountSimple(String count);

  /// No description provided for @createFirstGroup.
  ///
  /// In it, this message translates to:
  /// **'Crea il tuo primo gruppo'**
  String get createFirstGroup;

  /// No description provided for @myGroupsTab.
  ///
  /// In it, this message translates to:
  /// **'I miei Gruppi'**
  String get myGroupsTab;

  /// No description provided for @newChallenge.
  ///
  /// In it, this message translates to:
  /// **'Nuova Sfida'**
  String get newChallenge;

  /// No description provided for @challengeTitleRequired.
  ///
  /// In it, this message translates to:
  /// **'Titolo sfida *'**
  String get challengeTitleRequired;

  /// No description provided for @challengeTitleHint.
  ///
  /// In it, this message translates to:
  /// **'Es. Chi fa più km questa settimana?'**
  String get challengeTitleHint;

  /// No description provided for @challengeTypeRequired.
  ///
  /// In it, this message translates to:
  /// **'Tipo di sfida *'**
  String get challengeTypeRequired;

  /// No description provided for @goalRequired.
  ///
  /// In it, this message translates to:
  /// **'Obiettivo *'**
  String get goalRequired;

  /// No description provided for @durationRequired.
  ///
  /// In it, this message translates to:
  /// **'Durata *'**
  String get durationRequired;

  /// No description provided for @enterValidGoal.
  ///
  /// In it, this message translates to:
  /// **'Inserisci un obiettivo valido'**
  String get enterValidGoal;

  /// No description provided for @launchChallenge.
  ///
  /// In it, this message translates to:
  /// **'Lancia la Sfida!'**
  String get launchChallenge;

  /// No description provided for @distanceLabel.
  ///
  /// In it, this message translates to:
  /// **'Distanza'**
  String get distanceLabel;

  /// No description provided for @elevationLabel.
  ///
  /// In it, this message translates to:
  /// **'Dislivello'**
  String get elevationLabel;

  /// No description provided for @consistencyLabel.
  ///
  /// In it, this message translates to:
  /// **'Costanza'**
  String get consistencyLabel;

  /// No description provided for @distanceDesc.
  ///
  /// In it, this message translates to:
  /// **'Chi percorre più km'**
  String get distanceDesc;

  /// No description provided for @elevationDesc.
  ///
  /// In it, this message translates to:
  /// **'Chi accumula più metri'**
  String get elevationDesc;

  /// No description provided for @tracksDesc.
  ///
  /// In it, this message translates to:
  /// **'Chi registra più uscite'**
  String get tracksDesc;

  /// No description provided for @consistencyDesc.
  ///
  /// In it, this message translates to:
  /// **'Più giorni consecutivi'**
  String get consistencyDesc;

  /// No description provided for @distanceHint.
  ///
  /// In it, this message translates to:
  /// **'Es. 50 (km)'**
  String get distanceHint;

  /// No description provided for @elevationHint.
  ///
  /// In it, this message translates to:
  /// **'Es. 2000 (metri)'**
  String get elevationHint;

  /// No description provided for @tracksHint.
  ///
  /// In it, this message translates to:
  /// **'Es. 10 (tracce)'**
  String get tracksHint;

  /// No description provided for @streakHint.
  ///
  /// In it, this message translates to:
  /// **'Es. 7 (giorni)'**
  String get streakHint;

  /// No description provided for @suffixTracks.
  ///
  /// In it, this message translates to:
  /// **'tracce'**
  String get suffixTracks;

  /// No description provided for @suffixDays.
  ///
  /// In it, this message translates to:
  /// **'giorni'**
  String get suffixDays;

  /// No description provided for @threeDays.
  ///
  /// In it, this message translates to:
  /// **'3 giorni'**
  String get threeDays;

  /// No description provided for @oneWeek.
  ///
  /// In it, this message translates to:
  /// **'1 settimana'**
  String get oneWeek;

  /// No description provided for @twoWeeks.
  ///
  /// In it, this message translates to:
  /// **'2 settimane'**
  String get twoWeeks;

  /// No description provided for @oneMonth.
  ///
  /// In it, this message translates to:
  /// **'1 mese'**
  String get oneMonth;

  /// No description provided for @challengeInfoText.
  ///
  /// In it, this message translates to:
  /// **'La sfida inizia oggi e dura {days} giorni. I progressi vengono calcolati automaticamente dalle tracce registrate.'**
  String challengeInfoText(int days);

  /// No description provided for @challengeCreatedShort.
  ///
  /// In it, this message translates to:
  /// **'Sfida creata!'**
  String get challengeCreatedShort;

  /// No description provided for @challengeCreationError.
  ///
  /// In it, this message translates to:
  /// **'Errore nella creazione'**
  String get challengeCreationError;

  /// No description provided for @newEvent.
  ///
  /// In it, this message translates to:
  /// **'Nuovo Evento'**
  String get newEvent;

  /// No description provided for @titleRequired.
  ///
  /// In it, this message translates to:
  /// **'Titolo *'**
  String get titleRequired;

  /// No description provided for @eventTitleHint.
  ///
  /// In it, this message translates to:
  /// **'Es. Uscita al Rifugio Vaccaro'**
  String get eventTitleHint;

  /// No description provided for @dateAndTime.
  ///
  /// In it, this message translates to:
  /// **'Data e ora *'**
  String get dateAndTime;

  /// No description provided for @outingDetails.
  ///
  /// In it, this message translates to:
  /// **'Dettagli sull\'uscita...'**
  String get outingDetails;

  /// No description provided for @meetingPoint.
  ///
  /// In it, this message translates to:
  /// **'Punto di ritrovo'**
  String get meetingPoint;

  /// No description provided for @meetingPointHint.
  ///
  /// In it, this message translates to:
  /// **'Es. Parcheggio Parre centro'**
  String get meetingPointHint;

  /// No description provided for @routeDetails.
  ///
  /// In it, this message translates to:
  /// **'Dettagli percorso'**
  String get routeDetails;

  /// No description provided for @difficultyLabel.
  ///
  /// In it, this message translates to:
  /// **'Difficoltà'**
  String get difficultyLabel;

  /// No description provided for @mediumDifficulty.
  ///
  /// In it, this message translates to:
  /// **'Medio'**
  String get mediumDifficulty;

  /// No description provided for @expertDifficulty.
  ///
  /// In it, this message translates to:
  /// **'Esperto'**
  String get expertDifficulty;

  /// No description provided for @maxParticipantsLabel.
  ///
  /// In it, this message translates to:
  /// **'Partecipanti massimi'**
  String get maxParticipantsLabel;

  /// No description provided for @notesLabel.
  ///
  /// In it, this message translates to:
  /// **'Note'**
  String get notesLabel;

  /// No description provided for @notesHint.
  ///
  /// In it, this message translates to:
  /// **'Es. Portare pranzo al sacco, bastoncini consigliati...'**
  String get notesHint;

  /// No description provided for @eventCreatedSnack.
  ///
  /// In it, this message translates to:
  /// **'Evento creato!'**
  String get eventCreatedSnack;

  /// No description provided for @distanceHintShort.
  ///
  /// In it, this message translates to:
  /// **'Distanza'**
  String get distanceHintShort;

  /// No description provided for @elevationHintShort.
  ///
  /// In it, this message translates to:
  /// **'Dislivello'**
  String get elevationHintShort;

  /// No description provided for @activeFilter.
  ///
  /// In it, this message translates to:
  /// **'Attive'**
  String get activeFilter;

  /// No description provided for @allChallengesFilter.
  ///
  /// In it, this message translates to:
  /// **'Tutte'**
  String get allChallengesFilter;

  /// No description provided for @noChallenges.
  ///
  /// In it, this message translates to:
  /// **'Nessuna sfida'**
  String get noChallenges;

  /// No description provided for @launchGroupChallenge.
  ///
  /// In it, this message translates to:
  /// **'Lancia una sfida al gruppo!'**
  String get launchGroupChallenge;

  /// No description provided for @lastDay.
  ///
  /// In it, this message translates to:
  /// **'Ultimo giorno!'**
  String get lastDay;

  /// No description provided for @daysLeftCount.
  ///
  /// In it, this message translates to:
  /// **'{count} giorni'**
  String daysLeftCount(int count);

  /// No description provided for @concludedFemale.
  ///
  /// In it, this message translates to:
  /// **'Conclusa'**
  String get concludedFemale;

  /// No description provided for @createdByFemale.
  ///
  /// In it, this message translates to:
  /// **'Creata da {name}'**
  String createdByFemale(String name);

  /// No description provided for @goalColon.
  ///
  /// In it, this message translates to:
  /// **'Obiettivo: {value}'**
  String goalColon(String value);

  /// No description provided for @typeAndGoal.
  ///
  /// In it, this message translates to:
  /// **'{type} • Obiettivo: {goal}'**
  String typeAndGoal(String type, String goal);

  /// No description provided for @suffixDaysShort.
  ///
  /// In it, this message translates to:
  /// **'gg'**
  String get suffixDaysShort;

  /// No description provided for @membersWithCount.
  ///
  /// In it, this message translates to:
  /// **'Membri ({count})'**
  String membersWithCount(int count);

  /// No description provided for @inviteTooltip.
  ///
  /// In it, this message translates to:
  /// **'Invita'**
  String get inviteTooltip;

  /// No description provided for @removeMember.
  ///
  /// In it, this message translates to:
  /// **'Rimuovi membro'**
  String get removeMember;

  /// No description provided for @removeMemberConfirm.
  ///
  /// In it, this message translates to:
  /// **'Vuoi rimuovere {name} dal gruppo?'**
  String removeMemberConfirm(String name);

  /// No description provided for @removeAction.
  ///
  /// In it, this message translates to:
  /// **'Rimuovi'**
  String get removeAction;

  /// No description provided for @youSuffix.
  ///
  /// In it, this message translates to:
  /// **' (tu)'**
  String get youSuffix;

  /// No description provided for @adminWithCrown.
  ///
  /// In it, this message translates to:
  /// **'👑 Amministratore'**
  String get adminWithCrown;

  /// No description provided for @allContactsInGroup.
  ///
  /// In it, this message translates to:
  /// **'Tutti i tuoi contatti sono già nel gruppo'**
  String get allContactsInGroup;

  /// No description provided for @inviteContact.
  ///
  /// In it, this message translates to:
  /// **'Invita un contatto'**
  String get inviteContact;

  /// No description provided for @addedToGroup.
  ///
  /// In it, this message translates to:
  /// **'{name} aggiunto al gruppo!'**
  String addedToGroup(String name);

  /// No description provided for @inviteAction.
  ///
  /// In it, this message translates to:
  /// **'Invita'**
  String get inviteAction;

  /// No description provided for @shareTooltip.
  ///
  /// In it, this message translates to:
  /// **'Condividi'**
  String get shareTooltip;

  /// No description provided for @publishToCommunity.
  ///
  /// In it, this message translates to:
  /// **'Pubblica nella community'**
  String get publishToCommunity;

  /// No description provided for @elevationGainLabel.
  ///
  /// In it, this message translates to:
  /// **'Dislivello +'**
  String get elevationGainLabel;

  /// No description provided for @photosCount.
  ///
  /// In it, this message translates to:
  /// **'📸 {count} foto'**
  String photosCount(int count);

  /// No description provided for @publishedBadge.
  ///
  /// In it, this message translates to:
  /// **'Pubblica'**
  String get publishedBadge;

  /// No description provided for @dateLabel.
  ///
  /// In it, this message translates to:
  /// **'Data'**
  String get dateLabel;

  /// No description provided for @gpsPoints.
  ///
  /// In it, this message translates to:
  /// **'Punti GPS'**
  String get gpsPoints;

  /// No description provided for @maxElevation.
  ///
  /// In it, this message translates to:
  /// **'Quota max'**
  String get maxElevation;

  /// No description provided for @minElevation.
  ///
  /// In it, this message translates to:
  /// **'Quota min'**
  String get minElevation;

  /// No description provided for @caloriesLabel.
  ///
  /// In it, this message translates to:
  /// **'Calorie'**
  String get caloriesLabel;

  /// No description provided for @stepsLabel.
  ///
  /// In it, this message translates to:
  /// **'Passi'**
  String get stepsLabel;

  /// No description provided for @activityLabel.
  ///
  /// In it, this message translates to:
  /// **'Attività'**
  String get activityLabel;

  /// No description provided for @changeActivity.
  ///
  /// In it, this message translates to:
  /// **'Cambia attività'**
  String get changeActivity;

  /// No description provided for @onFoot.
  ///
  /// In it, this message translates to:
  /// **'A piedi'**
  String get onFoot;

  /// No description provided for @byBicycle.
  ///
  /// In it, this message translates to:
  /// **'In bicicletta'**
  String get byBicycle;

  /// No description provided for @winterSports.
  ///
  /// In it, this message translates to:
  /// **'Sport invernali'**
  String get winterSports;

  /// No description provided for @nameLabel.
  ///
  /// In it, this message translates to:
  /// **'Nome'**
  String get nameLabel;

  /// No description provided for @addDescription.
  ///
  /// In it, this message translates to:
  /// **'Aggiungi una descrizione...'**
  String get addDescription;

  /// No description provided for @nameCannotBeEmpty.
  ///
  /// In it, this message translates to:
  /// **'Il nome non può essere vuoto'**
  String get nameCannotBeEmpty;

  /// No description provided for @trackUpdated.
  ///
  /// In it, this message translates to:
  /// **'✅ Traccia aggiornata!'**
  String get trackUpdated;

  /// No description provided for @publishToCommunityTitle.
  ///
  /// In it, this message translates to:
  /// **'Pubblica nella community'**
  String get publishToCommunityTitle;

  /// No description provided for @publishCommunityDesc.
  ///
  /// In it, this message translates to:
  /// **'La tua traccia sarà visibile a tutti gli utenti nella sezione \"Scopri\".'**
  String get publishCommunityDesc;

  /// No description provided for @publishAction.
  ///
  /// In it, this message translates to:
  /// **'Pubblica'**
  String get publishAction;

  /// No description provided for @heartRateTitle.
  ///
  /// In it, this message translates to:
  /// **'Dati battito cardiaco'**
  String get heartRateTitle;

  /// No description provided for @searchHRFromWatch.
  ///
  /// In it, this message translates to:
  /// **'Tocca per cercare dati HR dal tuo smartwatch'**
  String get searchHRFromWatch;

  /// No description provided for @searchingHR.
  ///
  /// In it, this message translates to:
  /// **'🔍 Ricerca dati battito cardiaco...'**
  String get searchingHR;

  /// No description provided for @hrSamplesFound.
  ///
  /// In it, this message translates to:
  /// **'❤️ {count} campioni HR trovati!'**
  String hrSamplesFound(int count);

  /// No description provided for @noHRFound.
  ///
  /// In it, this message translates to:
  /// **'Nessun dato HR trovato. Assicurati che il tuo smartwatch abbia sincronizzato con Health Connect.'**
  String get noHRFound;

  /// No description provided for @hrRetrievalError.
  ///
  /// In it, this message translates to:
  /// **'Errore nel recupero dati HR'**
  String get hrRetrievalError;

  /// No description provided for @mustBeLoggedIn.
  ///
  /// In it, this message translates to:
  /// **'Devi essere loggato'**
  String get mustBeLoggedIn;

  /// No description provided for @trackPublished.
  ///
  /// In it, this message translates to:
  /// **'✅ Traccia pubblicata nella community!'**
  String get trackPublished;

  /// No description provided for @publishFailed.
  ///
  /// In it, this message translates to:
  /// **'Pubblicazione fallita'**
  String get publishFailed;

  /// No description provided for @unpublishTitle.
  ///
  /// In it, this message translates to:
  /// **'Rimuovi dalla community'**
  String get unpublishTitle;

  /// No description provided for @unpublishDesc.
  ///
  /// In it, this message translates to:
  /// **'La traccia non sarà più visibile nella sezione \"Scopri\". Puoi ripubblicarla in qualsiasi momento.'**
  String get unpublishDesc;

  /// No description provided for @trackUnpublished.
  ///
  /// In it, this message translates to:
  /// **'Traccia rimossa dalla community'**
  String get trackUnpublished;

  /// No description provided for @deleteTrackTitle.
  ///
  /// In it, this message translates to:
  /// **'Elimina traccia'**
  String get deleteTrackTitle;

  /// No description provided for @deleteTrackIrreversible.
  ///
  /// In it, this message translates to:
  /// **'Questa azione è irreversibile. La traccia verrà eliminata definitivamente.'**
  String get deleteTrackIrreversible;

  /// No description provided for @downloadTooltip.
  ///
  /// In it, this message translates to:
  /// **'Scarica'**
  String get downloadTooltip;

  /// No description provided for @quotaLabel.
  ///
  /// In it, this message translates to:
  /// **'Quota'**
  String get quotaLabel;

  /// No description provided for @positionLabel.
  ///
  /// In it, this message translates to:
  /// **'Posizione'**
  String get positionLabel;

  /// No description provided for @timeLabel.
  ///
  /// In it, this message translates to:
  /// **'Tempo'**
  String get timeLabel;

  /// No description provided for @photoInfo.
  ///
  /// In it, this message translates to:
  /// **'Informazioni Foto'**
  String get photoInfo;

  /// No description provided for @latitudeLabel.
  ///
  /// In it, this message translates to:
  /// **'Latitudine'**
  String get latitudeLabel;

  /// No description provided for @longitudeLabel.
  ///
  /// In it, this message translates to:
  /// **'Longitudine'**
  String get longitudeLabel;

  /// No description provided for @photoFrom.
  ///
  /// In it, this message translates to:
  /// **'Foto da {name}'**
  String photoFrom(String name);

  /// No description provided for @downloadError.
  ///
  /// In it, this message translates to:
  /// **'Errore download'**
  String get downloadError;

  /// No description provided for @errorLabel.
  ///
  /// In it, this message translates to:
  /// **'Errore'**
  String get errorLabel;

  /// No description provided for @editMenu.
  ///
  /// In it, this message translates to:
  /// **'Modifica'**
  String get editMenu;

  /// No description provided for @detailsHeader.
  ///
  /// In it, this message translates to:
  /// **'Dettagli'**
  String get detailsHeader;

  /// No description provided for @durationStatLabel.
  ///
  /// In it, this message translates to:
  /// **'Durata'**
  String get durationStatLabel;

  /// No description provided for @activityChangedTo.
  ///
  /// In it, this message translates to:
  /// **'Attività cambiata in {name}'**
  String activityChangedTo(String name);

  /// No description provided for @publishDialogContent.
  ///
  /// In it, this message translates to:
  /// **'La tua traccia sarà visibile a tutti gli utenti nella sezione \"Scopri\".'**
  String get publishDialogContent;

  /// No description provided for @heartRateDataTitle.
  ///
  /// In it, this message translates to:
  /// **'Dati battito cardiaco'**
  String get heartRateDataTitle;

  /// No description provided for @tapToSearchHR.
  ///
  /// In it, this message translates to:
  /// **'Tocca per cercare dati HR dal tuo smartwatch'**
  String get tapToSearchHR;

  /// No description provided for @noHRData.
  ///
  /// In it, this message translates to:
  /// **'Nessun dato HR trovato. Assicurati che il tuo smartwatch abbia sincronizzato con Health Connect.'**
  String get noHRData;

  /// No description provided for @unpublishContent.
  ///
  /// In it, this message translates to:
  /// **'La traccia non sarà più visibile nella sezione \"Scopri\". Puoi ripubblicarla in qualsiasi momento.'**
  String get unpublishContent;

  /// No description provided for @deleteTrackContent.
  ///
  /// In it, this message translates to:
  /// **'Questa azione è irreversibile. La traccia verrà eliminata definitivamente.'**
  String get deleteTrackContent;

  /// No description provided for @elevationLossLabel.
  ///
  /// In it, this message translates to:
  /// **'Dislivello -'**
  String get elevationLossLabel;

  /// No description provided for @photoInfoTitle.
  ///
  /// In it, this message translates to:
  /// **'Informazioni Foto'**
  String get photoInfoTitle;

  /// No description provided for @dateInfoLabel.
  ///
  /// In it, this message translates to:
  /// **'Data'**
  String get dateInfoLabel;

  /// No description provided for @timeInfoLabel.
  ///
  /// In it, this message translates to:
  /// **'Ora'**
  String get timeInfoLabel;

  /// No description provided for @elevationQuotaLabel.
  ///
  /// In it, this message translates to:
  /// **'Quota'**
  String get elevationQuotaLabel;

  /// No description provided for @captionLabel.
  ///
  /// In it, this message translates to:
  /// **'Descrizione'**
  String get captionLabel;

  /// No description provided for @quotaMetadata.
  ///
  /// In it, this message translates to:
  /// **'Quota'**
  String get quotaMetadata;

  /// No description provided for @positionMetadata.
  ///
  /// In it, this message translates to:
  /// **'Posizione'**
  String get positionMetadata;

  /// No description provided for @timeMetadata.
  ///
  /// In it, this message translates to:
  /// **'Ora'**
  String get timeMetadata;

  /// No description provided for @listTab.
  ///
  /// In it, this message translates to:
  /// **'Lista'**
  String get listTab;

  /// No description provided for @planTab.
  ///
  /// In it, this message translates to:
  /// **'Pianifica'**
  String get planTab;

  /// No description provided for @loginToSeeTracks.
  ///
  /// In it, this message translates to:
  /// **'Effettua il login per vedere le tue tracce'**
  String get loginToSeeTracks;

  /// No description provided for @loadingErrorWithDetails.
  ///
  /// In it, this message translates to:
  /// **'Errore caricamento: {error}'**
  String loadingErrorWithDetails(String error);

  /// No description provided for @noTracksSaved.
  ///
  /// In it, this message translates to:
  /// **'Nessuna traccia salvata'**
  String get noTracksSaved;

  /// No description provided for @startRecordingAdventures.
  ///
  /// In it, this message translates to:
  /// **'Inizia a registrare le tue avventure!'**
  String get startRecordingAdventures;

  /// No description provided for @loginToPlan.
  ///
  /// In it, this message translates to:
  /// **'Accedi per pianificare tracce'**
  String get loginToPlan;

  /// No description provided for @mapAction.
  ///
  /// In it, this message translates to:
  /// **'Mappa'**
  String get mapAction;

  /// No description provided for @deleteTrackConfirmName.
  ///
  /// In it, this message translates to:
  /// **'Sei sicuro di voler eliminare \"{name}\"?'**
  String deleteTrackConfirmName(String name);

  /// No description provided for @plannedBadge.
  ///
  /// In it, this message translates to:
  /// **'PIANIFICATA'**
  String get plannedBadge;

  /// No description provided for @todayAtTime.
  ///
  /// In it, this message translates to:
  /// **'Oggi {time}'**
  String todayAtTime(String time);

  /// No description provided for @cannotReadFile.
  ///
  /// In it, this message translates to:
  /// **'Impossibile leggere il file. Verifica che sia un file GPX o FIT valido.'**
  String get cannotReadFile;

  /// No description provided for @cannotReadGpx.
  ///
  /// In it, this message translates to:
  /// **'Impossibile leggere il file GPX. Verifica che sia un file valido.'**
  String get cannotReadGpx;

  /// No description provided for @importGpxTitle.
  ///
  /// In it, this message translates to:
  /// **'Importa un file GPX'**
  String get importGpxTitle;

  /// No description provided for @selectGpxFromDevice.
  ///
  /// In it, this message translates to:
  /// **'Seleziona un file .gpx dal tuo dispositivo'**
  String get selectGpxFromDevice;

  /// No description provided for @selectGpxFile.
  ///
  /// In it, this message translates to:
  /// **'Seleziona file GPX'**
  String get selectGpxFile;

  /// No description provided for @activityTypeLabel.
  ///
  /// In it, this message translates to:
  /// **'Tipo di attività'**
  String get activityTypeLabel;

  /// No description provided for @changeFile.
  ///
  /// In it, this message translates to:
  /// **'Cambia'**
  String get changeFile;

  /// No description provided for @trackImported.
  ///
  /// In it, this message translates to:
  /// **'✅ Traccia importata con successo!'**
  String get trackImported;

  /// No description provided for @saveErrorWithDetails.
  ///
  /// In it, this message translates to:
  /// **'Errore salvataggio: {error}'**
  String saveErrorWithDetails(String error);

  /// No description provided for @noGpsData.
  ///
  /// In it, this message translates to:
  /// **'Nessun dato GPS'**
  String get noGpsData;

  /// No description provided for @elevationGainShort.
  ///
  /// In it, this message translates to:
  /// **'Dislivello'**
  String get elevationGainShort;

  /// No description provided for @cannotCalculateRoute.
  ///
  /// In it, this message translates to:
  /// **'Impossibile calcolare il percorso. Riprova.'**
  String get cannotCalculateRoute;

  /// No description provided for @addAtLeast2Points.
  ///
  /// In it, this message translates to:
  /// **'Aggiungi almeno 2 punti al percorso'**
  String get addAtLeast2Points;

  /// No description provided for @loginToSave.
  ///
  /// In it, this message translates to:
  /// **'Devi effettuare il login per salvare'**
  String get loginToSave;

  /// No description provided for @routeSaved.
  ///
  /// In it, this message translates to:
  /// **'Percorso salvato! 🎉'**
  String get routeSaved;

  /// No description provided for @tapMapToStart.
  ///
  /// In it, this message translates to:
  /// **'Tocca la mappa per iniziare'**
  String get tapMapToStart;

  /// No description provided for @waypointCount.
  ///
  /// In it, this message translates to:
  /// **'{count} punti'**
  String waypointCount(int count);

  /// No description provided for @waypointSingle.
  ///
  /// In it, this message translates to:
  /// **'1 punto'**
  String get waypointSingle;

  /// No description provided for @longPressToRemove.
  ///
  /// In it, this message translates to:
  /// **'Tieni premuto per rimuovere'**
  String get longPressToRemove;

  /// No description provided for @addPointsToCreate.
  ///
  /// In it, this message translates to:
  /// **'Aggiungi punti per creare un percorso'**
  String get addPointsToCreate;

  /// No description provided for @calculatingRouteHiking.
  ///
  /// In it, this message translates to:
  /// **'Calcolo percorso hiking...'**
  String get calculatingRouteHiking;

  /// No description provided for @calculatingRouteCycling.
  ///
  /// In it, this message translates to:
  /// **'Calcolo percorso cycling...'**
  String get calculatingRouteCycling;

  /// No description provided for @ascentLabel.
  ///
  /// In it, this message translates to:
  /// **'Salita'**
  String get ascentLabel;

  /// No description provided for @descentLabel.
  ///
  /// In it, this message translates to:
  /// **'Discesa'**
  String get descentLabel;

  /// No description provided for @timeEstLabel.
  ///
  /// In it, this message translates to:
  /// **'Tempo'**
  String get timeEstLabel;

  /// No description provided for @clearRoute.
  ///
  /// In it, this message translates to:
  /// **'Cancella percorso'**
  String get clearRoute;

  /// No description provided for @clearRouteConfirm.
  ///
  /// In it, this message translates to:
  /// **'Vuoi cancellare tutti i punti?'**
  String get clearRouteConfirm;

  /// No description provided for @clearAction.
  ///
  /// In it, this message translates to:
  /// **'Cancella'**
  String get clearAction;

  /// No description provided for @saveRoute.
  ///
  /// In it, this message translates to:
  /// **'Salva percorso'**
  String get saveRoute;

  /// No description provided for @routeName.
  ///
  /// In it, this message translates to:
  /// **'Nome percorso'**
  String get routeName;

  /// No description provided for @enterAName.
  ///
  /// In it, this message translates to:
  /// **'Inserisci un nome'**
  String get enterAName;

  /// No description provided for @hikeDefaultName.
  ///
  /// In it, this message translates to:
  /// **'Escursione'**
  String get hikeDefaultName;

  /// No description provided for @bikeDefaultName.
  ///
  /// In it, this message translates to:
  /// **'Giro in bici'**
  String get bikeDefaultName;

  /// No description provided for @recordLabel.
  ///
  /// In it, this message translates to:
  /// **'Registra'**
  String get recordLabel;

  /// No description provided for @tracksNavLabel.
  ///
  /// In it, this message translates to:
  /// **'Tracce'**
  String get tracksNavLabel;

  /// No description provided for @discoverWithCount.
  ///
  /// In it, this message translates to:
  /// **'Scopri ({count})'**
  String discoverWithCount(int count);

  /// No description provided for @loadingTrails.
  ///
  /// In it, this message translates to:
  /// **'Caricamento sentieri...'**
  String get loadingTrails;

  /// No description provided for @trailsUpdating.
  ///
  /// In it, this message translates to:
  /// **'{count} sentieri · Aggiornamento...'**
  String trailsUpdating(int count);

  /// No description provided for @trailsZoomForDetails.
  ///
  /// In it, this message translates to:
  /// **'{count} sentieri (zoom per dettagli)'**
  String trailsZoomForDetails(int count);

  /// No description provided for @moveMapToExplore.
  ///
  /// In it, this message translates to:
  /// **'Sposta la mappa per esplorare i sentieri'**
  String get moveMapToExplore;

  /// No description provided for @trailsInArea.
  ///
  /// In it, this message translates to:
  /// **'{count} sentieri in questa zona'**
  String trailsInArea(int count);

  /// No description provided for @positionBtn.
  ///
  /// In it, this message translates to:
  /// **'📍 Posizione'**
  String get positionBtn;

  /// No description provided for @noResultsFor.
  ///
  /// In it, this message translates to:
  /// **'Nessun risultato per \"{query}\"'**
  String noResultsFor(String query);

  /// No description provided for @trailsLabel.
  ///
  /// In it, this message translates to:
  /// **'sentieri'**
  String get trailsLabel;

  /// No description provided for @noTrailInArea.
  ///
  /// In it, this message translates to:
  /// **'Nessun sentiero in questa zona'**
  String get noTrailInArea;

  /// No description provided for @moveOrZoomMap.
  ///
  /// In it, this message translates to:
  /// **'Sposta o zooma la mappa per esplorare altre aree'**
  String get moveOrZoomMap;

  /// No description provided for @trailFallback.
  ///
  /// In it, this message translates to:
  /// **'Sentiero'**
  String get trailFallback;

  /// No description provided for @circularBadge.
  ///
  /// In it, this message translates to:
  /// **'Circolare'**
  String get circularBadge;

  /// No description provided for @sharedOnDate.
  ///
  /// In it, this message translates to:
  /// **'Condiviso il {date}'**
  String sharedOnDate(String date);

  /// No description provided for @photosWithCount.
  ///
  /// In it, this message translates to:
  /// **'Foto ({count})'**
  String photosWithCount(int count);

  /// No description provided for @detailsLabel.
  ///
  /// In it, this message translates to:
  /// **'Dettagli'**
  String get detailsLabel;

  /// No description provided for @sourceLabel.
  ///
  /// In it, this message translates to:
  /// **'Fonte'**
  String get sourceLabel;

  /// No description provided for @communitySource.
  ///
  /// In it, this message translates to:
  /// **'Community'**
  String get communitySource;

  /// No description provided for @exporting.
  ///
  /// In it, this message translates to:
  /// **'Esportazione...'**
  String get exporting;

  /// No description provided for @downloadGpx.
  ///
  /// In it, this message translates to:
  /// **'Scarica GPX'**
  String get downloadGpx;

  /// No description provided for @alreadyPromoted.
  ///
  /// In it, this message translates to:
  /// **'Già promossa a Sentiero ✓'**
  String get alreadyPromoted;

  /// No description provided for @promotionInProgress.
  ///
  /// In it, this message translates to:
  /// **'Promozione in corso...'**
  String get promotionInProgress;

  /// No description provided for @promoteToTrail.
  ///
  /// In it, this message translates to:
  /// **'Promuovi a Sentiero'**
  String get promoteToTrail;

  /// No description provided for @promoteDialogDescription.
  ///
  /// In it, this message translates to:
  /// **'Questa traccia verrà aggiunta ai sentieri pubblici e sarà visibile a tutti gli utenti nella sezione Scopri.'**
  String get promoteDialogDescription;

  /// No description provided for @authorLabel.
  ///
  /// In it, this message translates to:
  /// **'Autore'**
  String get authorLabel;

  /// No description provided for @fewGpsPointsWarning.
  ///
  /// In it, this message translates to:
  /// **'Pochi punti GPS — la traccia potrebbe essere imprecisa'**
  String get fewGpsPointsWarning;

  /// No description provided for @promote.
  ///
  /// In it, this message translates to:
  /// **'Promuovi'**
  String get promote;

  /// No description provided for @trackPromotedSuccess.
  ///
  /// In it, this message translates to:
  /// **'✅ Traccia promossa a sentiero pubblico!'**
  String get trackPromotedSuccess;

  /// No description provided for @promotionFailed.
  ///
  /// In it, this message translates to:
  /// **'Promozione fallita'**
  String get promotionFailed;

  /// No description provided for @noGpsPointsToExport.
  ///
  /// In it, this message translates to:
  /// **'Nessun punto GPS da esportare'**
  String get noGpsPointsToExport;

  /// No description provided for @gpxTrackName.
  ///
  /// In it, this message translates to:
  /// **'Traccia GPX: {name}'**
  String gpxTrackName(String name);

  /// No description provided for @gpxExported.
  ///
  /// In it, this message translates to:
  /// **'✅ GPX esportato!'**
  String get gpxExported;

  /// No description provided for @cannotLoadImage.
  ///
  /// In it, this message translates to:
  /// **'Impossibile caricare l\'immagine'**
  String get cannotLoadImage;

  /// No description provided for @hikePhoto.
  ///
  /// In it, this message translates to:
  /// **'Foto escursione'**
  String get hikePhoto;

  /// No description provided for @lengthLabel.
  ///
  /// In it, this message translates to:
  /// **'Lunghezza'**
  String get lengthLabel;

  /// No description provided for @informationLabel.
  ///
  /// In it, this message translates to:
  /// **'Informazioni'**
  String get informationLabel;

  /// No description provided for @trailNumber.
  ///
  /// In it, this message translates to:
  /// **'Numero sentiero'**
  String get trailNumber;

  /// No description provided for @managerLabel.
  ///
  /// In it, this message translates to:
  /// **'Gestore'**
  String get managerLabel;

  /// No description provided for @networkLabel.
  ///
  /// In it, this message translates to:
  /// **'Rete'**
  String get networkLabel;

  /// No description provided for @regionLabel.
  ///
  /// In it, this message translates to:
  /// **'Regione'**
  String get regionLabel;

  /// No description provided for @openStreetMapSource.
  ///
  /// In it, this message translates to:
  /// **'OpenStreetMap'**
  String get openStreetMapSource;

  /// No description provided for @followTrail.
  ///
  /// In it, this message translates to:
  /// **'Segui la traccia'**
  String get followTrail;

  /// No description provided for @navigateToStart.
  ///
  /// In it, this message translates to:
  /// **'Naviga al punto di partenza'**
  String get navigateToStart;

  /// No description provided for @deleteTrailTitle.
  ///
  /// In it, this message translates to:
  /// **'Elimina sentiero'**
  String get deleteTrailTitle;

  /// No description provided for @deleteTrailConfirmIntro.
  ///
  /// In it, this message translates to:
  /// **'Stai per eliminare definitivamente:'**
  String get deleteTrailConfirmIntro;

  /// No description provided for @deleteTrailIrreversible.
  ///
  /// In it, this message translates to:
  /// **'Questa azione è irreversibile e rimuoverà il sentiero dalla mappa per tutti gli utenti.'**
  String get deleteTrailIrreversible;

  /// No description provided for @trailDeletedName.
  ///
  /// In it, this message translates to:
  /// **'✅ \"{name}\" eliminato'**
  String trailDeletedName(String name);

  /// No description provided for @deleteErrorWithDetails.
  ///
  /// In it, this message translates to:
  /// **'Errore eliminazione: {error}'**
  String deleteErrorWithDetails(String error);

  /// No description provided for @loadingTrailWait.
  ///
  /// In it, this message translates to:
  /// **'Caricamento traccia in corso, attendi...'**
  String get loadingTrailWait;

  /// No description provided for @loadingRetryLater.
  ///
  /// In it, this message translates to:
  /// **'Caricamento in corso, riprova tra un momento...'**
  String get loadingRetryLater;

  /// No description provided for @trailGpxName.
  ///
  /// In it, this message translates to:
  /// **'Sentiero GPX: {name}'**
  String trailGpxName(String name);

  /// No description provided for @cannotOpenNavigation.
  ///
  /// In it, this message translates to:
  /// **'Impossibile aprire la navigazione: {error}'**
  String cannotOpenNavigation(String error);

  /// No description provided for @gpsDisabled.
  ///
  /// In it, this message translates to:
  /// **'GPS disattivato'**
  String get gpsDisabled;

  /// No description provided for @gpsPermDenied.
  ///
  /// In it, this message translates to:
  /// **'Permesso GPS negato'**
  String get gpsPermDenied;

  /// No description provided for @gpsPermDeniedPermanently.
  ///
  /// In it, this message translates to:
  /// **'Permesso GPS negato permanentemente'**
  String get gpsPermDeniedPermanently;

  /// No description provided for @gpsError.
  ///
  /// In it, this message translates to:
  /// **'Errore GPS'**
  String get gpsError;

  /// No description provided for @navigationActive.
  ///
  /// In it, this message translates to:
  /// **'Navigazione attiva'**
  String get navigationActive;

  /// No description provided for @waitingForGps.
  ///
  /// In it, this message translates to:
  /// **'In attesa del GPS...'**
  String get waitingForGps;

  /// No description provided for @soundAlertEnabled.
  ///
  /// In it, this message translates to:
  /// **'🔊 Allarme sonoro attivato'**
  String get soundAlertEnabled;

  /// No description provided for @soundAlertDisabled.
  ///
  /// In it, this message translates to:
  /// **'🔇 Allarme sonoro disattivato'**
  String get soundAlertDisabled;

  /// No description provided for @severeOffTrailDistance.
  ///
  /// In it, this message translates to:
  /// **'Sei a {distance}m dalla traccia!'**
  String severeOffTrailDistance(String distance);

  /// No description provided for @offTrailDistance.
  ///
  /// In it, this message translates to:
  /// **'Fuori traccia ({distance}m)'**
  String offTrailDistance(String distance);

  /// No description provided for @arrivedAtEnd.
  ///
  /// In it, this message translates to:
  /// **'Sei arrivato alla fine del sentiero! 🎉'**
  String get arrivedAtEnd;

  /// No description provided for @seeFullTrail.
  ///
  /// In it, this message translates to:
  /// **'Vedi tutta la traccia'**
  String get seeFullTrail;

  /// No description provided for @centerOnMe.
  ///
  /// In it, this message translates to:
  /// **'Centra su di me'**
  String get centerOnMe;

  /// No description provided for @percentCompleted.
  ///
  /// In it, this message translates to:
  /// **'{percent}% completato'**
  String percentCompleted(String percent);

  /// No description provided for @remainingLabel.
  ///
  /// In it, this message translates to:
  /// **'Restante'**
  String get remainingLabel;

  /// No description provided for @altitudeLabel.
  ///
  /// In it, this message translates to:
  /// **'Quota'**
  String get altitudeLabel;

  /// No description provided for @fromTrailLabel.
  ///
  /// In it, this message translates to:
  /// **'Dalla traccia'**
  String get fromTrailLabel;

  /// No description provided for @activeRecording.
  ///
  /// In it, this message translates to:
  /// **'Registrazione attiva'**
  String get activeRecording;

  /// No description provided for @recordedPointsInfo.
  ///
  /// In it, this message translates to:
  /// **'Hai registrato {count} punti in {duration}.\nCosa vuoi fare?'**
  String recordedPointsInfo(int count, String duration);

  /// No description provided for @saveAndExit.
  ///
  /// In it, this message translates to:
  /// **'Salva ed esci'**
  String get saveAndExit;

  /// No description provided for @discardAndExit.
  ///
  /// In it, this message translates to:
  /// **'Scarta ed esci'**
  String get discardAndExit;

  /// No description provided for @stopNavigation.
  ///
  /// In it, this message translates to:
  /// **'Interrompere navigazione?'**
  String get stopNavigation;

  /// No description provided for @stopFollowingQuestion.
  ///
  /// In it, this message translates to:
  /// **'Vuoi smettere di seguire questa traccia?'**
  String get stopFollowingQuestion;

  /// No description provided for @tooFewPointsToSave.
  ///
  /// In it, this message translates to:
  /// **'Troppo pochi punti per salvare'**
  String get tooFewPointsToSave;

  /// No description provided for @mustBeLoggedToSave.
  ///
  /// In it, this message translates to:
  /// **'Devi essere loggato per salvare'**
  String get mustBeLoggedToSave;

  /// No description provided for @discardRecording.
  ///
  /// In it, this message translates to:
  /// **'Scartare registrazione?'**
  String get discardRecording;

  /// No description provided for @recordedPointsDiscard.
  ///
  /// In it, this message translates to:
  /// **'Hai registrato {count} punti. Vuoi scartarli?'**
  String recordedPointsDiscard(int count);

  /// No description provided for @noSave.
  ///
  /// In it, this message translates to:
  /// **'No, salva'**
  String get noSave;

  /// No description provided for @discardAction.
  ///
  /// In it, this message translates to:
  /// **'Scarta'**
  String get discardAction;

  /// No description provided for @trackSavedWithCount.
  ///
  /// In it, this message translates to:
  /// **'✅ Traccia \"{name}\" salvata! ({count} punti)'**
  String trackSavedWithCount(String name, int count);

  /// No description provided for @saveTrackTitle.
  ///
  /// In it, this message translates to:
  /// **'Salva traccia'**
  String get saveTrackTitle;

  /// No description provided for @pointsLabel.
  ///
  /// In it, this message translates to:
  /// **'Punti'**
  String get pointsLabel;

  /// No description provided for @sessionNotFound.
  ///
  /// In it, this message translates to:
  /// **'Sessione non trovata o scaduta'**
  String get sessionNotFound;

  /// No description provided for @inLive.
  ///
  /// In it, this message translates to:
  /// **'IN DIRETTA'**
  String get inLive;

  /// No description provided for @ended.
  ///
  /// In it, this message translates to:
  /// **'TERMINATA'**
  String get ended;

  /// No description provided for @lastSignal.
  ///
  /// In it, this message translates to:
  /// **'Ultimo segnale: {time}'**
  String lastSignal(String time);

  /// No description provided for @goBack.
  ///
  /// In it, this message translates to:
  /// **'Torna indietro'**
  String get goBack;

  /// No description provided for @recordingFound.
  ///
  /// In it, this message translates to:
  /// **'Registrazione trovata'**
  String get recordingFound;

  /// No description provided for @unsavedRecordingFound.
  ///
  /// In it, this message translates to:
  /// **'È stata trovata una registrazione non salvata:'**
  String get unsavedRecordingFound;

  /// No description provided for @wantToRecover.
  ///
  /// In it, this message translates to:
  /// **'Vuoi recuperarla?'**
  String get wantToRecover;

  /// No description provided for @recover.
  ///
  /// In it, this message translates to:
  /// **'Recupera'**
  String get recover;

  /// No description provided for @gpsPointsCount.
  ///
  /// In it, this message translates to:
  /// **'📍 {count} punti GPS'**
  String gpsPointsCount(int count);

  /// No description provided for @recoveredGpsPoints.
  ///
  /// In it, this message translates to:
  /// **'✅ Recuperati {count} punti GPS'**
  String recoveredGpsPoints(int count);

  /// No description provided for @lowBatteryWarning.
  ///
  /// In it, this message translates to:
  /// **'⚠️ Batteria bassa! La traccia verrà salvata automaticamente al 5%'**
  String get lowBatteryWarning;

  /// No description provided for @criticalBatteryWarning.
  ///
  /// In it, this message translates to:
  /// **'🔋 Batteria critica! Salvataggio traccia in corso...'**
  String get criticalBatteryWarning;

  /// No description provided for @autoSaved.
  ///
  /// In it, this message translates to:
  /// **'(auto-salvato)'**
  String get autoSaved;

  /// No description provided for @trackAutoSaved.
  ///
  /// In it, this message translates to:
  /// **'✅ Traccia salvata automaticamente!'**
  String get trackAutoSaved;

  /// No description provided for @uploadingPhotos.
  ///
  /// In it, this message translates to:
  /// **'Upload di {count} foto...'**
  String uploadingPhotos(int count);

  /// No description provided for @restoringRecording.
  ///
  /// In it, this message translates to:
  /// **'Ripristino registrazione...'**
  String get restoringRecording;

  /// No description provided for @gpsNotAvailable.
  ///
  /// In it, this message translates to:
  /// **'GPS non disponibile'**
  String get gpsNotAvailable;

  /// No description provided for @photoAdded.
  ///
  /// In it, this message translates to:
  /// **'📸 Foto aggiunta!'**
  String get photoAdded;

  /// No description provided for @photosAdded.
  ///
  /// In it, this message translates to:
  /// **'📸 {count} foto aggiunte!'**
  String photosAdded(int count);

  /// No description provided for @photoDeleted.
  ///
  /// In it, this message translates to:
  /// **'Foto eliminata'**
  String get photoDeleted;

  /// No description provided for @takePhoto.
  ///
  /// In it, this message translates to:
  /// **'Scatta foto'**
  String get takePhoto;

  /// No description provided for @pickFromGallery.
  ///
  /// In it, this message translates to:
  /// **'Scegli dalla galleria'**
  String get pickFromGallery;

  /// No description provided for @cancelRecording.
  ///
  /// In it, this message translates to:
  /// **'Annullare registrazione?'**
  String get cancelRecording;

  /// No description provided for @trackDataWillBeLost.
  ///
  /// In it, this message translates to:
  /// **'I dati della traccia corrente verranno persi.'**
  String get trackDataWillBeLost;

  /// No description provided for @trackAndPhotosWillBeLost.
  ///
  /// In it, this message translates to:
  /// **'I dati della traccia e le {count} foto verranno persi.'**
  String trackAndPhotosWillBeLost(int count);

  /// No description provided for @noPointsRecorded.
  ///
  /// In it, this message translates to:
  /// **'Nessun punto registrato'**
  String get noPointsRecorded;

  /// No description provided for @stopRecordingError.
  ///
  /// In it, this message translates to:
  /// **'Errore nel fermare la registrazione'**
  String get stopRecordingError;

  /// No description provided for @photosNotUploaded.
  ///
  /// In it, this message translates to:
  /// **'⚠️ {count} foto non caricate'**
  String photosNotUploaded(int count);

  /// No description provided for @paused.
  ///
  /// In it, this message translates to:
  /// **'IN PAUSA'**
  String get paused;

  /// No description provided for @speedLabel.
  ///
  /// In it, this message translates to:
  /// **'Vel.'**
  String get speedLabel;

  /// No description provided for @avgSpeedLabel.
  ///
  /// In it, this message translates to:
  /// **'Media'**
  String get avgSpeedLabel;

  /// No description provided for @paceLabel.
  ///
  /// In it, this message translates to:
  /// **'Passo'**
  String get paceLabel;

  /// No description provided for @cancelLabel.
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get cancelLabel;

  /// No description provided for @pauseLabel.
  ///
  /// In it, this message translates to:
  /// **'Pausa'**
  String get pauseLabel;

  /// No description provided for @resumeLabel.
  ///
  /// In it, this message translates to:
  /// **'Riprendi'**
  String get resumeLabel;

  /// No description provided for @saveLabel.
  ///
  /// In it, this message translates to:
  /// **'Salva'**
  String get saveLabel;

  /// No description provided for @motivational1.
  ///
  /// In it, this message translates to:
  /// **'Ottimo lavoro! 💪'**
  String get motivational1;

  /// No description provided for @motivational2.
  ///
  /// In it, this message translates to:
  /// **'Grande escursione! 🏔️'**
  String get motivational2;

  /// No description provided for @motivational3.
  ///
  /// In it, this message translates to:
  /// **'Fantastico percorso! 🥾'**
  String get motivational3;

  /// No description provided for @motivational4.
  ///
  /// In it, this message translates to:
  /// **'Che avventura! 🌟'**
  String get motivational4;

  /// No description provided for @motivational5.
  ///
  /// In it, this message translates to:
  /// **'Sei un vero esploratore! 🧭'**
  String get motivational5;

  /// No description provided for @motivational6.
  ///
  /// In it, this message translates to:
  /// **'Trail completato! 🎯'**
  String get motivational6;

  /// No description provided for @motivational7.
  ///
  /// In it, this message translates to:
  /// **'Complimenti, continua così! 🔥'**
  String get motivational7;

  /// No description provided for @metersDPlus.
  ///
  /// In it, this message translates to:
  /// **'m D+'**
  String get metersDPlus;

  /// No description provided for @continueBtn.
  ///
  /// In it, this message translates to:
  /// **'Continua'**
  String get continueBtn;

  /// No description provided for @chooseActivity.
  ///
  /// In it, this message translates to:
  /// **'Scegli attività'**
  String get chooseActivity;

  /// No description provided for @byCycle.
  ///
  /// In it, this message translates to:
  /// **'In bicicletta'**
  String get byCycle;

  /// No description provided for @photosLabel.
  ///
  /// In it, this message translates to:
  /// **'Foto'**
  String get photosLabel;

  /// No description provided for @savedTracks.
  ///
  /// In it, this message translates to:
  /// **'Percorsi Salvati'**
  String get savedTracks;

  /// No description provided for @removeFromSaved.
  ///
  /// In it, this message translates to:
  /// **'Rimuovi dai salvati'**
  String get removeFromSaved;

  /// No description provided for @removeTrackQuestion.
  ///
  /// In it, this message translates to:
  /// **'Vuoi rimuovere questo percorso dalla tua lista?'**
  String get removeTrackQuestion;

  /// No description provided for @removeLabel.
  ///
  /// In it, this message translates to:
  /// **'Rimuovi'**
  String get removeLabel;

  /// No description provided for @trackRemovedFromSaved.
  ///
  /// In it, this message translates to:
  /// **'Percorso rimosso dai salvati'**
  String get trackRemovedFromSaved;

  /// No description provided for @loginToSeeSaved.
  ///
  /// In it, this message translates to:
  /// **'Accedi per vedere i tuoi percorsi salvati'**
  String get loginToSeeSaved;

  /// No description provided for @saveTracksHint.
  ///
  /// In it, this message translates to:
  /// **'Salva i percorsi che ti interessano per ritrovarli facilmente!'**
  String get saveTracksHint;

  /// No description provided for @loadingError.
  ///
  /// In it, this message translates to:
  /// **'Errore nel caricamento'**
  String get loadingError;

  /// No description provided for @noSavedTracks.
  ///
  /// In it, this message translates to:
  /// **'Nessun percorso salvato'**
  String get noSavedTracks;

  /// No description provided for @exploreSavedHint.
  ///
  /// In it, this message translates to:
  /// **'Esplora la sezione \"Scopri\" e salva i percorsi che ti interessano!'**
  String get exploreSavedHint;

  /// No description provided for @goToDiscover.
  ///
  /// In it, this message translates to:
  /// **'Vai a Scopri'**
  String get goToDiscover;

  /// No description provided for @userFallback.
  ///
  /// In it, this message translates to:
  /// **'Utente'**
  String get userFallback;

  /// No description provided for @gpsAccessError.
  ///
  /// In it, this message translates to:
  /// **'Impossibile accedere al GPS. Verifica i permessi.'**
  String get gpsAccessError;

  /// No description provided for @gpsResumeError.
  ///
  /// In it, this message translates to:
  /// **'Impossibile riprendere il GPS.'**
  String get gpsResumeError;

  /// No description provided for @locationDisclosureTitle.
  ///
  /// In it, this message translates to:
  /// **'Accesso alla posizione'**
  String get locationDisclosureTitle;

  /// No description provided for @locationDisclosureBody.
  ///
  /// In it, this message translates to:
  /// **'TrailShare utilizza la tua posizione per:\n\n• Registrare le tracce GPS delle tue attività outdoor (escursioni, corsa, ciclismo)\n• Mostrarti i sentieri e i punti di interesse vicini a te\n• Fornire statistiche accurate su distanza, velocità e percorso\n• Permettere il tracciamento in background durante la registrazione per garantire la continuità del percorso anche con lo schermo spento\n\nLa tua posizione non viene condivisa con terze parti, salvo quando scegli volontariamente di pubblicare una traccia nella community.'**
  String get locationDisclosureBody;

  /// No description provided for @locationDisclosureDecline.
  ///
  /// In it, this message translates to:
  /// **'Non ora'**
  String get locationDisclosureDecline;

  /// No description provided for @locationDisclosureAccept.
  ///
  /// In it, this message translates to:
  /// **'Ho capito, continua'**
  String get locationDisclosureAccept;
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
