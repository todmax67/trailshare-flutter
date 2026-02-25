import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';

/// TileProvider che cerca prima offline, poi in rete
class OfflineFallbackTileProvider extends TileProvider {
  static String? _cachedBasePath;

  static Future<void> initialize() async {
    if (_cachedBasePath != null) return;
    final dir = await getApplicationDocumentsDirectory();
    _cachedBasePath = '${dir.path}/offline_tiles';
    debugPrint('[OfflineTile] Inizializzato: $_cachedBasePath');
  }

  ImageProvider _resolve(TileCoordinates coordinates, TileLayer options) {
    if (_cachedBasePath != null) {
      final file = File('$_cachedBasePath/${coordinates.z}/${coordinates.x}/${coordinates.y}.png');
      if (file.existsSync()) {
        return FileImage(file);
      }
    }

    final url = options.urlTemplate!
        .replaceAll('{z}', '${coordinates.z}')
        .replaceAll('{x}', '${coordinates.x}')
        .replaceAll('{y}', '${coordinates.y}')
        .replaceAll('{s}', 'a');
    return NetworkImage(url, headers: {'User-Agent': 'TrailShare/1.0'});
  }

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _resolve(coordinates, options);
  }

  @override
  bool get supportsCancelLoading => true;

  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) {
    return _resolve(coordinates, options);
  }
}