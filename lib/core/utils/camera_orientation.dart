import 'dart:math' as math;

/// Geometria della fotocamera per l'AR: orientamento nello spazio e
/// proiezione prospettica sul viewport.
///
/// Tutto qui dentro è **puro** (nessun sensore, nessun I/O, nessun Flutter
/// widget) proprio perché è la parte che deve essere giusta al primo colpo:
/// si testa con angoli noti invece che puntando il telefono verso una cima.

/// Raggio medio terrestre in metri. Stesso valore del viewshed, così le due
/// metà del sistema concordano su dove cade l'orizzonte.
const double earthRadiusM = 6371000.0;

/// Coefficiente di rifrazione atmosferica standard: la luce si incurva verso
/// il basso e "solleva" gli oggetti lontani di circa il 13% del calo dovuto
/// alla curvatura.
const double refractionK = 0.13;

/// Abbassamento apparente di un punto a distanza [distanceM], per curvatura
/// terrestre corretta dalla rifrazione.
///
/// A 10 km vale 7 m, a 50 km 171 m, a 100 km 683 m: a lunga distanza è la
/// differenza fra un pin sulla cima e un pin a mezza costa.
double earthDropMeters(double distanceM) =>
    (1 - refractionK) * distanceM * distanceM / (2 * earthRadiusM);

/// Orientamento della fotocamera posteriore, espresso come **terna di versori
/// nel sistema ENU locale** (X = Est, Y = Nord, Z = Su).
///
/// Perché una terna e non i soliti heading + pitch: con due angoli separati il
/// **roll** (telefono inclinato di lato) semplicemente non è rappresentabile, e
/// la proiezione sbaglia non appena l'utente non tiene il telefono in bolla —
/// cioè sempre, a mano libera. Con la terna la proiezione diventa quella vera
/// di una fotocamera (cambio di base + divisione prospettica) e azimut, pitch
/// e roll sono gestiti insieme, senza casi particolari e senza wrap-around.
class CameraBasis {
  /// Asse ottico: la direzione verso cui guarda l'obiettivo posteriore.
  final double fE, fN, fU;

  /// "Su" dello schermo, cioè verso il bordo alto di quello che l'utente vede.
  final double uE, uN, uU;

  /// "Destra" dello schermo.
  final double rE, rN, rU;

  const CameraBasis({
    required this.fE,
    required this.fN,
    required this.fU,
    required this.uE,
    required this.uN,
    required this.uU,
    required this.rE,
    required this.rN,
    required this.rU,
  });

  /// Costruisce la terna dalla matrice di rotazione **device → ENU** fornita
  /// dalla sensor fusion del sistema operativo (row-major, 9 elementi:
  /// `[r0 r1 r2; r3 r4 r5; r6 r7 r8]`, con `v_enu = M · v_device`).
  ///
  /// Assi del device, convenzione condivisa Android/iOS *nell'orientamento
  /// naturale del dispositivo* (portrait sui telefoni): X verso destra dello
  /// schermo, Y verso l'alto, Z uscente dallo schermo verso l'utente. L'obiettivo
  /// posteriore guarda quindi lungo **−Z**.
  ///
  /// [screenRotationDeg] è la rotazione della UI rispetto all'orientamento
  /// naturale (0/90/180/270), riportata dalla piattaforma: serve perché in
  /// landscape la "destra dello schermo" non è più l'asse X del device. Senza
  /// questa correzione i pin si muovono lungo l'asse sbagliato appena si ruota
  /// il telefono, e nei due landscape si muovono in versi opposti.
  factory CameraBasis.fromDeviceToEnu(
    List<double> m, {
    int screenRotationDeg = 0,
  }) {
    if (m.length < 9) {
      throw ArgumentError('matrice device→ENU: attesi 9 elementi, ${m.length}');
    }
    // Colonne della matrice = assi del device espressi in ENU.
    final devX = [m[0], m[3], m[6]];
    final devY = [m[1], m[4], m[7]];
    final devZ = [m[2], m[5], m[8]];

    // Dagli assi del device agli assi dello SCHERMO.
    //
    // La tabella segue la convenzione canonica di Android
    // (`SensorManager.remapCoordinateSystem`): per ROTATION_90 l'asse X del
    // device è mappato su Y e l'asse Y su −X, e invertendo si ottiene la riga
    // qui sotto. iOS riporta la stessa grandezza a partire da
    // `interfaceOrientation`.
    //
    // Se in campo i pin si muovessero al contrario in landscape, il rimedio è
    // scambiare le due righe 90 e 270: è l'unico grado di libertà rimasto.
    final List<double> screenRight;
    final List<double> screenUp;
    switch (screenRotationDeg % 360) {
      case 90:
        screenRight = _neg(devY);
        screenUp = devX;
        break;
      case 180:
        screenRight = _neg(devX);
        screenUp = _neg(devY);
        break;
      case 270:
        screenRight = devY;
        screenUp = _neg(devX);
        break;
      default: // 0 → orientamento naturale
        screenRight = devX;
        screenUp = devY;
    }

    // L'obiettivo guarda lungo −Z del device, e questo non dipende da come è
    // ruotata la UI.
    final forward = _neg(devZ);

    // Rinormalizziamo: la matrice che arriva dai sensori è ortonormale a meno
    // del rumore in virgola mobile, e un versore lungo 1.0001 si trasforma in
    // un pin che scivola.
    final f = _normalize(forward);
    final r = _normalize(screenRight);
    final u = _normalize(screenUp);

    return CameraBasis(
      fE: f[0], fN: f[1], fU: f[2],
      uE: u[0], uN: u[1], uU: u[2],
      rE: r[0], rN: r[1], rU: r[2],
    );
  }

  /// Costruisce la terna da azimut/pitch/roll. Serve al ripiego quando la
  /// sensor fusion nativa non è disponibile (lì il roll resta 0, perché
  /// bussola + accelerometro non lo forniscono) e ai test, dove partire da
  /// angoli noti è molto più leggibile che scrivere una matrice a mano.
  ///
  /// - [azimuthDeg]: 0 = nord, 90 = est, direzione verso cui punta l'obiettivo.
  /// - [pitchDeg]: 0 = orizzonte, positivo = obiettivo verso l'alto.
  /// - [rollDeg]: rotazione attorno all'asse ottico; positivo = il telefono
  ///   ruota in senso antiorario visto da dietro (cioè l'immagine sullo schermo
  ///   ruota in senso orario).
  factory CameraBasis.fromAngles({
    required double azimuthDeg,
    required double pitchDeg,
    double rollDeg = 0,
  }) {
    final az = _rad(azimuthDeg);
    final pitch = _rad(pitchDeg);
    final roll = _rad(rollDeg);

    final cp = math.cos(pitch);
    final f = [
      math.sin(az) * cp,
      math.cos(az) * cp,
      math.sin(pitch),
    ];
    // Destra "a roll zero": orizzontale, a 90° in senso orario dall'azimut.
    final r0 = [math.cos(az), -math.sin(az), 0.0];
    // Su "a roll zero" = destra × avanti (terna destrorsa destra-su-avanti).
    final u0 = _cross(r0, f);

    final cr = math.cos(roll);
    final sr = math.sin(roll);
    final r = [
      r0[0] * cr + u0[0] * sr,
      r0[1] * cr + u0[1] * sr,
      r0[2] * cr + u0[2] * sr,
    ];
    final u = [
      -r0[0] * sr + u0[0] * cr,
      -r0[1] * sr + u0[1] * cr,
      -r0[2] * sr + u0[2] * cr,
    ];

    return CameraBasis(
      fE: f[0], fN: f[1], fU: f[2],
      uE: u[0], uN: u[1], uU: u[2],
      rE: r[0], rN: r[1], rU: r[2],
    );
  }

  /// Azimut dell'asse ottico in gradi, 0 = nord, 0..360.
  double get azimuthDeg {
    final a = _deg(math.atan2(fE, fN));
    return (a + 360) % 360;
  }

  /// Inclinazione dell'asse ottico sull'orizzonte, −90..+90.
  double get pitchDeg => _deg(math.asin(fU.clamp(-1.0, 1.0)));

  /// Rotazione attorno all'asse ottico, −180..+180. Zero quando il bordo
  /// superiore dello schermo punta verso l'alto del mondo.
  double get rollDeg {
    // Verticale del mondo proiettata sul piano immagine, poi letta nella base
    // (destra, su) dello schermo.
    final dot = fU; // (0,0,1) · f
    final px = -dot * fE;
    final py = -dot * fN;
    final pz = 1 - dot * fU;
    final onRight = px * rE + py * rN + pz * rU;
    final onUp = px * uE + py * uN + pz * uU;
    if (onRight.abs() < 1e-9 && onUp.abs() < 1e-9) return 0; // zenit/nadir
    return _deg(math.atan2(onRight, onUp));
  }

  /// Ruota la terna attorno all'asse verticale ([deltaAzimuthDeg]) e attorno
  /// all'asse orizzontale dello schermo ([deltaPitchDeg]).
  ///
  /// È il gancio per la correzione manuale dell'allineamento (drag-to-align,
  /// sprint 3): l'offset si applica qui, una volta, invece di sparpagliarsi
  /// nei punti in cui si legge l'orientamento.
  CameraBasis nudged({double deltaAzimuthDeg = 0, double deltaPitchDeg = 0}) {
    if (deltaAzimuthDeg == 0 && deltaPitchDeg == 0) return this;
    return CameraBasis.fromAngles(
      azimuthDeg: azimuthDeg + deltaAzimuthDeg,
      pitchDeg: (pitchDeg + deltaPitchDeg).clamp(-89.9, 89.9),
      rollDeg: rollDeg,
    );
  }

  @override
  String toString() => 'CameraBasis(az=${azimuthDeg.toStringAsFixed(1)}°, '
      'pitch=${pitchDeg.toStringAsFixed(1)}°, '
      'roll=${rollDeg.toStringAsFixed(1)}°)';
}

/// Vettore osservatore → bersaglio nel sistema ENU locale, in metri.
///
/// La componente verticale include l'abbassamento per curvatura terrestre e
/// rifrazione: senza, una cima a 100 km finisce 683 m troppo in alto.
List<double> enuOffsetMeters({
  required double observerLat,
  required double observerLng,
  required double observerElevationM,
  required double targetLat,
  required double targetLng,
  required double targetElevationM,
}) {
  final distance = haversineMeters(
    observerLat,
    observerLng,
    targetLat,
    targetLng,
  );
  final bearing = initialBearingDeg(
    observerLat,
    observerLng,
    targetLat,
    targetLng,
  );
  final b = _rad(bearing);
  final up =
      (targetElevationM - earthDropMeters(distance)) - observerElevationM;
  return [distance * math.sin(b), distance * math.cos(b), up];
}

/// Risultato della proiezione prospettica di una direzione sul viewport.
class ScreenProjection {
  /// Pixel sul viewport, origine in alto a sinistra.
  final double x;
  final double y;

  /// Scostamento angolare dall'asse ottico, in gradi: orizzontale (positivo =
  /// a destra del centro) e verticale (positivo = sopra il centro). Servono per
  /// ordinare le cime per "centratura" e per gli highlight.
  final double relativeBearingDeg;
  final double relativePitchDeg;

  const ScreenProjection({
    required this.x,
    required this.y,
    required this.relativeBearingDeg,
    required this.relativePitchDeg,
  });
}

/// Proietta una direzione ENU sul viewport con la **proiezione rettilinea**
/// di una vera fotocamera.
///
/// Il punto chiave: l'immagine è proporzionale alla **tangente** dell'angolo,
/// non all'angolo. La mappatura lineare usata prima è esatta al centro e ai
/// bordi e sbaglia in mezzo — cioè proprio dove si guarda: fino al 3-4%
/// dell'altezza dello schermo a 20° dal centro con FOV verticale 80°.
///
/// [zoom] è lo zoom ottico/digitale applicato alla preview: restringe il cono
/// dividendo la **tangente** del semiangolo, non i gradi (a 2× il campo non è
/// metà in gradi).
///
/// Restituisce `null` se il bersaglio è dietro la fotocamera o fuori dal cono.
ScreenProjection? projectDirection({
  required List<double> enu,
  required CameraBasis basis,
  required double viewportWidth,
  required double viewportHeight,
  required double horizontalFovDeg,
  required double verticalFovDeg,
  double zoom = 1.0,
}) {
  final e = enu[0], n = enu[1], u = enu[2];

  // Cambio di base: dal mondo alla fotocamera.
  final z = e * basis.fE + n * basis.fN + u * basis.fU; // avanti
  if (z <= 1e-6) return null; // dietro di noi o esattamente di lato
  final x = e * basis.rE + n * basis.rN + u * basis.rU; // destra
  final y = e * basis.uE + n * basis.uN + u * basis.uU; // su

  final halfTanH = math.tan(_rad(horizontalFovDeg / 2)) / zoom;
  final halfTanV = math.tan(_rad(verticalFovDeg / 2)) / zoom;
  if (halfTanH <= 0 || halfTanV <= 0) return null;

  // Divisione prospettica, normalizzata a ±1 sui bordi del viewport.
  // La tolleranza evita che un bersaglio esattamente sul bordo sparisca per
  // rumore in virgola mobile (tan(45°) vale 0,999...9, non 1).
  const edgeEpsilon = 1e-9;
  final ndcX = (x / z) / halfTanH;
  final ndcY = (y / z) / halfTanV;
  if (ndcX.abs() > 1 + edgeEpsilon || ndcY.abs() > 1 + edgeEpsilon) return null;

  return ScreenProjection(
    x: viewportWidth / 2 * (1 + ndcX),
    y: viewportHeight / 2 * (1 - ndcY),
    relativeBearingDeg: _deg(math.atan2(x, z)),
    relativePitchDeg: _deg(math.atan2(y, math.sqrt(x * x + z * z))),
  );
}

/// Distanza great-circle in metri fra due coordinate WGS84.
double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  final dLat = _rad(lat2 - lat1);
  final dLng = _rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) *
          math.cos(_rad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return 2 * earthRadiusM * math.asin(math.min(1.0, math.sqrt(a)));
}

/// Bearing iniziale in gradi (0 = nord, 90 = est) da p1 a p2.
double initialBearingDeg(double lat1, double lng1, double lat2, double lng2) {
  final phi1 = _rad(lat1);
  final phi2 = _rad(lat2);
  final dl = _rad(lng2 - lng1);
  final y = math.sin(dl) * math.cos(phi2);
  final x = math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(dl);
  return (_deg(math.atan2(y, x)) + 360) % 360;
}

// ─── Utility vettoriali ───────────────────────────────────────────────────

List<double> _neg(List<double> v) => [-v[0], -v[1], -v[2]];

List<double> _cross(List<double> a, List<double> b) => [
      a[1] * b[2] - a[2] * b[1],
      a[2] * b[0] - a[0] * b[2],
      a[0] * b[1] - a[1] * b[0],
    ];

List<double> _normalize(List<double> v) {
  final len = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
  if (len < 1e-12) return [0, 0, 1];
  return [v[0] / len, v[1] / len, v[2] / len];
}

double _rad(double deg) => deg * math.pi / 180;
double _deg(double rad) => rad * 180 / math.pi;
