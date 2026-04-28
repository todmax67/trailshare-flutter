import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'firebase_options.dart';
import 'app.dart';
import 'core/services/location_service.dart';
import 'core/services/theme_service.dart';
import 'core/services/push_notification_service.dart';
import 'core/services/lifeline_alert_service.dart';
import 'package:flutter/foundation.dart';
import 'core/services/health_service.dart';
import 'core/services/offline_tile_provider.dart';
import 'core/services/garmin_sync_service.dart';
import 'core/services/pro_gate_service.dart';
import 'core/services/subscription_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
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

  runApp(const TrailShareApp());
}
