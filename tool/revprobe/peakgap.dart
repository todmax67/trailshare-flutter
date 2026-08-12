// Di quanto la superficie che disegneremmo passa SOTTO le etichette delle cime.
// Usa le cime vere del dataset dell'app e il DEM stratificato di produzione.
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
  final coarse = rr.build(dir, lat, lng, 100.0, 10)!;
  final dem = LayeredDem(coarse: coarse, fine: fine);

  final rows = File('/tmp/peaks.csv').readAsLinesSync();
  final buckets = <String, List<double>>{};
  final angBuckets = <String, List<double>>{};
  for (final r in rows) {
    final f = r.split(',');
    final d = double.parse(f[0]);
    if (d < 300) continue;
    final pl = double.parse(f[1]), pg = double.parse(f[2]);
    final ele = double.parse(f[3]);
    final demE = dem.elevationAt(pl, pg);
    if (demE.isNaN) continue;
    final gap = ele - demE; // >0 = il DEM sta SOTTO la quota della cima
    // di quanti gradi, visti dall'occhio, la linea passa sotto l'etichetta
    final angErr = math.atan2(gap, d) * 180 / math.pi;
    final key = d < 5000
        ? 'a <5 km'
        : d < 12000
            ? 'b 5-12 km (griglia fitta)'
            : d < 25000
                ? 'c 12-25 km (solo z10)'
                : d < 60000
                    ? 'd 25-60 km (solo z10)'
                    : 'e';
    (buckets[key] ??= []).add(gap);
    (angBuckets[key] ??= []).add(angErr);
  }
  final keys = buckets.keys.toList()..sort();
  stdout.writeln('scarto quota DEM vs quota del dataset, per distanza:');
  for (final k in keys) {
    final v = buckets[k]!..sort();
    final a = angBuckets[k]!..sort();
    double med(List<double> l) => l[l.length ~/ 2];
    double p90(List<double> l) => l[(l.length * .9).floor()];
    stdout.writeln('  $k  n=${v.length}  '
        'mediana ${med(v).toStringAsFixed(0)} m  p90 ${p90(v).toStringAsFixed(0)} m  '
        '| in gradi: mediana ${med(a).toStringAsFixed(2)}° '
        '(${(med(a) * 68.8).round()} px)  p90 ${p90(a).toStringAsFixed(2)}° '
        '(${(p90(a) * 68.8).round()} px)');
  }
}
