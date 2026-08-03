import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:math' as math;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

import 'offline_tile_provider.dart' show kOfflineStyleUrlTemplate;

/// Servizio per la gestione delle mappe offline
///
/// Permette di scaricare e gestire tile di mappe per uso offline.
class OfflineMapsService {
  static final OfflineMapsService _instance = OfflineMapsService._internal();
  factory OfflineMapsService() => _instance;
  OfflineMapsService._internal();

  // Stile dei tile scaricati: condiviso con OfflineFallbackTileProvider così
  // download e fallback restano sempre sullo stesso stile (Standard/OSM).
  static const String _tileUrlTemplate = kOfflineStyleUrlTemplate;
  static const String _tilesFolder = 'offline_tiles';
  
  String? _basePath;

  /// Inizializza il servizio
  Future<void> initialize() async {
    final dir = await getApplicationDocumentsDirectory();
    _basePath = '${dir.path}/$_tilesFolder';
    
    // Crea la cartella se non esiste
    final folder = Directory(_basePath!);
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
  }

  /// Ottiene il path base per i tile
  Future<String> get basePath async {
    if (_basePath == null) {
      await initialize();
    }
    return _basePath!;
  }

  /// Scarica un'area della mappa per uso offline
  /// 
  /// [bounds] - I limiti dell'area (minLat, minLon, maxLat, maxLon)
  /// [minZoom] - Zoom minimo da scaricare
  /// [maxZoom] - Zoom massimo da scaricare
  /// [onProgress] - Callback per il progresso (0.0 - 1.0)
  Future<DownloadResult> downloadArea({
    required MapBounds bounds,
    required int minZoom,
    required int maxZoom,
    required String regionName,
    Function(double progress, int downloaded, int total)? onProgress,
    Function()? onCancel,
  }) async {
    await initialize();
    
    // TODO: Implementare cancellazione con ValueNotifier se necessario
    const bool cancelled = false;

    int totalTiles = 0;
    int downloadedTiles = 0;
    int failedTiles = 0;
    int skippedTiles = 0;

    // Calcola il numero totale di tile
    for (int z = minZoom; z <= maxZoom; z++) {
      final tiles = _getTilesForBounds(bounds, z);
      totalTiles += tiles.length;
    }

    debugPrint('[OfflineMaps] Scaricamento $totalTiles tile per "$regionName"');

    // Scarica i tile per ogni livello di zoom
    for (int z = minZoom; z <= maxZoom; z++) {
      final tiles = _getTilesForBounds(bounds, z);
      
      for (final tile in tiles) {
        final x = tile['x']!;
        final y = tile['y']!;
        
        // Controlla se il tile esiste già
        final tilePath = '$_basePath/$z/$x/$y.png';
        final file = File(tilePath);
        
        if (await file.exists()) {
          skippedTiles++;
          downloadedTiles++;
        } else {
          // Scarica il tile
          final success = await _downloadTile(z, x, y);
          if (success) {
            downloadedTiles++;
          } else {
            failedTiles++;
            downloadedTiles++;
          }
        }

        // Aggiorna progresso
        onProgress?.call(
          downloadedTiles / totalTiles,
          downloadedTiles,
          totalTiles,
        );

        // Piccola pausa per non sovraccaricare il server
        if (downloadedTiles % 10 == 0) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }
    }

    // Salva info regione
    await _saveRegionInfo(regionName, bounds, minZoom, maxZoom, downloadedTiles - skippedTiles);

    return DownloadResult(
      success: !cancelled && failedTiles == 0,
      totalTiles: totalTiles,
      downloadedTiles: downloadedTiles - skippedTiles,
      skippedTiles: skippedTiles,
      failedTiles: failedTiles,
      cancelled: cancelled,
    );
  }

  /// Scarica un singolo tile
  Future<bool> _downloadTile(int z, int x, int y) async {
    try {
      final url = _tileUrlTemplate
          .replaceAll('{z}', z.toString())
          .replaceAll('{x}', x.toString())
          .replaceAll('{y}', y.toString());

      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'TrailShare/1.0'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return false;

      // Un 200 non garantisce un'immagine: captive portal degli hotel, pagine
      // di rate-limit e messaggi d'errore rispondono 200 con dell'HTML. Salvato
      // con estensione .png, quell'HTML diventa un tile che il decoder
      // rifiutera' per sempre — e a scoprirlo e' l'utente, in montagna.
      if (!_looksLikeImage(response.bodyBytes)) {
        debugPrint('[OfflineMaps] Tile $z/$x/$y non e\' un\'immagine: scartato');
        return false;
      }

      final tilePath = '$_basePath/$z/$x/$y.png';
      final file = File(tilePath);
      await file.parent.create(recursive: true);

      // Scrittura atomica: prima su un file temporaneo, poi rename.
      //
      // `writeAsBytes` direttamente sul percorso finale lascia un file troncato
      // se il processo muore a meta' — ed e' proprio quello che succede quando
      // Android sospende l'app durante un'escursione. Il rename invece o
      // avviene per intero o non avviene: in cache non puo' finire mezzo tile.
      final tmp = File('$tilePath.part');
      await tmp.writeAsBytes(response.bodyBytes, flush: true);
      await tmp.rename(tilePath);
      return true;
    } catch (e) {
      debugPrint('[OfflineMaps] Errore download tile $z/$x/$y: $e');
      return false;
    }
  }

  /// Riconosce un'immagine dai primi byte, senza decodificarla.
  ///
  /// Non serve a validare il contenuto — un PNG puo' essere valido e mostrare
  /// il tile sbagliato — ma a fermare sulla soglia quello che immagine non e'
  /// affatto: HTML di un captive portal, JSON di errore, risposte vuote.
  ///
  /// Accetta anche JPEG e WebP: l'estensione con cui li salviamo e' `.png` per
  /// convenzione del percorso, ma i provider di tile non sono obbligati a
  /// rispettarla e un tile valido non va buttato per il suo formato.
  static bool _looksLikeImage(List<int> b) {
    if (b.length < 12) return false;
    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      return true;
    }
    // JPEG: FF D8 FF
    if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return true;
    // WebP: "RIFF" .... "WEBP"
    if (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
        b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
      return true;
    }
    return false;
  }

  /// Calcola i tile necessari per un'area
  List<Map<String, int>> _getTilesForBounds(MapBounds bounds, int zoom) {
    final tiles = <Map<String, int>>[];
    
    final minTileX = _lonToTileX(bounds.minLon, zoom);
    final maxTileX = _lonToTileX(bounds.maxLon, zoom);
    final minTileY = _latToTileY(bounds.maxLat, zoom); // Nota: Y è invertito
    final maxTileY = _latToTileY(bounds.minLat, zoom);

    for (int x = minTileX; x <= maxTileX; x++) {
      for (int y = minTileY; y <= maxTileY; y++) {
        tiles.add({'x': x, 'y': y});
      }
    }

    return tiles;
  }

  /// Converte longitudine in tile X
  int _lonToTileX(double lon, int zoom) {
    return ((lon + 180.0) / 360.0 * (1 << zoom)).floor();
  }

  /// Converte latitudine in tile Y
  int _latToTileY(double lat, int zoom) {
    final latRad = lat * math.pi / 180.0;
    return ((1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) / 2.0 * (1 << zoom)).floor();
  }

  /// Stima il numero di tile per un'area
  int estimateTileCount(MapBounds bounds, int minZoom, int maxZoom) {
    int total = 0;
    for (int z = minZoom; z <= maxZoom; z++) {
      total += _getTilesForBounds(bounds, z).length;
    }
    return total;
  }

  /// Stima la dimensione del download in MB
  double estimateDownloadSize(int tileCount) {
    // Media ~15KB per tile
    return (tileCount * 15) / 1024;
  }

  /// Salva le informazioni della regione
  Future<void> _saveRegionInfo(
    String name,
    MapBounds bounds,
    int minZoom,
    int maxZoom,
    int tileCount,
  ) async {
    final regionsFile = File('$_basePath/regions.txt');
    final timestamp = DateTime.now().toIso8601String();
    final line = '$name|${bounds.minLat}|${bounds.minLon}|${bounds.maxLat}|${bounds.maxLon}|$minZoom|$maxZoom|$tileCount|$timestamp\n';
    
    await regionsFile.writeAsString(line, mode: FileMode.append);
  }

  /// Ottiene la lista delle regioni scaricate
  Future<List<OfflineRegion>> getDownloadedRegions() async {
    await initialize();
    
    final regionsFile = File('$_basePath/regions.txt');
    if (!await regionsFile.exists()) {
      return [];
    }

    final lines = await regionsFile.readAsLines();
    final regions = <OfflineRegion>[];

    for (final line in lines) {
      try {
        final parts = line.split('|');
        if (parts.length >= 9) {
          regions.add(OfflineRegion(
            name: parts[0],
            bounds: MapBounds(
              minLat: double.parse(parts[1]),
              minLon: double.parse(parts[2]),
              maxLat: double.parse(parts[3]),
              maxLon: double.parse(parts[4]),
            ),
            minZoom: int.parse(parts[5]),
            maxZoom: int.parse(parts[6]),
            tileCount: int.parse(parts[7]),
            downloadedAt: DateTime.parse(parts[8]),
          ));
        }
      } catch (e) {
        debugPrint('[OfflineMaps] Errore parsing regione: $e');
      }
    }

    return regions;
  }

  /// Elimina una regione offline
  Future<bool> deleteRegion(String regionName) async {
    await initialize();
    
    // Rimuovi dalla lista
    final regionsFile = File('$_basePath/regions.txt');
    if (await regionsFile.exists()) {
      final lines = await regionsFile.readAsLines();
      final newLines = lines.where((l) => !l.startsWith('$regionName|')).toList();
      await regionsFile.writeAsString(newLines.join('\n'));
    }

    // Nota: Non eliminiamo i tile perché potrebbero essere condivisi con altre regioni
    // In una versione più avanzata, si potrebbe fare reference counting
    
    return true;
  }

  /// Elimina tutti i tile offline
  Future<void> clearAllTiles() async {
    await initialize();
    
    final folder = Directory(_basePath!);
    if (await folder.exists()) {
      await folder.delete(recursive: true);
      await folder.create(recursive: true);
    }
  }

  /// Calcola lo spazio utilizzato dai tile offline
  Future<int> getStorageUsed() async {
    await initialize();
    
    final folder = Directory(_basePath!);
    if (!await folder.exists()) return 0;

    int totalSize = 0;
    await for (final entity in folder.list(recursive: true)) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }
    return totalSize;
  }

  /// Verifica se un tile è disponibile offline
  Future<bool> isTileAvailable(int z, int x, int y) async {
    await initialize();
    final tilePath = '$_basePath/$z/$x/$y.png';
    return File(tilePath).exists();
  }

  /// Ottiene il path di un tile offline
  Future<String?> getTilePath(int z, int x, int y) async {
    await initialize();
    final tilePath = '$_basePath/$z/$x/$y.png';
    if (await File(tilePath).exists()) {
      return tilePath;
    }
    return null;
  }
}

/// Limiti di un'area geografica
class MapBounds {
  final double minLat;
  final double minLon;
  final double maxLat;
  final double maxLon;

  const MapBounds({
    required this.minLat,
    required this.minLon,
    required this.maxLat,
    required this.maxLon,
  });

  /// Centro dell'area
  double get centerLat => (minLat + maxLat) / 2;
  double get centerLon => (minLon + maxLon) / 2;

  /// Crea bounds da centro e raggio in km
  factory MapBounds.fromCenter({
    required double lat,
    required double lon,
    required double radiusKm,
  }) {
    // Approssimazione: 1 grado ≈ 111 km
    final latDelta = radiusKm / 111;
    final lonDelta = radiusKm / (111 * math.cos(lat * math.pi / 180));
    
    return MapBounds(
      minLat: lat - latDelta,
      minLon: lon - lonDelta,
      maxLat: lat + latDelta,
      maxLon: lon + lonDelta,
    );
  }
}

/// Risultato del download
class DownloadResult {
  final bool success;
  final int totalTiles;
  final int downloadedTiles;
  final int skippedTiles;
  final int failedTiles;
  final bool cancelled;

  const DownloadResult({
    required this.success,
    required this.totalTiles,
    required this.downloadedTiles,
    required this.skippedTiles,
    required this.failedTiles,
    required this.cancelled,
  });
}

/// Regione offline salvata
class OfflineRegion {
  final String name;
  final MapBounds bounds;
  final int minZoom;
  final int maxZoom;
  final int tileCount;
  final DateTime downloadedAt;

  const OfflineRegion({
    required this.name,
    required this.bounds,
    required this.minZoom,
    required this.maxZoom,
    required this.tileCount,
    required this.downloadedAt,
  });

  /// Dimensione stimata in MB
  double get estimatedSizeMB => (tileCount * 15) / 1024;
}
