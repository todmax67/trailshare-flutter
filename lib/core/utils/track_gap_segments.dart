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

import 'dart:math' as math;

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

// ─── Rilevamento a posteriori dei buchi non dichiarati ─────────────────────

/// Sotto questi valori un intervallo fra due punti non e' un candidato.
///
/// I 5 minuti allineano la soglia del watchdog (`_staleAfter`): sotto, puo'
/// essere una galleria o un semaforo. I 300 metri servono a distinguere il
/// congelamento dalla pausa pranzo: chi si ferma al rifugio produce un buco di
/// tempo ma resta dov'e', chi viene congelato mentre cammina ricompare
/// lontano.
///
/// Limite dichiarato: un congelamento durante un anello che ripassa vicino
/// allo stesso punto (fermo al parcheggio, si riparte da li') non supera la
/// soglia spaziale e non viene proposto. E' il compromesso giusto: il falso
/// positivo costerebbe una dichiarazione sbagliata suggerita al proprietario,
/// il falso negativo costa solo una retta corta che nessuno nota.
const Duration kMinUndeclaredGapTime = Duration(minutes: 5);
const double kMinUndeclaredGapMeters = 300;

/// Tolleranza sul bilancio del tempo mancante (vedi sotto): copre gli
/// arrotondamenti dell'accumulatore del tempo in movimento.
const Duration kGapBudgetSlack = Duration(seconds: 60);

/// Trova, in una traccia gia' salvata, gli archi che hanno la firma di
/// un'interruzione mai dichiarata: tanto tempo E tanta distanza fra due punti
/// consecutivi, E un bilancio del tempo che confermi l'assenza.
///
/// Serve per le tracce salvate prima che il watchdog scrivesse i buchi
/// (campo `gaps` della 2.11.3): li' la retta c'e' ma nessun metadato la
/// spiega. Il rilevamento NON scrive niente — produce candidati che solo il
/// proprietario puo' confermare, perche' l'unica cosa che rende accettabile
/// un dato non misurato e' che lo dichiari chi c'era.
///
/// ## Perche' servono [duration] e [movingTime]
///
/// I punti salvati sono l'output di Douglas-Peucker: su un rettilineo vero
/// (pianura in bici) la semplificazione butta i punti intermedi, e due punti
/// consecutivi SALVATI possono distare chilometri e minuti anche in una
/// registrazione perfetta. Tempo e distanza da soli non distinguono quel caso
/// da un congelamento — lo distingue il **tempo in movimento**, che viene
/// calcolato sui punti a piena risoluzione PRIMA della semplificazione:
///
/// - congelamento vero → quei minuti non hanno campioni → esclusi dal tempo
///   in movimento → il "tempo mancante" (durata − movimento) li copre;
/// - rettilineo compresso → quei minuti erano pedalati → contati nel tempo in
///   movimento → il tempo mancante NON li copre.
///
/// Quindi: si accettano candidati solo finche' la loro durata complessiva sta
/// nel tempo mancante (piu' [kGapBudgetSlack]), scegliendo prima i piu'
/// lunghi. Se il tempo in movimento non e' attendibile (zero, o uguale alla
/// durata — le tracce di prima della 2.10.0, dove era una copia) non si
/// propone niente: prudenza, non certezza che non ci siano buchi.
List<TrackGap> detectUndeclaredGaps(
  List<TrackPoint> points,
  List<TrackGap> declared, {
  required Duration duration,
  required Duration movingTime,
}) {
  if (points.length < 2) return const [];

  // Il bilancio: quanto tempo della traccia NON risulta in movimento.
  if (movingTime <= Duration.zero || movingTime >= duration) return const [];
  final budget = duration - movingTime + kGapBudgetSlack;

  final raw = <TrackGap>[];
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1];
    final b = points[i];

    final dt = b.timestamp.difference(a.timestamp);
    // Orologi che tornano indietro (cambio fuso, correzioni NTP): non e' un
    // buco, e' un dato inaffidabile — si lascia stare.
    if (dt < kMinUndeclaredGapTime) continue;

    if (_metersBetween(a, b) < kMinUndeclaredGapMeters) continue;

    final alreadyCovered = declared.any(
      (g) => g.startedAt.isBefore(b.timestamp) && g.endedAt.isAfter(a.timestamp),
    );
    if (alreadyCovered) continue;

    raw.add(TrackGap(
      startedAt: a.timestamp,
      endedAt: b.timestamp,
      cause: TrackGap.causeOwnerDeclared,
    ));
  }
  if (raw.isEmpty) return raw;

  // Prima i piu' lunghi: se il bilancio copre solo una parte, meglio tenere
  // il congelamento da 37 minuti e scartare l'arco da 6 che potrebbe essere
  // un rettilineo compresso.
  raw.sort((x, y) => y.duration.compareTo(x.duration));
  var spent = Duration.zero;
  final accepted = <TrackGap>[];
  for (final g in raw) {
    if (spent + g.duration > budget) continue;
    spent += g.duration;
    accepted.add(g);
  }
  accepted.sort((x, y) => x.startedAt.compareTo(y.startedAt));
  return accepted;
}

/// La distanza in linea retta del ponte sopra i buchi: serve alla UI per dire
/// "X km in linea retta", non entra in nessuna statistica.
double straightLineMeters(List<TrackPoint> points, List<TrackGap> gaps) {
  var total = 0.0;
  for (final s in splitTrackOnGaps(points, gaps)) {
    if (s.isGap && s.points.length == 2) {
      total += _metersBetween(s.points.first, s.points.last);
    }
  }
  return total;
}

/// Haversine locale, come in poi_business_dedup: bastano pochi metri di
/// precisione e si evita una dipendenza dal plugin geolocator in un'utility
/// pura.
double _metersBetween(TrackPoint a, TrackPoint b) {
  const r = 6371000.0;
  final dLat = _rad(b.latitude - a.latitude);
  final dLng = _rad(b.longitude - a.longitude);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(a.latitude)) *
          math.cos(_rad(b.latitude)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return 2 * r * math.asin(math.sqrt(h));
}

double _rad(double deg) => deg * math.pi / 180;
