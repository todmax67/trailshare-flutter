// Asimmetria: con la STESSA copertura parziale, le CIME risultano incerte e
// le CRESTE (regola del piano) no.
import 'dart:io';
import 'dart:math' as math;

import 'package:trailshare_flutter/core/utils/viewshed_compute.dart';
import 'real_ridges.dart' as rr;

const _R = 6371000.0;
double _hav(double a, double b, double c, double d) {
  final dl = (c - a) * math.pi / 180, dn = (d - b) * math.pi / 180;
  final x = math.sin(dl / 2) * math.sin(dl / 2) +
      math.cos(a * math.pi / 180) *
          math.cos(c * math.pi / 180) *
          math.sin(dn / 2) *
          math.sin(dn / 2);
  return 2 * _R * math.asin(math.min(1.0, math.sqrt(x)));
}

void main(List<String> args) {
  final dir = args[0];
  const lat = 46.07152, lng = 10.01154;
  final fine = rr.build(dir, lat, lng, 12.0, 12)!;

  // coarse con solo le tessere il cui centro sta entro 30 km
  final drop = <String>{};
  for (final f in Directory(dir).listSync()) {
    final n = f.uri.pathSegments.last;
    if (!n.startsWith('10_') || !n.endsWith('.bin')) continue;
    final p = n.replaceAll('.bin', '').split('_');
    final t = rr.loadTile(dir, 10, int.parse(p[1]), int.parse(p[2]));
    if (t == null) continue;
    if (_hav(lat, lng, (t.minLat + t.maxLat) / 2, (t.minLng + t.maxLng) / 2) >
        30000) {
      drop.add(n.replaceAll('.bin', ''));
    }
  }
  final coarse = rr.build(dir, lat, lng, 100.0, 10, drop: drop)!;
  final dem = LayeredDem(coarse: coarse, fine: fine);

  final peaks = <Map<String, dynamic>>[];
  for (final r in File('/tmp/peaks.csv').readAsLinesSync()) {
    final f = r.split(',');
    peaks.add({
      'id': f.length > 4 ? f[4] : f[0],
      'lat': double.parse(f[1]),
      'lng': double.parse(f[2]),
      'ele': double.parse(f[3]),
    });
  }
  final res = computeViewshed(ViewshedRequest(
    observerLat: lat,
    observerLng: lng,
    dem: dem,
    candidatePeaks: peaks,
    computeSkyline: false,
  ));
  final vis = res.peaks.where((p) => p.visible).toList();
  final unc = vis.where((p) => p.uncertain).length;
  stdout.writeln('CIME: ${vis.length} dichiarate visibili, di cui incerte $unc '
      '(${(unc * 100 / vis.length).toStringAsFixed(0)}%) '
      '-> hasPatchyTerrain=${unc * 4 > vis.length}');

  final ground = dem.elevationAt(lat, lng);
  final rf = rr.ridges(dem, lat, lng, ground + 1.7, 720, 100000);
  var u = 0;
  for (var i = 0; i < rf.count; i++) {
    if (rf.uncertain[i] == 1) u++;
  }
  stdout.writeln('CRESTE: ${rf.count} estratte, di cui incerte secondo la '
      'regola del piano: $u (${(u * 100 / rf.count).toStringAsFixed(0)}%)');
}
