// Verifica avversariale su TERRENO VERO (tessere terrarium scaricate).
// Replica esatta di terrain_tile_service._mosaic e usa il computeViewshed reale.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:trailshare_flutter/core/utils/viewshed_compute.dart';

/// Copia verbatim di terrain_tile_service.destinationRangeFor (che non si può
/// importare qui perché quel file tira dentro Flutter/Hive).
({int rowFrom, int rowTo, int colFrom, int colTo})? destinationRangeFor({
  required double gridMinLat,
  required double gridMaxLat,
  required double gridMinLng,
  required double gridMaxLng,
  required int rows,
  required int cols,
  required double tileMinLat,
  required double tileMaxLat,
  required double tileMinLng,
  required double tileMaxLng,
}) {
  final latSpan = gridMaxLat - gridMinLat;
  final lngSpan = gridMaxLng - gridMinLng;
  if (latSpan <= 0 || lngSpan <= 0 || rows < 2 || cols < 2) return null;
  final rowFrom = ((tileMinLat - gridMinLat) / latSpan * (rows - 1)).ceil();
  final rowTo = ((tileMaxLat - gridMinLat) / latSpan * (rows - 1)).floor();
  final colFrom = ((tileMinLng - gridMinLng) / lngSpan * (cols - 1)).ceil();
  final colTo = ((tileMaxLng - gridMinLng) / lngSpan * (cols - 1)).floor();
  if (rowFrom > rows - 1 || rowTo < 0 || colFrom > cols - 1 || colTo < 0) {
    return null;
  }
  final rf = rowFrom.clamp(0, rows - 1);
  final rt = rowTo.clamp(0, rows - 1);
  final cf = colFrom.clamp(0, cols - 1);
  final ct = colTo.clamp(0, cols - 1);
  if (rf > rt || cf > ct) return null;
  return (rowFrom: rf, rowTo: rt, colFrom: cf, colTo: ct);
}

const _earthRadiusM = 6371000.0;
const _refractionK = 0.13;
double _earthDrop(double d) => (1 - _refractionK) * d * d / (2 * _earthRadiusM);

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

class Tile {
  final int z, x, y, width, height;
  final double minLat, maxLat, minLng, maxLng;
  final Float32List ele;
  Tile(this.z, this.x, this.y, this.width, this.height, this.minLat, this.maxLat,
      this.minLng, this.maxLng, this.ele);
}

double _tileYToLat(int y, int zoom) {
  final n = math.pow(2, zoom).toDouble();
  final r = math.pi * (1 - 2 * y / n);
  final sh = (math.exp(r) - math.exp(-r)) / 2;
  return math.atan(sh) * 180 / math.pi;
}

int _latToTileY(double lat, int zoom) {
  final n = math.pow(2, zoom).toDouble();
  final r = lat * math.pi / 180;
  return ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n)
      .floor();
}

Tile? loadTile(String dir, int z, int x, int y) {
  final f = File('$dir/${z}_${x}_$y.bin');
  if (!f.existsSync()) return null;
  final b = f.readAsBytesSync();
  final bd = ByteData.sublistView(b);
  final w = bd.getInt32(0, Endian.little);
  final h = bd.getInt32(4, Endian.little);
  final ele = Float32List(w * h);
  for (var i = 0; i < w * h; i++) {
    ele[i] = bd.getFloat32(8 + i * 4, Endian.little);
  }
  final n = math.pow(2, z).toDouble();
  final lng0 = x / n * 360 - 180;
  final lng1 = (x + 1) / n * 360 - 180;
  final lat0 = _tileYToLat(y, z);
  final lat1 = _tileYToLat(y + 1, z);
  return Tile(z, x, y, w, h, math.min(lat0, lat1), math.max(lat0, lat1), lng0,
      lng1, ele);
}

/// Copia fedele di terrain_tile_service._mosaic.
DemGrid mosaic(List<Tile> tiles,
    {required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
    required int zoom,
    Set<String>? drop}) {
  final tileCount = math.pow(2, zoom).toInt();
  final lngPx = (360.0 / tileCount) / tiles.first.width;
  final first = tiles.first;
  final latPx = (first.maxLat - first.minLat) / first.height;
  final cols = math.max(2, ((maxLng - minLng) / lngPx).round());
  final rows = math.max(2, ((maxLat - minLat) / latPx).round());
  final out = Float32List(rows * cols)..fillRange(0, rows * cols, double.nan);
  final grid = DemGrid(
      minLat: minLat,
      maxLat: maxLat,
      minLng: minLng,
      maxLng: maxLng,
      rows: rows,
      cols: cols,
      elevations: out);
  for (final tile in tiles) {
    if (drop != null && drop.contains('${tile.z}_${tile.x}_${tile.y}')) continue;
    final r = destinationRangeFor(
        gridMinLat: minLat,
        gridMaxLat: maxLat,
        gridMinLng: minLng,
        gridMaxLng: maxLng,
        rows: rows,
        cols: cols,
        tileMinLat: tile.minLat,
        tileMaxLat: tile.maxLat,
        tileMinLng: tile.minLng,
        tileMaxLng: tile.maxLng);
    if (r == null) continue;
    final tLatSpan = tile.maxLat - tile.minLat;
    final tLngSpan = tile.maxLng - tile.minLng;
    for (var row = r.rowFrom; row <= r.rowTo; row++) {
      final lat = grid.latForRow(row);
      final fy = (tile.maxLat - lat) / tLatSpan * (tile.height - 1);
      final ry = fy.round().clamp(0, tile.height - 1);
      final rowBase = ry * tile.width;
      final outBase = row * cols;
      for (var c = r.colFrom; c <= r.colTo; c++) {
        final lng = grid.lngForCol(c);
        final fx = (lng - tile.minLng) / tLngSpan * (tile.width - 1);
        final rx = fx.round().clamp(0, tile.width - 1);
        out[outBase + c] = tile.ele[rowBase + rx];
      }
    }
  }
  return grid;
}

DemGrid? build(String dir, double lat, double lng, double km, int zoom,
    {Set<String>? drop}) {
  final latDelta = km / 111.0;
  final lngDelta = km / (111.0 * math.cos(lat * math.pi / 180));
  final minLat = lat - latDelta, maxLat = lat + latDelta;
  final minLng = lng - lngDelta, maxLng = lng + lngDelta;
  final n = math.pow(2, zoom).toInt();
  final x0 = ((minLng + 180) / 360 * n).floor().clamp(0, n - 1);
  final x1 = ((maxLng + 180) / 360 * n).floor().clamp(0, n - 1);
  final y0 = _latToTileY(maxLat, zoom).clamp(0, n - 1);
  final y1 = _latToTileY(minLat, zoom).clamp(0, n - 1);
  final tiles = <Tile>[];
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      final t = loadTile(dir, zoom, x, y);
      if (t != null) tiles.add(t);
    }
  }
  if (tiles.isEmpty) return null;
  stdout.writeln('  z$zoom: ${tiles.length} tessere caricate');
  return mosaic(tiles,
      minLat: minLat,
      maxLat: maxLat,
      minLng: minLng,
      maxLng: maxLng,
      zoom: zoom,
      drop: drop);
}

class Ridges {
  final Float32List angles, dists;
  final Uint8List uncertain;
  final Int32List offsets;
  final int count;
  final Float32List last;
  Ridges(this.angles, this.dists, this.uncertain, this.offsets, this.count,
      this.last);
}

/// Estrazione creste secondo la specifica del piano.
Ridges ridges(LayeredDem dem, double lat, double lng, double eye, int azSteps,
    double maxRange,
    {double prom = 0.06, double stepScale = 1.0}) {
  final cap = azSteps * 32;
  final angles = Float32List(cap);
  final dists = Float32List(cap);
  final unc = Uint8List(cap);
  final offsets = Int32List(azSteps + 1);
  final last = Float32List(azSteps)..fillRange(0, azSteps, double.nan);
  var n = 0;
  for (var a = 0; a < azSteps; a++) {
    offsets[a] = n;
    final az = a * 360.0 / azSteps;
    var maxAngle = double.nan;
    var pendA = double.nan, pendD = 0.0;
    var rising = false, sawNan = false, pendNan = false;
    var d = dem.stepAt(0) * stepScale;
    while (d <= maxRange) {
      final pt = _dest(lat, lng, az, d);
      final e = dem.elevationAt(pt[0], pt[1]);
      if (e.isNaN) {
        sawNan = true;
      } else {
        final ang = math.atan2(e - _earthDrop(d) - eye, d) * 180 / math.pi;
        if (!(ang <= maxAngle)) {
          maxAngle = ang;
          pendA = ang;
          pendD = d;
          pendNan = sawNan;
          rising = true;
        } else if (rising && ang < pendA - prom) {
          if (n < cap) {
            angles[n] = pendA;
            dists[n] = pendD;
            unc[n] = pendNan ? 1 : 0;
            n++;
          }
          rising = false;
        }
      }
      d += dem.stepAt(d) * stepScale;
    }
    if (rising && n < cap) {
      angles[n] = pendA;
      dists[n] = pendD;
      unc[n] = pendNan ? 1 : 0;
      n++;
    }
    last[a] = maxAngle;
  }
  offsets[azSteps] = n;
  return Ridges(angles, dists, unc, offsets, n, last);
}

void main(List<String> args) {
  final dir = args.isNotEmpty
      ? args[0]
      : '/private/tmp/claude-501/-Volumes-Lexar-Sviluppo-trailshare-flutter--claude-worktrees-compassionate-turing-9734eb/76f8d087-4230-41cb-b121-574c84473da4/scratchpad/tiles';
  const lat = 46.07152, lng = 10.01154;
  final radiusKm = args.length > 1 ? double.parse(args[1]) : 100.0;
  final rayKm = args.length > 2 ? double.parse(args[2]) : 60.0;

  stdout.writeln('== DEM da tessere VERE, Pizzo Coca $lat/$lng');
  final coarse = build(dir, lat, lng, radiusKm, 10)!;
  final fine = build(dir, lat, lng, 12.0, 12)!;
  final dem = LayeredDem(coarse: coarse, fine: fine);
  var nan = 0;
  for (final v in coarse.elevations) {
    if (v.isNaN) nan++;
  }
  stdout.writeln('coarse ${coarse.rows}x${coarse.cols} '
      '(${(coarse.rows * coarse.cols * 4 / 1e6).toStringAsFixed(1)} MB) '
      'cella ${coarse.cellSizeMeters.toStringAsFixed(1)} m  NaN=${(nan * 100 / coarse.elevations.length).toStringAsFixed(2)}%');
  stdout.writeln('fine   ${fine.rows}x${fine.cols} cella '
      '${fine.cellSizeMeters.toStringAsFixed(1)} m');

  final ground = dem.elevationAt(lat, lng);
  final eye = ground + 1.7;
  stdout.writeln('quota DEM sotto l\'osservatore: ${ground.toStringAsFixed(1)} m');
  var samples = 0;
  var d = dem.stepAt(0);
  while (d <= rayKm * 1000) {
    samples++;
    d += dem.stepAt(d);
  }
  stdout.writeln('campioni per raggio a ${rayKm}km: $samples  '
      'step(0)=${dem.stepAt(0).toStringAsFixed(1)} step(30k)=${dem.stepAt(30000).toStringAsFixed(1)}');

  final req = ViewshedRequest(
      observerLat: lat,
      observerLng: lng,
      dem: dem,
      candidatePeaks: const [],
      computeSkyline: true,
      azimuthSteps: 720,
      skylineRadiusM: rayKm * 1000);

  // warmup di entrambi
  computeViewshed(req);
  ridges(dem, lat, lng, eye, 720, rayKm * 1000);

  final skyT = <int>[], ridT = <int>[];
  List<double> sky = const [];
  Ridges? rf;
  for (var i = 0; i < 6; i++) {
    if (i.isEven) {
      var sw = Stopwatch()..start();
      sky = computeViewshed(req).skylineAngles;
      skyT.add(sw.elapsedMicroseconds);
      sw = Stopwatch()..start();
      rf = ridges(dem, lat, lng, eye, 720, rayKm * 1000);
      ridT.add(sw.elapsedMicroseconds);
    } else {
      var sw = Stopwatch()..start();
      rf = ridges(dem, lat, lng, eye, 720, rayKm * 1000);
      ridT.add(sw.elapsedMicroseconds);
      sw = Stopwatch()..start();
      sky = computeViewshed(req).skylineAngles;
      skyT.add(sw.elapsedMicroseconds);
    }
  }
  String ms(List<int> t) {
    final s = [...t]..sort();
    return 'mediana ${(s[s.length ~/ 2] / 1000).toStringAsFixed(1)} ms '
        '[${t.map((e) => (e / 1000).toStringAsFixed(0)).join(',')}]';
  }

  stdout.writeln('SKYLINE (codice reale): ${ms(skyT)}');
  stdout.writeln('CRESTE  (stessa marcia): ${ms(ridT)}');

  final f = rf!;
  var maxDelta = 0.0, mismatch = 0, empty = 0, uncertainN = 0;
  final hist = <int, int>{};
  for (var a = 0; a < 720; a++) {
    final cnt = f.offsets[a + 1] - f.offsets[a];
    hist[cnt] = (hist[cnt] ?? 0) + 1;
    if (cnt == 0) empty++;
    final lastR = cnt == 0 ? double.nan : f.angles[f.offsets[a + 1] - 1];
    final s = sky[a];
    if (s.isNaN && lastR.isNaN) continue;
    if (s.isNaN != lastR.isNaN) {
      mismatch++;
      continue;
    }
    final dd = (s - lastR).abs();
    if (dd > maxDelta) maxDelta = dd;
    if (dd > 0.001) mismatch++;
  }
  for (var i = 0; i < f.count; i++) {
    if (f.uncertain[i] == 1) uncertainN++;
  }
  stdout.writeln('creste=${f.count} media/az=${(f.count / 720).toStringAsFixed(2)} '
      'azimut senza creste=$empty incerte=$uncertainN');
  stdout.writeln('ultima cresta vs skyline: scarto max ${maxDelta.toStringAsFixed(4)}° '
      'azimut discordanti=$mismatch');
  final keys = hist.keys.toList()..sort();
  stdout.writeln('istogramma creste:azimut ${keys.map((k) => '$k:${hist[k]}').join(' ')}');

  // ── sensibilità al passo: le creste sono terreno o rumore di campionamento?
  for (final s in [0.5, 0.25]) {
    final r2 = ridges(dem, lat, lng, eye, 720, rayKm * 1000, stepScale: s);
    stdout.writeln('passo x$s -> creste=${r2.count} '
        'media/az=${(r2.count / 720).toStringAsFixed(2)}');
  }
  // ── sensibilità alla soglia di prominenza
  for (final p in [0.03, 0.12, 0.25]) {
    final r2 = ridges(dem, lat, lng, eye, 720, rayKm * 1000, prom: p);
    stdout.writeln('prominenza ${p}° -> creste=${r2.count} '
        'media/az=${(r2.count / 720).toStringAsFixed(2)}');
  }
}
