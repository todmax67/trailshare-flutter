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


class TrailShareApp extends StatefulWidget {
  const TrailShareApp({super.key});

  @override
  State<TrailShareApp> createState() => _TrailShareAppState();
}

class _TrailShareAppState extends State<TrailShareApp> {
  final ThemeService _themeService = ThemeService();

  @override
  void initState() {
    super.initState();
    _themeService.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _themeService.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: MaterialApp(
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
    try {
      final doc = await FirebaseFirestore.instance
          .collection('user_profiles')
          .doc(widget.user.uid)
          .get();

      final data = doc.data();
      final username = data?['username'] as String?;

      // Ha username se il campo esiste, non è vuoto, e non è un placeholder
      final valid = username != null && 
                    username.isNotEmpty && 
                    username != 'Utente';

      if (mounted) {
        setState(() {
          _hasUsername = valid;
          _isChecking = false;
        });
      }
    } catch (e) {
      print('[UsernameGate] Errore check: $e');
      // In caso di errore, lascia passare per non bloccare l'utente
      if (mounted) {
        setState(() {
          _hasUsername = true;
          _isChecking = false;
        });
      }
    }
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
