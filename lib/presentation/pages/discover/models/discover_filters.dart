import 'package:flutter/material.dart';

/// Categoria di attività (raggruppamento dei vari activityType OSM)
enum ActivityCategory {
  foot('A piedi', Icons.directions_walk),
  bike('Bici', Icons.directions_bike),
  snow('Neve', Icons.downhill_skiing);

  final String label;
  final IconData icon;
  const ActivityCategory(this.label, this.icon);
}

/// Criterio di ordinamento per la lista sentieri
enum TrailSortBy {
  defaultOrder('Predefinito'),
  distance('Distanza'),
  lengthAsc('Lunghezza ↑'),
  lengthDesc('Lunghezza ↓'),
  elevationAsc('Dislivello ↑'),
  elevationDesc('Dislivello ↓'),
  difficultyAsc('Difficoltà ↑');

  final String label;
  const TrailSortBy(this.label);
}

/// Stato immutabile dei filtri della pagina Scopri
@immutable
class DiscoverFilters {
  /// Codici difficoltà CAI: 't', 'e', 'ee', 'eea'
  final Set<String> difficulties;

  /// Range lunghezza in km (null = nessun filtro)
  final RangeValues? lengthKm;

  /// Range dislivello in metri (null = nessun filtro)
  final RangeValues? elevation;

  /// Categorie attività selezionate
  final Set<ActivityCategory> categories;

  /// Mostra solo sentieri circolari
  final bool onlyCircular;

  /// Ordinamento lista
  final TrailSortBy sortBy;

  /// Epic 4.5 — codice regione amministrativa italiana (vedi
  /// [ItalianRegion.code]). Null = nessun filtro regionale. La
  /// regione `international` non è usata come filtro (sentinella
  /// profilo utente). Il filtro confronta il primo punto del trail
  /// con il bbox della regione.
  final String? regionCode;

  const DiscoverFilters({
    this.difficulties = const {},
    this.lengthKm,
    this.elevation,
    this.categories = const {},
    this.onlyCircular = false,
    this.sortBy = TrailSortBy.defaultOrder,
    this.regionCode,
  });

  const DiscoverFilters.empty() : this();

  /// Numero di filtri attivi (per badge UI)
  int get activeCount {
    var count = 0;
    if (difficulties.isNotEmpty) count++;
    if (lengthKm != null) count++;
    if (elevation != null) count++;
    if (categories.isNotEmpty) count++;
    if (onlyCircular) count++;
    if (sortBy != TrailSortBy.defaultOrder) count++;
    if (regionCode != null && regionCode!.isNotEmpty) count++;
    return count;
  }

  bool get isEmpty => activeCount == 0;

  DiscoverFilters copyWith({
    Set<String>? difficulties,
    RangeValues? lengthKm,
    bool clearLengthKm = false,
    RangeValues? elevation,
    bool clearElevation = false,
    Set<ActivityCategory>? categories,
    bool? onlyCircular,
    TrailSortBy? sortBy,
    String? regionCode,
    bool clearRegion = false,
  }) {
    return DiscoverFilters(
      difficulties: difficulties ?? this.difficulties,
      lengthKm: clearLengthKm ? null : (lengthKm ?? this.lengthKm),
      elevation: clearElevation ? null : (elevation ?? this.elevation),
      categories: categories ?? this.categories,
      onlyCircular: onlyCircular ?? this.onlyCircular,
      sortBy: sortBy ?? this.sortBy,
      regionCode: clearRegion ? null : (regionCode ?? this.regionCode),
    );
  }
}
