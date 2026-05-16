import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import '../core/constants/app_colors.dart';
import '../data/models/track.dart';
import '../data/repositories/tracks_repository.dart';
import '../l10n/generated/app_localizations.dart';
import 'pages/web_business_dashboard_page.dart';
import 'pages/web_business_public_page.dart';
import 'pages/web_home_page.dart';
import 'pages/web_login_page.dart';
import 'pages/web_self_claim_page.dart';
import 'pages/web_track_detail_page.dart';

/// Mappa tab WebHomePage → path URL e viceversa.
///
/// Centralizzata qui per evitare drift tra sidebar (web_home_page),
/// onGenerateRoute (qui) e link diretti (track tile, ecc.).
class WebRoutes {
  static const String dashboard = '/dashboard';
  static const String tracks = '/tracks';
  static const String planner = '/planner';
  static const String profile = '/profile';
  static const String business = '/business';
  static const String groups = '/groups';
  static const String discover = '/discover';
  static const String admin = '/admin';

  static int tabFromPath(String path) {
    if (path == dashboard || path == '/') return 0;
    if (path == tracks || path.startsWith('$tracks/')) return 1;
    if (path == planner) return 2;
    if (path == profile) return 3;
    if (path == business || path.startsWith('$business/')) return 4;
    if (path == groups) return 5;
    if (path == discover) return 6;
    if (path == admin) return 7;
    return 0;
  }

  static String pathFromTab(int tab) {
    switch (tab) {
      case 1:
        return tracks;
      case 2:
        return planner;
      case 3:
        return profile;
      case 4:
        return business;
      case 5:
        return groups;
      case 6:
        return discover;
      case 7:
        return admin;
      case 0:
      default:
        return dashboard;
    }
  }

  static String trackDetail(String trackId) => '$tracks/$trackId';
  static String businessDashboard(String businessId) => '$business/$businessId';
}

/// Root MaterialApp della dashboard B2B web con routing path-based.
///
/// URL supportati:
/// - `/`              → Dashboard (tab 0)
/// - `/dashboard`     → Dashboard
/// - `/tracks`        → Lista tracce
/// - `/tracks/{id}`   → Dettaglio traccia (deep link condivisibile)
/// - `/planner`       → Pianificatore
/// - `/profile`       → Profilo
/// - `/groups`        → Gruppi Business (solo admin)
///
/// Tutte le route protette passano dall'AuthGate: se l'utente non è
/// loggato vede [WebLoginPage] e dopo il login viene rilanciata l'URL
/// originale (Firebase Auth aggiorna lo stream e il widget rebuilda).
class BusinessWebApp extends StatelessWidget {
  const BusinessWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    // URL puliti (no `#/...`). Necessario configurare il rewrite a
    // index.html lato Firebase Hosting (già attivo in firebase.json).
    usePathUrlStrategy();

    return MaterialApp(
      title: 'TrailShare',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: AppColors.background,
        fontFamily: 'Outfit',
      ),
      // Le pagine condivise con mobile (GroupMembersPage, ecc.) usano
      // context.l10n: senza i delegate, la chiamata si schianta con
      // "Null check operator used on a null value" quando il widget
      // legge una stringa localizzata.
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('it'),
        Locale('en'),
      ],
      initialRoute: '/',
      onGenerateRoute: _onGenerateRoute,
    );
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    final uri = Uri.parse(settings.name ?? '/');
    final segments = uri.pathSegments;

    // 7.D1 — Landing pubblica `/b/{slug}` per Spazi Pro: NESSUN AuthGate,
    // pagina visibile a tutti (anche bot SEO + visitatori non loggati).
    if (segments.length == 2 && segments[0] == 'b') {
      return MaterialPageRoute<dynamic>(
        settings: settings,
        builder: (_) => WebBusinessPublicPage(slug: segments[1]),
      );
    }

    // 7.H1 — Self-claim flow: `/claim-self/{businessId}?t={token}`.
    // L'AuthGate fa il suo lavoro: se l'utente non e' loggato vede la
    // login, dopo login Firebase rinfresca lo stream e la pagina
    // appare. La pagina legge il token dal query param e chiama
    // acceptSelfClaim() Cloud Function.
    if (segments.length == 2 && segments[0] == 'claim-self') {
      final token = uri.queryParameters['t'] ?? '';
      return MaterialPageRoute<dynamic>(
        settings: settings,
        builder: (_) => _AuthGate(
          child: WebSelfClaimPage(
            businessId: segments[1],
            token: token,
          ),
        ),
      );
    }

    Widget child;

    if (segments.isEmpty) {
      child = const WebHomePage(initialTab: 0);
    } else if (segments[0] == 'dashboard') {
      child = const WebHomePage(initialTab: 0);
    } else if (segments[0] == 'tracks') {
      if (segments.length == 1) {
        child = const WebHomePage(initialTab: 1);
      } else {
        // /tracks/:id — deep link a singola traccia
        child = _TrackByIdLoader(trackId: segments[1]);
      }
    } else if (segments[0] == 'planner') {
      child = const WebHomePage(initialTab: 2);
    } else if (segments[0] == 'profile') {
      child = const WebHomePage(initialTab: 3);
    } else if (segments[0] == 'business') {
      if (segments.length == 1) {
        child = const WebHomePage(initialTab: 4);
      } else {
        // /business/:id deep link → dashboard del singolo Spazio Pro
        child = WebBusinessDashboardPage(businessId: segments[1]);
      }
    } else if (segments[0] == 'groups') {
      child = const WebHomePage(initialTab: 5);
    } else if (segments[0] == 'discover') {
      child = const WebHomePage(initialTab: 6);
    } else if (segments[0] == 'admin') {
      child = const WebHomePage(initialTab: 7);
    } else {
      // Unknown path → fallback a dashboard
      child = const WebHomePage(initialTab: 0);
    }

    return MaterialPageRoute<dynamic>(
      settings: settings,
      builder: (_) => _AuthGate(child: child),
    );
  }
}

/// Wrappa una pagina protetta: se l'utente non è loggato mostra il
/// login, altrimenti il [child]. Dopo il login Firebase emette il
/// nuovo stato e questo widget ricostruisce con la pagina originale,
/// preservando la URL richiesta.
class _AuthGate extends StatelessWidget {
  final Widget child;
  const _AuthGate({required this.child});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user == null) return const WebLoginPage();
        return child;
      },
    );
  }
}

/// Carica async una traccia per ID e mostra il dettaglio.
/// Se la traccia non esiste / non è dell'utente loggato → fallback
/// alla lista tracce con messaggio.
class _TrackByIdLoader extends StatefulWidget {
  final String trackId;
  const _TrackByIdLoader({required this.trackId});

  @override
  State<_TrackByIdLoader> createState() => _TrackByIdLoaderState();
}

class _TrackByIdLoaderState extends State<_TrackByIdLoader> {
  final _repo = TracksRepository();
  Track? _track;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await _repo.getTrackById(widget.trackId);
    if (!mounted) return;
    setState(() {
      _track = t;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final track = _track;
    if (track == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Traccia non trovata')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.search_off, size: 56),
                const SizedBox(height: 16),
                const Text(
                  'Traccia non trovata',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'La traccia richiesta non esiste o non è del tuo account.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pushReplacementNamed(
                    context,
                    WebRoutes.tracks,
                  ),
                  child: const Text('Vai alle mie tracce'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return WebTrackDetailPage(track: track);
  }
}
