import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  /// Codici difficoltà CAI: 't', 'e', 'ee', 'eea', più il valore speciale
  /// [nonClassificato].
  ///
  /// Il grado tecnico è rilevato su meno della metà del catalogo: prima
  /// questo filtro faceva sparire in silenzio tutti gli altri, cioè la
  /// maggioranza. Ora "non classificato" è una scelta come le altre, così
  /// l'utente sa che esistono e decide lui.
  final Set<String> difficulties;

  /// Chiave per i sentieri di cui non conosciamo la difficoltà tecnica.
  static const nonClassificato = 'nd';

  /// Nasconde i sentieri di cui non conosciamo la difficolta' TECNICA, cioe'
  /// quelli il cui grado e' una stima storica invece di un rilievo.
  ///
  /// Serve perche' la vecchia euristica su lunghezza e dislivello sbagliava
  /// nel 58% dei casi dove abbiamo potuto verificarla: tenerla nel filtro
  /// come se fosse un dato accertato ingannava, toglierla d'ufficio avrebbe
  /// svuotato la ricerca. Cosi' decide chi cerca.
  final bool excludeUnclassified;

  /// Nasconde le vie attrezzate (imbrago, casco, set da ferrata).
  /// Possibile solo da quando le riconosciamo dai tag OSM: prima 168 non
  /// erano nemmeno individuabili, e 136 risultavano "turistiche".
  final bool excludeViaFerrata;

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
  /// [GeoRegion.code]). Null = nessun filtro regionale. La
  /// regione `international` non è usata come filtro (sentinella
  /// profilo utente). Il filtro confronta il primo punto del trail
  /// con il bbox della regione.
  final String? regionCode;

  /// Layer POI: mostra sulla mappa le colonnine di ricarica e-bike
  /// (OSM, asset bundlato). Non filtra i sentieri — aggiunge marker.
  final bool showEbikeCharging;

  const DiscoverFilters({
    this.difficulties = const {},
    this.excludeUnclassified = false,
    this.excludeViaFerrata = false,
    this.lengthKm,
    this.elevation,
    this.categories = const {},
    this.onlyCircular = false,
    this.sortBy = TrailSortBy.defaultOrder,
    this.regionCode,
    this.showEbikeCharging = false,
  });

  const DiscoverFilters.empty() : this();

  /// Numero di filtri attivi (per badge UI)
  int get activeCount {
    var count = 0;
    if (difficulties.isNotEmpty) count++;
    if (excludeUnclassified) count++;
    if (excludeViaFerrata) count++;
    if (lengthKm != null) count++;
    if (elevation != null) count++;
    if (categories.isNotEmpty) count++;
    if (onlyCircular) count++;
    if (sortBy != TrailSortBy.defaultOrder) count++;
    if (regionCode != null && regionCode!.isNotEmpty) count++;
    if (showEbikeCharging) count++;
    return count;
  }

  bool get isEmpty => activeCount == 0;

  // ── Persistenza (tasto "Salva filtri" nello sheet) ──────────────────
  //
  // Chi fa sempre la stessa attività (trekking, e-bike…) imposta i filtri
  // una volta e li ritrova a ogni apertura della mappa. Salvataggio
  // esplicito (non automatico): l'utente decide quale set è "il suo".

  static const String _prefsKey = 'discover_saved_filters_v1';

  Map<String, dynamic> toJson() => {
        'difficulties': difficulties.toList(),
        'excludeUnclassified': excludeUnclassified,
        'excludeViaFerrata': excludeViaFerrata,
        if (lengthKm != null) 'lengthKm': [lengthKm!.start, lengthKm!.end],
        if (elevation != null) 'elevation': [elevation!.start, elevation!.end],
        'categories': categories.map((c) => c.name).toList(),
        'onlyCircular': onlyCircular,
        'sortBy': sortBy.name,
        if (regionCode != null) 'regionCode': regionCode,
        'showEbikeCharging': showEbikeCharging,
      };

  factory DiscoverFilters.fromJson(Map<String, dynamic> j) {
    RangeValues? range(dynamic v) => v is List && v.length == 2
        ? RangeValues((v[0] as num).toDouble(), (v[1] as num).toDouble())
        : null;
    return DiscoverFilters(
      difficulties:
          ((j['difficulties'] as List?) ?? const []).cast<String>().toSet(),
      excludeUnclassified: j['excludeUnclassified'] == true,
      excludeViaFerrata: j['excludeViaFerrata'] == true,
      lengthKm: range(j['lengthKm']),
      elevation: range(j['elevation']),
      categories: ((j['categories'] as List?) ?? const [])
          .map((n) => ActivityCategory.values
              .where((c) => c.name == n)
              .firstOrNull)
          .whereType<ActivityCategory>()
          .toSet(),
      onlyCircular: j['onlyCircular'] == true,
      sortBy: TrailSortBy.values
              .where((s) => s.name == j['sortBy'])
              .firstOrNull ??
          TrailSortBy.defaultOrder,
      regionCode: j['regionCode'] as String?,
      showEbikeCharging: j['showEbikeCharging'] == true,
    );
  }

  /// Salva questi filtri come predefiniti dell'utente.
  Future<void> saveAsDefault() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(toJson()));
    } catch (e) {
      debugPrint('[DiscoverFilters] save error: $e');
    }
  }

  /// Carica i filtri salvati (null se mai salvati o illeggibili).
  static Future<DiscoverFilters?> loadSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return null;
      return DiscoverFilters.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[DiscoverFilters] load error: $e');
      return null;
    }
  }

  DiscoverFilters copyWith({
    Set<String>? difficulties,
    bool? excludeUnclassified,
    bool? excludeViaFerrata,
    RangeValues? lengthKm,
    bool clearLengthKm = false,
    RangeValues? elevation,
    bool clearElevation = false,
    Set<ActivityCategory>? categories,
    bool? onlyCircular,
    TrailSortBy? sortBy,
    String? regionCode,
    bool clearRegion = false,
    bool? showEbikeCharging,
  }) {
    return DiscoverFilters(
      difficulties: difficulties ?? this.difficulties,
      excludeUnclassified: excludeUnclassified ?? this.excludeUnclassified,
      excludeViaFerrata: excludeViaFerrata ?? this.excludeViaFerrata,
      lengthKm: clearLengthKm ? null : (lengthKm ?? this.lengthKm),
      elevation: clearElevation ? null : (elevation ?? this.elevation),
      categories: categories ?? this.categories,
      onlyCircular: onlyCircular ?? this.onlyCircular,
      sortBy: sortBy ?? this.sortBy,
      regionCode: clearRegion ? null : (regionCode ?? this.regionCode),
      showEbikeCharging: showEbikeCharging ?? this.showEbikeCharging,
    );
  }
}
