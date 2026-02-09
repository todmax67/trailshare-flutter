/// Utility condivisa per il calcolo dell'elevazione con filtro anti-rumore GPS.
///
/// Usa filtro mediano (window 5) + soglia dead-band (5m) per eliminare
/// le micro-oscillazioni dell'altimetro GPS (tipicamente ±3m).
///
/// USATO IN:
/// - RecalculateStatsPage (ricalcolo retroattivo)
/// - TracksRepository._recalculateStats (salvataggio nuove tracce)
/// - LapSplitsWidget (stats per km)
///
/// Posizione file: lib/core/utils/elevation_utils.dart
class ElevationUtils {
  /// Soglia dead-band: variazioni sotto questa soglia sono considerate rumore.
  /// Il GPS oscilla tipicamente di ±3m, quindi 5m filtra il rumore
  /// senza perdere variazioni reali del terreno.
  static const double deadBandThreshold = 5.0; // metri

  /// Dimensione finestra per filtro mediano
  static const int medianWindowSize = 5;

  /// Applica filtro mediano alle elevazioni raw.
  /// Il filtro mediano è più robusto della media mobile contro outlier/spike.
  ///
  /// Punti con elevation null o ≤0 vengono interpolati con l'ultimo valore valido.
  static List<double> smoothElevations(List<double?> rawElevations) {
    if (rawElevations.isEmpty) return [];

    // Estrai elevazioni valide (sostituisci null/≤0 con interpolazione)
    final raw = <double>[];
    double lastValid = 0;
    for (final ele in rawElevations) {
      if (ele != null && ele > 0) {
        raw.add(ele);
        lastValid = ele;
      } else {
        raw.add(lastValid); // Interpola con ultimo valore valido
      }
    }

    if (raw.length < medianWindowSize) return raw;

    final halfWindow = medianWindowSize ~/ 2;
    final smoothed = List<double>.filled(raw.length, 0);

    for (int i = 0; i < raw.length; i++) {
      final start = (i - halfWindow).clamp(0, raw.length - 1);
      final end = (i + halfWindow).clamp(0, raw.length - 1);

      // Raccogli valori nella finestra
      final window = <double>[];
      for (int j = start; j <= end; j++) {
        window.add(raw[j]);
      }

      // Ordina e prendi la mediana
      window.sort();
      smoothed[i] = window[window.length ~/ 2];
    }

    return smoothed;
  }

  /// Calcola dislivello positivo, negativo, min e max dalle elevazioni smoothed,
  /// usando soglia dead-band per filtrare rumore residuo.
  ///
  /// La dead-band funziona così: l'elevazione "confermata" si aggiorna solo
  /// quando la variazione supera la soglia. Oscillazioni sotto-soglia
  /// vengono ignorate completamente.
  static ElevationResult calculateGainLoss(List<double> smoothedElevations) {
    if (smoothedElevations.isEmpty) {
      return const ElevationResult(
        gain: 0,
        loss: 0,
        maxElevation: 0,
        minElevation: 0,
      );
    }

    double gain = 0;
    double loss = 0;
    double maxEle = double.negativeInfinity;
    double minEle = double.infinity;

    // Ultima elevazione "confermata" (ha superato la soglia)
    double? lastConfirmedElevation;

    for (final ele in smoothedElevations) {
      if (ele <= 0) continue;

      // Min/Max assoluti (dai valori smoothed)
      if (ele > maxEle) maxEle = ele;
      if (ele < minEle) minEle = ele;

      // Dislivello con soglia dead-band
      if (lastConfirmedElevation == null) {
        lastConfirmedElevation = ele;
      } else {
        final diff = ele - lastConfirmedElevation;
        if (diff >= deadBandThreshold) {
          gain += diff;
          lastConfirmedElevation = ele;
        } else if (diff <= -deadBandThreshold) {
          loss += diff.abs();
          lastConfirmedElevation = ele;
        }
        // Se non supera la soglia → NON aggiornare lastConfirmedElevation
        // Questo è essenziale: le oscillazioni restano "bloccate" al valore confermato
      }
    }

    return ElevationResult(
      gain: gain,
      loss: loss,
      maxElevation: maxEle.isFinite ? maxEle : 0,
      minElevation: minEle.isFinite ? minEle : 0,
    );
  }

  /// Calcolo completo: smooth + gain/loss.
  /// Metodo di convenienza che combina smoothElevations + calculateGainLoss.
  static ElevationResult process(List<double?> rawElevations) {
    final smoothed = smoothElevations(rawElevations);
    return calculateGainLoss(smoothed);
  }
}

/// Risultato del calcolo elevazione
class ElevationResult {
  final double gain;
  final double loss;
  final double maxElevation;
  final double minElevation;

  const ElevationResult({
    required this.gain,
    required this.loss,
    required this.maxElevation,
    required this.minElevation,
  });
}
