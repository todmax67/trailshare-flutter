import 'package:flutter/foundation.dart';
import 'package:flutter_screen_recording/flutter_screen_recording.dart';

/// Wrapper isolato attorno alla registrazione schermo nativa usata per
/// l'export video del fly-through 3D.
///
/// Il fly gira in WebView (MapLibre) e iOS WKWebView non supporta
/// MediaRecorder/captureStream → l'unica via cross-platform è la
/// registrazione schermo nativa (Android MediaProjection + iOS ReplayKit).
/// Incapsuliamo il plugin qui così, se un domani serve cambiarlo (es.
/// problemi su Android 14), si tocca solo questo file.
///
/// ⚠️ Richiede test sul device: la registrazione schermo dipende da
/// permessi di sistema e dialog nativi non riproducibili in CI.
class FlyExportService {
  FlyExportService._();

  static bool _recording = false;
  static bool get isRecording => _recording;

  /// Avvia la registrazione schermo. Su Android mostra il dialog di consenso
  /// MediaProjection; su iOS il prompt ReplayKit. Ritorna true se partita.
  static Future<bool> start(String name) async {
    if (_recording) return true;
    try {
      // Solo video (audio silenzioso per scelta di prodotto: chi condivide
      // aggiunge la propria musica). Niente permesso microfono.
      final ok = await FlutterScreenRecording.startRecordScreen(name);
      _recording = ok;
      return ok;
    } catch (e) {
      debugPrint('[FlyExport] start error: $e');
      _recording = false;
      return false;
    }
  }

  /// Ferma la registrazione e ritorna il path del file video (o null).
  static Future<String?> stop() async {
    if (!_recording) return null;
    try {
      final path = await FlutterScreenRecording.stopRecordScreen;
      _recording = false;
      return (path.isEmpty) ? null : path;
    } catch (e) {
      debugPrint('[FlyExport] stop error: $e');
      _recording = false;
      return null;
    }
  }
}
