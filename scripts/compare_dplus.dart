// Confronta la formula del D+ dell'importer del catalogo con quella che l'app
// usa per tutto il resto (ElevationProcessor), sugli stessi dati reali.
//
// Usa la classe VERA, non una riscrittura: cosi' il confronto non dipende da un
// porting fedele. ElevationProcessor e' Dart puro (solo dart:math), quindi
// gira fuori da Flutter.
//
// Input: JSON {"<trailId>": {"eles": [...], "activity": "trekking"}, ...}
// Output: JSON {"<trailId>": {"attuale": n, "processor": n, "min": n, "max": n}}
//
// Uso: dart run scripts/compare_dplus.dart in.json out.json
import 'dart:convert';
import 'dart:io';

import '../lib/core/utils/elevation_processor.dart';

/// La formula attuale di trail_import_service.calculateElevationStats:
/// confronta solo punti ADIACENTI e scarta i passi sotto i 3 m invece di
/// accumularli. Riprodotta qui per il confronto.
double gainAttuale(List<double> e) {
  double gain = 0;
  for (int i = 1; i < e.length; i++) {
    final diff = e[i] - e[i - 1];
    if (diff > 3) gain += diff;
  }
  return gain;
}

void main(List<String> args) {
  final input = jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>;
  final out = <String, dynamic>{};

  for (final entry in input.entries) {
    final m = entry.value as Map<String, dynamic>;
    final raw = (m['eles'] as List)
        .map((v) => v == null ? null : (v as num).toDouble())
        .toList();
    final activity = (m['activity'] as String?) ?? 'trekking';

    final valide = raw.whereType<double>().toList();
    if (valide.length < 2) continue;

    final res = ElevationProcessor.forActivity(activity).process(raw);
    out[entry.key] = {
      'attuale': gainAttuale(valide).round(),
      'processor': res.elevationGain.round(),
      'processorLoss': res.elevationLoss.round(),
      'min': res.minElevation.round(),
      'max': res.maxElevation.round(),
      'punti': raw.length,
    };
  }

  File(args[1]).writeAsStringSync(jsonEncode(out));
  stdout.writeln('confrontati ${out.length} sentieri -> ${args[1]}');
}
