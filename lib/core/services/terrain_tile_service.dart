import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../utils/viewshed_compute.dart';

/// Fetch e decode di tile DEM da AWS Open Terrain Tiles.
///
/// Endpoint:
///   https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png
///
/// Formato Terrarium (Mapzen): PNG RGB con elevazione codificata:
///   elevation = (R*256 + G + B/256) - 32768
///
/// Cache: in-memory LRU (max 64 tile = ~16 MB se 256x256 PNG). Persistent
/// cache opzionale per utenti Pro (Hive) viene aggiunta in step successivo.
class TerrainTileService {
  TerrainTileService._();
  static final TerrainTileService _instance = TerrainTileService._();
  factory TerrainTileService() => _instance;

  static const String _tileBase =
      'https://s3.amazonaws.com/elevation-tiles-prod/terrarium';

  /// LRU cache in-memory: key = "z/x/y" → griglia 256×256 di quote.
  final _memCache = <String, _DemTile>{};
  final _memCacheOrder = <String>[];
  static const int _memCacheLimit = 64;

  final _inflight = <String, Future<_DemTile?>>{};

  /// Default zoom: 12 = ~38 m/pixel all'equatore, scende a ~25-30 m/pixel
  /// in Italia. Buon compromesso perf/qualità per skyline a 50-100 km.
  static const int defaultZoom = 12;

  /// Costruisce un [DemGrid] coprente la bbox richiesta scaricando i tile
  /// terrarium necessari e mosaicandoli in una griglia unica.
  ///
  /// [maxResolutionMeters] usato per scegliere automaticamente lo zoom: più
  /// alto = meno tile (più veloce, meno preciso).
  Future<DemGrid?> buildDemGrid({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
    int zoom = defaultZoom,
  }) async {
    final tiles = _tilesInBbox(
      minLat: minLat,
      maxLat: maxLat,
      minLng: minLng,
      maxLng: maxLng,
      zoom: zoom,
    );

    if (tiles.isEmpty) return null;

    // Fetch parallelo (ma cap a 8 concurrent per non saturare AWS).
    final fetched = <_DemTile>[];
    final batchSize = 8;
    for (int i = 0; i < tiles.length; i += batchSize) {
      final batch = tiles
          .skip(i)
          .take(batchSize)
          .map((t) => _fetchTile(t[0], t[1], t[2]));
      final results = await Future.wait(batch);
      for (final r in results) {
        if (r != null) fetched.add(r);
      }
    }

    if (fetched.isEmpty) return null;

    // Mosaico: trova bbox totale dei tile, crea griglia destinazione
    // sufficientemente densa, riempi pixel-by-pixel con lookup nearest tile.
    return _mosaic(fetched);
  }

  Future<_DemTile?> _fetchTile(int z, int x, int y) async {
    final key = '$z/$x/$y';
    final cached = _memCache[key];
    if (cached != null) {
      _touchCache(key);
      return cached;
    }
    if (_inflight.containsKey(key)) return _inflight[key]!;

    final fut = _doFetch(z, x, y);
    _inflight[key] = fut;
    final result = await fut;
    _inflight.remove(key);
    if (result != null) _putCache(key, result);
    return result;
  }

  Future<_DemTile?> _doFetch(int z, int x, int y) async {
    final url = '$_tileBase/$z/$x/$y.png';
    try {
      final resp = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) {
        debugPrint('[Terrain] $z/$x/$y → ${resp.statusCode}');
        return null;
      }
      return await _decode(resp.bodyBytes, z, x, y);
    } on TimeoutException {
      debugPrint('[Terrain] timeout $z/$x/$y');
      return null;
    } on SocketException catch (e) {
      debugPrint('[Terrain] socket $z/$x/$y: $e');
      return null;
    } catch (e) {
      debugPrint('[Terrain] error $z/$x/$y: $e');
      return null;
    }
  }

  Future<_DemTile?> _decode(Uint8List bytes, int z, int x, int y) async {
    final image = img.decodePng(bytes);
    if (image == null) return null;
    final w = image.width;
    final h = image.height;
    final ele = Float32List(w * h);
    for (int row = 0; row < h; row++) {
      for (int col = 0; col < w; col++) {
        final p = image.getPixel(col, row);
        final r = p.r.toDouble();
        final g = p.g.toDouble();
        final b = p.b.toDouble();
        ele[row * w + col] = (r * 256 + g + b / 256) - 32768;
      }
    }
    final bbox = _tileBbox(z, x, y);
    return _DemTile(
      z: z, x: x, y: y,
      width: w, height: h,
      minLat: bbox[0], maxLat: bbox[1], minLng: bbox[2], maxLng: bbox[3],
      elevations: ele,
    );
  }

  void _putCache(String key, _DemTile tile) {
    _memCache[key] = tile;
    _memCacheOrder.add(key);
    if (_memCacheOrder.length > _memCacheLimit) {
      final evicted = _memCacheOrder.removeAt(0);
      _memCache.remove(evicted);
    }
  }

  void _touchCache(String key) {
    _memCacheOrder.remove(key);
    _memCacheOrder.add(key);
  }

  /// Combina più tile in una griglia DemGrid unica con risoluzione uniforme.
  /// La risoluzione output combacia con quella dei tile (256 px per tile).
  DemGrid _mosaic(List<_DemTile> tiles) {
    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;
    for (final t in tiles) {
      if (t.minLat < minLat) minLat = t.minLat;
      if (t.maxLat > maxLat) maxLat = t.maxLat;
      if (t.minLng < minLng) minLng = t.minLng;
      if (t.maxLng > maxLng) maxLng = t.maxLng;
    }
    // Pixel size: usa lo stesso dei tile (tutti hanno stesso zoom).
    final z = tiles.first.z;
    final tileCount = math.pow(2, z).toInt();
    final lngRangePerTile = 360.0 / tileCount;
    final px = lngRangePerTile / tiles.first.width;
    final cols = ((maxLng - minLng) / px).round();
    final rows = ((maxLat - minLat) / px).round(); // approssimato (latitudine)
    final out = Float32List(rows * cols);

    // Per ogni cella destinazione, trova il tile contenente e fai sampling.
    for (int r = 0; r < rows; r++) {
      final lat = maxLat - (r + 0.5) * (maxLat - minLat) / rows;
      for (int c = 0; c < cols; c++) {
        final lng = minLng + (c + 0.5) * (maxLng - minLng) / cols;
        final tile = _findTile(tiles, lat, lng);
        if (tile == null) continue;
        final fy = (tile.maxLat - lat) / (tile.maxLat - tile.minLat) * (tile.height - 1);
        final fx = (lng - tile.minLng) / (tile.maxLng - tile.minLng) * (tile.width - 1);
        final ry = fy.round().clamp(0, tile.height - 1);
        final rx = fx.round().clamp(0, tile.width - 1);
        out[r * cols + c] = tile.elevations[ry * tile.width + rx];
      }
    }

    return DemGrid(
      minLat: minLat, maxLat: maxLat,
      minLng: minLng, maxLng: maxLng,
      rows: rows, cols: cols,
      elevations: out.toList(growable: false),
    );
  }

  _DemTile? _findTile(List<_DemTile> tiles, double lat, double lng) {
    for (final t in tiles) {
      if (lat >= t.minLat && lat <= t.maxLat &&
          lng >= t.minLng && lng <= t.maxLng) {
        return t;
      }
    }
    return null;
  }

  // ── XYZ tile math ────────────────────────────────────────────────────

  List<List<int>> _tilesInBbox({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
    required int zoom,
  }) {
    final n = math.pow(2, zoom).toInt();
    final x0 = ((minLng + 180) / 360 * n).floor().clamp(0, n - 1);
    final x1 = ((maxLng + 180) / 360 * n).floor().clamp(0, n - 1);
    final y0 = _latToTileY(maxLat, zoom).clamp(0, n - 1);
    final y1 = _latToTileY(minLat, zoom).clamp(0, n - 1);
    final out = <List<int>>[];
    for (int y = y0; y <= y1; y++) {
      for (int x = x0; x <= x1; x++) {
        out.add([zoom, x, y]);
      }
    }
    return out;
  }

  int _latToTileY(double lat, int zoom) {
    final n = math.pow(2, zoom).toDouble();
    final r = lat * math.pi / 180;
    return ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n).floor();
  }

  List<double> _tileBbox(int z, int x, int y) {
    final n = math.pow(2, z).toDouble();
    final lng0 = x / n * 360 - 180;
    final lng1 = (x + 1) / n * 360 - 180;
    final lat0 = _tileYToLat(y, z);
    final lat1 = _tileYToLat(y + 1, z);
    return [math.min(lat0, lat1), math.max(lat0, lat1), lng0, lng1];
  }

  double _tileYToLat(int y, int zoom) {
    final n = math.pow(2, zoom).toDouble();
    final r = math.pi * (1 - 2 * y / n);
    return math.atan(_sinh(r)) * 180 / math.pi;
  }

  double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;
}

class _DemTile {
  final int z, x, y;
  final int width, height;
  final double minLat, maxLat, minLng, maxLng;
  final Float32List elevations;

  _DemTile({
    required this.z,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
    required this.elevations,
  });
}
