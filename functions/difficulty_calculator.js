// Porting JavaScript di lib/core/utils/difficulty_calculator.dart.
//
// Serve al backfill di `computedDifficulty` sul catalogo public_trails, che
// gli script .cjs e le Cloud Function non possono fare chiamando il Dart.
//
// ATTENZIONE — QUESTO FILE E' UN GEMELLO, NON UN ORIGINALE.
// Ogni modifica ai pesi, alle curve o alle soglie va fatta su ENTRAMBI i
// file, altrimenti la stessa traccia riceve due difficolta' diverse a
// seconda di chi la calcola (app o backfill). La prova di fedelta' e' in
// scripts/difficulty_parity_check.cjs: rieseguirla dopo ogni modifica.
//
// Allineato al Dart al 2026-07-28, che include il tuning del 2026-05-27
// (absoluteGainScore + factor ebike/eMTB rialzati + soglie 40/80/140/200).

'use strict';

/// Livelli, con la chiave persistita su Firestore. NON cambiare le chiavi.
const LIVELLI = [
  { key: 't1', code: 'T1', label: 'Facile' },
  { key: 't2', code: 'T2', label: 'Moderato' },
  { key: 't3', code: 'T3', label: 'Impegnativo' },
  { key: 't4', code: 'T4', label: 'Difficile' },
  { key: 't5', code: 'T5', label: 'Estremo' },
];

/// I tre gruppi di fattori per tipo di attivita'. Le chiavi sono i nomi
/// dell'enum Dart ActivityType cosi' come finiscono su Firestore.
const FATTORI = {
  //                    gain   dist   absGain
  cycling:            [ 0.50,  0.30,  0.55 ],
  gravelBiking:       [ 0.55,  0.35,  0.60 ],
  eBike:              [ 0.55,  0.30,  0.60 ],
  eMountainBike:      [ 0.65,  0.35,  0.70 ],
  mountainBiking:     [ 0.65,  0.40,  0.75 ],
  running:            [ 1.15,  1.15,  1.10 ],
  trailRunning:       [ 1.20,  1.30,  1.15 ],
  snowshoeing:        [ 1.20,  1.20,  1.20 ],
  skiTouring:         [ 1.10,  1.10,  1.15 ],
  alpineSkiing:       [ 0.70,  0.60,  0.50 ],
  nordicSkiing:       [ 1.05,  1.00,  1.00 ],
  snowboarding:       [ 0.70,  0.60,  0.50 ],
  trekking:           [ 1.00,  1.00,  1.00 ],
  walking:            [ 0.85,  1.30,  0.95 ],
};

/// Attivita' sconosciuta → trekking. Non e' una scelta di comodo: replica
/// _parseActivity in tracks_repository.dart, che confronta il nome esatto
/// dell'enum e ripiega su trekking per tutto il resto.
///
/// NON aggiungere qui la normalizzazione degli alias presenti sui dati
/// ('escursionismo' 2606, 'ebike' 17, 'trail-running' 3, 'corsa' 2,
/// 'bike' 1). Il Dart non li riconosce: normalizzarli solo qui farebbe
/// dare due risposte diverse alla stessa traccia — t2 dall'app, t3 dal
/// backfill. Vanno sistemati alla fonte (ripulendo i valori salvati) o su
/// entrambi i gemelli insieme.
///
/// Conseguenza da conoscere: le 17 tracce 'ebike' sono gia' oggi valutate
/// come trekking dall'app stessa, quindi sovrastimate. E' un difetto
/// preesistente, non introdotto da questo modulo.
function fattoriDi(activityType) {
  return FATTORI[activityType] || FATTORI.trekking;
}

/// Score dal dislivello relativo (m/km). Curva a 4 segmenti.
function gainScore(gainPerKm, activityType) {
  let raw;
  if (gainPerKm <= 50) raw = gainPerKm * 0.5;
  else if (gainPerKm <= 150) raw = 25 + (gainPerKm - 50) * 0.55;
  else if (gainPerKm <= 300) raw = 80 + (gainPerKm - 150) * 0.53;
  else raw = 160 + (gainPerKm - 300) * 0.4;
  return raw * fattoriDi(activityType)[0];
}

/// Score dalla distanza assoluta. Sublineare, satura verso i 50 km.
function distanceScore(distanceKm, activityType) {
  let raw;
  if (distanceKm <= 10) raw = distanceKm * 2.0;
  else if (distanceKm <= 25) raw = 20 + (distanceKm - 10) * 2.0;
  else if (distanceKm <= 50) raw = 50 + (distanceKm - 25) * 1.2;
  else raw = 80 + (distanceKm - 50) * 0.5;
  return raw * fattoriDi(activityType)[1];
}

/// Score dal dislivello positivo assoluto. Curva a 5 segmenti.
function absoluteGainScore(totalGain, activityType) {
  if (totalGain <= 0) return 0;
  let raw;
  if (totalGain <= 500) raw = totalGain * 0.030;
  else if (totalGain <= 1000) raw = 15 + (totalGain - 500) * 0.040;
  else if (totalGain <= 1500) raw = 35 + (totalGain - 1000) * 0.050;
  else if (totalGain <= 2000) raw = 60 + (totalGain - 1500) * 0.060;
  else raw = 90 + (totalGain - 2000) * 0.040;
  return raw * fattoriDi(activityType)[2];
}

function scoreToLevel(score) {
  if (score < 40) return LIVELLI[0];
  if (score < 80) return LIVELLI[1];
  if (score < 140) return LIVELLI[2];
  if (score < 200) return LIVELLI[3];
  return LIVELLI[4];
}

/**
 * Calcola la difficolta' computata. Ritorna null se i dati non bastano,
 * esattamente come il Dart (distanza sotto i 100 m).
 *
 * @param {{distance:number, elevationGain:number, elevationLoss?:number}} stats
 *        distance in METRI, dislivelli in metri.
 * @param {string} activityType  nome enum Dart (es. 'trekking', 'eBike').
 * @returns {{key:string, code:string, label:string, score:number}|null}
 */
function compute(stats, activityType) {
  if (!stats) return null;
  const distanceKm = Number(stats.distance) / 1000;
  if (!Number.isFinite(distanceKm) || distanceKm < 0.1) return null;

  const gain = Number(stats.elevationGain);
  if (!Number.isFinite(gain)) return null;
  // Il Dart riceve sempre un loss valorizzato dalle TrackStats; qui puo'
  // mancare (i doc pubblicati non lo conservano). Assente = 0, che annulla
  // il bonus discesa invece di inventarlo.
  const loss = Number.isFinite(Number(stats.elevationLoss))
    ? Number(stats.elevationLoss) : 0;

  const gainPerKm = gain / distanceKm;

  // Bonus discesa "tecnica", con lo stesso tetto del Dart (clamp 0..30).
  let lossBonus = 0;
  if (loss > gain * 1.3) {
    lossBonus = Math.min(30, Math.max(0, (loss - gain) / distanceKm));
  }

  const score = gainScore(gainPerKm, activityType)
    + distanceScore(distanceKm, activityType)
    + absoluteGainScore(gain, activityType)
    + lossBonus;

  return { ...scoreToLevel(score), score };
}

module.exports = { compute, LIVELLI, FATTORI };
