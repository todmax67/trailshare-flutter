import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/constants/app_colors.dart';
import '../l10n/generated/app_localizations.dart';
import 'pages/web_home_page.dart';
import 'pages/web_login_page.dart';

/// Root MaterialApp della dashboard B2B web.
///
/// È volutamente isolata da [TrailShareApp] mobile per non importarne
/// dipendenze nativo-only (foreground task, BLE, ecc.). Tema light
/// fisso per ora — il dark mode lato web verrà aggiunto se richiesto.
class BusinessWebApp extends StatelessWidget {
  const BusinessWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TrailShare Business',
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
      home: const _AuthGate(),
    );
  }
}

/// Switch tra login e dashboard in base allo stato auth Firebase.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

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
        return const WebHomePage();
      },
    );
  }
}
