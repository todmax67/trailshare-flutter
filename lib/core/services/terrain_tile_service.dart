import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
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

  // ── Persistent cache (Pro) ────────────────────────────────────────────
  static const String _boxName = 'terrain_tiles_v1';
  Box<Uint8List>? _diskBox;
  bool _diskInitialized = false;

  /// Abilita la cache persistente Hive. Idempotente. Chiama questo solo
  /// per utenti Pro — per i free, l'in-memory LRU basta.
  Future<void> enableDiskCache() async {
    if (_diskInitialized) return;
    try {
      await Hive.initFlutter();
      _diskBox = await Hive.openBox<Uint8List>(_boxName);
      _diskInitialized = true;
      debugPrint('[Terrain] ✅ disk cache aperta (${_diskBox!.length} tile)');
    } catch (e) {
      debugPrint('[Terrain] ❌ disk cache init failed: $e');
    }
  }

  /// True se la cache su disco è pronta.
  bool get diskCacheReady => _diskInitialized && _diskBox != null;

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

    final fut = _fetchTileWithDiskCache(key, z, x, y);
    _inflight[key] = fut;
    final result = await fut;
    _inflight.remove(key);
    if (result != null) _putCache(key, result);
    return result;
  }

  /// Disk cache first, poi rete. Salva su disco se Pro tier abilitato.
  Future<_DemTile?> _fetchTileWithDiskCache(String key, int z, int x, int y) async {
    // 1. Try disk
    if (diskCacheReady) {
      final bytes = _diskBox!.get(key);
      if (bytes != null) {
        final tile = _bytesToTile(bytes, z, x, y);
        if (tile != null) {
          debugPrint('[Terrain] disk HIT $key');
          return tile;
        }
      }
    }
    // 2. Network + decode in isolate
    final tile = await _doFetch(z, x, y);
    if (tile != null && diskCacheReady) {
      try {
        await _diskBox!.put(key, _tileToBytes(tile));
      } catch (e) {
        debugPrint('[Terrain] disk put error: $e');
      }
    }
    return tile;
  }

  /// Encoding compatto su disco: 16 bytes header (w,h,minLat,maxLat,minLng,maxLng)
  /// + Float32List elevations (raw little-endian).
  Uint8List _tileToBytes(_DemTile t) {
    final out = BytesBuilder();
    final header = ByteData(16 + 4 * 4);
    header.setUint32(0, t.width, Endian.little);
    header.setUint32(4, t.height, Endian.little);
    header.setFloat32(8, t.minLat, Endian.little);
    header.setFloat32(12, t.maxLat, Endian.little);
    header.setFloat32(16, t.minLng, Endian.little);
    header.setFloat32(20, t.maxLng, Endian.little);
    out.add(header.buffer.asUint8List());
    out.add(t.elevations.buffer.asUint8List());
    return out.toBytes();
  }

  _DemTile? _bytesToTile(Uint8List bytes, int z, int x, int y) {
    try {
      final bd = ByteData.sublistView(bytes, 0, 32);
      final w = bd.getUint32(0, Endian.little);
      final h = bd.getUint32(4, Endian.little);
      final minLat = bd.getFloat32(8, Endian.little);
      final maxLat = bd.getFloat32(12, Endian.little);
      final minLng = bd.getFloat32(16, Endian.little);
      final maxLng = bd.getFloat32(20, Endian.little);
      // Copia in nuovo Float32List per evitare problemi di allineamento
      // (la Uint8List restituita da Hive non garantisce alignment a 4 byte).
      final ele = Float32List(w * h);
      final eleBytes = ByteData.sublistView(bytes, 32, 32 + w * h * 4);
      for (int i = 0; i < w * h; i++) {
        ele[i] = eleBytes.getFloat32(i * 4, Endian.little);
      }
      return _DemTile(
        z: z, x: x, y: y,
        width: w, height: h,
        minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng,
        elevations: ele,
      );
    } catch (e) {
      debugPrint('[Terrain] decode disk bytes failed: $e');
      return null;
    }
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
    // Decode PNG → Float32List in isolate per non bloccare UI.
    final decoded = await compute(_decodePngInIsolate, bytes);
    if (decoded == null) return null;
    final bbox = _tileBbox(z, x, y);
    return _DemTile(
      z: z, x: x, y: y,
      width: decoded.width, height: decoded.height,
      minLat: bbox[0], maxLat: bbox[1], minLng: bbox[2], maxLng: bbox[3],
      elevations: decoded.elevations,
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

/// Risultato decode in isolate. Solo tipi primitivi (Float32List + int)
/// per attraversare il confine isolate.
class _DecodedTile {
  final int width;
  final int height;
  final Float32List elevations;
  _DecodedTile(this.width, this.height, this.elevations);
}

/// Top-level fn richiesta da `compute()`. Decodifica PNG terrarium →
/// Float32List di quote. Niente Flutter API qui dentro (gira in isolate).
_DecodedTile? _decodePngInIsolate(Uint8List bytes) {
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
  return _DecodedTile(w, h, ele);
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
