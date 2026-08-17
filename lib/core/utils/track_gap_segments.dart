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

  /// TUTTI i buchi che cadono su questo arco, non uno solo.
  ///
  /// Su un'interruzione lunga sono la norma: il watchdog ne emette uno ogni
  /// cinque minuti finche' i punti mancano, quindi un congelamento da mezz'ora
  /// produce sei buchi fra la stessa coppia di punti registrati. Tenerne uno
  /// solo faceva divergere chi disegna da chi offre la ricostruzione: l'utente
  /// disegnava, il salvataggio riusciva, e la mappa non cambiava.
  final List<TrackGap> gaps;

  const TrackSegment({
    required this.points,
    required this.kind,
    this.gapDuration,
    this.gaps = const [],
  });

  bool get isGap => kind == TrackSegmentKind.gap;

  /// Il buco che rappresenta questo arco: quello ricostruito se c'e',
  /// altrimenti il piu' lungo. **La stessa regola va usata dalla UI** quando
  /// offre di ricostruire, o le due parti tornano a divergere.
  TrackGap? get gap {
    if (gaps.isEmpty) return null;
    for (final g in gaps) {
      if (g.hasReconstruction) return g;
    }
    return gaps.reduce((a, b) => b.duration > a.duration ? b : a);
  }
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

  // Ogni buco va assegnato a UN SOLO arco, prima di cominciare.
  //
  // La tentazione e' dare l'arco a ogni buco che lo tocca, ma la finestra del
  // watchdog parte dall'ultimo TICK, non dall'ultimo punto: un fix arrivato
  // nei secondi fra il tick e il congelamento cade dentro la finestra, e lo
  // stesso buco finiva per coprire due archi. Le conseguenze non erano
  // estetiche: i chilometri ricostruiti si sommavano due volte nella scheda,
  // e il disegnatore riceveva gli estremi dell'arco sbagliato — 23 secondi di
  // traccia registrata davvero al posto dei 37 minuti mancanti, con il
  // percorso disegnato poi steso sopra entrambi.
  //
  // La regola e' la sovrapposizione piu' lunga: l'arco che contiene la fetta
  // piu' grande della finestra e' quello che il buco spiega davvero. Un buco
  // che non tocca nessun arco resta fuori: non lo si puo' ne' disegnare ne'
  // offrire.
  final assegnati = <int, List<TrackGap>>{};
  for (final g in gaps) {
    var vincente = -1;
    var massima = Duration.zero;
    for (var i = 1; i < points.length; i++) {
      final ov = _overlap(g, points[i - 1].timestamp, points[i].timestamp);
      if (ov > massima) {
        massima = ov;
        vincente = i;
      }
    }
    if (vincente >= 0) (assegnati[vincente] ??= <TrackGap>[]).add(g);
  }

  final segments = <TrackSegment>[];
  var run = <TrackPoint>[points.first];

  for (var i = 1; i < points.length; i++) {
    final from = points[i - 1];
    final to = points[i];

    final qui = assegnati[i] ?? const <TrackGap>[];

    if (qui.isEmpty) {
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
      // La durata dell'arco e' la somma dei buchi che ci cadono dentro.
      gapDuration: qui.fold<Duration>(Duration.zero, (t, g) => t + g.duration),
      gaps: qui,
    ));
    run = <TrackPoint>[to];
  }

  if (run.length >= 2) {
    segments.add(TrackSegment(points: run, kind: TrackSegmentKind.recorded));
  }
  return segments;
}

/// Quanto della finestra di [g] cade dentro l'arco [from]–[to].
///
/// Zero se non si toccano, o se si sfiorano in un istante solo: un buco che
/// finisce esattamente sul punto precedente non riguarda questo arco.
Duration _overlap(TrackGap g, DateTime from, DateTime to) {
  final inizio = g.startedAt.isAfter(from) ? g.startedAt : from;
  final fine = g.endedAt.isBefore(to) ? g.endedAt : to;
  final d = fine.difference(inizio);
  return d.isNegative ? Duration.zero : d;
}

/// Il buco che la UI deve offrire di ricostruire per un dato arco, con la
/// STESSA regola usata da [TrackSegment.gap]. Esportata apposta: quando le due
/// parti scelgono buchi diversi, il disegno si salva su uno e la mappa ne
/// legge un altro — e all'utente sembra che il salvataggio non abbia fatto
/// niente.
List<TrackGap> gapsRappresentativi(
  List<TrackPoint> points,
  List<TrackGap> gaps,
) =>
    [
      for (final s in splitTrackOnGaps(points, gaps))
        if (s.isGap && s.gap != null) s.gap!,
    ];

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

/// Da quando le tracce vengono salvate con la semplificazione PER FORMA
/// (Douglas-Peucker, commit ce2523c del 2026-08-05, in produzione con la
/// 2.10.0 del 9 agosto).
///
/// Prima la riduzione era uniforme — un punto ogni N — e conservava la
/// cadenza temporale: un arco di 5+ minuti nel salvato poteva essere solo un
/// buco vero. Da questa data in poi puo' anche essere un rettilineo
/// collassato, e serve il bilancio del tempo in movimento per distinguerli.
///
/// Le tracce piu' vecchie di questa data hanno anche un movingTime copiato
/// dalla durata (corretto solo nella 2.10.0), quindi senza questa distinzione
/// il bilancio le escluderebbe tutte — proprio quelle per cui la Fase 1
/// esiste. Si usa la data del commit e non della release: le tracce salvate
/// nei quattro giorni di build di sviluppo finiscono nel regime moderno, che
/// e' il lato prudente.
final DateTime kShapeSimplifiedSince = DateTime.utc(2026, 8, 5);

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
  bool savedBeforeShapeSimplification = false,
}) {
  if (points.length < 2) return const [];

  // Regime d'epoca (vedi [kShapeSimplifiedSince]): sulle tracce ridotte
  // uniformemente un arco lungo E' un buco — il bilancio non serve, e il loro
  // movingTime copiato dalla durata lo renderebbe comunque inutilizzabile.
  final useBudget = !savedBeforeShapeSimplification;

  // Il bilancio: quanto tempo della traccia NON risulta in movimento.
  if (useBudget &&
      (movingTime <= Duration.zero || movingTime >= duration)) {
    return const [];
  }
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
  if (raw.isEmpty || !useBudget) return raw;

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
