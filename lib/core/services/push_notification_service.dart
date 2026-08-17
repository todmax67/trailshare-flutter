import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import '../../app.dart';
import '../../data/repositories/community_tracks_repository.dart';
import '../../presentation/pages/discover/community_track_detail_page.dart';
import '../../presentation/pages/groups/group_detail_page.dart';
import '../../presentation/pages/profile/public_profile_page.dart';

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
      // Posticipa di un frame: navigatorKey può non essere ancora pronto
      // al cold start (stesso accorgimento di DeepLinkService).
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _handleNotificationTap(initialMessage));
    }
  }

  /// Salva il token FCM corrente
  Future<void> _saveToken() async {
    try {
      final token = await _messaging.getToken()
          .timeout(const Duration(seconds: 10));
      if (token != null) {
        debugPrint('[Push] Token FCM: ${token.substring(0, 20)}...');
        await _saveTokenToFirestore(token)
            .timeout(const Duration(seconds: 5));
      }
    } catch (e) {
      debugPrint('[Push] Errore get token (offline?): $e');
    }
  }

  /// Salva token su Firestore nel profilo utente
  Future<void> _saveTokenToFirestore(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final email = user.email ?? '';
      await _firestore.collection('user_profiles').doc(user.uid).set({
        'fcmTokens': FieldValue.arrayUnion([token]),
        'email': email,
        'isPrivateRelayEmail': email.endsWith('@privaterelay.appleid.com'),
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('[Push] Token salvato su Firestore');
    } catch (e) {
      debugPrint('[Push] Errore salvataggio token: $e');
    }
  }

  /// Aggiorna `lastOpenedAt` nel profilo utente.
  /// Va chiamato all'avvio app e ad ogni resume dal background.
  /// Distinto da `lastActive` (aggiornato solo al login/refresh token),
  /// permette di segmentare utenti realmente dormienti per campagne push.
  Future<void> updateLastOpened() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final email = user.email ?? '';
      await _firestore.collection('user_profiles').doc(user.uid).set({
        'lastOpenedAt': FieldValue.serverTimestamp(),
        'isPrivateRelayEmail': email.endsWith('@privaterelay.appleid.com'),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[Push] Errore update lastOpenedAt: $e');
    }
  }

  /// Legge la preferenza opt-in per notifiche di novità / campagne.
  /// Default: true (opt-in implicito per utenti storici).
  Future<bool> getNewsUpdatesEnabled() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return true;

    try {
      final doc = await _firestore.collection('user_profiles').doc(user.uid).get();
      final prefs = doc.data()?['notificationPreferences'] as Map<String, dynamic>?;
      final value = prefs?['newsUpdates'];
      return value is bool ? value : true;
    } catch (e) {
      debugPrint('[Push] Errore lettura notificationPreferences: $e');
      return true;
    }
  }

  /// Aggiorna la preferenza opt-in per notifiche di novità.
  Future<void> setNewsUpdatesEnabled(bool enabled) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await _firestore.collection('user_profiles').doc(user.uid).set({
        'notificationPreferences': {'newsUpdates': enabled},
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[Push] Errore salvataggio notificationPreferences: $e');
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
    _routeToContent(message.data);
  }

  /// Tab del gruppo da aprire in base al tipo di notifica — prima si
  /// aprivano tutte sulla Home, indipendentemente dal contenuto.
  static const _groupTabByType = {
    'group_message': 0, // Chat
    'group_event': 1, // Eventi
    'group_challenge': 3, // Sfide
    'group_challenge_won': 3, // Sfide
    'join_request': 4, // Info — dove l'admin approva/rifiuta
    'join_approved': 0, // Chat — appena entrato, si parte da lì
  };

  Future<void> _routeToContent(Map<String, dynamic> data) async {
    final type = data['type'] as String?;

    final groupId = data['groupId'] as String?;
    final tabIndex = _groupTabByType[type];
    if (groupId != null && groupId.isNotEmpty && tabIndex != null) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'GroupDetailPage'),
          builder: (_) => GroupDetailPage(
            groupId: groupId,
            groupName: 'Gruppo',
            initialTabIndex: tabIndex,
          ),
        ),
      );
      return;
    }

    // Nuovo follower → profilo pubblico di chi ti segue ora.
    if (type == 'new_follower') {
      final userId = data['userId'] as String?;
      if (userId == null || userId.isEmpty) return;
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'PublicProfilePage'),builder: (_) => PublicProfilePage(userId: userId)),
      );
      return;
    }

    // Cheer ("kudos" nel payload — il prodotto lo chiama Cheer) o menzione
    // in un commento → dettaglio della traccia pubblicata (mostra i
    // commenti). Serve fetchare la traccia: il payload ha solo l'id.
    if (type == 'kudos' || type == 'mention') {
      final trackId = data['trackId'] as String?;
      if (trackId == null || trackId.isEmpty) return;
      final track = await CommunityTracksRepository().getTrackById(trackId);
      if (track == null) return;
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'CommunityTrackDetailPage'),builder: (_) => CommunityTrackDetailPage(track: track)),
      );
      return;
    }
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