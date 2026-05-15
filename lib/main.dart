import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'app.dart';
import 'core/services/theme_service.dart';
import 'core/services/push_notification_service.dart';
import 'core/services/lifeline_alert_service.dart';
import 'core/services/health_service.dart';
import 'core/services/offline_tile_provider.dart';
import 'core/services/garmin_sync_service.dart';
import 'core/services/hud_prefs_service.dart';
import 'core/services/pro_gate_service.dart';
import 'core/services/subscription_manager.dart';
import 'core/services/deep_link_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Overflow hunter — solo in debug. Stampa un log evidente quando un
  // RenderFlex/Box overflow, con file:linea del widget colpevole nello
  // stack. Da rimuovere/spegnere quando avremo chiuso tutti i casi.
  if (kDebugMode) {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      final msg = details.exception.toString();
      if (msg.contains('overflowed') || msg.contains('RenderFlex')) {
        debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        debugPrint('🔴 OVERFLOW: $msg');
        // Anche il "context" del FlutterErrorDetails contiene spesso il
        // file:linea del widget creatore (es. Row:file:///.../foo.dart:42).
        if (details.context != null) {
          debugPrint('📍 Context: ${details.context}');
        }
        if (details.stack != null) {
          final lines = details.stack.toString().split('\n');
          final ours = lines
              .where((l) => l.contains('package:trailshare_flutter/'))
              .take(10)
              .toList();
          if (ours.isNotEmpty) {
            debugPrint('📍 Stack (codice nostro):');
            for (final l in ours) {
              debugPrint('   $l');
            }
          }
        }
        debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      }
      originalOnError?.call(details);
    };
  }

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 2.4.5 — Firestore cache cap a 40MB (default 100MB) per evitare
  // crash SQLitePersistence su Android con heap 256MB. Crash tipico:
  //   E/AndroidRuntime SQLitePersistence.runTransaction
  //   preceduto da 'Alloc concurrent mark compact GC freed 149MB'
  // = OOM corrompe il db SQLite locale. Con cap 40MB Firestore prune
  // proattivamente e non superiamo mai una soglia critica anche su
  // utenti con storico massiccio.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: 40 * 1024 * 1024,
  );

  // Inizializza tema
  await ThemeService().initialize();
  
  // Inizializza notifiche push (non blocca l'avvio)
  PushNotificationService().initialize().catchError((e) {
    debugPrint('[Push] Init fallita, riproverà dopo: $e');
  });

  // Inizializza sincronizzazione Garmin
  GarminSyncService().initialize();
  
  // Configura Health Connect/HealthKit (registra permission launcher)
  HealthService().configure().catchError((e) {
    debugPrint('[Health] Init fallita: $e');
  });

  // Inizializza tile offline
  await OfflineFallbackTileProvider.initialize();

  // Inizializza alert notifica Lifeline (canale max priority + permessi)
  LifelineAlertService().initialize().catchError((e) {
    debugPrint('[LifelineAlert] Init fallita: $e');
  });

  // Carica stato Pro persistito (da SharedPreferences) prima di runApp
  // così la UI parte con il valore corretto, niente flicker di paywall.
  await ProGateService().load();

  // 1.D4 — preferenze auto-hide HUD (record page). Caricamento veloce,
  // legge solo 2 chiavi da SharedPreferences.
  await HudPrefsService().load();

  // Apre il sync con Firestore: ascolta authStateChanges e allinea Pro
  // con users/{uid}.proStatus (sorgente autorevole, scritta da
  // validateAppleReceipt). Garantisce cross-device sync e gestisce
  // logout. Non bloccante.
  ProGateService().initFirestoreSync();

  // Inizializza il manager degli abbonamenti (in_app_purchase). Non
  // bloccante: lo store può essere lento e a noi basta che parta in
  // parallelo. Il PaywallSheet aspetta la lista prodotti via listener.
  SubscriptionManager().init().catchError((e) {
    debugPrint('[SubscriptionManager] Init fallita: $e');
  });

  // Deep link handler (custom scheme trailshare://g/{code} dal QR
  // della Card invito brandizzata). Non bloccante.
  DeepLinkService().initialize().catchError((e) {
    debugPrint('[DeepLink] Init fallita: $e');
  });

  runApp(const TrailShareApp());
}
