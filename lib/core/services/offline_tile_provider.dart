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
    debugPrint('[OfflineTile] BasePath: $_cachedBasePath');

    final folder = Directory(_cachedBasePath!);
    if (await folder.exists()) {
      final items = await folder.list().where((e) => e is Directory).toList();
      debugPrint('[OfflineTile] Cartelle zoom: ${items.length}');
    } else {
      debugPrint('[OfflineTile] CARTELLA NON ESISTE!');
    }
  }

  ImageProvider _resolve(TileCoordinates coordinates, TileLayer options) {
    if (_cachedBasePath != null) {
      final path = '$_cachedBasePath/${coordinates.z}/${coordinates.x}/${coordinates.y}.png';
      final file = File(path);
      if (file.existsSync()) {
        debugPrint('[OfflineTile] HIT: ${coordinates.z}/${coordinates.x}/${coordinates.y}');
        return FileImage(file);
      }
    }

    final url = options.urlTemplate!
        .replaceAll('{z}', '${coordinates.z}')
        .replaceAll('{x}', '${coordinates.x}')
        .replaceAll('{y}', '${coordinates.y}')
        .replaceAll('{s}', 'a');
    debugPrint('[OfflineTile] NET: ${coordinates.z}/${coordinates.x}/${coordinates.y}');
    return NetworkImage(url, headers: {'User-Agent': 'TrailShare/1.0'});
  }

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    debugPrint('[OfflineTile] getImage chiamato');
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
    debugPrint('[OfflineTile] getImageWithCancel chiamato');
    return _resolve(coordinates, options);
  }
}
/// Helper: crea un TileLayer con supporto offline
TileLayer offlineTileLayer({
  required String urlTemplate,
  List<String> subdomains = const ['a', 'b', 'c'],
}) {
  return TileLayer(
    urlTemplate: urlTemplate,
    userAgentPackageName: 'com.trailshare.app',
    subdomains: subdomains,
    tileProvider: OfflineFallbackTileProvider(),
  );
}