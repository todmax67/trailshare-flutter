import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'firebase_options.dart';
import 'app.dart';
import 'core/services/location_service.dart';
import 'core/services/theme_service.dart';
import 'core/services/push_notification_service.dart';
import 'package:flutter/foundation.dart';
import 'core/services/health_service.dart';
import 'core/services/offline_tile_provider.dart';

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
  
  // Configura Health Connect/HealthKit (registra permission launcher)
  HealthService().configure().catchError((e) {
    debugPrint('[Health] Init fallita: $e');
  });

  // Inizializza tile offline
  await OfflineFallbackTileProvider.initialize();
  
  runApp(const TrailShareApp());
}
