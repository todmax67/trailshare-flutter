import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'presentation/pages/auth/login_page.dart';
import 'presentation/pages/home/home_page.dart';
import 'core/constants/app_themes.dart';
import 'core/services/theme_service.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'presentation/pages/onboarding/onboarding_page.dart';
import 'core/services/push_notification_service.dart';


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
          return const HomePage();
        }
        return const LoginPage();
      },
    );
  }
}