/// Divide una traccia nei tratti realmente percorsi e nei ponti sopra i buchi
/// di registrazione.
///
/// Serve a smettere di disegnare una cosa sola: oggi la mappa collega tutti i
/// punti con la stessa linea, quindi il salto sopra un buco esce identico al
/// sentiero percorso. Chi guarda non ha modo di distinguerli — ed e' il motivo
/// per cui un utente ha segnalato "la traccia ha una retta" invece di "qui la
/// registrazione si e' fermata".
///
/// Un tratto di tipo [TrackSegmentKind.gap] contiene **due soli punti**:
/// l'ultimo prima dell'interruzione e il primo dopo. Non e' un percorso, e' la
/// dichiarazione che fra quei due punti non sappiamo cosa sia successo.
library;

import '../../data/models/track.dart';

enum TrackSegmentKind {
  /// Punti consecutivi registrati davvero.
  recorded,

  /// Il salto sopra un'interruzione: due punti, nessun dato in mezzo.
  gap,
}

class TrackSegment {
  final List<TrackPoint> points;
  final TrackSegmentKind kind;

  /// Quanto e' durata l'interruzione. Valorizzata solo sui tratti [gap].
  final Duration? gapDuration;

  const TrackSegment({
    required this.points,
    required this.kind,
    this.gapDuration,
  });

  bool get isGap => kind == TrackSegmentKind.gap;
}

/// Spezza [points] usando [gaps].
///
/// Il confronto e' per **sovrapposizione di intervalli**, non per uguaglianza
/// di istanti: gli estremi del buco arrivano dal watchdog e sono precisi al
/// tick, non al secondo, quindi non coincideranno mai esattamente con il
/// timestamp di un punto. Un arco fra due punti e' un ponte se la finestra del
/// buco ci cade dentro anche solo in parte.
///
/// Con [gaps] vuota restituisce un solo tratto registrato: e' il caso della
/// stragrande maggioranza delle tracce, e di tutte quelle salvate prima che il
/// campo esistesse — per le quali "nessun buco noto" non vuol dire "nessun
/// buco".
List<TrackSegment> splitTrackOnGaps(
  List<TrackPoint> points,
  List<TrackGap> gaps,
) {
  if (points.length < 2) {
    return points.isEmpty
        ? const []
        : [TrackSegment(points: List.of(points), kind: TrackSegmentKind.recorded)];
  }
  if (gaps.isEmpty) {
    return [
      TrackSegment(points: List.of(points), kind: TrackSegmentKind.recorded),
    ];
  }

  final segments = <TrackSegment>[];
  var run = <TrackPoint>[points.first];

  for (var i = 1; i < points.length; i++) {
    final from = points[i - 1];
    final to = points[i];

    // Il buco tocca questo arco? Intervalli aperti: un buco che finisce
    // esattamente sul punto precedente non riguarda questo arco.
    final gap = _gapOverlapping(gaps, from.timestamp, to.timestamp);

    if (gap == null) {
      run.add(to);
      continue;
    }

    // Si chiude il tratto percorso, si dichiara il ponte, si riparte.
    if (run.length >= 2) {
      segments.add(
        TrackSegment(points: run, kind: TrackSegmentKind.recorded),
      );
    }
    segments.add(TrackSegment(
      points: [from, to],
      kind: TrackSegmentKind.gap,
      gapDuration: gap.duration,
    ));
    run = <TrackPoint>[to];
  }

  if (run.length >= 2) {
    segments.add(TrackSegment(points: run, kind: TrackSegmentKind.recorded));
  }
  return segments;
}

TrackGap? _gapOverlapping(List<TrackGap> gaps, DateTime from, DateTime to) {
  for (final g in gaps) {
    if (g.startedAt.isBefore(to) && g.endedAt.isAfter(from)) return g;
  }
  return null;
}

/// Il totale del tempo perso, per la riga da mostrare nella scheda.
Duration totalGapDuration(List<TrackGap> gaps) =>
    gaps.fold(Duration.zero, (sum, g) => sum + g.duration);
