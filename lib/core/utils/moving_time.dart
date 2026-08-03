import '../../data/models/track.dart';

/// Tempo effettivamente passato in movimento, distinto dal tempo totale.
///
/// Esisteva in tre copie identiche (gpx, tcx, fit) e in nessuna versione nel
/// percorso della registrazione, dove `movingTime` era assegnato uguale a
/// `duration` con un commento che prometteva di migliorarlo. Il risultato è
/// che per le tracce registrate la statistica più in vista dell'app —
/// "In movimento" — non misurava niente: su un giro reale di 6h15 dichiarava
/// 6h15, un secondo di differenza.
const double _minSpeedMs = 0.5; // ~1,8 km/h: sotto questa soglia si è fermi

/// Oltre questo intervallo fra due punti non c'è più una misura di movimento:
/// c'è un buco.
///
/// Con `distanceFilter` a 5 m e `intervalDuration` a 2 s, due punti
/// consecutivi distano secondi quando ci si muove. Se distano minuti, o si era
/// fermi — e allora la soglia di velocità li scarta già — oppure la
/// registrazione si era interrotta, e quel tempo non è stato misurato affatto.
///
/// Il caso che ha reso necessaria questa guardia: il 2026-08-03 il sistema ha
/// sospeso l'app per 37 minuti, durante i quali si sono percorsi 1231 m in
/// linea d'aria. Sono **0,553 m/s**, cioè *sopra* [_minSpeedMs]: con la sola
/// soglia di velocità l'intero blackout sarebbe finito nel tempo di movimento,
/// spacciando per camminata un tratto che nessuno ha misurato.
const Duration _maxSampleGap = Duration(seconds: 90);

/// Somma gli intervalli in cui ci si stava davvero muovendo.
///
/// Scarta, nell'ordine: i punti senza un timestamp credibile, gli intervalli
/// non positivi (orologi che tornano indietro), i buchi più lunghi di
/// [_maxSampleGap] e infine tutto ciò che è più lento di [_minSpeedMs].
Duration computeMovingTime(List<TrackPoint> points) {
  if (points.length < 2) return Duration.zero;

  var moving = Duration.zero;
  for (var i = 1; i < points.length; i++) {
    moving += movingDelta(points[i - 1], points[i]);
  }
  return moving;
}

/// Quanto vale, ai fini del tempo in movimento, il tratto fra due punti
/// consecutivi: la sua durata se ci si stava muovendo, zero altrimenti.
///
/// Esposta separatamente perché durante la registrazione i punti arrivano uno
/// alla volta: accumulare questo delta costa un confronto, mentre richiamare
/// [computeMovingTime] sull'intera lista a ogni punto costerebbe un giro
/// completo — su un'uscita di sei ore sono milioni di operazioni in più, su un
/// dispositivo che si sta già cercando di non far spegnere.
Duration movingDelta(TrackPoint prev, TrackPoint curr) {
  // Timestamp di default (epoch, o comunque assurdi) su tracce importate da
  // sorgenti che non li portano: non si può dedurne alcuna durata.
  if (prev.timestamp.year <= 2000 || curr.timestamp.year <= 2000) {
    return Duration.zero;
  }

  final dt = curr.timestamp.difference(prev.timestamp);
  if (dt <= Duration.zero) return Duration.zero;
  if (dt > _maxSampleGap) return Duration.zero;

  final metres = prev.distanceTo(curr);
  if (metres / dt.inMilliseconds * 1000 < _minSpeedMs) return Duration.zero;

  return dt;
}
