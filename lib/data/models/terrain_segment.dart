import 'package:flutter/material.dart';

/// Komoot K1b — tipo di terreno/fondo di un tratto di sentiero.
///
/// Categorie pensate per essere visivamente distinguibili e utili al
/// camminatore/biker per stimare effort e calzature appropriate. Derivate
/// dai tag OSM way (highway, surface, sac_scale, tracktype, via_ferrata).
///
/// L'ordine dell'enum NON è significativo (a differenza di
/// ComputedDifficulty). Le label sono italiane brevi per stare in legenda.
enum TerrainType {
  asphalt(
    'asphalt',
    'Asfalto',
    Icons.add_road,
    Color(0xFF424242),
    'Strada o ciclabile asfaltata',
  ),
  gravel(
    'gravel',
    'Sterrato',
    Icons.terrain,
    Color(0xFFA0743A),
    'Strada bianca, sterrato compatto',
  ),
  path(
    'path',
    'Sentiero',
    Icons.hiking,
    Color(0xFF689F38),
    'Sentiero escursionistico in terra/erba',
  ),
  rocky(
    'rocky',
    'Roccia',
    Icons.landscape,
    Color(0xFF8D6E63),
    'Tratti rocciosi o pietraia',
  ),
  viaFerrata(
    'via_ferrata',
    'Ferrata',
    Icons.warning_amber,
    Color(0xFFD32F2F),
    'Via ferrata o passaggio attrezzato',
  ),
  unknown(
    'unknown',
    'Sconosciuto',
    Icons.help_outline,
    Color(0xFF9E9E9E),
    'Fondo non determinato dai dati OSM',
  );

  /// Chiave persistita su Firestore. NON cambiare.
  final String firestoreKey;

  /// Label leggibile italiana.
  final String label;

  /// Icona per legenda + tooltip.
  final IconData icon;

  /// Colore distintivo per la colorazione della polyline e la legenda.
  final Color color;

  /// Descrizione estesa per UI tooltip / accessibility.
  final String description;

  const TerrainType(
    this.firestoreKey,
    this.label,
    this.icon,
    this.color,
    this.description,
  );

  static TerrainType fromKey(String? key) {
    if (key == null) return TerrainType.unknown;
    for (final t in values) {
      if (t.firestoreKey == key) return t;
    }
    return TerrainType.unknown;
  }
}

/// Komoot K1b — segmento di terreno omogeneo lungo un sentiero.
///
/// Un sentiero è rappresentato come una lista di `TerrainSegment` che
/// coprono in modo contiguo i punti della polyline. Ogni segmento è
/// identificato da:
/// - [startPointIdx] / [endPointIdx]: indici (inclusivi) nei `TrackPoint[]`
///   della geometria del sentiero. Permette al rendering di colorare le
///   polyline a tratti senza ricalcolare distanze.
/// - [type]: tipo terreno predominante nel tratto.
///
/// Storage: array `terrainSegments` denormalizzato dentro
/// `public_trail_geometries/{trailId}.terrainSegments[]`.
/// Popolato dalla Cloud Function batch `enrichTrailsWithTerrain` (cron
/// mensile + onCall per refresh manuale admin).
class TerrainSegment {
  final int startPointIdx;
  final int endPointIdx;
  final TerrainType type;

  const TerrainSegment({
    required this.startPointIdx,
    required this.endPointIdx,
    required this.type,
  });

  /// Numero di punti coperti dal segmento (inclusivi su entrambi gli estremi).
  int get pointCount => endPointIdx - startPointIdx + 1;

  Map<String, dynamic> toMap() => {
        'startIdx': startPointIdx,
        'endIdx': endPointIdx,
        'type': type.firestoreKey,
      };

  static TerrainSegment? fromMap(Map<String, dynamic> map) {
    final start = (map['startIdx'] as num?)?.toInt();
    final end = (map['endIdx'] as num?)?.toInt();
    if (start == null || end == null || end < start) return null;
    return TerrainSegment(
      startPointIdx: start,
      endPointIdx: end,
      type: TerrainType.fromKey(map['type']?.toString()),
    );
  }

  /// Parser di una lista da Firestore. Skippa entry malformate.
  static List<TerrainSegment> listFromFirestore(dynamic raw) {
    if (raw is! List) return const [];
    final out = <TerrainSegment>[];
    for (final entry in raw) {
      if (entry is Map) {
        final seg = TerrainSegment.fromMap(Map<String, dynamic>.from(entry));
        if (seg != null) out.add(seg);
      }
    }
    return out;
  }
}

/// Komoot K1b — converte i tag OSM way in un [TerrainType].
///
/// Logica decisionale a priorità decrescente (la prima regola che matcha
/// vince). Pensata per essere "good enough" senza pretendere copertura
/// del 100% delle varianti OSM possibili.
///
/// Riferimenti OSM:
/// - highway: https://wiki.openstreetmap.org/wiki/Key:highway
/// - surface: https://wiki.openstreetmap.org/wiki/Key:surface
/// - sac_scale: https://wiki.openstreetmap.org/wiki/Key:sac_scale
/// - tracktype: https://wiki.openstreetmap.org/wiki/Key:tracktype
/// - via_ferrata_scale: https://wiki.openstreetmap.org/wiki/Key:via_ferrata_scale
///
/// Pura — testabile senza I/O. Usata sia client-side (per fallback) sia
/// nella Cloud Function batch di arricchimento.
TerrainType parseTerrainFromOsmTags(Map<String, String> tags) {
  String? get(String key) {
    final v = tags[key];
    if (v == null) return null;
    final trimmed = v.trim().toLowerCase();
    return trimmed.isEmpty ? null : trimmed;
  }

  final highway = get('highway');

  // 1. Via ferrata: sempre prioritaria — sicurezza-critical
  if (highway == 'via_ferrata' ||
      tags.containsKey('via_ferrata_scale') ||
      get('climbing') == 'via_ferrata') {
    return TerrainType.viaFerrata;
  }

  final surface = get('surface');
  final sacScale = get('sac_scale');
  final tracktype = get('tracktype');

  // 2. Roccia esplicita o passaggi alpinistici (SAC >= alpine_hiking)
  const rockySurfaces = {'rock', 'rocks', 'scree', 'pebblestone', 'stone'};
  const alpineSacScales = {
    'alpine_hiking',
    'demanding_alpine_hiking',
    'difficult_alpine_hiking',
  };
  if (surface != null && rockySurfaces.contains(surface)) {
    return TerrainType.rocky;
  }
  if (sacScale != null && alpineSacScales.contains(sacScale)) {
    return TerrainType.rocky;
  }

  // 3. Asfalto: highway primary/secondary/tertiary/residential/cycleway
  //    oppure surface esplicita asfalto/cemento
  const asphaltSurfaces = {
    'asphalt',
    'paved',
    'concrete',
    'paving_stones',
    'sett',
    'cobblestone',
  };
  const asphaltHighways = {
    'primary',
    'secondary',
    'tertiary',
    'unclassified',
    'residential',
    'service',
    'cycleway',
    'living_street',
  };
  if (surface != null && asphaltSurfaces.contains(surface)) {
    return TerrainType.asphalt;
  }
  if (highway != null && asphaltHighways.contains(highway)) {
    return TerrainType.asphalt;
  }

  // 4. Sterrato: highway=track con tracktype grade1-grade3, oppure
  //    surface esplicito ghiaia/sterrato
  const gravelSurfaces = {
    'gravel',
    'fine_gravel',
    'dirt',
    'earth',
    'ground',
    'unpaved',
    'compacted',
  };
  if (surface != null && gravelSurfaces.contains(surface)) {
    return TerrainType.gravel;
  }
  if (highway == 'track') {
    // tracktype grade1/2 → sterrato compatto; grade4/5 più simile a sentiero
    if (tracktype == 'grade1' || tracktype == 'grade2' || tracktype == 'grade3') {
      return TerrainType.gravel;
    }
    if (tracktype == 'grade4' || tracktype == 'grade5') {
      return TerrainType.path;
    }
    // tracktype assente: assumiamo grade media → sterrato
    return TerrainType.gravel;
  }

  // 5. Sentiero: highway=path/footway/bridleway, sac_scale T1-T2
  if (highway == 'path' || highway == 'footway' || highway == 'bridleway') {
    return TerrainType.path;
  }
  if (sacScale == 'hiking' || sacScale == 'mountain_hiking') {
    return TerrainType.path;
  }

  // Fallback
  return TerrainType.unknown;
}

