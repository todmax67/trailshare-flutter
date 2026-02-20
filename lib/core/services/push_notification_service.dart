import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._();
  factory PushNotificationService() => _instance;
  PushNotificationService._();

  final _messaging = FirebaseMessaging.instance;
  final _firestore = FirebaseFirestore.instance;

  /// Inizializza le notifiche push
  Future<void> initialize() async {
    // 1. Richiedi permessi
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('[Push] Permessi negati');
      return;
    }

    debugPrint('[Push] Permessi: ${settings.authorizationStatus}');

    // 2. Salva token
    await _saveToken();

    // 3. Aggiorna token quando cambia
    _messaging.onTokenRefresh.listen((newToken) {
      _saveTokenToFirestore(newToken);
    });

    // 4. Gestisci notifiche in foreground
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // 5. Gestisci tap su notifica (app in background)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // 6. Controlla se l'app è stata aperta da una notifica
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }
  }

  /// Salva il token FCM corrente
  Future<void> _saveToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        debugPrint('[Push] Token FCM: ${token.substring(0, 20)}...');
        await _saveTokenToFirestore(token);
      }
    } catch (e) {
      debugPrint('[Push] Errore get token: $e');
    }
  }

  /// Salva token su Firestore nel profilo utente
  Future<void> _saveTokenToFirestore(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await _firestore.collection('user_profiles').doc(user.uid).set({
        'fcmTokens': FieldValue.arrayUnion([token]),
        'email': user.email,
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('[Push] Token salvato su Firestore');
    } catch (e) {
      debugPrint('[Push] Errore salvataggio token: $e');
    }
  }

  /// Rimuovi token al logout
  Future<void> removeToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _firestore.collection('user_profiles').doc(user.uid).update({
          'fcmTokens': FieldValue.arrayRemove([token]),
        });
        debugPrint('[Push] Token rimosso');
      }
    } catch (e) {
      debugPrint('[Push] Errore rimozione token: $e');
    }
  }

  /// Aggiorna token dopo login
  Future<void> onUserLogin() async {
    await _saveToken();
  }

  /// Gestisci notifica ricevuta in foreground
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('[Push] Notifica in foreground: ${message.notification?.title}');

    // Le notifiche in foreground non mostrano banner automaticamente
    // Usiamo un overlay/snackbar — lo gestiamo dal navigatorKey
    _onNotificationReceived?.call(message);
  }

  /// Gestisci tap su notifica
  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('[Push] Tap su notifica: ${message.data}');
    _onNotificationTap?.call(message);
  }

  // Callback per gestire notifiche nell'UI
  static Function(RemoteMessage)? _onNotificationReceived;
  static Function(RemoteMessage)? _onNotificationTap;

  /// Registra callback per notifiche foreground (da chiamare nel widget principale)
  static void setOnNotificationReceived(Function(RemoteMessage) callback) {
    _onNotificationReceived = callback;
  }

  /// Registra callback per tap su notifiche
  static void setOnNotificationTap(Function(RemoteMessage) callback) {
    _onNotificationTap = callback;
  }
}