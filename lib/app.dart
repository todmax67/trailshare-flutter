import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'presentation/pages/auth/login_page.dart';
import 'presentation/pages/home/home_page.dart';
import 'presentation/pages/auth/choose_username_page.dart';
import 'core/constants/app_themes.dart';
import 'core/services/theme_service.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'presentation/pages/onboarding/onboarding_page.dart';
import 'core/services/push_notification_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/generated/app_localizations.dart';
import 'dart:async';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'presentation/pages/tracks/import_gpx_page.dart';

/// Chiave globale per la navigazione da qualsiasi punto
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class TrailShareApp extends StatefulWidget {
  const TrailShareApp({super.key});

  @override
  State<TrailShareApp> createState() => _TrailShareAppState();
}

class _TrailShareAppState extends State<TrailShareApp> with WidgetsBindingObserver {
  final ThemeService _themeService = ThemeService();
  StreamSubscription? _intentSub;

  @override
  void initState() {
    super.initState();
    _themeService.addListener(_onThemeChanged);
    WidgetsBinding.instance.addObserver(this);
    _listenForSharedFiles();
    // Primo tracking apertura app (se utente gia loggato).
    PushNotificationService().updateLastOpened();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _themeService.removeListener(_onThemeChanged);
    _intentSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      PushNotificationService().updateLastOpened();
    }
  }

  void _onThemeChanged() {
    setState(() {});
  }

  void _listenForSharedFiles() {
    // File ricevuti mentre l'app è aperta
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      _handleSharedFiles(files);
    });

    // File ricevuti all'avvio dell'app
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      _handleSharedFiles(files);
      ReceiveSharingIntent.instance.reset();
    });
  }

  void _handleSharedFiles(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    
    for (final file in files) {
      final path = file.path;
      final ext = path.split('.').last.toLowerCase();
      
      if (['gpx', 'fit', 'tcx'].contains(ext)) {
        Future.delayed(const Duration(milliseconds: 500), () {
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => ImportGpxPage(initialFilePath: path),
            ),
          );
        });
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'TrailShare',
        debugShowCheckedModeBanner: false,
        theme: AppThemes.lightTheme,
        darkTheme: AppThemes.darkTheme,
        themeMode: _themeService.themeMode,
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
        home: const AuthWrapper(),
      ),
    );
  }
}

/// Wrapper che gestisce lo stato di autenticazione
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _checkingOnboarding = true;
  bool _showOnboarding = false;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final completed = await OnboardingService.isCompleted();
    setState(() {
      _showOnboarding = !completed;
      _checkingOnboarding = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingOnboarding) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_showOnboarding) {
      return OnboardingPage(onComplete: () => setState(() => _showOnboarding = false));
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) {
          PushNotificationService().onUserLogin();
          return _UsernameGate(user: snapshot.data!);
        }
        return const LoginPage();
      },
    );
  }
}

/// ⭐ Gate che verifica se l'utente ha un username prima di mostrare HomePage
class _UsernameGate extends StatefulWidget {
  final User user;

  const _UsernameGate({required this.user});

  @override
  State<_UsernameGate> createState() => _UsernameGateState();
}

class _UsernameGateState extends State<_UsernameGate> {
  bool _isChecking = true;
  bool _hasUsername = false;

  @override
  void initState() {
    super.initState();
    _checkUsername();
  }

  Future<void> _checkUsername() async {
    // Fast path 1: se il displayName di FirebaseAuth è già un username
    // valido (popolato da Google Sign-In / Apple Sign-In / sign-up flow),
    // ci fidiamo senza neppure fetchare Firestore. Risolve il caso
    // "reinstall + cache vuota + rete lenta" dove il vecchio gate
    // rispediva l'utente alla ChooseUsernamePage anche se il profilo
    // su server aveva l'username corretto.
    final displayName = widget.user.displayName?.trim();
    if (displayName != null &&
        displayName.isNotEmpty &&
        displayName != 'Utente') {
      debugPrint(
          '[UsernameGate] fast-path displayName=$displayName → ok');
      if (mounted) {
        setState(() {
          _hasUsername = true;
          _isChecking = false;
        });
      }
      // In background, tenta comunque di leggere user_profiles per
      // sincronizzare la cache locale. Non blocca la UI.
      _warmupProfileCache();
      return;
    }

    // Fast path 2: lookup Firestore. Server timeout esteso a 10s
    // per reti lente; fallback cache solo se il server fallisce.
    try {
      DocumentSnapshot doc;
      try {
        doc = await FirebaseFirestore.instance
            .collection('user_profiles')
            .doc(widget.user.uid)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        doc = await FirebaseFirestore.instance
            .collection('user_profiles')
            .doc(widget.user.uid)
            .get();
      }

      final data = doc.data() as Map<String, dynamic>?;
      final username = data?['username'] as String?;

      final valid = username != null &&
          username.trim().isNotEmpty &&
          username != 'Utente';

      debugPrint('[UsernameGate] Username: $username, valid: $valid');

      if (mounted) {
        setState(() {
          _hasUsername = valid;
          _isChecking = false;
        });
      }
    } catch (e) {
      // Default conservativo: non bombardare l'utente con la
      // ChooseUsernamePage se un errore di rete ci impedisce di
      // verificare. Se davvero non ha username, lo gestiremo la
      // prossima volta che apre l'app online.
      debugPrint('[UsernameGate] Errore check: $e → assumo username ok');
      if (mounted) {
        setState(() {
          _hasUsername = true;
          _isChecking = false;
        });
      }
    }
  }

  /// Pre-carica user_profiles in cache locale così le query successive
  /// non pagano un round-trip. Fire-and-forget, no errori critici.
  void _warmupProfileCache() {
    FirebaseFirestore.instance
        .collection('user_profiles')
        .doc(widget.user.uid)
        .get(const GetOptions(source: Source.server))
        .catchError((e) {
      debugPrint('[UsernameGate] warmup error: $e');
      return FirebaseFirestore.instance
          .collection('user_profiles')
          .doc(widget.user.uid)
          .get();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_hasUsername) {
      return ChooseUsernamePage(
        onUsernameChosen: () {
          setState(() => _hasUsername = true);
        },
      );
    }

    return const HomePage();
  }
}
