/// Entrypoint dedicato alla **dashboard B2B web** (`app.trailshare.app`).
///
/// Build command:
/// ```
/// flutter build web --target=lib/main_web.dart --release
/// ```
///
/// Mantiene la condivisione di modelli/repository/widget con l'app
/// mobile (lo stesso pubspec, gli stessi `lib/data/...` e
/// `lib/core/...`), ma evita di inizializzare i servizi mobile-only
/// (foreground service, BLE, Health, in_app_purchase consumer Pro,
/// notifiche locali, ecc.) che lato web non hanno senso o non
/// compilano.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'web/business_web_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const BusinessWebApp());
}
