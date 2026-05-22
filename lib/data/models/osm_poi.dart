import 'package:flutter/material.dart';

import 'trail_poi.dart' show PoiType;

/// Tipo OSM "raw" — corrisponde 1:1 al campo `type` nell'asset
/// `assets/data/pois_italy_clean.json`. Usato per:
///   - Filtri UI (mostra solo rifugi, solo fontane, ecc.)
///   - Mapping verso [PoiType] per riusare icone/colori dell'UI esistente
enum OsmPoiType {
  alpineHut('alpine_hut', 'Rifugio gestito', Icons.cabin),
  wildernessHut('wilderness_hut', 'Bivacco', Icons.holiday_village),
  shelter('shelter', 'Riparo', Icons.house_siding),
  spring('spring', 'Sorgente', Icons.water),
  drinkingWater('drinking_water', 'Fontana', Icons.water_drop),
  viewpoint('viewpoint', 'Panorama', Icons.landscape),
  waysideCross('wayside_cross', 'Croce', Icons.add),
  picnicSite('picnic_site', 'Picnic', Icons.deck),
  cairn('cairn', 'Ometto', Icons.terrain);

  final String code;
  final String displayName;
  final IconData icon;
  const OsmPoiType(this.code, this.displayName, this.icon);

  static OsmPoiType? fromCode(String? code) {
    if (code == null) return null;
    for (final t in OsmPoiType.values) {
      if (t.code == code) return t;
    }
    return null;
  }

  /// Conversione verso il [PoiType] consumer-facing usato dalla UI POI
  /// community. Permette di riusare gli stessi marker/colori per OSM e
  /// community con un solo path di rendering.
  PoiType toPoiType() {
    switch (this) {
      case OsmPoiType.alpineHut:
      case OsmPoiType.wildernessHut:
      case OsmPoiType.shelter:
        return PoiType.shelter;
      case OsmPoiType.spring:
      case OsmPoiType.drinkingWater:
        return PoiType.water;
      case OsmPoiType.viewpoint:
        return PoiType.viewpoint;
      case OsmPoiType.waysideCross:
      case OsmPoiType.cairn:
        return PoiType.historical;
      case OsmPoiType.picnicSite:
        return PoiType.nature;
    }
  }
}

/// POI immutabile derivato da OpenStreetMap (via Overpass API), bundlato
/// nell'app come asset statico. È **read-only** dal punto di vista app —
/// gli utenti non possono modificare un OsmPoi, ma possono "verificare"
/// o "correggere" creando un POI community sopra (gestito altrove).
///
/// Schema asset di provenienza: vedi `tool/fetch_italian_pois.sh`.
@immutable
class OsmPoi {
  /// ID univoco del nodo OSM, prefissato con "n" (es. "n123456789").
  final String id;
  final OsmPoiType type;
  final String name;
  final double latitude;
  final double longitude;
  final double? elevation;

  /// Operatore/gestore (per rifugi: "CAI Bergamo", "SAT", ecc.). Spesso null.
  final String? operatorName;

  /// Sito web ufficiale (rifugi gestiti, alcuni viewpoint). Spesso null.
  final String? website;

  const OsmPoi({
    required this.id,
    required this.type,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.elevation,
    this.operatorName,
    this.website,
  });

  /// Decodifica un record dall'asset JSON. Ritorna null se i campi
  /// minimi mancano o sono invalidi.
  static OsmPoi? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final typeCode = json['type'] as String?;
    final name = json['name'] as String?;
    final lat = (json['lat'] as num?)?.toDouble();
    final lng = (json['lng'] as num?)?.toDouble();

    if (id == null ||
        name == null ||
        name.isEmpty ||
        lat == null ||
        lng == null) {
      return null;
    }

    final type = OsmPoiType.fromCode(typeCode);
    if (type == null) return null;

    return OsmPoi(
      id: id,
      type: type,
      name: name,
      latitude: lat,
      longitude: lng,
      elevation: (json['ele'] as num?)?.toDouble(),
      operatorName: json['operator'] as String?,
      website: json['website'] as String?,
    );
  }
}
