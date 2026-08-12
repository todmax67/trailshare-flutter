/// Dove stanno il sole e la luna nel cielo, visti da un punto e in un istante.
///
/// Serve al Peak Finder per rispondere alla domanda che si fa chi va in
/// montagna a fotografare: *dietro quale cima tramonta il sole stasera?* È una
/// funzione di punta dei concorrenti, e a differenza del terreno non richiede
/// né rete né dati scaricati — sono formule.
///
/// **Precisione dichiarata.** Il sole è calcolato con l'algoritmo NOAA a bassa
/// precisione: qualche primo d'arco, cioè molto meglio di quanto serva per dire
/// dietro quale montagna sparisce. La luna usa i termini principali della serie
/// di Meeus e vale circa mezzo grado — abbastanza per sapere dove sorge, non per
/// prevedere un'occultazione. Nessuna delle due include la rifrazione
/// atmosferica se non nella soglia di alba e tramonto, dove è convenzione.
library;

import 'dart:math' as math;

/// Posizione di un astro nel cielo dell'osservatore.
class SkyPosition {
  /// Azimut in gradi, 0 = nord, 90 = est.
  final double azimuthDeg;

  /// Altezza sull'orizzonte in gradi. Negativa quando è sotto.
  final double elevationDeg;

  const SkyPosition({required this.azimuthDeg, required this.elevationDeg});

  bool get isAboveHorizon => elevationDeg > 0;

  @override
  String toString() => 'az ${azimuthDeg.toStringAsFixed(1)}°, '
      'alt ${elevationDeg.toStringAsFixed(1)}°';
}

/// Un istante lungo il cammino di un astro.
class SkyTrackPoint {
  final DateTime time;
  final SkyPosition position;
  const SkyTrackPoint({required this.time, required this.position});
}

/// Giorni giuliani dall'epoca J2000.0.
double _daysSinceJ2000(DateTime utc) =>
    utc.toUtc().millisecondsSinceEpoch / 86400000.0 + 2440587.5 - 2451545.0;

const double _deg = math.pi / 180;

double _norm360(double d) {
  final r = d % 360;
  return r < 0 ? r + 360 : r;
}

/// Da coordinate equatoriali (ascensione retta, declinazione) a orizzontali.
///
/// L'azimut esce **dal nord in senso orario**, che è la convenzione usata da
/// tutto il resto del Peak Finder: mischiare qui la convenzione "dal sud" degli
/// almanacchi astronomici significherebbe disegnare il sole a 180° dal punto in
/// cui sta.
SkyPosition _equatorialToHorizontal({
  required double rightAscensionDeg,
  required double declinationDeg,
  required double siderealTimeDeg,
  required double latDeg,
}) {
  final hourAngle = (siderealTimeDeg - rightAscensionDeg) * _deg;
  final dec = declinationDeg * _deg;
  final lat = latDeg * _deg;

  final sinAlt = math.sin(dec) * math.sin(lat) +
      math.cos(dec) * math.cos(lat) * math.cos(hourAngle);
  final alt = math.asin(sinAlt.clamp(-1.0, 1.0));

  final cosAz = (math.sin(dec) - sinAlt * math.sin(lat)) /
      (math.cos(alt) * math.cos(lat));
  var az = math.acos(cosAz.clamp(-1.0, 1.0)) / _deg;
  if (math.sin(hourAngle) > 0) az = 360 - az;

  return SkyPosition(azimuthDeg: _norm360(az), elevationDeg: alt / _deg);
}

/// Tempo siderale locale in gradi.
double _localSiderealDeg(double d, double lngDeg) {
  final gmstHours = 18.697374558 + 24.06570982441908 * d;
  return _norm360(gmstHours * 15 + lngDeg);
}

/// Obliquità dell'eclittica in gradi.
double _obliquityDeg(double d) => 23.439 - 0.0000004 * d;

/// Longitudine eclittica del sole in gradi, e anomalia media (serve alla luna).
({double lambda, double meanAnomaly}) _sunEcliptic(double d) {
  final meanLongitude = 280.460 + 0.9856474 * d;
  final meanAnomaly = (357.528 + 0.9856003 * d) * _deg;
  final lambda = meanLongitude +
      1.915 * math.sin(meanAnomaly) +
      0.020 * math.sin(2 * meanAnomaly);
  return (lambda: _norm360(lambda), meanAnomaly: meanAnomaly);
}

/// Posizione del sole vista da (lat, lng) all'istante [utc].
SkyPosition sunPosition(DateTime utc, double latDeg, double lngDeg) {
  final d = _daysSinceJ2000(utc);
  final sun = _sunEcliptic(d);
  final lambda = sun.lambda * _deg;
  final eps = _obliquityDeg(d) * _deg;

  final ra = math.atan2(math.cos(eps) * math.sin(lambda), math.cos(lambda)) / _deg;
  final dec = math.asin(math.sin(eps) * math.sin(lambda)) / _deg;

  return _equatorialToHorizontal(
    rightAscensionDeg: _norm360(ra),
    declinationDeg: dec,
    siderealTimeDeg: _localSiderealDeg(d, lngDeg),
    latDeg: latDeg,
  );
}

/// Posizione della luna, con la frazione illuminata del disco.
({SkyPosition position, double illuminatedFraction}) moonPosition(
  DateTime utc,
  double latDeg,
  double lngDeg,
) {
  final d = _daysSinceJ2000(utc);

  // Termini principali della serie lunare: bastano per dire dove sorge.
  final meanLongitude = 218.316 + 13.176396 * d;
  final meanAnomaly = (134.963 + 13.064993 * d) * _deg;
  final meanDistance = (93.272 + 13.229350 * d) * _deg;

  final lambda = (meanLongitude + 6.289 * math.sin(meanAnomaly)) * _deg;
  final beta = 5.128 * math.sin(meanDistance) * _deg;
  final eps = _obliquityDeg(d) * _deg;

  final ra = math.atan2(
        math.sin(lambda) * math.cos(eps) - math.tan(beta) * math.sin(eps),
        math.cos(lambda),
      ) /
      _deg;
  final dec = math.asin(
        math.sin(beta) * math.cos(eps) +
            math.cos(beta) * math.sin(eps) * math.sin(lambda),
      ) /
      _deg;

  final position = _equatorialToHorizontal(
    rightAscensionDeg: _norm360(ra),
    declinationDeg: dec,
    siderealTimeDeg: _localSiderealDeg(d, lngDeg),
    latDeg: latDeg,
  );

  // Frazione illuminata dall'elongazione dal sole. Approssimazione geometrica:
  // la luna piena è quando è opposta al sole.
  final sunLambda = _sunEcliptic(d).lambda * _deg;
  final elongation = math.acos(
    (math.cos(beta) * math.cos(lambda - sunLambda)).clamp(-1.0, 1.0),
  );
  final fraction = (1 - math.cos(elongation)) / 2;

  return (position: position, illuminatedFraction: fraction.clamp(0.0, 1.0));
}

/// Il cammino del sole in un giorno, campionato ogni [stepMinutes].
///
/// [dayLocalMidnightUtc] è la mezzanotte locale espressa in UTC: si passa già
/// convertita perché il fuso orario è una faccenda della UI, non
/// dell'astronomia.
List<SkyTrackPoint> sunTrack(
  DateTime dayLocalMidnightUtc,
  double latDeg,
  double lngDeg, {
  int stepMinutes = 10,
}) {
  final out = <SkyTrackPoint>[];
  for (var m = 0; m <= 24 * 60; m += stepMinutes) {
    final t = dayLocalMidnightUtc.add(Duration(minutes: m));
    out.add(SkyTrackPoint(time: t, position: sunPosition(t, latDeg, lngDeg)));
  }
  return out;
}

/// Cammino della luna, stessa convenzione di [sunTrack].
List<SkyTrackPoint> moonTrack(
  DateTime dayLocalMidnightUtc,
  double latDeg,
  double lngDeg, {
  int stepMinutes = 10,
}) {
  final out = <SkyTrackPoint>[];
  for (var m = 0; m <= 24 * 60; m += stepMinutes) {
    final t = dayLocalMidnightUtc.add(Duration(minutes: m));
    out.add(SkyTrackPoint(
      time: t,
      position: moonPosition(t, latDeg, lngDeg).position,
    ));
  }
  return out;
}

/// Fase lunare: quanto disco è illuminato, e se sta crescendo o calando.
///
/// Non dipende da dove si guarda — è geometria fra Terra, Sole e Luna — quindi
/// non chiede una posizione. Il verso si ricava confrontando due istanti: se fra
/// sei ore ce n'è di più, è crescente.
({double fraction, bool waxing}) moonPhase(DateTime utc) {
  final now = moonPosition(utc, 0, 0).illuminatedFraction;
  final later =
      moonPosition(utc.add(const Duration(hours: 6)), 0, 0).illuminatedFraction;
  return (fraction: now, waxing: later > now);
}

/// Nome italiano della fase, dalle otto convenzionali.
String moonPhaseLabel(({double fraction, bool waxing}) phase) {
  final f = phase.fraction;
  if (f < 0.04) return 'luna nuova';
  if (f > 0.96) return 'luna piena';
  if (f < 0.46) return phase.waxing ? 'falce crescente' : 'falce calante';
  if (f < 0.54) return phase.waxing ? 'primo quarto' : 'ultimo quarto';
  return phase.waxing ? 'gibbosa crescente' : 'gibbosa calante';
}

/// Il momento in cui un astro **scompare dietro il terreno**, o ne riemerge.
///
/// È una cosa diversa dal tramonto da almanacco: in montagna il sole sparisce
/// dietro una cresta anche mezz'ora prima dell'orizzonte teorico, ed è
/// esattamente questo l'istante che interessa a chi fotografa.
///
/// [horizonElevationDeg] restituisce l'altezza del terreno a un dato azimut, e
/// `NaN` dove non la conosciamo: dove il terreno è ignoto non si dichiara nessun
/// tramonto, perché sarebbe inventato.
({DateTime time, double azimuthDeg, double elevationDeg})? horizonCrossing(
  List<SkyTrackPoint> track,
  double Function(double azimuthDeg) horizonElevationDeg, {
  /// `true` per la sparizione dietro la cresta, `false` per la ricomparsa.
  bool descending = true,

  /// Da quale istante in poi cercare. Serve a chiedere «il prossimo tramonto»
  /// e non quello di stamattina.
  DateTime? after,
}) {
  bool? wasAbove;
  for (final p in track) {
    if (after != null && p.time.isBefore(after)) continue;
    final ground = horizonElevationDeg(p.position.azimuthDeg);
    if (ground.isNaN) {
      // Terreno ignoto a questo azimut: si interrompe la continuità invece di
      // far finta che l'orizzonte sia piatto.
      wasAbove = null;
      continue;
    }
    final above = p.position.elevationDeg > ground;
    if (wasAbove != null && wasAbove != above && above != descending) {
      return (
        time: p.time,
        azimuthDeg: p.position.azimuthDeg,
        elevationDeg: p.position.elevationDeg,
      );
    }
    wasAbove = above;
  }
  return null;
}

/// Soglia convenzionale di alba e tramonto: il disco solare tocca l'orizzonte
/// quando il suo centro è mezzo grado sotto, e la rifrazione atmosferica lo
/// solleva di altri 34 primi.
const double sunriseElevationDeg = -0.833;

/// Alba e tramonto **astronomici**, cioè rispetto a un orizzonte piatto.
///
/// In montagna il sole scompare dietro una cresta molto prima: per quello serve
/// incrociare il cammino con il profilo del terreno, che è ciò che fa il
/// panorama. Questi due valori restano utili come riferimento.
({DateTime? sunrise, DateTime? sunset}) sunriseSunset(
  DateTime dayLocalMidnightUtc,
  double latDeg,
  double lngDeg,
) {
  final track = sunTrack(dayLocalMidnightUtc, latDeg, lngDeg, stepMinutes: 2);
  DateTime? rise;
  DateTime? set;
  for (var i = 1; i < track.length; i++) {
    final a = track[i - 1].position.elevationDeg;
    final b = track[i].position.elevationDeg;
    if (a <= sunriseElevationDeg && b > sunriseElevationDeg) {
      rise ??= track[i].time;
    }
    if (a > sunriseElevationDeg && b <= sunriseElevationDeg) {
      set ??= track[i].time;
    }
  }
  return (sunrise: rise, sunset: set);
}
