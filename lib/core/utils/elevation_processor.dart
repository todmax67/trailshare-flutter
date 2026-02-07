import 'dart:math';

/// Processore per i dati di elevazione GPS
///
/// Risolve i problemi di rumore GPS nell'altitudine tramite:
/// 1. Rimozione spike (outlier detection)
/// 2. Smoothing con media mobile ponderata
/// 3. Calcolo dislivello con isteresi (dead band) — stesso approccio di Garmin/Strava
///
/// Due modalità:
/// - [process()] — per elaborare una lista completa di punti (tracce salvate, import GPX)
/// - [createTracker()] — per tracking in tempo reale (punto per punto)
///
/// Usato da:
/// - tracking_bloc.dart (_calculateStats, _calculateStatsFromPoints)
/// - lap_splits_widget.dart (calcolo dislivello per km)
/// - gpx_service.dart (import GPX)
/// - track_charts_widget.dart (grafico elevazione smoothed)
class ElevationProcessor {
  /// Soglia di isteresi per il calcolo dislivello (metri)
  /// Garmin usa ~5m, Strava usa ~3-5m
  final double hysteresisThreshold;

  /// Finestra per la media mobile (numero di punti)
  final int smoothingWindow;

  /// Soglia massima di variazione tra punti consecutivi (metri)
  /// Punti che variano più di questo vengono considerati spike
  final double maxElevationChangePerPoint;

  /// Finestra per il filtro mediano (deve essere dispari)
  /// Elimina blocchi di punti GPS errati consecutivi.
  /// 0 = disabilitato (per tracking real-time dove non serve)
  final int medianWindow;

  const ElevationProcessor({
    this.hysteresisThreshold = 4.0,
    this.smoothingWindow = 5,
    this.maxElevationChangePerPoint = 50.0,
    this.medianWindow = 11,
  });

  /// Factory per diversi tipi di attività
  /// medianWindow: usato solo in batch processing (process()),
  /// ignorato nel tracking real-time (ElevationTracker)
  factory ElevationProcessor.forActivity(String activityType) {
    switch (activityType.toLowerCase()) {
      case 'cycling':
        return const ElevationProcessor(
          hysteresisThreshold: 3.0,
          smoothingWindow: 7,
          maxElevationChangePerPoint: 30.0,
          medianWindow: 11,
        );
      case 'trailrunning':
        return const ElevationProcessor(
          hysteresisThreshold: 3.0,
          smoothingWindow: 7,
          maxElevationChangePerPoint: 40.0,
          medianWindow: 11,
        );
      default: // trekking, walking
        return const ElevationProcessor(
          hysteresisThreshold: 4.0,
          smoothingWindow: 7,
          maxElevationChangePerPoint: 50.0,
          medianWindow: 11,
        );
    }
  }

  // ============================================================
  // MODALITÀ 1: Elaborazione lista completa (tracce salvate/GPX)
  // ============================================================

  /// Processa una lista di elevazioni grezze e restituisce i risultati completi.
  ///
  /// [rawElevations] - lista di elevazioni nullable dal GPS
  /// Ritorna [ElevationResult] con dati smoothed e statistiche accurate
  ElevationResult process(List<double?> rawElevations) {
    if (rawElevations.isEmpty) {
      return ElevationResult.empty();
    }

    // Step 1: Estrai solo elevazioni valide (non null)
    final validElevations = <double>[];
    final validIndices = <int>[];
    for (int i = 0; i < rawElevations.length; i++) {
      if (rawElevations[i] != null) {
        validElevations.add(rawElevations[i]!);
        validIndices.add(i);
      }
    }

    if (validElevations.isEmpty) {
      return ElevationResult.empty();
    }

    if (validElevations.length == 1) {
      return ElevationResult(
        smoothedElevations: List.filled(rawElevations.length, validElevations.first),
        elevationGain: 0,
        elevationLoss: 0,
        maxElevation: validElevations.first,
        minElevation: validElevations.first,
      );
    }

    // Step 1b: Filtro mediano per eliminare blocchi di punti GPS errati
    // (es. 5-10 punti consecutivi che scendono da 1650 a 1200 e risalgono)
    final medianFiltered = medianWindow > 0
        ? _applyMedianFilter(validElevations, medianWindow)
        : validElevations;

    // Step 2: Rimuovi spike residui (singoli punti anomali)
    final despiked = _removeSpikes(medianFiltered);

    // Step 3: Applica smoothing
    final smoothed = _applySmoothing(despiked);

    // Step 4: Calcola dislivello con isteresi
    final stats = _calculateWithHysteresis(smoothed);

    // Step 5: Ricostruisci la lista completa (interpolazione per punti null)
    final fullSmoothed = _reconstructFullList(
      rawElevations.length,
      smoothed,
      validIndices,
    );

    return ElevationResult(
      smoothedElevations: fullSmoothed,
      elevationGain: stats.gain,
      elevationLoss: stats.loss,
      maxElevation: smoothed.reduce(max),
      minElevation: smoothed.reduce(min),
    );
  }

  /// Calcola SOLO gain/loss da una lista di elevazioni (senza smoothing).
  /// Utile per ricalcoli veloci dove si hanno già dati buoni.
  ElevationGainLoss calculateGainLoss(List<double> elevations) {
    if (elevations.length < 2) {
      return const ElevationGainLoss(gain: 0, loss: 0);
    }
    final result = _calculateWithHysteresis(elevations);
    return ElevationGainLoss(gain: result.gain, loss: result.loss);
  }

  // ============================================================
  // MODALITÀ 2: Tracking in tempo reale (punto per punto)
  // ============================================================

  /// Crea un tracker incrementale per uso durante la registrazione.
  ///
  /// Uso:
  /// ```dart
  /// final tracker = ElevationProcessor.forActivity('trekking').createTracker();
  /// tracker.addPoint(altitude); // ad ogni punto GPS
  /// print('Gain: ${tracker.elevationGain}');
  /// ```
  ElevationTracker createTracker() {
    return ElevationTracker(
      hysteresisThreshold: hysteresisThreshold,
      smoothingWindow: smoothingWindow,
      maxElevationChangePerPoint: maxElevationChangePerPoint,
    );
  }

  // ============================================================
  // STEP 1b: Filtro mediano
  // ============================================================
  //
  // Il filtro mediano è il modo più robusto per rimuovere outlier
  // anche quando sono in blocchi consecutivi (5-10 punti errati).
  // Per ogni punto, prende la mediana dei punti nella finestra.
  // La mediana è immune a valori estremi: anche se 4 punti su 11
  // sono errati, la mediana seleziona comunque un valore buono.

  List<double> _applyMedianFilter(List<double> elevations, int windowSize) {
    if (elevations.length <= windowSize) return List.from(elevations);

    // Assicura finestra dispari
    final w = windowSize.isOdd ? windowSize : windowSize + 1;
    final halfW = w ~/ 2;
    final result = List<double>.from(elevations);

    for (int i = halfW; i < elevations.length - halfW; i++) {
      final window = List<double>.from(
        elevations.sublist(i - halfW, i + halfW + 1),
      );
      window.sort();
      result[i] = window[window.length ~/ 2];
    }

    return result;
  }

  // ============================================================
  // STEP 2: Rimozione spike
  // ============================================================

  List<double> _removeSpikes(List<double> elevations) {
    if (elevations.length < 3) return List.from(elevations);

    final result = List<double>.from(elevations);

    for (int i = 1; i < elevations.length - 1; i++) {
      final prev = result[i - 1]; // usa result per cascata
      final curr = elevations[i];
      final next = elevations[i + 1];

      final diffPrev = (curr - prev).abs();
      final diffNext = (curr - next).abs();
      final diffPrevNext = (next - prev).abs();

      // Spike chiaro: salta molto rispetto a entrambi i vicini,
      // ma i vicini sono simili tra loro
      if (diffPrev > maxElevationChangePerPoint &&
          diffNext > maxElevationChangePerPoint &&
          diffPrevNext < maxElevationChangePerPoint) {
        result[i] = (prev + next) / 2;
        continue;
      }

      // Spike meno evidente: check con mediana locale
      if (diffPrev > maxElevationChangePerPoint * 0.7) {
        final windowSize = min(smoothingWindow, elevations.length);
        final start = max(0, i - windowSize ~/ 2);
        final end = min(elevations.length, i + windowSize ~/ 2 + 1);
        final window = List<double>.from(elevations.sublist(start, end));
        window.sort();
        final median = window[window.length ~/ 2];

        if ((curr - median).abs() > maxElevationChangePerPoint * 0.5) {
          result[i] = median;
        }
      }
    }

    return result;
  }

  // ============================================================
  // STEP 3: Smoothing (media mobile ponderata)
  // ============================================================

  List<double> _applySmoothing(List<double> elevations) {
    if (elevations.length <= smoothingWindow) return List.from(elevations);

    final result = List<double>.filled(elevations.length, 0);
    final halfWindow = smoothingWindow ~/ 2;

    for (int i = 0; i < elevations.length; i++) {
      double weightedSum = 0;
      double weightTotal = 0;

      for (int j = -halfWindow; j <= halfWindow; j++) {
        final idx = i + j;
        if (idx >= 0 && idx < elevations.length) {
          // Peso triangolare: più peso al centro
          final weight = (halfWindow + 1 - j.abs()).toDouble();
          weightedSum += elevations[idx] * weight;
          weightTotal += weight;
        }
      }

      result[i] = weightedSum / weightTotal;
    }

    return result;
  }

  // ============================================================
  // STEP 4: Calcolo dislivello con isteresi (dead band)
  // ============================================================
  //
  // Come funziona:
  // - Segue la direzione corrente (salita/discesa)
  // - Registra gain/loss SOLO quando c'è un'inversione che supera la soglia
  // - Le micro-oscillazioni sotto soglia vengono ignorate
  // - Stesso principio usato da Garmin e Strava

  _GainLoss _calculateWithHysteresis(List<double> elevations) {
    if (elevations.length < 2) return const _GainLoss(0, 0);

    double totalGain = 0;
    double totalLoss = 0;

    double referenceElevation = elevations.first;
    int direction = 0; // 0=indeterminato, 1=salita, -1=discesa
    double extremeElevation = elevations.first;

    for (int i = 1; i < elevations.length; i++) {
      final current = elevations[i];

      if (direction == 0) {
        // Stato iniziale: determina la direzione
        final diff = current - referenceElevation;
        if (diff > hysteresisThreshold) {
          direction = 1;
          extremeElevation = current;
        } else if (diff < -hysteresisThreshold) {
          direction = -1;
          extremeElevation = current;
        }
      } else if (direction == 1) {
        // In salita
        if (current > extremeElevation) {
          extremeElevation = current;
        } else if (extremeElevation - current > hysteresisThreshold) {
          // Inversione → registra il gain
          totalGain += extremeElevation - referenceElevation;
          referenceElevation = extremeElevation;
          direction = -1;
          extremeElevation = current;
        }
      } else {
        // In discesa
        if (current < extremeElevation) {
          extremeElevation = current;
        } else if (current - extremeElevation > hysteresisThreshold) {
          // Inversione → registra la loss
          totalLoss += referenceElevation - extremeElevation;
          referenceElevation = extremeElevation;
          direction = 1;
          extremeElevation = current;
        }
      }
    }

    // Registra l'ultimo segmento
    if (direction == 1) {
      final lastGain = extremeElevation - referenceElevation;
      if (lastGain > hysteresisThreshold) {
        totalGain += lastGain;
      }
    } else if (direction == -1) {
      final lastLoss = referenceElevation - extremeElevation;
      if (lastLoss > hysteresisThreshold) {
        totalLoss += lastLoss;
      }
    }

    return _GainLoss(totalGain, totalLoss);
  }

  // ============================================================
  // Ricostruzione lista completa
  // ============================================================

  List<double> _reconstructFullList(
    int totalLength,
    List<double> smoothedValid,
    List<int> validIndices,
  ) {
    if (validIndices.length == totalLength) {
      return smoothedValid;
    }

    final result = List<double>.filled(totalLength, 0);

    // Riempi i punti validi
    for (int i = 0; i < validIndices.length; i++) {
      result[validIndices[i]] = smoothedValid[i];
    }

    // Interpola i punti mancanti tra due validi
    int lastValidIdx = -1;
    for (int i = 0; i < validIndices.length; i++) {
      final currentValidIdx = validIndices[i];
      if (lastValidIdx >= 0 && currentValidIdx - lastValidIdx > 1) {
        final startEle = result[lastValidIdx];
        final endEle = result[currentValidIdx];
        final gap = currentValidIdx - lastValidIdx;
        for (int j = lastValidIdx + 1; j < currentValidIdx; j++) {
          final t = (j - lastValidIdx) / gap;
          result[j] = startEle + (endEle - startEle) * t;
        }
      }
      lastValidIdx = currentValidIdx;
    }

    // Riempi punti iniziali/finali senza valore
    if (validIndices.isNotEmpty) {
      final firstValid = validIndices.first;
      final lastValid = validIndices.last;
      for (int i = 0; i < firstValid; i++) {
        result[i] = result[firstValid];
      }
      for (int i = lastValid + 1; i < totalLength; i++) {
        result[i] = result[lastValid];
      }
    }

    return result;
  }
}

// ================================================================
// ElevationTracker — per tracking in tempo reale
// ================================================================

/// Tracker incrementale per calcolo dislivello durante la registrazione.
///
/// Mantiene un buffer interno per smoothing e applica isteresi punto per punto.
class ElevationTracker {
  final double hysteresisThreshold;
  final int smoothingWindow;
  final double maxElevationChangePerPoint;

  /// Buffer ultimi punti per smoothing
  final List<double> _buffer = [];

  double _elevationGain = 0;
  double _elevationLoss = 0;
  double _maxElevation = double.negativeInfinity;
  double _minElevation = double.infinity;

  // Stato isteresi
  double? _referenceElevation;
  int _direction = 0; // 0=indeterminato, 1=salita, -1=discesa
  double? _extremeElevation;

  // Ultima elevazione smoothed
  double? _lastSmoothedElevation;

  ElevationTracker({
    required this.hysteresisThreshold,
    required this.smoothingWindow,
    required this.maxElevationChangePerPoint,
  });

  // --- Getters ---
  double get elevationGain => _elevationGain;
  double get elevationLoss => _elevationLoss;
  double get maxElevation => _maxElevation.isFinite ? _maxElevation : 0;
  double get minElevation => _minElevation.isFinite ? _minElevation : 0;
  double? get lastSmoothedElevation => _lastSmoothedElevation;
  int get pointCount => _buffer.length;

  /// Aggiunge un nuovo punto di elevazione.
  ///
  /// Ritorna l'elevazione smoothed (utile per grafico in tempo reale).
  /// Ritorna null se il punto è stato scartato (spike) o null in input.
  double? addPoint(double? rawElevation) {
    if (rawElevation == null) return _lastSmoothedElevation;

    // Spike detection: se il buffer ha dati, controlla la variazione
    if (_buffer.isNotEmpty) {
      final diff = (rawElevation - _buffer.last).abs();
      if (diff > maxElevationChangePerPoint) {
        // Spike! Ignora questo punto
        return _lastSmoothedElevation;
      }
    }

    // Aggiungi al buffer
    _buffer.add(rawElevation);

    // Calcola elevazione smoothed (media mobile sugli ultimi N punti)
    final windowStart = max(0, _buffer.length - smoothingWindow);
    final window = _buffer.sublist(windowStart);
    double sum = 0;
    for (final v in window) {
      sum += v;
    }
    final smoothed = sum / window.length;

    _lastSmoothedElevation = smoothed;

    // Aggiorna min/max
    if (smoothed > _maxElevation) _maxElevation = smoothed;
    if (smoothed < _minElevation) _minElevation = smoothed;

    // Aggiorna isteresi
    _updateHysteresis(smoothed);

    return smoothed;
  }

  void _updateHysteresis(double current) {
    if (_referenceElevation == null) {
      _referenceElevation = current;
      _extremeElevation = current;
      return;
    }

    if (_direction == 0) {
      final diff = current - _referenceElevation!;
      if (diff > hysteresisThreshold) {
        _direction = 1;
        _extremeElevation = current;
      } else if (diff < -hysteresisThreshold) {
        _direction = -1;
        _extremeElevation = current;
      }
    } else if (_direction == 1) {
      if (current > _extremeElevation!) {
        _extremeElevation = current;
      } else if (_extremeElevation! - current > hysteresisThreshold) {
        _elevationGain += _extremeElevation! - _referenceElevation!;
        _referenceElevation = _extremeElevation;
        _direction = -1;
        _extremeElevation = current;
      }
    } else {
      if (current < _extremeElevation!) {
        _extremeElevation = current;
      } else if (current - _extremeElevation! > hysteresisThreshold) {
        _elevationLoss += _referenceElevation! - _extremeElevation!;
        _referenceElevation = _extremeElevation;
        _direction = 1;
        _extremeElevation = current;
      }
    }
  }

  /// Finalizza: registra l'ultimo segmento pendente.
  /// Chiamare quando si ferma la registrazione.
  void finalize() {
    if (_referenceElevation == null || _extremeElevation == null) return;

    if (_direction == 1) {
      final lastGain = _extremeElevation! - _referenceElevation!;
      if (lastGain > hysteresisThreshold) {
        _elevationGain += lastGain;
      }
    } else if (_direction == -1) {
      final lastLoss = _referenceElevation! - _extremeElevation!;
      if (lastLoss > hysteresisThreshold) {
        _elevationLoss += lastLoss;
      }
    }
  }

  /// Reset completo del tracker
  void reset() {
    _buffer.clear();
    _elevationGain = 0;
    _elevationLoss = 0;
    _maxElevation = double.negativeInfinity;
    _minElevation = double.infinity;
    _referenceElevation = null;
    _direction = 0;
    _extremeElevation = null;
    _lastSmoothedElevation = null;
  }
}

// ================================================================
// Modelli risultato
// ================================================================

/// Risultato completo del processing elevazioni
class ElevationResult {
  /// Elevazioni dopo smoothing e rimozione spike
  final List<double> smoothedElevations;

  /// Dislivello positivo calcolato con isteresi
  final double elevationGain;

  /// Dislivello negativo calcolato con isteresi
  final double elevationLoss;

  /// Quota massima (dopo smoothing)
  final double maxElevation;

  /// Quota minima (dopo smoothing)
  final double minElevation;

  const ElevationResult({
    required this.smoothedElevations,
    required this.elevationGain,
    required this.elevationLoss,
    required this.maxElevation,
    required this.minElevation,
  });

  factory ElevationResult.empty() => const ElevationResult(
        smoothedElevations: [],
        elevationGain: 0,
        elevationLoss: 0,
        maxElevation: 0,
        minElevation: 0,
      );
}

/// Coppia gain/loss per uso pubblico
class ElevationGainLoss {
  final double gain;
  final double loss;
  const ElevationGainLoss({required this.gain, required this.loss});
}

/// Coppia gain/loss interna
class _GainLoss {
  final double gain;
  final double loss;
  const _GainLoss(this.gain, this.loss);
}
