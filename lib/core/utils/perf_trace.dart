/// Timing leggero per misurare i caricamenti dati.
///
/// Usa `print` (non `debugPrint`) così le righe `[PERF]` sono visibili anche
/// in `flutter run --release` via logcat. Strumentazione diagnostica nata per
/// l'analisi del gap di velocità Android vs iOS (2026-07-04, vedi memoria
/// progetto): attiva in debug; nelle build release è SILENZIOSA a meno di
/// compilare con `--dart-define=PERF_TRACE=true`.
library;

import 'package:flutter/foundation.dart';

class PerfTrace {
  /// Attivo in debug, oppure in release solo con
  /// `flutter run/build --dart-define=PERF_TRACE=true`.
  static const bool enabled =
      kDebugMode || bool.fromEnvironment('PERF_TRACE');

  /// Misura un'operazione async e stampa `[PERF] label: Xms (extra)`.
  static Future<T> track<T>(
    String label,
    Future<T> Function() op, {
    String Function(T result)? describe,
  }) async {
    if (!enabled) return op();
    final sw = Stopwatch()..start();
    try {
      final result = await op();
      sw.stop();
      final extra = describe != null ? ' (${describe(result)})' : '';
      // ignore: avoid_print
      print('[PERF] $label: ${sw.elapsedMilliseconds}ms$extra');
      return result;
    } catch (e) {
      sw.stop();
      // ignore: avoid_print
      print('[PERF] $label: ${sw.elapsedMilliseconds}ms (ERRORE: $e)');
      rethrow;
    }
  }

  /// Misura un'operazione sincrona (es. parse) e stampa `[PERF] label: Xms`.
  static T trackSync<T>(
    String label,
    T Function() op, {
    String Function(T result)? describe,
  }) {
    if (!enabled) return op();
    final sw = Stopwatch()..start();
    final result = op();
    sw.stop();
    final extra = describe != null ? ' (${describe(result)})' : '';
    // ignore: avoid_print
    print('[PERF] $label: ${sw.elapsedMilliseconds}ms$extra');
    return result;
  }

  /// Marca un istante (per correlare avvio/fine fasi).
  static void mark(String label) {
    if (!enabled) return;
    // ignore: avoid_print
    print('[PERF] mark: $label @${DateTime.now().toIso8601String()}');
  }
}
