// Esperimenti sull'ONESTA' del dato: risoluzione del DEM, buchi NaN,
// e tenuta della regola "cresta incerta" proposta dal piano.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:trailshare_flutter/core/utils/viewshed_compute.dart';
import 'real_ridges.dart' as rr;

const _earthRadiusM = 6371000.0;

double _hav(double lat1, double lng1, double lat2, double lng2) {
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return 2 * _earthRadiusM * math.asin(math.min(1.0, math.sqrt(a)));
}

/// Costruisce il coarse tenendo solo le tessere il cui CENTRO sta entro
/// [keepKm] dall'osservatore: simula "ho scaricato solo la zona vicina".
DemGrid buildPartial(String dir, double lat, double lng, double km, int zoom,
    double keepKm) {
  final latDelta = km / 111.0;
  final lngDelta = km / (111.0 * math.cos(lat * math.pi / 180));
  final drop = <String>{};
  final n = math.pow(2, zoom).toInt();
  final x0 = ((lng - lngDelta + 180) / 360 * n).floor();
  final x1 = ((lng + lngDelta + 180) / 360 * n).floor();
  for (var y = 0; y < n; y++) {
    // niente: iteriamo sulle tessere esistenti sul disco
  }
  for (final f in Directory(dir).listSync()) {
    final name = f.uri.pathSegments.last;
    if (!name.startsWith('${zoom}_') || !name.endsWith('.bin')) continue;
    final parts = name.replaceAll('.bin', '').split('_');
    final tx = int.parse(parts[1]), ty = int.parse(parts[2]);
    if (tx < x0 || tx > x1) continue;
    final t = rr.loadTile(dir, zoom, tx, ty)!;
    final cLat = (t.minLat + t.maxLat) / 2, cLng = (t.minLng + t.maxLng) / 2;
    if (_hav(lat, lng, cLat, cLng) > keepKm * 1000) {
      drop.add('${zoom}_${tx}_$ty');
    }
  }
  stdout.writeln('  tessere z$zoom scartate (oltre ${keepKm}km): ${drop.length}');
  return rr.build(dir, lat, lng, km, zoom, drop: drop)!;
}

void main(List<String> args) {
  final dir = args.isNotEmpty
      ? args[0]
      : '/private/tmp/claude-501/-Volumes-Lexar-Sviluppo-trailshare-flutter--claude-worktrees-compassionate-turing-9734eb/76f8d087-4230-41cb-b121-574c84473da4/scratchpad/tiles';
  const lat = 46.07152, lng = 10.01154;

  final coarse = rr.build(dir, lat, lng, 100.0, 10)!;
  final fine = rr.build(dir, lat, lng, 12.0, 12)!;
  final full = LayeredDem(coarse: coarse, fine: fine);
  final coarseOnly = LayeredDem(coarse: coarse);
  final ground = full.elevationAt(lat, lng);
  final eye = ground + 1.7;

  // ── E2: quanto cambia il DISEGNO se il terreno è a 105 m invece che a 26 m
  stdout.writeln('\n== E2  risoluzione: stesso punto, raggi 12 km');
  final a = rr.ridges(full, lat, lng, eye, 720, 12000);
  final b = rr.ridges(coarseOnly, lat, lng, eye, 720, 12000);
  var maxD = 0.0;
  final deltas = <double>[];
  for (var i = 0; i < 720; i++) {
    final x = a.last[i], y = b.last[i];
    if (x.isNaN || y.isNaN) continue;
    final d = (x - y).abs();
    deltas.add(d);
    if (d > maxD) maxD = d;
  }
  deltas.sort();
  stdout.writeln('creste con DEM 26 m: ${a.count}   con DEM 105 m: ${b.count}');
  stdout.writeln('orizzonte disegnato, differenza in gradi: '
      'mediana ${deltas[deltas.length ~/ 2].toStringAsFixed(3)} '
      'p90 ${deltas[(deltas.length * 0.9).floor()].toStringAsFixed(3)} '
      'max ${maxD.toStringAsFixed(3)}');
  // in pixel sul telefono del founder: 68,8 px per grado
  stdout.writeln('  in pixel a 68,8 px/grado: mediana '
      '${(deltas[deltas.length ~/ 2] * 68.8).round()} px, '
      'p90 ${(deltas[(deltas.length * 0.9).floor()] * 68.8).round()} px, '
      'max ${(maxD * 68.8).round()} px');

  // ── E3: copertura parziale (il caso offline vero) e regola "incerta"
  for (final keepKm in [30.0, 50.0]) {
    stdout.writeln('\n== E3  copertura parziale: scaricati solo ${keepKm.round()} km');
    final partialCoarse = buildPartial(dir, lat, lng, 100.0, 10, keepKm);
    var nan = 0;
    for (final v in partialCoarse.elevations) {
      if (v.isNaN) nan++;
    }
    stdout.writeln('  celle NaN nella griglia larga: '
        '${(nan * 100 / partialCoarse.elevations.length).toStringAsFixed(1)}%');
    final partial = LayeredDem(coarse: partialCoarse, fine: fine);
    final truth = rr.ridges(full, lat, lng, eye, 720, 100000);
    final holed = rr.ridges(partial, lat, lng, eye, 720, 100000);

    var wrong = 0, wrongFlagged = 0, flagged = 0, wrongBad = 0, wrongBadFlagged = 0;
    var maxErr = 0.0;
    for (var i = 0; i < 720; i++) {
      final cT = truth.offsets[i + 1] - truth.offsets[i];
      final cH = holed.offsets[i + 1] - holed.offsets[i];
      if (cT == 0 || cH == 0) continue;
      final tLast = truth.angles[truth.offsets[i + 1] - 1];
      final hLast = holed.angles[holed.offsets[i + 1] - 1];
      final unc = holed.uncertain[holed.offsets[i + 1] - 1] == 1;
      if (unc) flagged++;
      final err = (tLast - hLast).abs();
      if (err > 0.1) {
        wrong++;
        if (unc) wrongFlagged++;
        if (err > maxErr) maxErr = err;
      }
      if (err > 0.5) {
        wrongBad++;
        if (unc) wrongBadFlagged++;
      }
    }
    stdout.writeln('  orizzonte SBAGLIATO (>0,1°) su $wrong azimut su 720; '
        'di questi marcati incerti dalla regola del piano: $wrongFlagged');
    stdout.writeln('  orizzonte MOLTO sbagliato (>0,5°): $wrongBad, '
        'marcati incerti: $wrongBadFlagged');
    stdout.writeln('  azimut marcati incerti in totale: $flagged; '
        'errore massimo ${maxErr.toStringAsFixed(2)}°  '
        '(${(maxErr * 68.8).round()} px sullo schermo)');
  }

  // ── E4: la regola di emissione del piano, presa alla lettera
  stdout.writeln('\n== E4  regola di emissione "sale poi ridiscende", alla lettera');
  for (final spec in [
    [lat, lng, 100.0, 'vetta Pizzo Coca, raggio 100 km'],
    [lat, lng, 20.0, 'vetta Pizzo Coca, raggio 20 km (free)'],
    [46.0000, 10.0500, 20.0, 'fondovalle 46,00/10,05, raggio 20 km (free)'],
    [46.0000, 10.0500, 100.0, 'fondovalle 46,00/10,05, raggio 100 km'],
  ]) {
    final oLat = spec[0] as double, oLng = spec[1] as double;
    final km = spec[2] as double, name = spec[3] as String;
    final g = full.elevationAt(oLat, oLng);
    if (g.isNaN) {
      stdout.writeln('  $name: fuori DEM');
      continue;
    }
    final r = _endOfRayCount(full, oLat, oLng, g + 1.7, 720, km * 1000);
    stdout.writeln('  $name (quota ${g.round()} m): '
        'azimut in cui il massimo cade sull\'ULTIMO campione = ${r.$1} su 720 '
        '(${(r.$1 * 100 / 720).toStringAsFixed(1)}%) — '
        'senza lo scarico finale la linea dell\'orizzonte sparirebbe lì');
  }
}

/// Conta gli azimut in cui il ray-march termina mentre il terreno sta ancora
/// salendo: lì la regola "(a) supera il massimo e (b) poi ridiscende" non
/// emette nessuna cresta, e lo skyline derivato resta vuoto.
(int, int) _endOfRayCount(LayeredDem dem, double lat, double lng, double eye,
    int azSteps, double maxRange) {
  var rising = 0, total = 0;
  for (var a = 0; a < azSteps; a++) {
    final az = a * 360.0 / azSteps;
    var maxAngle = double.nan;
    var isRising = false;
    var d = dem.stepAt(0);
    while (d <= maxRange) {
      final pt = _dest(lat, lng, az, d);
      final e = dem.elevationAt(pt[0], pt[1]);
      if (!e.isNaN) {
        final ang = math.atan2(
                e - (1 - 0.13) * d * d / (2 * _earthRadiusM) - eye, d) *
            180 /
            math.pi;
        if (!(ang <= maxAngle)) {
          maxAngle = ang;
          isRising = true;
        } else if (isRising && ang < maxAngle - 0.06) {
          isRising = false;
        }
      }
      d += dem.stepAt(d);
    }
    total++;
    if (isRising) rising++;
  }
  return (rising, total);
}

List<double> _dest(double lat, double lng, double bearingDeg, double distanceM) {
  final phi1 = lat * math.pi / 180;
  final lambda1 = lng * math.pi / 180;
  final theta = bearingDeg * math.pi / 180;
  final delta = distanceM / _earthRadiusM;
  final phi2 = math.asin(math.sin(phi1) * math.cos(delta) +
      math.cos(phi1) * math.sin(delta) * math.cos(theta));
  final lambda2 = lambda1 +
      math.atan2(math.sin(theta) * math.sin(delta) * math.cos(phi1),
          math.cos(delta) - math.sin(phi1) * math.sin(phi2));
  return [phi2 * 180 / math.pi, ((lambda2 * 180 / math.pi) + 540) % 360 - 180];
}

// evita warning su import inutilizzato
final _keep = Float32List(0);
