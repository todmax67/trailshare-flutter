import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Wrapper semplice su [FlutterTts] per la guida vocale in italiano.
///
/// Uso tipico:
/// ```dart
/// final voice = VoiceGuidanceService();
/// await voice.init();
/// await voice.speak('Svolta a sinistra tra 200 metri');
/// ...
/// await voice.dispose();
/// ```
class VoiceGuidanceService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool _enabled = true;

  bool get enabled => _enabled;
  set enabled(bool v) {
    _enabled = v;
    if (!v) stop();
  }

  Future<void> init() async {
    if (_initialized) return;
    try {
      await _tts.setLanguage('it-IT');
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(true);
      _initialized = true;
    } catch (e) {
      debugPrint('[Voice] Errore init: $e');
    }
  }

  Future<void> speak(String text) async {
    if (!_enabled || text.isEmpty) return;
    if (!_initialized) await init();
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('[Voice] Errore speak: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
