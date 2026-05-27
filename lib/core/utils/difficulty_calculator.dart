import 'package:flutter/material.dart';

import '../../data/models/track.dart';

/// Komoot K1a Step 2 — scala di difficoltà calcolata.
///
/// Cinque livelli ispirati alla scala SAC/CAI ma generalizzati per
/// funzionare anche con attività ciclabili. Le label sono brevi per
/// stare in un chip nelle list view.
///
/// Mapping orientativo:
/// - T1 Facile      → famiglie/principianti, sentieri ben tracciati
/// - T2 Moderato    → camminatori abitudinari, mezza giornata
/// - T3 Impegnativo → escursionisti allenati
/// - T4 Difficile   → esperti, fondo o pendenze importanti
/// - T5 Estremo     → alpinismo facile / tour molto lunghi
enum ComputedDifficulty {
  t1('t1', 'T1', 'Facile', Color(0xFF388E3C)),
  t2('t2', 'T2', 'Moderato', Color(0xFF689F38)),
  t3('t3', 'T3', 'Impegnativo', Color(0xFFFBC02D)),
  t4('t4', 'T4', 'Difficile', Color(0xFFE65100)),
  t5('t5', 'T5', 'Estremo', Color(0xFFD32F2F));

  /// Chiave persistita su Firestore. NON cambiare.
  final String firestoreKey;

  /// Codice corto da chip (es. "T3").
  final String code;

  /// Nome leggibile italiano.
  final String label;

  /// Colore associato al livello (verde → rosso).
  final Color color;

  const ComputedDifficulty(this.firestoreKey, this.code, this.label, this.color);

  static ComputedDifficulty? fromKey(String? key) {
    if (key == null) return null;
    for (final d in values) {
      if (d.firestoreKey == key) return d;
    }
    return null;
  }
}

/// Calcolatore di difficoltà computata per una traccia.
///
/// Formula score-based che combina **tre segnali principali**:
/// 1. **Dislivello relativo** (m / km) — pendenza media percepita
/// 2. **Dislivello assoluto** (m totali in salita) — fatica oggettiva
///    indipendente da come si distribuisce sul percorso
/// 3. **Distanza assoluta** (km) — fatica accumulata
///
/// I pesi e le soglie variano per [ActivityType]: una ferrata di 200m
/// di dislivello su 1km è T4-T5, lo stesso m/km in mtb è normale.
///
/// Storia tuning (2026-05-27): aggiunto absoluteGainScore dopo
/// feedback utente. Precedentemente, 1266m di dislivello su 26km in
/// ebike risultava T1 perché il rapporto m/km (48) cadeva nella zona
/// "facile" e il totale assoluto non veniva considerato. Ora 1000m+
/// gain pesano oggettivamente anche con rapporto basso. Inoltre i
/// factor ebike/eMTB sono stati rivisti al rialzo: l'assistenza riduce
/// lo sforzo ma non lo azzera.
///
/// Implementato come funzione pura per essere testabile e riusabile
/// sia client-side post-recording sia su Cloud Function batch.
class DifficultyCalculator {
  DifficultyCalculator._();

  /// Calcola la difficoltà per le statistiche fornite. Ritorna `null`
  /// se i dati sono insufficienti (distanza < 100m o dislivello/distanza
  /// mancanti).
  static ComputedDifficulty? compute({
    required TrackStats stats,
    required ActivityType activityType,
  }) {
    final distanceKm = stats.distance / 1000;
    if (distanceKm < 0.1) return null;

    final gain = stats.elevationGain;
    final loss = stats.elevationLoss;
    // m/km — segnale principale. Usiamo gain perché chi sale poi scende
    // (su anello/A-B simmetrico): la fatica è dominata dalla salita.
    final gainPerKm = gain / distanceKm;

    // Distanza totale come fattore secondario: 30km piatto può essere
    // più impegnativo di 5km con 500m gain.
    final distScore = _distanceScore(distanceKm, activityType);

    // Gain score lineare con bonus quando supera soglie OEM-style.
    final gainScore = _gainScore(gainPerKm, activityType);

    // Dislivello assoluto: 1500m di salita restano impegnativi
    // anche se diluiti su 40km. Componente fondamentale per
    // escursioni lunghe ad approccio dolce.
    final absoluteGainScore = _absoluteGainScore(gain, activityType);

    // Bonus discesa "tecnica": una traccia con loss >> gain (es. via di
    // discesa MTB di 1500m in 8km) è più impegnativa di una piana.
    // Capped per non triplare il punteggio.
    final lossBonus = loss > gain * 1.3
        ? ((loss - gain) / distanceKm).clamp(0.0, 30.0)
        : 0.0;

    final totalScore =
        gainScore + distScore + absoluteGainScore + lossBonus;

    return _scoreToLevel(totalScore);
  }

  /// Lookup tabella score → livello T1..T5. Soglie tarate empiricamente
  /// per generare ~30% T1-T2 / ~40% T3 / ~25% T4 / ~5% T5 sul dataset
  /// outdoor tipico italiano (Alpi + Appennini).
  ///
  /// Soglie ricalibrate 2026-05-27 dopo aggiunta di
  /// [_absoluteGainScore] (componente extra che alza
  /// strutturalmente il totale): da 35/70/120/180 a 40/80/140/200.
  static ComputedDifficulty _scoreToLevel(double score) {
    if (score < 40) return ComputedDifficulty.t1;
    if (score < 80) return ComputedDifficulty.t2;
    if (score < 140) return ComputedDifficulty.t3;
    if (score < 200) return ComputedDifficulty.t4;
    return ComputedDifficulty.t5;
  }

  /// Score dal dislivello relativo. La curva è non lineare: piccoli
  /// aumenti di m/km tra 0-50 contano poco, tra 100-200 diventano
  /// significativi (siamo già in zona "salita seria").
  static double _gainScore(double gainPerKm, ActivityType type) {
    // Fattore per attività: in mtb e bici un m/km equivale a meno
    // fatica relativa (la bici aiuta), quindi peso minore. Per trail
    // running e trekking pesa di più. Sci alpinismo + racchette su
    // neve aggiungono fatica.
    //
    // Tuning 2026-05-27: alzati factor ebike e eMTB. L'assistenza
    // riduce lo sforzo ma non lo azzera: 1200m di dislivello
    // restano impegnativi anche in ebike (batteria + ore in sella).
    final factor = switch (type) {
      ActivityType.cycling => 0.50,
      ActivityType.gravelBiking => 0.55,
      ActivityType.eBike => 0.55,
      ActivityType.eMountainBike => 0.65,
      ActivityType.mountainBiking => 0.65,
      ActivityType.running => 1.15,
      ActivityType.trailRunning => 1.20,
      ActivityType.snowshoeing => 1.20,
      ActivityType.skiTouring => 1.10,
      ActivityType.alpineSkiing => 0.70, // discesa con risalite con impianti
      ActivityType.nordicSkiing => 1.05,
      ActivityType.snowboarding => 0.70,
      ActivityType.trekking => 1.0,
      ActivityType.walking => 0.85,
    };

    // Curva: 0..50 m/km → score 0..25 (lineare)
    //        50..150 m/km → score 25..80 (più ripida)
    //        150..300 m/km → score 80..160 (zona alpinistica)
    //        300+ → +0.5 per ogni metro extra
    double raw;
    if (gainPerKm <= 50) {
      raw = gainPerKm * 0.5;
    } else if (gainPerKm <= 150) {
      raw = 25 + (gainPerKm - 50) * 0.55;
    } else if (gainPerKm <= 300) {
      raw = 80 + (gainPerKm - 150) * 0.53;
    } else {
      raw = 160 + (gainPerKm - 300) * 0.4;
    }
    return raw * factor;
  }

  /// Score dalla distanza assoluta. Sublineare: i primi km contano,
  /// dopo 30km la fatica accumulata aumenta meno per ogni km extra
  /// (siamo già stanchi).
  static double _distanceScore(double distanceKm, ActivityType type) {
    // Fattore: bici copre distanza facilmente, walking si stanca prima.
    // Tuning 2026-05-27: alzati ebike e eMTB di 0.05 ciascuno.
    final factor = switch (type) {
      ActivityType.cycling => 0.30,
      ActivityType.gravelBiking => 0.35,
      ActivityType.eBike => 0.30,
      ActivityType.eMountainBike => 0.35,
      ActivityType.mountainBiking => 0.40,
      ActivityType.running => 1.15,
      ActivityType.trailRunning => 1.30,
      ActivityType.snowshoeing => 1.20,
      ActivityType.skiTouring => 1.10,
      ActivityType.alpineSkiing => 0.60,
      ActivityType.nordicSkiing => 1.0,
      ActivityType.snowboarding => 0.60,
      ActivityType.trekking => 1.0,
      ActivityType.walking => 1.30,
    };

    // Curva sublineare con saturazione attorno a 50km.
    // 0-10km → 0..20  (2 punti/km)
    // 10-25km → 20..50 (2 punti/km)
    // 25-50km → 50..80 (1.2 punti/km)
    // 50+km → 80 + 0.5 per km extra
    double raw;
    if (distanceKm <= 10) {
      raw = distanceKm * 2.0;
    } else if (distanceKm <= 25) {
      raw = 20 + (distanceKm - 10) * 2.0;
    } else if (distanceKm <= 50) {
      raw = 50 + (distanceKm - 25) * 1.2;
    } else {
      raw = 80 + (distanceKm - 50) * 0.5;
    }
    return raw * factor;
  }

  /// Score dal dislivello positivo assoluto (totale m saliti).
  ///
  /// Aggiunto 2026-05-27: gestisce il caso di escursioni con
  /// dislivello importante distribuito su molti km (es. Ardesio →
  /// Passo Branchino, 1266m in 26km ebike). Il rapporto m/km
  /// (48 in quell'esempio) sottostimava la fatica, mentre il totale
  /// assoluto la cattura correttamente.
  ///
  /// Curva non lineare a 5 segmenti pensata per discriminare:
  /// - 0-500m: T1-T2 territory (gite brevi)
  /// - 500-1000m: T2-T3 (mezza giornata)
  /// - 1000-1500m: T3-T4 (giornata piena)
  /// - 1500-2000m: T4 (lunga giornata o tappa hut-to-hut)
  /// - 2000+m: T4-T5 (impresa)
  static double _absoluteGainScore(double totalGain, ActivityType type) {
    if (totalGain <= 0) return 0;

    // Factor: bici/ebike riducono lo sforzo della salita ma non lo
    // azzerano. Alpinismo/sci touring lo amplificano. La proporzione
    // è simile (ma non identica) ai factor di _gainScore — il
    // dislivello assoluto pesa relativamente meno per le bici
    // rispetto al rapporto m/km.
    final factor = switch (type) {
      ActivityType.cycling => 0.55,
      ActivityType.gravelBiking => 0.60,
      ActivityType.eBike => 0.60,
      ActivityType.eMountainBike => 0.70,
      ActivityType.mountainBiking => 0.75,
      ActivityType.running => 1.10,
      ActivityType.trailRunning => 1.15,
      ActivityType.snowshoeing => 1.20,
      ActivityType.skiTouring => 1.15,
      ActivityType.alpineSkiing => 0.50,
      ActivityType.nordicSkiing => 1.0,
      ActivityType.snowboarding => 0.50,
      ActivityType.trekking => 1.0,
      ActivityType.walking => 0.95,
    };

    // Curva: 5 segmenti che accelerano fino a 1500m, poi rallentano.
    // 0-500m     → 0..15   (0.030/m)
    // 500-1000m  → 15..35  (0.040/m)
    // 1000-1500m → 35..60  (0.050/m)
    // 1500-2000m → 60..90  (0.060/m)
    // 2000+m     → 90 + 0.040/m
    double raw;
    if (totalGain <= 500) {
      raw = totalGain * 0.030;
    } else if (totalGain <= 1000) {
      raw = 15 + (totalGain - 500) * 0.040;
    } else if (totalGain <= 1500) {
      raw = 35 + (totalGain - 1000) * 0.050;
    } else if (totalGain <= 2000) {
      raw = 60 + (totalGain - 1500) * 0.060;
    } else {
      raw = 90 + (totalGain - 2000) * 0.040;
    }
    return raw * factor;
  }
}
