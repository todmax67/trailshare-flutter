/// Motore di crescita — Fase 0: la spina dorsale della misura.
///
/// Nasce dalla constatazione del 2026-07-31: l'app non misurava **nulla** di
/// acquisizione (zero `logEvent` in tutto `lib/`), mentre il manager social
/// leggeva like e reach. Cioe' potevamo pubblicare per un anno senza sapere se
/// un solo post avesse portato un utente. Ogni strategia costruita su quei
/// numeri ottimizza la metrica sbagliata.
///
/// ## Due sink, un'unica API
///
/// **Firebase Analytics** riceve lo stream completo degli eventi. E' il sink su
/// cui si agganciano l'attribuzione degli store, Apple Search Ads e le
/// campagne, e da' coorti e retention in console senza scrivere una query.
///
/// **`growth_users/{uid}`** riceve le sole *milestone*: un documento per utente
/// con il timestamp della prima volta che ha fatto una certa cosa, piu' la
/// fonte da cui e' arrivato. Serve perche' Analytics ha 24h di ritardo e per
/// interrogarlo davvero serve l'export BigQuery, mentre l'aggregatore del
/// manager (`growth_daily`) deve poter calcolare il funnel **oggi** — e legge
/// gia' il Firestore di produzione col service account cross-project.
///
/// Un doc per utente, non uno per evento come in [SaveDiagnosticsService]: qui
/// gli eventi interessanti sono per-vita-utente ("la prima traccia salvata"), e
/// la forma naturale per funnel e coorti e' la riga-utente. Costo: un update al
/// giorno per utente attivo, al massimo.
///
/// ## Regola d'oro
///
/// Come per la telemetria di salvataggio: questa classe non deve **mai** far
/// fallire nulla. Ogni metodo inghiotte le proprie eccezioni ed e'
/// fire-and-forget.
library;

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:play_install_referrer/play_install_referrer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Le tappe del funnel, dalla prima apertura all'abbonamento.
///
/// L'ordine e' quello del percorso utente: serve solo a leggere il codice, il
/// funnel vero lo ricostruisce l'aggregatore dai timestamp.
enum GrowthMilestone {
  /// Primissima apertura dell'app su questo dispositivo (pre-registrazione).
  firstOpen,

  /// Account creato.
  signup,

  /// Slide di onboarding completate.
  onboardingDone,

  /// **Attivazione**: prima traccia salvata. E' il momento in cui un
  /// installato diventa un utente vero — la metrica nord di questa fase.
  firstTrackSaved,

  /// Prima traccia resa pubblica: l'utente inizia a produrre contenuto per
  /// gli altri (l'unico motore di network effect che abbiamo).
  firstTrackPublic,

  /// Primo Discover aperto.
  firstDiscover,

  /// Primo sentiero messo nei preferiti.
  firstFavorite,

  /// Abbonamento Pro acquistato.
  proPurchase,
}

extension on GrowthMilestone {
  /// Campo su `growth_users/{uid}` che porta il timestamp della milestone.
  String get field => switch (this) {
        GrowthMilestone.firstOpen => 'firstOpenAt',
        GrowthMilestone.signup => 'signupAt',
        GrowthMilestone.onboardingDone => 'onboardingDoneAt',
        GrowthMilestone.firstTrackSaved => 'firstTrackSavedAt',
        GrowthMilestone.firstTrackPublic => 'firstTrackPublicAt',
        GrowthMilestone.firstDiscover => 'firstDiscoverAt',
        GrowthMilestone.firstFavorite => 'firstFavoriteAt',
        GrowthMilestone.proPurchase => 'proPurchaseAt',
      };

  /// Nome evento per Analytics.
  ///
  /// Attenzione ai nomi riservati da GA4 (`first_open`, `in_app_purchase`,
  /// `session_start`…): riusarli fa scartare l'evento in silenzio.
  String get eventName => switch (this) {
        GrowthMilestone.firstOpen => 'ts_first_open',
        GrowthMilestone.signup => 'signup_completed',
        GrowthMilestone.onboardingDone => 'onboarding_completed',
        GrowthMilestone.firstTrackSaved => 'activation_track_saved',
        GrowthMilestone.firstTrackPublic => 'track_made_public',
        GrowthMilestone.firstDiscover => 'discover_first_open',
        GrowthMilestone.firstFavorite => 'trail_first_favorited',
        GrowthMilestone.proPurchase => 'pro_purchase_completed',
      };
}

/// Da dove e' arrivato l'utente. Riempita dai parametri del link d'ingresso
/// (QR nei rifugi, bio social, articolo di stampa) e congelata al signup.
class AcquisitionSource {
  /// Chi ci ha portato l'utente: `qr_rifugio_arlaud`, `instagram`, `press`…
  final String source;

  /// Il mezzo: `qr`, `social`, `press`, `ads`, `referral`.
  final String? medium;

  /// La campagna specifica: `estate2026`, `lancio_2_9`…
  final String? campaign;

  const AcquisitionSource({
    required this.source,
    this.medium,
    this.campaign,
  });

  Map<String, dynamic> toMap() => {
        'source': source,
        if (medium != null) 'medium': medium,
        if (campaign != null) 'campaign': campaign,
      };

  /// Legge i parametri da un URI di ingresso.
  ///
  /// Accetta sia la forma lunga standard (`utm_source`, `utm_medium`,
  /// `utm_campaign`) sia quella corta (`src`, `med`, `cmp`): sui QR stampati
  /// l'URL piu' corto e' un QR meno denso, quindi piu' facile da leggere con
  /// poca luce — che nei rifugi capita spesso.
  ///
  /// Ritorna null se il link non porta attribuzione: la maggior parte dei deep
  /// link (invito a un gruppo, callback di Strava) non ne ha, ed e' giusto che
  /// non sovrascrivano quella gia' raccolta.
  static AcquisitionSource? fromUri(Uri uri) {
    final q = uri.queryParameters;
    final source = q['utm_source'] ?? q['src'];
    if (source == null || source.trim().isEmpty) return null;

    final cleaned = _clean(source);
    final medium = _cleanOrNull(q['utm_medium'] ?? q['med']);
    final campaign = _cleanOrNull(q['utm_campaign'] ?? q['cmp']);

    // Un segnaposto non e' un canale.
    if (_isNonValue(cleaned)) return null;

    // Play inietta `utm_source=google-play&utm_medium=organic` quando non c'e'
    // campagna. Il commento che lo diceva esisteva gia' in
    // `_captureInstallReferrer`, ma stava nel ramo "attribuzione inutile" —
    // che non veniva mai preso, perche' `google-play` e' un utm_source non
    // vuoto e passava il controllo. Risultato: il traffico organico dallo
    // Store compariva come un canale a se', il piu' grande della tabella.
    //
    // Si scarta solo in assenza di campagna: un link vero con
    // `utm_campaign` resta attribuito, qualunque sia la sorgente.
    if (cleaned == 'google-play' && campaign == null) return null;

    return AcquisitionSource(
      source: cleaned,
      medium: medium,
      campaign: campaign,
    );
  }

  /// Valori con cui gli store dicono "nessuna attribuzione".
  ///
  /// Google li manda in forme diverse — `not set`, `(not set)`, `none` — e
  /// [_clean] li trasforma in stringhe diverse fra loro: `not_set` e
  /// `_not_set_` sono finiti nel report come **due canali distinti**, che poi
  /// erano lo stesso non-canale. Si toglie la punteggiatura ai bordi prima di
  /// confrontare, cosi' ogni variante collassa sulla stessa parola.
  static bool _isNonValue(String cleaned) {
    final s = cleaned.replaceAll(RegExp(r'^[_-]+|[_-]+$'), '');
    return s.isEmpty ||
        const {
          'not_set',
          'notset',
          'none',
          'null',
          'undefined',
          'unknown',
          'direct',
        }.contains(s);
  }

  /// Analytics rifiuta valori sopra i 100 caratteri e i nomi con spazi si
  /// spezzano male nei report: normalizziamo qui una volta per tutte.
  static String _clean(String v) {
    final s = v.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]+'), '_');
    return s.length <= 100 ? s : s.substring(0, 100);
  }

  static String? _cleanOrNull(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return _clean(v);
  }
}

class GrowthAnalyticsService {
  GrowthAnalyticsService._();
  static final GrowthAnalyticsService instance = GrowthAnalyticsService._();

  static const String _collection = 'growth_users';

  /// Attribuzione in attesa di un utente a cui essere attaccata: chi arriva da
  /// un QR apre l'app prima di registrarsi, e quel momento e' l'unico in cui
  /// conosciamo la fonte.
  static const String _kPendingSource = 'growth_pending_source';
  static const String _kPendingMedium = 'growth_pending_medium';
  static const String _kPendingCampaign = 'growth_pending_campaign';

  static const String _kFirstOpenDone = 'growth_first_open_done';
  static const String _kLastSeenDay = 'growth_last_seen_day';

  /// Consenso a Firebase Analytics. **Assente** = non ancora chiesto, che non
  /// e' la stessa cosa di un rifiuto: l'utente va portato alla schermata di
  /// consenso, e fino ad allora non si raccoglie niente.
  static const String _kAnalyticsConsent = 'growth_analytics_consent';

  /// Opposizione alla misura del funnel first-party. Separata dal consenso
  /// Analytics perche' le due cose hanno basi giuridiche diverse: Analytics e'
  /// terza parte con identificativo persistente e va consentito, il funnel sta
  /// sul nostro backend a supporto del servizio e si esercita in opposizione.
  static const String _kFunnelOptOut = 'growth_funnel_opt_out';

  FirebaseAnalytics? _analytics;
  bool _analyticsUnavailable = false;
  String? _appVersion;

  /// Copia in memoria dell'opposizione al funnel: [_mergeDoc] e' sul percorso
  /// di salvataggio tracce e non puo' permettersi una lettura asincrona da
  /// SharedPreferences a ogni scrittura.
  bool _funnelOptedOut = false;

  /// Guardia di rientro per [_countWatchTracks]: vedi il commento la' dentro.
  bool _countingWatchTracks = false;

  /// Ultimo giorno per cui `lastSeenAt` e' gia' stato aggiornato in questa
  /// sessione. Vedi [_touchLastSeen] per il perche' non basti SharedPreferences.
  String? _lastSeenDayInMemory;

  /// Analytics non ha implementazione su tutte le piattaforme che compiliamo
  /// (macOS/Windows) e su web richiede il measurementId in
  /// `firebase_options.dart`: se manca, meglio restare senza che far esplodere
  /// l'avvio.
  FirebaseAnalytics? get _ga {
    if (_analyticsUnavailable) return null;
    try {
      return _analytics ??= FirebaseAnalytics.instance;
    } catch (e) {
      _analyticsUnavailable = true;
      debugPrint('[Growth] Analytics non disponibile: $e');
      return null;
    }
  }

  String get _platform {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.name;
  }

  Future<String> _version() async {
    if (_appVersion != null) return _appVersion!;
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      _appVersion = 'unknown';
    }
    return _appVersion!;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AVVIO
  // ═══════════════════════════════════════════════════════════════════════════

  /// Da chiamare una volta in `main()`, dopo l'init di Firebase.
  ///
  /// Registra la primissima apertura e tiene aggiornato `lastSeenAt` (che e'
  /// cio' che permette di calcolare la retention a D1/D7/D30). Non blocca
  /// l'avvio: se qualcosa va storto restiamo senza misura, non senza app.
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _funnelOptedOut = prefs.getBool(_kFunnelOptOut) ?? false;

      // Prima di ogni altra cosa: finche' l'utente non ha risposto alla
      // schermata di consenso, Analytics resta spento. `false` e non `null`
      // come default e' il punto — chi non ha ancora scelto non ha scelto di
      // essere misurato.
      await _applyAnalyticsConsent(
        prefs.containsKey(_kAnalyticsConsent)
            ? (prefs.getBool(_kAnalyticsConsent) ?? false)
            : false,
      );

      // In debug non raccogliere nemmeno il funnel: i numeri si sporcherebbero
      // con le decine di hot restart dello sviluppo e la retention
      // diventerebbe finzione. Stessa scelta fatta per Crashlytics.
      if (kDebugMode) return;
      if (!(prefs.getBool(_kFirstOpenDone) ?? false)) {
        await prefs.setBool(_kFirstOpenDone, true);
        await _logEvent(GrowthMilestone.firstOpen.eventName, {
          'platform': _platform,
          'app_version': await _version(),
        });
        // Nessuna scrittura Firestore: qui l'utente non esiste ancora. La
        // prima apertura viene riportata sul doc al momento della
        // registrazione, insieme all'attribuzione.
        await prefs.setString(
          'growth_first_open_at',
          DateTime.now().toUtc().toIso8601String(),
        );
        // Solo alla prima apertura: dopo, il referrer e' comunque lo stesso e
        // interrogare il Play Store a ogni avvio e' spreco.
        await _captureInstallReferrer();
      }

      // `lastSeenAt` va agganciato all'auth, non chiamato qui e basta: a
      // questo punto dell'avvio `currentUser` e' quasi sempre ancora null
      // anche per chi e' loggato, perche' il ripristino della sessione e'
      // asincrono. Chiamandolo direttamente, l'utente che riapre l'app —
      // cioe' esattamente quello che la retention deve contare — non
      // verrebbe mai registrato.
      //
      // Il listener scatta anche ai refresh del token: il tetto giornaliero
      // dentro `_touchLastSeen` rende le chiamate in piu' gratuite.
      FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user == null) return;
        unawaited(_touchLastSeen());
        // Qui e non alla milestone `signup`: quella scatta solo per gli account
        // nuovi (`isNew`), mentre chi reinstalla e rientra con un account che
        // aveva gia' rifa' l'onboarding senza passare di li'. Il listener copre
        // entrambi, incluso il ripristino silenzioso della sessione.
        unawaited(_flushPreLoginMilestones());
        unawaited(_countWatchTracks());
      });
    } catch (e) {
      debugPrint('[Growth] initialize: $e');
    }
  }

  /// Aggiorna `lastSeenAt` al massimo una volta al giorno.
  ///
  /// Il cap giornaliero non e' un dettaglio di costo: senza, ogni apertura
  /// sarebbe una scrittura, e con l'app in tasca durante un'escursione sono
  /// decine di riaperture per utente al giorno.
  Future<void> _touchLastSeen() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    // Guardia sincrona, prima di qualunque await: il listener puo' emettere
    // due volte a distanza di millisecondi (login + refresh token) e due
    // chiamate concorrenti supererebbero entrambe il controllo su prefs,
    // incrementando `activeDaysCount` due volte nello stesso giorno.
    if (_lastSeenDayInMemory == today) return;
    _lastSeenDayInMemory = today;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_kLastSeenDay) == today) return;
      await prefs.setString(_kLastSeenDay, today);

      unawaited(_mergeDoc(uid, {
        'lastSeenAt': FieldValue.serverTimestamp(),
        'lastSeenDay': today,
        'activeDaysCount': FieldValue.increment(1),
        'appVersion': await _version(),
        'platform': _platform,
      }));
    } catch (e) {
      debugPrint('[Growth] touchLastSeen: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONSENSO
  // ═══════════════════════════════════════════════════════════════════════════

  /// Stato del consenso ad Analytics: `null` se non e' mai stato chiesto.
  ///
  /// La distinzione fra "non chiesto" e "rifiutato" e' l'unica cosa che dice
  /// all'app se deve ancora mostrare la schermata di consenso. Collassarle in
  /// un bool significherebbe o richiedere il consenso all'infinito a chi ha
  /// gia' detto di no, o non chiederlo mai a chi non e' stato interpellato.
  Future<bool?> analyticsConsent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey(_kAnalyticsConsent)) return null;
      return prefs.getBool(_kAnalyticsConsent) ?? false;
    } catch (e) {
      debugPrint('[Growth] lettura consenso: $e');
      // In dubbio, "non chiesto": al massimo si richiede, mai si raccoglie
      // senza risposta.
      return null;
    }
  }

  /// Registra la scelta dell'utente e la applica subito.
  Future<void> setAnalyticsConsent(bool granted) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAnalyticsConsent, granted);
    } catch (e) {
      debugPrint('[Growth] scrittura consenso: $e');
    }
    await _applyAnalyticsConsent(granted);
  }

  Future<void> _applyAnalyticsConsent(bool granted) async {
    final enabled = granted && !kDebugMode;
    try {
      await _ga?.setAnalyticsCollectionEnabled(enabled);
      if (!granted) {
        // Non basta smettere di raccogliere: alla revoca va buttato anche
        // l'identificativo di istanza gia' generato, altrimenti resta un
        // pseudonimo persistente associato a dati raccolti prima.
        await _ga?.resetAnalyticsData();
      }
    } catch (e) {
      debugPrint('[Growth] applicazione consenso: $e');
    }
  }

  /// True se l'utente si e' opposto alla misura del funnel first-party.
  Future<bool> funnelOptedOut() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kFunnelOptOut) ?? false;
    } catch (_) {
      return _funnelOptedOut;
    }
  }

  /// Esercita (o revoca) l'opposizione alla misura del funnel.
  ///
  /// Opporsi non ferma solo le scritture future: cancella anche il documento
  /// gia' esistente. Un'opposizione che lascia in piedi i dati raccolti non e'
  /// un'opposizione, e la riga per utente non serve a nulla di cui l'app abbia
  /// bisogno per funzionare.
  Future<void> setFunnelOptOut(bool optedOut) async {
    _funnelOptedOut = optedOut;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kFunnelOptOut, optedOut);
    } catch (e) {
      debugPrint('[Growth] scrittura opposizione funnel: $e');
    }
    if (!optedOut) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection(_collection).doc(uid).delete();
    } catch (e) {
      debugPrint('[Growth] cancellazione doc funnel fallita: $e');
    }
  }

  /// Attribuzione delle installazioni **nuove** su Android.
  ///
  /// E' il pezzo che rende misurabile il ground game nei rifugi: chi inquadra
  /// il QR non ha l'app, quindi non c'e' nessun deep link da leggere — ma il
  /// Play Store trasporta fino alla prima apertura il parametro `referrer`
  /// messo nel link. Senza questo, ogni installazione da QR sarebbe
  /// indistinguibile da una organica.
  ///
  /// Il link del QR deve avere la forma:
  /// `https://play.google.com/store/apps/details?id=...&referrer=utm_source%3Dqr_arlaud%26utm_medium%3Dqr`
  ///
  /// Su iOS il plugin solleva per costruzione (non esiste un equivalente per
  /// il traffico organico): li' i numeri restano aggregati, nei campaign link
  /// di App Store Connect.
  Future<void> _captureInstallReferrer() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final details = await PlayInstallReferrer.installReferrer;
      final raw = details.installReferrer;
      if (raw == null || raw.isEmpty) return;

      // Il referrer arriva come query string (`utm_source=x&utm_medium=y`),
      // non come URL: gli diamo un host fittizio per poterlo parsare.
      final acq = AcquisitionSource.fromUri(Uri.parse('https://x/?$raw'));
      if (acq == null) {
        // Play inietta `utm_source=google-play&utm_medium=organic` quando non
        // c'e' campagna: non e' un errore, e' semplicemente traffico organico.
        debugPrint('[Growth] referrer senza attribuzione utile: $raw');
        return;
      }
      await recordAcquisition(acq);
    } catch (e) {
      // Play Services assenti (device cinesi, emulatori) o utente installato
      // da APK: nessuna attribuzione, nessun dramma.
      debugPrint('[Growth] install referrer non disponibile: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ATTRIBUZIONE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Registra da dove arriva l'utente, letto dal link d'ingresso.
  ///
  /// Vale il **primo** tocco: se qualcuno arriva dal QR del rifugio e due
  /// giorni dopo riapre da un link Instagram, l'utente resta attribuito al
  /// rifugio. Altrimenti l'ultimo canale toccato si prenderebbe il merito del
  /// lavoro fatto dal primo.
  Future<void> recordAcquisition(AcquisitionSource acq) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final already = prefs.getString(_kPendingSource);
      if (already != null && already.isNotEmpty) return;

      await prefs.setString(_kPendingSource, acq.source);
      if (acq.medium != null) await prefs.setString(_kPendingMedium, acq.medium!);
      if (acq.campaign != null) {
        await prefs.setString(_kPendingCampaign, acq.campaign!);
      }

      // Come proprieta' utente, non solo evento: cosi' in console si possono
      // segmentare retention e conversione per fonte senza BigQuery.
      await _ga?.setUserProperty(name: 'acq_source', value: acq.source);
      if (acq.campaign != null) {
        await _ga?.setUserProperty(name: 'acq_campaign', value: acq.campaign);
      }

      await _logEvent('acquisition_attributed', acq.toMap());

      // Se l'utente e' gia' registrato (riapertura da link, non primo
      // ingresso) l'attribuzione va scritta subito: non ci sara' un signup a
      // farlo per noi.
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && !kDebugMode) {
        unawaited(_mergeDoc(uid, {'acquisition': _pendingMap(prefs)}));
      }
    } catch (e) {
      debugPrint('[Growth] recordAcquisition: $e');
    }
  }

  /// Segnala l'apertura da deep link, con o senza attribuzione: serve a sapere
  /// quanti scan/click producono almeno un'apertura, che e' il numeratore del
  /// tasso di conversione del ground game.
  Future<void> recordDeepLinkOpen(Uri uri) async {
    final acq = AcquisitionSource.fromUri(uri);
    await _logEvent('deep_link_open', {
      'link_kind': _linkKind(uri),
      if (acq != null) ...acq.toMap(),
    });
    if (acq != null) await recordAcquisition(acq);
  }

  /// Categoria del link, per non mandare ad Analytics URL completi (che
  /// possono contenere codici invito e altri dati personali).
  String _linkKind(Uri uri) {
    final first = uri.pathSegments.isNotEmpty
        ? uri.pathSegments.first
        : (uri.host.isNotEmpty ? uri.host : 'unknown');
    return switch (first) {
      'g' || 'group' => 'group_invite',
      'b' => 'business',
      'sfide' || 'challenges' => 'challenges',
      'strava' || 'polar' || 'suunto' => 'integration_callback',
      _ => 'other',
    };
  }

  Map<String, dynamic>? _pendingMap(SharedPreferences prefs) {
    final source = prefs.getString(_kPendingSource);
    if (source == null || source.isEmpty) return null;
    return {
      'source': source,
      if (prefs.getString(_kPendingMedium) != null)
        'medium': prefs.getString(_kPendingMedium),
      if (prefs.getString(_kPendingCampaign) != null)
        'campaign': prefs.getString(_kPendingCampaign),
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MILESTONE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Registra una tappa del funnel, una sola volta per utente.
  ///
  /// Il doppio guardiano (flag locale + `_mergeDoc` che non sovrascrive un
  /// timestamp gia' presente) e' voluto: il flag evita la scrittura inutile,
  /// il controllo lato dato protegge dal caso reale in cui l'utente
  /// reinstalla o cambia dispositivo — li' il flag locale e' vergine ma la
  /// milestone e' gia' stata raggiunta, e riscriverla falserebbe le coorti.
  Future<void> milestone(
    GrowthMilestone m, {
    Map<String, dynamic>? params,
  }) async {
    try {
      if (kDebugMode) return;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final prefs = await SharedPreferences.getInstance();
      final key = 'growth_ms_${uid ?? 'anon'}_${m.name}';
      if (prefs.getBool(key) ?? false) return;
      await prefs.setBool(key, true);

      await _logEvent(m.eventName, params);

      // Senza uid non c'e' un documento a cui attaccare la milestone, ma il
      // fatto e' avvenuto lo stesso: va messo da parte, non buttato.
      //
      // Prima qui c'era un `return` secco, due righe dopo aver marcato la
      // milestone come "gia' fatta". L'effetto: l'onboarding, che [app.dart]
      // mostra PRIMA del login, non arrivava mai su Firestore — e non poteva
      // riprovarci, perche' il flag locale diceva di lasciar perdere.
      // `onboardingDoneAt` risultava vuoto per tutti, sempre: quel gradino del
      // funnel riportava 0 per costruzione, non perche' nessuno ci arrivasse.
      if (uid == null) {
        await _queuePreLoginMilestone(prefs, m, params);
        return;
      }

      final data = <String, dynamic>{
        m.field: FieldValue.serverTimestamp(),
        // In UTC e lato client: se il doc resta in coda offline il
        // serverTimestamp e' null finche' non sincronizza, e la milestone
        // sparirebbe dalle query per giorni.
        '${m.field}Client': DateTime.now().toUtc().toIso8601String(),
        if (params != null) '${m.name}Params': params,
      };

      // La registrazione e' il momento in cui l'utente prende un'identita':
      // e' li' che l'attribuzione raccolta prima del login trova un uid a cui
      // attaccarsi, e che la prima apertura entra nel doc.
      if (m == GrowthMilestone.signup) {
        data['acquisition'] = _pendingMap(prefs) ?? {'source': 'organic'};
        data['firstOpenAtClient'] = prefs.getString('growth_first_open_at');
        data['platform'] = _platform;
        data['appVersion'] = await _version();
      }

      unawaited(_mergeDoc(uid, data));
    } catch (e) {
      debugPrint('[Growth] milestone ${m.name}: $e');
    }
  }

  /// Chiave della coda delle milestone raggiunte da sloggati.
  static const String _kPendingMilestones = 'growth_pending_milestones';

  /// Fin dove si sono gia' contate le tracce arrivate dall'orologio.
  static const String _kWatchCursor = 'growth_watch_cursor';

  /// Registra le tracce che l'orologio ha caricato scavalcando l'app.
  ///
  /// Una traccia registrata al polso non passa da `TracksRepository.saveTrack`:
  /// la scrive la Cloud Function `syncGarminTrack`, che riceve i dati dal
  /// dispositivo e crea il documento lato server. Tutta la strumentazione del
  /// funnel vive invece nell'app, e quindi non se ne accorgeva mai: verificato
  /// il 2026-08-05, un account con una traccia da 10,8 km caricata dall'orologio
  /// non aveva ne' `firstTrackSavedAt` ne' `tracksSaved`. Chi registra solo col
  /// Garmin non si attivava **mai**, per sempre.
  ///
  /// Il recupero sta qui e non nella Cloud Function per una ragione precisa:
  /// l'opposizione dell'utente alla misura e' un flag locale, che il server non
  /// puo' vedere. Una scrittura dal server avrebbe ricreato il documento che
  /// l'opposizione aveva cancellato — spegnendo in silenzio un controllo
  /// privacy. Passando da qui, la scrittura attraversa `_mergeDoc`, che
  /// l'opposizione la conosce gia'.
  ///
  /// Il cursore parte da "adesso" alla prima esecuzione invece di recuperare lo
  /// storico: le regole non permettono all'app di **leggere** `growth_users`
  /// (`allow read: if false`), quindi non c'e' modo di sapere cosa sia gia'
  /// stato contato. Ripartire dal passato significherebbe ricontare tutto a
  /// ogni reinstallazione. Meglio perdere le tracce arrivate prima di questo
  /// codice che gonfiare il contatore per sempre.
  Future<void> _countWatchTracks() async {
    if (kDebugMode || _funnelOptedOut) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Guardia SINCRONA, prima di qualunque await. `authStateChanges` emette
    // piu' volte a distanza di millisecondi (login, poi refresh del token):
    // due esecuzioni concorrenti leggerebbero lo stesso cursore — che viene
    // riscritto solo a fine ciclo — e conterebbero due volte le stesse
    // tracce.
    //
    // E' la stessa trappola gia' documentata in [_touchLastSeen] poche righe
    // piu' su, dove era stata osservata sul campo. Qui non risulta ancora
    // essere successa: e' prevenzione, messa perche' il codice ha la stessa
    // forma — legge una preferenza, lavora, la riscrive alla fine — e quella
    // forma in questo file ha gia' morso una volta.
    if (_countingWatchTracks) return;
    _countingWatchTracks = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kWatchCursor);
      final now = DateTime.now().toUtc();
      if (saved == null) {
        await prefs.setString(_kWatchCursor, now.toIso8601String());
        return;
      }
      final cursor = DateTime.tryParse(saved);
      if (cursor == null) {
        await prefs.setString(_kWatchCursor, now.toIso8601String());
        return;
      }

      // Filtro sul solo `createdAt`, e `source` scremato lato client: bastano
      // due campi in `where` per pretendere un indice composito, e qui i
      // documenti sono quelli dall'ultima apertura — una manciata.
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('tracks')
          .where('createdAt', isGreaterThan: Timestamp.fromDate(cursor))
          .orderBy('createdAt')
          // Le tracce da orologio portano i punti dentro il documento, e un
          // documento cosi' pesa. Il tetto tiene bassa la memoria di una query
          // che gira a ogni accesso: ordinando dalla piu' vecchia e spostando
          // il cursore su quanto si e' letto, l'eventuale eccedenza viene
          // raccolta alla prossima apertura invece di essere persa.
          .limit(20)
          .get();

      var newest = cursor;
      var counted = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        final created = (data['createdAt'] as Timestamp?)?.toDate().toUtc();
        if (created != null && created.isAfter(newest)) newest = created;
        if (data['source'] != 'garmin') continue;

        // Si riusano i due metodi normali invece di scrivere a mano: sono gia'
        // gli unici a sapere come si marca una milestone una volta sola e come
        // si rispetta l'opposizione.
        await milestone(
          GrowthMilestone.firstTrackSaved,
          params: {'source': 'garmin'},
        );
        await recordTrackSaved(isPublic: data['isPublic'] == true);
        counted++;
      }

      await prefs.setString(_kWatchCursor, newest.toIso8601String());
      if (counted > 0) {
        debugPrint('[Growth] tracce da orologio recuperate: $counted');
      }
    } catch (e) {
      debugPrint('[Growth] recupero tracce da orologio: $e');
    } finally {
      _countingWatchTracks = false;
    }
  }

  /// Mette da parte una milestone raggiunta prima del login, con **l'ora in
  /// cui e' avvenuta davvero**.
  ///
  /// Conservare il momento originale non e' pignoleria: al login si potrebbe
  /// scrivere `serverTimestamp()`, ma allora ogni onboarding risulterebbe
  /// completato nello stesso istante della registrazione, e la distanza fra i
  /// due gradini — cioe' quanto si perde fra l'uno e l'altro, l'unica cosa che
  /// quel gradino misura — sarebbe sempre zero.
  Future<void> _queuePreLoginMilestone(
    SharedPreferences prefs,
    GrowthMilestone m,
    Map<String, dynamic>? params,
  ) async {
    final queue = prefs.getStringList(_kPendingMilestones) ?? <String>[];
    queue.add(jsonEncode({
      'name': m.name,
      'at': DateTime.now().toUtc().toIso8601String(),
      if (params != null) 'params': params,
    }));
    await prefs.setStringList(_kPendingMilestones, queue);
  }

  /// Scarica sulla scheda utente le milestone raggiunte prima del login.
  ///
  /// Una scrittura sola per tutta la coda, con i timestamp originali.
  Future<void> _flushPreLoginMilestones() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final queue = prefs.getStringList(_kPendingMilestones);
      if (queue == null || queue.isEmpty) return;

      final data = <String, dynamic>{};
      for (final entry in queue) {
        Map<String, dynamic> map;
        try {
          map = jsonDecode(entry) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }

        GrowthMilestone? m;
        for (final v in GrowthMilestone.values) {
          if (v.name == map['name']) {
            m = v;
            break;
          }
        }
        // Enum rinominato fra due versioni: si scarta la voce invece di far
        // fallire l'intera coda.
        if (m == null) continue;

        final at = DateTime.tryParse(map['at'] as String? ?? '');
        if (at == null) continue;

        data[m.field] = Timestamp.fromDate(at);
        data['${m.field}Client'] = at.toIso8601String();
        final p = map['params'];
        if (p is Map) data['${m.name}Params'] = Map<String, dynamic>.from(p);

        // Segna la milestone come fatta anche sotto l'uid: senza, un'eventuale
        // ri-emissione la riscriverebbe con `serverTimestamp()`, sostituendo
        // l'ora vera con quella del login.
        await prefs.setBool('growth_ms_${uid}_${m.name}', true);
      }

      // La coda si svuota comunque. `_mergeDoc` inghiotte i propri errori, e
      // tenerla in vita in attesa di una conferma che non arriva mai
      // significherebbe riprovare a ogni avvio per sempre: e' telemetria, non
      // deve diventare un problema dell'utente.
      await prefs.remove(_kPendingMilestones);
      if (data.isNotEmpty) unawaited(_mergeDoc(uid, data));
    } catch (e) {
      debugPrint('[Growth] flush milestone pre-login: $e');
    }
  }

  /// Conta ogni traccia salvata, non solo la prima.
  ///
  /// Le milestone rispondono a "è arrivato fin qui?", una volta per vita. Non
  /// rispondono a "quanto la usa": un utente che ha salvato una traccia a
  /// marzo e uno che ne registra due a settimana hanno lo stesso documento.
  ///
  /// `lastTrackSavedAt` è il segnale di vita che conta per un'app di
  /// registrazione, più di `lastSeenAt`: aprire l'app per guardare una mappa
  /// non è la stessa cosa che uscire a camminare.
  ///
  /// Le tracce private contano quanto le pubbliche. Chi registra per sé è un
  /// utente attivo a tutti gli effetti — la condivisione è un'altra domanda,
  /// e ha già il suo campo.
  Future<void> recordTrackSaved({required bool isPublic}) async {
    if (kDebugMode) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _mergeDoc(uid, {
      'tracksSaved': FieldValue.increment(1),
      if (isPublic) 'tracksPublic': FieldValue.increment(1),
      'lastTrackSavedAt': FieldValue.serverTimestamp(),
    });
  }

  /// L'utente ha scelto un metodo di registrazione (prima che vada a buon
  /// fine). La differenza tra questo e [GrowthMilestone.signup] misura quanto
  /// il login stesso perde per strada.
  Future<void> signupStarted(String method) =>
      _logEvent('signup_started', {'method': method});

  /// L'utente ha toccato "Collega" su un orologio, prima di sapere come
  /// andra' a finire.
  ///
  /// Serve perche' `connect()` di questi servizi restituisce true appena il
  /// browser si apre: l'autorizzazione avviene fuori dall'app, e se il
  /// fornitore la rifiuta l'utente torna indietro senza che accada niente —
  /// nessun messaggio, nessuna traccia. Il successo lo sappiamo gia' (e' la
  /// Cloud Function a scrivere il token), il tentativo no.
  ///
  /// Senza questo numero, "nessuno ci ha provato" e "tutti quelli che ci hanno
  /// provato hanno fallito" sono lo stesso dato. Il 2026-08-07, con
  /// l'abbonamento di produzione Suunto ancora in attesa di approvazione,
  /// c'era un solo account collegato — il fondatore — e non c'era modo di dire
  /// quale delle due cose stesse succedendo.
  ///
  /// Il contatore va su Firestore e non solo su Analytics perche' e' li' che
  /// si puo' incrociare con chi il token ce l'ha davvero.
  Future<void> integrationConnectStarted(String provider) async {
    await _logEvent('integration_connect_started', {'provider': provider});
    if (kDebugMode) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    unawaited(_mergeDoc(uid, {
      '${provider}ConnectStarts': FieldValue.increment(1),
      '${provider}ConnectLastAt': FieldValue.serverTimestamp(),
    }));
  }

  /// Paywall mostrato. Non e' una milestone: va contato ogni volta, perche' la
  /// domanda utile e' "quante visualizzazioni servono per una conversione".
  Future<void> paywallViewed(String trigger) async {
    await _logEvent('paywall_viewed', {'trigger': trigger});
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || kDebugMode) return;
    unawaited(_mergeDoc(uid, {'paywallViews': FieldValue.increment(1)}));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SINK
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _logEvent(String name, Map<String, dynamic>? params) async {
    try {
      await _ga?.logEvent(
        name: name,
        parameters: params == null || params.isEmpty
            ? null
            : params.map((k, v) => MapEntry(k, _asAnalyticsValue(v))),
      );
    } catch (e) {
      debugPrint('[Growth] logEvent $name: $e');
    }
  }

  /// Analytics accetta solo String e num come valori: tutto il resto va
  /// convertito, altrimenti il plugin solleva e perdiamo l'evento.
  Object _asAnalyticsValue(dynamic v) {
    if (v is num) return v;
    if (v is String) return v.length <= 100 ? v : v.substring(0, 100);
    return v.toString();
  }

  Future<void> _mergeDoc(String uid, Map<String, dynamic> data) async {
    // Unico punto da cui passano tutte le scritture del funnel: e' qui che
    // l'opposizione dell'utente deve mordere, non sparsa nei call site.
    if (_funnelOptedOut) return;
    try {
      await FirebaseFirestore.instance
          .collection(_collection)
          .doc(uid)
          .set({...data, 'uid': uid}, SetOptions(merge: true));
    } catch (e) {
      // Un rifiuto delle rules o un'assenza di rete non devono trasformarsi in
      // un errore non gestito: finirebbe in PlatformDispatcher.onError
      // (main.dart), che marca fatal: true — un problema di telemetria
      // travestito da crash.
      debugPrint('[Growth] scrittura growth_users fallita: $e');
    }
  }
}
