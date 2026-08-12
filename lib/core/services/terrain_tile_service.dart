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

    // Cap di sicurezza: oltre questo numero la mosaicata satura la RAM e
    // l'UI freeza. Indicatore di zoom troppo alto per il raggio richiesto.
    const maxTilesPerRequest = 100;
    if (tiles.length > maxTilesPerRequest) {
      debugPrint('[Terrain] ⚠️ richiesti ${tiles.length} tile, oltre il cap '
          '$maxTilesPerRequest. Abort: usa uno zoom più basso.');
      return null;
    }
    debugPrint('[Terrain] fetching ${tiles.length} tile (z=$zoom)...');

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
    if (fetched.length < tiles.length) {
      debugPrint('[Terrain] ⚠️ ${tiles.length - fetched.length} tile su '
          '${tiles.length} non scaricati: quelle zone restano NaN');
    }

    // Mosaico sulla bbox **richiesta**, non su quella dei soli tile riusciti:
    // altrimenti un tile mancante al bordo restringe in silenzio la griglia,
    // e nel caso peggiore la griglia non contiene nemmeno l'osservatore.
    return _mosaic(
      fetched,
      minLat: minLat,
      maxLat: maxLat,
      minLng: minLng,
      maxLng: maxLng,
      zoom: zoom,
    );
  }

  /// Costruisce il terreno a due risoluzioni per il viewshed: una griglia
  /// fitta attorno all'osservatore e una larga che copre tutto il raggio.
  ///
  /// Le occlusioni si decidono soprattutto vicino — un dosso a 200 m nasconde
  /// mezzo orizzonte — ma su una griglia a 110 m/cella quel dosso è tre pixel e
  /// sparisce nella media. Lontano invece la risoluzione conta poco, perché a
  /// 50 km un dettaglio di 100 m sottende un decimo di grado.
  ///
  /// Se la griglia fitta non arriva (rete lenta, cap tile) si prosegue con la
  /// sola griglia larga: peggio di prima non si sta mai.
  Future<LayeredDem?> buildLayeredDem({
    required double observerLat,
    required double observerLng,
    required double radiusKm,
    int coarseZoom = 10,
    int fineZoom = 12,
    double fineRadiusKm = 10,
  }) async {
    Future<DemGrid?> build(double km, int zoom) {
      final latDelta = km / 111.0;
      final lngDelta = km / (111.0 * math.cos(observerLat * math.pi / 180));
      return buildDemGrid(
        minLat: observerLat - latDelta,
        maxLat: observerLat + latDelta,
        minLng: observerLng - lngDelta,
        maxLng: observerLng + lngDelta,
        zoom: zoom,
      );
    }

    // Le due griglie si costruiscono **in parallelo**: sono indipendenti, e
    // metterle in fila raddoppiava l'attesa prima che comparisse una sola cima.
    // Non ha senso chiedere la griglia fitta più grande del raggio totale.
    final fineKm = math.min(fineRadiusKm, radiusKm);
    final built = await Future.wait([
      build(radiusKm, coarseZoom),
      build(fineKm, fineZoom),
    ]);
    final coarse = built[0];
    // La griglia larga è indispensabile: senza, non c'è viewshed. Quella fitta
    // è un miglioramento, e se manca si prosegue lo stesso.
    if (coarse == null) return null;
    final fine = built[1];

    debugPrint('[Terrain] DEM a strati: '
        'fine=${fine == null ? "assente" : "${fine.rows}×${fine.cols} ~${fine.cellSizeMeters.round()}m"}'
        ' coarse=${coarse.rows}×${coarse.cols} ~${coarse.cellSizeMeters.round()}m');
    return LayeredDem(coarse: coarse, fine: fine);
  }

  /// Quota del terreno in un punto, dal DEM. Scarica (e cacha) il solo tile
  /// che contiene il punto, quindi dopo il primo accesso è immediata.
  ///
  /// Serve per la quota dell'**osservatore**: quella del GPS sbaglia di 20-50 m
  /// su Android, che a 3 km di distanza vale un grado di errore verticale — i
  /// pin scivolano sopra o sotto le cime. Il DEM è molto più stabile, ed è la
  /// stessa quota che usa il viewshed: così le due metà del sistema concordano
  /// su dove si trova l'utente.
  ///
  /// Zoom 12 (~30 m/pixel in Italia) perché qui conta la precisione locale, non
  /// l'estensione: è un tile solo.
  Future<double?> groundElevationAt(
    double lat,
    double lng, {
    int zoom = 12,
  }) async {
    final n = math.pow(2, zoom).toInt();
    final x = ((lng + 180) / 360 * n).floor().clamp(0, n - 1);
    final y = _latToTileY(lat, zoom).clamp(0, n - 1);
    final tile = await _fetchTile(zoom, x, y);
    if (tile == null) return null;
    final fy = (tile.maxLat - lat) /
        (tile.maxLat - tile.minLat) *
        (tile.height - 1);
    final fx = (lng - tile.minLng) /
        (tile.maxLng - tile.minLng) *
        (tile.width - 1);
    final ry = fy.round().clamp(0, tile.height - 1);
    final rx = fx.round().clamp(0, tile.width - 1);
    final ele = tile.elevations[ry * tile.width + rx];
    return ele.isFinite ? ele.toDouble() : null;
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
        if (tile != null) return tile; // niente log spam (tipicamente 30+ HIT)
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

  /// Combina più tile in una griglia DemGrid unica con risoluzione uniforme,
  /// sulla bbox **richiesta**.
  ///
  /// Le celle che nessun tile copre restano **NaN**, non 0. Prima erano zeri
  /// (la `Float32List` nasce azzerata) e il viewshed li leggeva come quota
  /// valida sul livello del mare: un tile mancante diventava un buco da cui si
  /// vedeva *attraverso* la montagna. NaN significa "non lo so", e chi legge
  /// salta il campione invece di credere a una pianura che non esiste.
  DemGrid _mosaic(
    List<_DemTile> tiles, {
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
    required int zoom,
  }) {
    // Passo dei pixel: quello nativo dei tile, **separato per i due assi**.
    // In Mercator un pixel è quadrato in metri ma non in gradi: alle nostre
    // latitudini copre 1,4 volte meno gradi in latitudine che in longitudine.
    // Usando il passo della longitudine anche per le righe si buttava via un
    // terzo del dettaglio verticale del DEM.
    final tileCount = math.pow(2, zoom).toInt();
    final lngPx = (360.0 / tileCount) / tiles.first.width;
    final first = tiles.first;
    final latPx = (first.maxLat - first.minLat) / first.height;
    final cols = math.max(2, ((maxLng - minLng) / lngPx).round());
    final rows = math.max(2, ((maxLat - minLat) / latPx).round());

    // La griglia si costruisce PRIMA e si riempie attraverso i suoi stessi
    // `latForRow`/`lngForCol`. Non è un vezzo: scrivendo la formula a mano qui
    // dentro, questa funzione e `DemGrid.elevationAt` avevano finito per usare
    // convenzioni opposte per le righe, e il DEM veniva letto specchiato
    // nord-sud. Passando dai metodi della griglia le due cose non possono più
    // divergere.
    final out = Float32List(rows * cols)..fillRange(0, rows * cols, double.nan);
    final grid = DemGrid(
      minLat: minLat, maxLat: maxLat,
      minLng: minLng, maxLng: maxLng,
      rows: rows, cols: cols,
      elevations: out,
    );

    // Si scorre **per tile**, non per cella di destinazione.
    //
    // Il verso opposto sembrava più naturale ("per ogni cella, trova il tile")
    // ma cercava il tile con una scansione lineare: su due milioni di celle e
    // qualche decina di tile sono decine di milioni di confronti, tutti sul
    // thread principale, cioè scatti nella preview della fotocamera proprio
    // mentre l'utente sta inquadrando. Qui invece ogni tile calcola una volta
    // sola l'intervallo di righe e colonne che gli compete e ci scrive dentro:
    // il costo torna lineare nel numero di celle.
    for (final tile in tiles) {
      // Righe/colonne della destinazione che cadono dentro questo tile.
      final range = destinationRangeFor(
        gridMinLat: minLat, gridMaxLat: maxLat,
        gridMinLng: minLng, gridMaxLng: maxLng,
        rows: rows, cols: cols,
        tileMinLat: tile.minLat, tileMaxLat: tile.maxLat,
        tileMinLng: tile.minLng, tileMaxLng: tile.maxLng,
      );
      if (range == null) continue;
      final rowFrom = range.rowFrom;
      final rowTo = range.rowTo;
      final colFrom = range.colFrom;
      final colTo = range.colTo;

      final tLatSpan = tile.maxLat - tile.minLat;
      final tLngSpan = tile.maxLng - tile.minLng;
      if (tLatSpan <= 0 || tLngSpan <= 0) continue;

      for (int r = rowFrom; r <= rowTo; r++) {
        final lat = grid.latForRow(r);
        final fy = (tile.maxLat - lat) / tLatSpan * (tile.height - 1);
        final ry = fy.round().clamp(0, tile.height - 1);
        final rowBase = ry * tile.width;
        final outBase = r * cols;
        for (int c = colFrom; c <= colTo; c++) {
          final lng = grid.lngForCol(c);
          final fx = (lng - tile.minLng) / tLngSpan * (tile.width - 1);
          final rx = fx.round().clamp(0, tile.width - 1);
          out[outBase + c] = tile.elevations[rowBase + rx];
        }
      }
    }

    return grid;
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

/// Intervallo di righe e colonne della griglia destinazione coperte da una
/// bbox (tipicamente quella di un tile). `null` se non si intersecano.
///
/// Vive fuori dal mosaico e senza stato apposta: è la parte che sbagliando
/// scrive quote nel posto sbagliato, ed è già successo — la versione
/// precedente del mosaico riempiva le righe al contrario e il DEM veniva
/// riletto specchiato nord-sud. Qui si può testare con numeri.
///
/// Convenzione: riga 0 = bordo sud, colonna 0 = bordo ovest, come [DemGrid].
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

  // Il tile non interseca la destinazione: va scartato **prima** di limitare
  // gli indici. Limitandoli soltanto, un tile tutto a nord finirebbe
  // schiacciato sull'ultima riga e ci scriverebbe dentro quote prese da
  // tutt'altro posto.
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
