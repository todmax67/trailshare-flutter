import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // 2.4.6 — Firestore cache cap a 20MB (era 40 in 2.4.5, default 100).
  //
  // Root cause OOM Android: i doc tracks hanno i GPS `points` embedded
  // (anche 5+ MB cad.). Quando Firestore decodifica i protobuf
  // (SQLiteRemoteDocumentCache.decodeMaybeDocument →
  //  MessageSchema.parseMapField), il peak memory per il PARSING è
  // molto > della size on-disk. Con cache da 40MB su disco abbiamo
  // visto comunque OOM 'Failed to allocate 32 byte allocation' dopo
  // un po' di uso = parsing+heap pressure cumulato.
  //
  // 20MB è aggressivo (LRU eviction frequente, qualche query in
  // più al server) ma blocca l'esplosione di memory.
  //
  // Fix sistemico vero: split tracks in sub-collection track_points
  // (in backlog 1-2 settimane). Quando arriverà, alzeremo di nuovo
  // il cap.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: 20 * 1024 * 1024,
  );

  // Recovery automatico post-OOM: se all'avvio precedente abbiamo
  // visto un crash, la cache SQLite può essere corrotta. Chiamiamo
  // clearPersistence al boot successivo per ripartire pulito (la
  // perdita è solo l'offline cache, niente dati utente).
  await _maybeRecoverFromCrash();

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

  // Marca boot-success dopo che l'app è running. Se l'app crasha
  // prima di arrivare qui, il flag '_boot_in_progress' resta true e
  // il prossimo avvio scatena clearPersistence (vedi
  // _maybeRecoverFromCrash). Delay 8s per essere sicuri che siamo
  // davvero stabili (la home + i primi snapshot listener sono
  // partiti).
  Future.delayed(const Duration(seconds: 8), () async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('_boot_in_progress', false);
    } catch (_) {
      // silent
    }
  });
}

/// Se il boot precedente non è arrivato a completarsi (probabile
/// crash, es. OOM su parse Firestore), il flag '_boot_in_progress'
/// è rimasto true → pulisco la cache locale Firestore prima di
/// iniziare il nuovo boot. È una recovery pragmatica per i casi in
/// cui la SQLite cache è satura/corrotta da un crash precedente.
///
/// La perdita è solo della cache offline: tutti i dati utente sono
/// su Firestore server, vengono rifecchati al primo accesso.
Future<void> _maybeRecoverFromCrash() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final wasBooting = prefs.getBool('_boot_in_progress') ?? false;
    if (wasBooting) {
      debugPrint(
          '[Boot] Recovery: il boot precedente non è arrivato a fine, '
          'pulizia cache Firestore in corso...');
      try {
        await FirebaseFirestore.instance.terminate();
        await FirebaseFirestore.instance.clearPersistence();
        debugPrint('[Boot] Cache Firestore ripulita');
      } catch (e) {
        debugPrint('[Boot] clearPersistence fallito: $e');
      }
    }
    // Sempre: marca questo boot come "in progresso". Verrà flippato
    // a false 8 secondi dopo runApp se tutto va liscio.
    await prefs.setBool('_boot_in_progress', true);
  } catch (e) {
    debugPrint('[Boot] _maybeRecoverFromCrash error: $e');
  }
}
