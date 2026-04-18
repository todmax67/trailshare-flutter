import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';

/// Servizio dedicato all'**allarme di inattività Lifeline** in standby.
///
/// Problema risolto: quando il telefono è in tasca / schermo spento / standby,
/// il dialog in-app "Tutto bene?" non può essere visto. Serve un alert
/// **sistemato dal SO** che:
/// - fa suonare un tono di allarme (canale MAX priority)
/// - vibra con pattern intenso e ripetuto
/// - riattiva lo schermo se possibile
/// - mostra una notifica cliccabile che apre l'app sul dialog
///
/// Implementa il "primo livello" dell'auto-alert 2-step: prima che scatti
/// l'invio effettivo ai contatti (dopo 5 min senza risposta), l'utente
/// DEVE avere ogni possibilità di sentire l'alert e rispondere.
class LifelineAlertService {
  LifelineAlertService._();
  static final LifelineAlertService _i = LifelineAlertService._();
  factory LifelineAlertService() => _i;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  Timer? _vibrationLoop;

  /// ID della notifica di inattività. Usando un id fisso assicuriamo di
  /// non accumulare notifiche multiple: ogni nuovo alert sostituisce
  /// il precedente.
  static const int _inactivityNotifId = 1701;

  /// Channel ID Android dedicato. IMPORTANCE_HIGH permette suono + heads-up
  /// + wake screen anche se lo schermo è spento.
  static const String _channelId = 'lifeline_inactivity';
  static const String _channelName = 'Lifeline — Check di sicurezza';
  static const String _channelDesc =
      'Notifiche quando Lifeline rileva inattività prolungata e '
      'richiede la tua conferma';

  /// Inizializza il plugin (chiamare una volta all'avvio app).
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      ),
    );

    // Crea canale Android con IMPORTANCE_HIGH (suona + heads-up + wake)
    const androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    // Richiedi permesso notifiche (Android 13+)
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Scatena l'alert completo di inattività:
  /// - notifica di sistema MAX priority che sveglia lo schermo
  /// - vibrazione ripetuta per 30s (o finché dismiss)
  /// - suono di allarme via canale notifica
  ///
  /// La UI deve chiamare [dismiss] quando l'utente risponde al dialog.
  Future<void> fireInactivityAlert() async {
    debugPrint('[LifelineAlert] fireInactivityAlert');
    if (!_initialized) await initialize();

    // 1. Notifica di sistema
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
      ongoing: true, // non rimovibile con swipe finché non confermata
      autoCancel: false,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    await _plugin.show(
      _inactivityNotifId,
      'Tutto bene?',
      'Lifeline ha rilevato inattività prolungata. Apri TrailShare per confermare.',
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );

    // 2. Vibrazione ripetuta (pattern intenso per 30s, poi si ferma)
    _startVibrationLoop();
  }

  /// Dismiss tutto: cancella notifica, ferma vibrazione.
  /// Chiamato quando l'utente tocca un bottone nel dialog o quando il
  /// timer di response window scade (poi parte l'auto-alert ai contatti).
  Future<void> dismiss() async {
    debugPrint('[LifelineAlert] dismiss');
    _stopVibrationLoop();
    try {
      await _plugin.cancel(_inactivityNotifId);
    } catch (e) {
      debugPrint('[LifelineAlert] errore cancel: $e');
    }
  }

  /// Pattern di vibrazione lungo + ripetuto: 1s on, 0.5s off, loop per 30s.
  /// Su iOS il sistema gestisce la vibrazione tramite la notifica; qui
  /// usiamo comunque il package per dispositivi Android dove serve più
  /// intensità.
  void _startVibrationLoop() {
    _stopVibrationLoop();
    if (kIsWeb) return;

    _vibrationLoop = Timer.periodic(const Duration(milliseconds: 1500), (t) {
      if (t.tick > 20) {
        // 20 cicli ~ 30 secondi
        _stopVibrationLoop();
        return;
      }
      _vibrateOnce();
    });
    // Prima vibrazione immediata (senza aspettare 1.5s)
    _vibrateOnce();
  }

  void _vibrateOnce() {
    Vibration.hasVibrator().then((has) {
      if (has == true) {
        Vibration.vibrate(duration: 1000, amplitude: 255);
      }
    }).catchError((e) {
      debugPrint('[LifelineAlert] errore vibration: $e');
    });
  }

  void _stopVibrationLoop() {
    _vibrationLoop?.cancel();
    _vibrationLoop = null;
    try {
      Vibration.cancel();
    } catch (_) {}
  }
}
