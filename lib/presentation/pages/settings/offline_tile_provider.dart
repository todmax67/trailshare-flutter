import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Tile provider che supporta cache offline
/// 
/// Prima cerca i tile nella cache locale, poi li scarica se necessario.
class OfflineTileProvider extends TileProvider {
  final String _cacheFolder = 'offline_tiles';
  String? _basePath;
  bool _initialized = false;

  /// Se true, salva automaticamente i tile visualizzati
  final bool cacheOnView;

  OfflineTileProvider({this.cacheOnView = true});

  Future<void> _initialize() async {
    if (_initialized) return;
    
    final dir = await getApplicationDocumentsDirectory();
    _basePath = '${dir.path}/$_cacheFolder';
    
    final folder = Directory(_basePath!);
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    _initialized = true;
  }

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return OfflineTileImage(
      coordinates: coordinates,
      options: options,
      basePath: _basePath,
      cacheOnView: cacheOnView,
      initializeCallback: _initialize,
    );
  }
}

/// ImageProvider personalizzato che gestisce cache offline
class OfflineTileImage extends ImageProvider<OfflineTileImage> {
  final TileCoordinates coordinates;
  final TileLayer options;
  final String? basePath;
  final bool cacheOnView;
  final Future<void> Function() initializeCallback;

  OfflineTileImage({
    required this.coordinates,
    required this.options,
    required this.basePath,
    required this.cacheOnView,
    required this.initializeCallback,
  });

  @override
  Future<OfflineTileImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(
    OfflineTileImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadTile(decode),
      scale: 1.0,
    );
  }

  Future<Codec> _loadTile(ImageDecoderCallback decode) async {
    await initializeCallback();

    final z = coordinates.z.toInt();
    final x = coordinates.x.toInt();
    final y = coordinates.y.toInt();

    // 1. Prova a caricare dalla cache locale
    if (basePath != null) {
      final tilePath = '$basePath/$z/$x/$y.png';
      final file = File(tilePath);
      
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final buffer = await ImmutableBuffer.fromUint8List(bytes);
        return decode(buffer);
      }
    }

    // 2. Scarica dal server
    final url = _buildTileUrl(z, x, y);
    
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'TrailShare/1.0'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;

        // Salva in cache se abilitato
        if (cacheOnView && basePath != null) {
          _saveTileToCache(z, x, y, bytes);
        }

        final buffer = await ImmutableBuffer.fromUint8List(bytes);
        return decode(buffer);
      }
    } catch (e) {
      print('[OfflineTile] Errore download $z/$x/$y: $e');
    }

    // 3. Restituisci placeholder trasparente
    final emptyPng = _createEmptyPng();
    final buffer = await ImmutableBuffer.fromUint8List(emptyPng);
    return decode(buffer);
  }

  String _buildTileUrl(int z, int x, int y) {
    // Usa il template URL dalle opzioni o default OSM
    String urlTemplate = options.urlTemplate ?? 
        'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    
    return urlTemplate
        .replaceAll('{z}', z.toString())
        .replaceAll('{x}', x.toString())
        .replaceAll('{y}', y.toString())
        .replaceAll('{s}', 'a'); // Subdomain default
  }

  Future<void> _saveTileToCache(int z, int x, int y, Uint8List bytes) async {
    try {
      final tilePath = '$basePath/$z/$x/$y.png';
      final file = File(tilePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
    } catch (e) {
      // Ignora errori di cache
    }
  }

  /// Crea un PNG trasparente 256x256
  Uint8List _createEmptyPng() {
    // PNG minimo trasparente 1x1 (per semplicità)
    return Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
      0x42, 0x60, 0x82,
    ]);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OfflineTileImage &&
        other.coordinates == coordinates;
  }

  @override
  int get hashCode => coordinates.hashCode;
}
