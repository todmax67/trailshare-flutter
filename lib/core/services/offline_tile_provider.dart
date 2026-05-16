import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';

import '../constants/api_keys.dart';

/// User-Agent OSM Tile Usage Policy compliant
/// (https://operations.osmfoundation.org/policies/tiles/).
///
/// Deve identificare l'app + version + contatto. Versioni release
/// pubblicate sugli store con UA generici (es. 'TrailShareApp/1.0')
/// vengono ratelimitate/bannate dai server tile.openstreetmap.org —
/// in debug Flutter cade su UA Dart di default che OSM tollera, in
/// release passa il nostro UA esplicito che senza version+contatto
/// scatena il ban → tile bianche/grigie sull'app.
///
/// Aggiorna la version qui ad ogni release (o leggi da pubspec a
/// runtime via package_info_plus se vuoi automazione).
const String _osmUserAgent =
    'TrailShare/2.4.6 (+https://trailshare.app; info@trailshare.app)';

/// TileProvider che cerca prima offline, poi in rete
class OfflineFallbackTileProvider extends TileProvider {
  static String? _cachedBasePath;

  static Future<void> initialize() async {
    if (_cachedBasePath != null) return;
    // Su web non esiste filesystem persistente accessibile: niente
    // cache offline tile. Saltiamo l'init, _resolve cadrà direttamente
    // su NetworkImage (il branch File.existsSync è gated dal null
    // check di _cachedBasePath).
    if (kIsWeb) return;
    final dir = await getApplicationDocumentsDirectory();
    _cachedBasePath = '${dir.path}/offline_tiles';
    debugPrint('[OfflineTile] Inizializzato: $_cachedBasePath');
  }

  /// User-Agent corretto in base al provider. MapTiler ha una
  /// restrizione lato dashboard che richiede UA contenente
  /// [ApiKeys.mapTilerUserAgent] ('TrailShareApp'). Per tutto il
  /// resto (OSM, OpenTopoMap, ArcGIS, CartoDB) usiamo l'UA
  /// OSM-policy compliant con version + contatto.
  String _uaFor(String url) {
    if (url.contains('maptiler.com')) {
      return '${ApiKeys.mapTilerUserAgent}/2.4.6';
    }
    return _osmUserAgent;
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
    return NetworkImage(
      url,
      headers: {
        'User-Agent': _uaFor(url),
        // OSM Tile Usage Policy raccomanda anche Referer per
        // identificare la sorgente. Non strettamente obbligatorio ma
        // riduce il rischio di throttling.
        'Referer': 'https://trailshare.app',
      },
    );
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