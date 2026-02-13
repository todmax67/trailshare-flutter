import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'firebase_options.dart';
import 'app.dart';
import 'core/services/location_service.dart';
import 'core/services/theme_service.dart';
import 'core/services/push_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Inizializza tema
  await ThemeService().initialize();
  
  // Inizializza notifiche push
  await PushNotificationService().initialize();
  
  runApp(const TrailShareApp());
}
