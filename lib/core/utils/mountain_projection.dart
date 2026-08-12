import 'dart:math' as math;

import 'package:flutter/widgets.dart' show Size;

import '../../data/models/mountain_peak.dart';
import '../../data/models/osm_poi.dart';
import 'camera_orientation.dart';

/// Proiezione **AR** di cime e POI sul viewport della fotocamera.
///
/// La geometria vera e propria sta in `camera_orientation.dart` (terna della
/// fotocamera + proiezione prospettica): qui resta solo il collegamento fra
/// quel motore e i modelli di dominio.
///
/// Cosa è cambiato rispetto alla prima versione, e perché:
/// - l'orientamento arriva come **terna di versori** invece che come coppia
///   heading/pitch, così il **roll** del telefono non manda più fuori posto le
///   etichette;
/// - la mappatura angolo→pixel è **rettilinea** (tangente), come quella di una
///   fotocamera vera, invece che lineare;
/// - la quota dell'osservatore è un parametro esplicito, perché va presa dal
///   DEM e non dal GPS (che sbaglia di 20-50 m e sposta i pin in verticale);
/// - la curvatura terrestre è inclusa: a 100 km vale 683 m, cioè 0,4°.
class MountainProjection {
  MountainProjection._();

  /// FOV orizzontale tipico delle camere posteriori smartphone tenute in
  /// portrait. Gli iPhone main camera sono ~63°, gli Android variano fra
  /// 60 e 75°. Valore medio prudente, affinabile dalla calibrazione utente.
  static const double defaultHorizontalFovDeg = 60.0;

  /// FOV verticale: in portrait il sensor ratio si capovolge, quindi
  /// vediamo "alto e stretto". 80° è un buon range.
  static const double defaultVerticalFovDeg = 80.0;

  /// Proietta un punto generico (lat/lng/quota) sul viewport.
  /// Restituisce `null` se il punto è fuori dal cono visibile o alle spalle.
  static ScreenProjection? _projectPoint({
    required double targetLat,
    required double targetLng,
    required double? targetElevation,
    required double observerLat,
    required double observerLng,
    required double observerElevationMeters,
    required CameraBasis basis,
    required Size viewport,
    required double horizontalFovDeg,
    required double verticalFovDeg,
    required double zoom,
  }) {
    final enu = enuOffsetMeters(
      observerLat: observerLat,
      observerLng: observerLng,
      observerElevationM: observerElevationMeters,
      targetLat: targetLat,
      targetLng: targetLng,
      // Senza quota nota trattiamo il punto come se fosse alla stessa altezza
      // dell'osservatore: finisce sull'orizzonte, che è la scelta meno
      // sbagliata (i POI OSM spesso non hanno `ele`).
      targetElevationM: targetElevation ?? observerElevationMeters,
    );
    return projectDirection(
      enu: enu,
      basis: basis,
      viewportWidth: viewport.width,
      viewportHeight: viewport.height,
      horizontalFovDeg: horizontalFovDeg,
      verticalFovDeg: verticalFovDeg,
      zoom: zoom,
    );
  }

  static ProjectedPeak? project({
    required MountainPeak peak,
    required double observerLat,
    required double observerLng,
    required double observerElevationMeters,
    required CameraBasis basis,
    required Size viewport,
    double horizontalFovDeg = defaultHorizontalFovDeg,
    double verticalFovDeg = defaultVerticalFovDeg,
    double zoom = 1.0,
  }) {
    final r = _projectPoint(
      targetLat: peak.latitude,
      targetLng: peak.longitude,
      targetElevation: peak.elevation,
      observerLat: observerLat,
      observerLng: observerLng,
      observerElevationMeters: observerElevationMeters,
      basis: basis,
      viewport: viewport,
      horizontalFovDeg: horizontalFovDeg,
      verticalFovDeg: verticalFovDeg,
      zoom: zoom,
    );
    if (r == null) return null;
    return ProjectedPeak(
      peak: peak,
      screenX: r.x,
      screenY: r.y,
      distanceMeters: haversineMeters(
        observerLat,
        observerLng,
        peak.latitude,
        peak.longitude,
      ),
      bearingDeg: initialBearingDeg(
        observerLat,
        observerLng,
        peak.latitude,
        peak.longitude,
      ),
      relativeBearingDeg: r.relativeBearingDeg,
      relativePitchDeg: r.relativePitchDeg,
    );
  }

  /// Proietta un POI OSM (rifugio, sorgente, ecc.) sul viewport.
  /// Stessa math di [project] ma con [OsmPoi] al posto di [MountainPeak].
  static ProjectedPoi? projectPoi({
    required OsmPoi poi,
    required double observerLat,
    required double observerLng,
    required double observerElevationMeters,
    required CameraBasis basis,
    required Size viewport,
    double horizontalFovDeg = defaultHorizontalFovDeg,
    double verticalFovDeg = defaultVerticalFovDeg,
    double zoom = 1.0,
  }) {
    final r = _projectPoint(
      targetLat: poi.latitude,
      targetLng: poi.longitude,
      targetElevation: poi.elevation,
      observerLat: observerLat,
      observerLng: observerLng,
      observerElevationMeters: observerElevationMeters,
      basis: basis,
      viewport: viewport,
      horizontalFovDeg: horizontalFovDeg,
      verticalFovDeg: verticalFovDeg,
      zoom: zoom,
    );
    if (r == null) return null;
    return ProjectedPoi(
      poi: poi,
      screenX: r.x,
      screenY: r.y,
      distanceMeters: haversineMeters(
        observerLat,
        observerLng,
        poi.latitude,
        poi.longitude,
      ),
      bearingDeg: initialBearingDeg(
        observerLat,
        observerLng,
        poi.latitude,
        poi.longitude,
      ),
      relativeBearingDeg: r.relativeBearingDeg,
      relativePitchDeg: r.relativePitchDeg,
    );
  }

  /// Quanto più in basso può scendere una cima già mostrata prima di perdere il
  /// nome, in multipli di [maxVisible].
  ///
  /// È il cuore dell'isteresi: si entra al trentesimo posto ma si esce solo al
  /// quarantaduesimo. Senza questa banda morta le cime che oscillano attorno
  /// alla soglia comparivano e sparivano a ogni campione dei sensori.
  static const double labelExitSlack = 1.4;

  /// Filtra/proietta tutte le [peaks] e ritorna le top [maxVisible]
  /// **più centrate** rispetto al puntamento.
  ///
  /// Tiebreaker: a parità di centratura preferisce l'altitudine maggiore.
  ///
  /// [previouslyShownIds] attiva la **selezione stabile**: vedi [selectStable].
  /// Passandolo, l'insieme restituito cambia molto più lentamente a parità di
  /// movimento — che è ciò che si vede, non il numero di cime.
  static List<ProjectedPeak> projectAll({
    required Iterable<MountainPeak> peaks,
    required double observerLat,
    required double observerLng,
    required double observerElevationMeters,
    required CameraBasis basis,
    required Size viewport,
    int maxVisible = 5,
    double horizontalFovDeg = defaultHorizontalFovDeg,
    double verticalFovDeg = defaultVerticalFovDeg,
    double zoom = 1.0,
    Set<String>? previouslyShownIds,
  }) {
    final visible = <ProjectedPeak>[];
    for (final p in peaks) {
      final proj = project(
        peak: p,
        observerLat: observerLat,
        observerLng: observerLng,
        observerElevationMeters: observerElevationMeters,
        basis: basis,
        viewport: viewport,
        horizontalFovDeg: horizontalFovDeg,
        verticalFovDeg: verticalFovDeg,
        zoom: zoom,
      );
      if (proj != null) visible.add(proj);
    }

    visible.sort((a, b) {
      final diff = _centeringScore(a, horizontalFovDeg, verticalFovDeg)
          .compareTo(_centeringScore(b, horizontalFovDeg, verticalFovDeg));
      if (diff != 0) return diff;
      final eleA = a.peak.elevation ?? 0;
      final eleB = b.peak.elevation ?? 0;
      return eleB.compareTo(eleA);
    });

    if (visible.length <= maxVisible) return visible;
    if (previouslyShownIds == null) return visible.take(maxVisible).toList();
    return selectStable(
      ranked: visible,
      previouslyShownIds: previouslyShownIds,
      maxVisible: maxVisible,
    );
  }

  /// Sceglie quali cime mostrare **con isteresi**, per non farle sfarfallare.
  ///
  /// Il problema che risolve non è il costo, è il ricambio. Puntando il telefono
  /// verso le Orobie cadono nel cono circa 168 cime e se ne etichettano 30: la
  /// classifica per centratura cambia a ogni campione dei sensori, quindi le
  /// cime attorno al trentesimo posto entravano e uscivano di continuo —
  /// misurate 4,5 sostituzioni per campione muovendosi piano e **14 muovendosi
  /// in fretta**, ognuna con un'etichetta che compare o sparisce di colpo. Con
  /// l'animazione tolta il ritardo è sparito, ma questo sfarfallio no: è un
  /// difetto di *decisione*, non di disegno.
  ///
  /// La cura è quella di un termostato: due soglie invece di una. Si entra al
  /// posto [maxVisible], si esce solo dopo esserne scesi di [labelExitSlack]
  /// volte tanto. Fra le due c'è una banda morta dove una cima non cambia
  /// stato, e l'oscillazione non produce più eventi.
  ///
  /// Due invarianti si mantengono: la cima **più centrata** ha sempre il nome
  /// (è quella che l'utente sta inquadrando, e togliergliela sarebbe il difetto
  /// peggiore di tutti), e l'ordine restituito resta quello di classifica,
  /// perché chi chiama si aspetta la più centrata in testa.
  ///
  /// [ranked] dev'essere già ordinata dalla più centrata alla meno.
  static List<ProjectedPeak> selectStable({
    required List<ProjectedPeak> ranked,
    required Set<String> previouslyShownIds,
    required int maxVisible,
    double exitSlack = labelExitSlack,
  }) {
    if (ranked.length <= maxVisible) return ranked;

    final chosen = <String>{};

    // 1. La più centrata, sempre e comunque: se restasse fuori perché trenta
    //    veterani le occupano il posto, l'utente vedrebbe senza nome proprio la
    //    montagna che sta inquadrando.
    chosen.add(ranked.first.peak.id);

    // 2. I veterani, finché non escono dalla banda morta.
    final exitRank = math.min(ranked.length, (maxVisible * exitSlack).round());
    for (var i = 0; i < exitRank && chosen.length < maxVisible; i++) {
      if (previouslyShownIds.contains(ranked[i].peak.id)) {
        chosen.add(ranked[i].peak.id);
      }
    }

    // 3. I posti avanzati vanno ai migliori nuovi arrivati. Senza questo passo
    //    la lista si svuoterebbe girando su sé stessi, invece di riempirsi con
    //    quello che si sta guardando adesso.
    for (var i = 0; i < ranked.length && chosen.length < maxVisible; i++) {
      chosen.add(ranked[i].peak.id);
    }

    return [for (final p in ranked) if (chosen.contains(p.peak.id)) p];
  }

  /// Variante di [projectAll] per i POI OSM (rifugi, sorgenti, fontane,
  /// panorami, ecc.). Stessa logica di selezione, tiebreaker sul più vicino.
  static List<ProjectedPoi> projectAllPois({
    required Iterable<OsmPoi> pois,
    required double observerLat,
    required double observerLng,
    required double observerElevationMeters,
    required CameraBasis basis,
    required Size viewport,
    int maxVisible = 9999,
    double horizontalFovDeg = defaultHorizontalFovDeg,
    double verticalFovDeg = defaultVerticalFovDeg,
    double zoom = 1.0,
  }) {
    final visible = <ProjectedPoi>[];
    for (final p in pois) {
      final proj = projectPoi(
        poi: p,
        observerLat: observerLat,
        observerLng: observerLng,
        observerElevationMeters: observerElevationMeters,
        basis: basis,
        viewport: viewport,
        horizontalFovDeg: horizontalFovDeg,
        verticalFovDeg: verticalFovDeg,
        zoom: zoom,
      );
      if (proj != null) visible.add(proj);
    }

    visible.sort((a, b) {
      final centerA = (a.relativeBearingDeg.abs() / horizontalFovDeg) +
          (a.relativePitchDeg.abs() / verticalFovDeg);
      final centerB = (b.relativeBearingDeg.abs() / horizontalFovDeg) +
          (b.relativePitchDeg.abs() / verticalFovDeg);
      final diff = centerA.compareTo(centerB);
      if (diff != 0) return diff;
      return a.distanceMeters.compareTo(b.distanceMeters);
    });

    if (visible.length <= maxVisible) return visible;
    return visible.take(maxVisible).toList();
  }

  static double _centeringScore(
    ProjectedPeak p,
    double hFov,
    double vFov,
  ) =>
      (p.relativeBearingDeg.abs() / hFov) + (p.relativePitchDeg.abs() / vFov);

  /// Stima del **pitch del telefono** dato il vettore gravità
  /// dell'accelerometro (in m/s², asse standard Android/iOS).
  ///
  /// Usata solo dal **ripiego** quando la sensor fusion nativa non è
  /// disponibile: l'accelerometro da solo misura gravità *più* accelerazione
  /// lineare, quindi sbanda appena ci si muove. La sorgente buona è
  /// `DeviceAttitudeService`.
  ///
  /// Convenzione output:
  /// - 0° quando il telefono è in portrait con la camera all'orizzonte
  /// - +90° quando la camera punta verso lo zenit
  /// - -90° quando la camera punta verso il basso
  static double pitchFromAccelerometer(double ax, double ay, double az) {
    final pitchRad = math.atan2(-az, math.sqrt(ax * ax + ay * ay));
    return pitchRad * 180 / math.pi;
  }
}

/// Risultato di una proiezione AR.
class ProjectedPeak {
  final MountainPeak peak;

  /// Coordinate di pixel sul viewport, origin top-left.
  final double screenX;
  final double screenY;

  /// Distanza geografica osservatore -> peak in metri.
  final double distanceMeters;

  /// Bearing assoluto (0=Nord) osservatore -> peak.
  final double bearingDeg;

  /// Scostamento angolare dall'asse ottico (-180..+180,
  /// 0 = perfettamente centrato in orizzontale).
  final double relativeBearingDeg;

  /// Scostamento verticale dall'asse ottico in gradi.
  /// 0 = centrato, positivo = sopra il centro, negativo = sotto.
  final double relativePitchDeg;

  const ProjectedPeak({
    required this.peak,
    required this.screenX,
    required this.screenY,
    required this.distanceMeters,
    required this.bearingDeg,
    required this.relativeBearingDeg,
    required this.relativePitchDeg,
  });

  /// True se la cima è centrata entro il 10% del viewport (utile per highlight).
  bool isCentered(Size viewport) {
    final dx = (screenX - viewport.width / 2).abs();
    final dy = (screenY - viewport.height / 2).abs();
    return dx < viewport.width * 0.10 && dy < viewport.height * 0.10;
  }
}

/// POI OSM proiettato sul viewport (parallelo a [ProjectedPeak]).
class ProjectedPoi {
  final OsmPoi poi;
  final double screenX;
  final double screenY;
  final double distanceMeters;
  final double bearingDeg;
  final double relativeBearingDeg;
  final double relativePitchDeg;

  const ProjectedPoi({
    required this.poi,
    required this.screenX,
    required this.screenY,
    required this.distanceMeters,
    required this.bearingDeg,
    required this.relativeBearingDeg,
    required this.relativePitchDeg,
  });
}
