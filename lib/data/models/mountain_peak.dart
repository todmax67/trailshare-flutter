/// Una cima riconoscibile dalla feature **Mountain Recognition AR**.
///
/// Sorgente dati: dataset OSM `natural=peak` (in arrivo nello Step 3 sotto
/// forma di asset bundled). In Step 1 usiamo una manciata di cime
/// hardcoded ([famousItalianPeaks]) per validare la math di proiezione.
class MountainPeak {
  /// Identificatore stabile (es. `osm_node_4242` o slug per i test).
  final String id;

  final String name;
  final double latitude;
  final double longitude;

  /// Altitudine in metri sul livello del mare. `null` se sconosciuta.
  final double? elevation;

  /// Regione amministrativa principale (display only, non usato per query).
  final String? region;

  /// Categoria libera, es. `peak`, `volcano`, `ridge`, `pass`. Default `peak`.
  final String type;

  const MountainPeak({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.elevation,
    this.region,
    this.type = 'peak',
  });

  /// Display name compatto: "Monte Bianco · 4.808 m".
  String get displayLabel {
    if (elevation == null || elevation! <= 0) return name;
    final m = elevation!.round();
    return '$name · $m m';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': latitude,
        'lng': longitude,
        if (elevation != null) 'ele': elevation,
        if (region != null) 'region': region,
        'type': type,
      };

  factory MountainPeak.fromJson(Map<String, dynamic> json) {
    return MountainPeak(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Sconosciuta',
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lng'] as num).toDouble(),
      elevation: (json['ele'] as num?)?.toDouble(),
      region: json['region']?.toString(),
      type: json['type']?.toString() ?? 'peak',
    );
  }
}

/// Set di cime "vetrina" italiane usate in Step 1 (v2.0.0) per testare la
/// math di proiezione AR senza dipendere dal dataset OSM completo.
///
/// Coordinate da Wikipedia / OpenStreetMap. Le altezze sono quelle ufficiali
/// più aggiornate.
const List<MountainPeak> famousItalianPeaks = [
  MountainPeak(
    id: 'demo_monte_bianco',
    name: 'Monte Bianco',
    latitude: 45.832622,
    longitude: 6.865175,
    elevation: 4805.6,
    region: "Valle d'Aosta",
  ),
  MountainPeak(
    id: 'demo_cervino',
    name: 'Cervino',
    latitude: 45.976660,
    longitude: 7.658629,
    elevation: 4478,
    region: "Valle d'Aosta",
  ),
  MountainPeak(
    id: 'demo_monte_rosa',
    name: 'Monte Rosa (Punta Dufour)',
    latitude: 45.936944,
    longitude: 7.866944,
    elevation: 4634,
    region: 'Piemonte',
  ),
  MountainPeak(
    id: 'demo_marmolada',
    name: 'Marmolada (Punta Penia)',
    latitude: 46.434167,
    longitude: 11.851667,
    elevation: 3343,
    region: 'Veneto',
  ),
  MountainPeak(
    id: 'demo_gran_sasso',
    name: 'Gran Sasso (Corno Grande)',
    latitude: 42.469167,
    longitude: 13.566944,
    elevation: 2912,
    region: 'Abruzzo',
  ),
  MountainPeak(
    id: 'demo_etna',
    name: 'Etna',
    latitude: 37.751,
    longitude: 14.9934,
    elevation: 3357,
    region: 'Sicilia',
    type: 'volcano',
  ),
  MountainPeak(
    id: 'demo_vesuvio',
    name: 'Vesuvio',
    latitude: 40.821938,
    longitude: 14.426119,
    elevation: 1281,
    region: 'Campania',
    type: 'volcano',
  ),
  MountainPeak(
    id: 'demo_stelvio',
    name: 'Ortles',
    latitude: 46.508889,
    longitude: 10.544722,
    elevation: 3905,
    region: 'Trentino-Alto Adige',
  ),
  MountainPeak(
    id: 'demo_grigna',
    name: 'Grigna Settentrionale',
    latitude: 45.954167,
    longitude: 9.391944,
    elevation: 2410,
    region: 'Lombardia',
  ),
  MountainPeak(
    id: 'demo_resegone',
    name: 'Resegone',
    latitude: 45.875833,
    longitude: 9.464167,
    elevation: 1875,
    region: 'Lombardia',
  ),
];
