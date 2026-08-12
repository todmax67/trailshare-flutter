// E5: quanto è vera la superficie che disegneremmo oltre la griglia fitta?
// Confronta la stratificazione DI PRODUZIONE (z12 entro 12 km, z10 oltre)
// con un DEM z12 ovunque fino a 30 km, sullo stesso punto e sugli stessi raggi.
import 'dart:io';
import 'dart:math' as math;

import 'package:trailshare_flutter/core/utils/viewshed_compute.dart';
import 'real_ridges.dart' as rr;

void main(List<String> args) {
  final dir = args[0];
  const lat = 46.07152, lng = 10.01154;
  const rangeM = 30000.0;

  final fine = rr.build(dir, lat, lng, 12.0, 12)!;
  final coarse10 = rr.build(dir, lat, lng, 100.0, 10)!;
  final coarse12 = rr.build(dir, lat, lng, 30.0, 12)!;

  final prod = LayeredDem(coarse: coarse10, fine: fine); // produzione
  final truth = LayeredDem(coarse: coarse12, fine: fine); // 26 m ovunque

  final ground = prod.elevationAt(lat, lng);
  final eye = ground + 1.7;
  stdout.writeln('coarse produzione cella ${coarse10.cellSizeMeters.toStringAsFixed(1)} m, '
      'step lontano ${prod.stepAt(20000).toStringAsFixed(1)} m');
  stdout.writeln('coarse riferimento cella ${coarse12.cellSizeMeters.toStringAsFixed(1)} m, '
      'step lontano ${truth.stepAt(20000).toStringAsFixed(1)} m');

  final a = rr.ridges(prod, lat, lng, eye, 720, rangeM);
  final b = rr.ridges(truth, lat, lng, eye, 720, rangeM);
  stdout.writeln('creste: produzione ${a.count}  riferimento ${b.count}');

  final d = <double>[];
  for (var i = 0; i < 720; i++) {
    final x = a.last[i], y = b.last[i];
    if (x.isNaN || y.isNaN) continue;
    d.add((x - y).abs());
  }
  d.sort();
  String px(double deg) => '${(deg * 68.8).round()} px';
  stdout.writeln('linea dell\'orizzonte, differenza fra i due DEM:');
  stdout.writeln('  mediana ${d[d.length ~/ 2].toStringAsFixed(3)}° (${px(d[d.length ~/ 2])})'
      '  p90 ${d[(d.length * .9).floor()].toStringAsFixed(3)}° (${px(d[(d.length * .9).floor()])})'
      '  max ${d.last.toStringAsFixed(3)}° (${px(d.last)})');

  // quanti azimut hanno un NUMERO DIVERSO di creste (= strati diversi disegnati)
  var diffCount = 0, sameCount = 0;
  for (var i = 0; i < 720; i++) {
    final ca = a.offsets[i + 1] - a.offsets[i];
    final cb = b.offsets[i + 1] - b.offsets[i];
    if (ca == cb) {
      sameCount++;
    } else {
      diffCount++;
    }
  }
  stdout.writeln('azimut con numero di creste diverso: $diffCount su 720 '
      '(uguale: $sameCount)');

  // Quanto sbaglia la QUOTA del DEM sulle vette note (smussamento).
  // Pizzo Coca 3050 m (OSM) — e qualche vetta vicina come controprova.
  const probes = [
    [46.07152, 10.01154, 3050.0, 'Pizzo Coca'],
    [46.05611, 9.99167, 3013.0, 'Pizzo Redorta'],
    [46.04722, 10.05833, 2872.0, 'Monte Gleno'],
  ];
  for (final p in probes) {
    final la = p[0] as double, lo = p[1] as double, real = p[2] as double;
    final z12 = fine.elevationAt(la, lo);
    final z10 = coarse10.elevationAt(la, lo);
    stdout.writeln('${p[3]}: OSM ${real.round()} m | DEM z12 ${z12.toStringAsFixed(0)} m '
        '(${(z12 - real).toStringAsFixed(0)}) | DEM z10 ${z10.toStringAsFixed(0)} m '
        '(${(z10 - real).toStringAsFixed(0)})');
  }
}
