import 'package:latlong2/latlong.dart';
import '../../core/services/routing_service.dart';
import 'navigation_step.dart';

/// Origine della traccia di riferimento passata a [RecordPage] in modalità
/// "guidata" (utente segue un percorso mentre registra la propria attività).
enum RecordingReferenceSource {
  /// Percorso creato nel Planner (con step turn-by-turn ORS).
  planner,

  /// Traccia pubblica o della community.
  trail,
}

/// Traccia di riferimento opzionale che RecordPage può usare per disegnare
/// una polyline guida sulla mappa, attivare guida vocale (solo `planner`) o
/// alert di off-trail sonori (solo `trail`) durante la registrazione.
///
/// La registrazione GPS, il salvataggio su Firestore, foto, Health sync,
/// crash recovery e tutte le feature normali restano attive in entrambi i
/// casi — così da qualunque punto l'utente avvii il "segui traccia" ottiene
/// la stessa UX e le stesse feature premium.
class RecordingReference {
  final RecordingReferenceSource source;

  /// Nome mostrato all'utente (es. "Percorso pianificato", "Anello Resegone").
  final String name;

  /// Polyline della traccia di riferimento (per render sulla mappa + calcolo
  /// off-trail / arrivo / distanza residua).
  final List<LatLng> polyline;

  /// Step turn-by-turn per guida vocale. Vuoto per `trail` (OSM non fornisce
  /// istruzioni di manovra), pieno per `planner` se ORS ha restituito steps.
  final List<NavigationStep> steps;

  /// Lunghezza totale in metri, se nota dalla fonte.
  final double? totalDistance;

  /// Dislivello positivo in metri, se noto.
  final double? totalElevationGain;

  /// Durata stimata in secondi (planner only).
  final double? estimatedDuration;

  const RecordingReference({
    required this.source,
    required this.name,
    required this.polyline,
    this.steps = const [],
    this.totalDistance,
    this.totalElevationGain,
    this.estimatedDuration,
  });

  /// Costruisce un reference dal risultato del Planner.
  factory RecordingReference.fromPlanner({
    required RouteResult route,
    String name = 'Percorso pianificato',
  }) {
    return RecordingReference(
      source: RecordingReferenceSource.planner,
      name: name,
      polyline: route.points.map((p) => p.latLng).toList(),
      steps: route.steps,
      totalDistance: route.distance,
      totalElevationGain: route.elevationGain,
      estimatedDuration: route.estimatedDuration,
    );
  }

  /// Costruisce un reference da una traccia pubblica / community.
  factory RecordingReference.fromTrail({
    required List<LatLng> trailPoints,
    required String trailName,
    double? totalDistance,
    double? totalElevationGain,
  }) {
    return RecordingReference(
      source: RecordingReferenceSource.trail,
      name: trailName,
      polyline: trailPoints,
      totalDistance: totalDistance,
      totalElevationGain: totalElevationGain,
    );
  }

  bool get isPlanner => source == RecordingReferenceSource.planner;
  bool get isTrail => source == RecordingReferenceSource.trail;

  /// Vero se sono disponibili step turn-by-turn (attiva la guida vocale).
  bool get hasTurnByTurn => steps.isNotEmpty;
}
