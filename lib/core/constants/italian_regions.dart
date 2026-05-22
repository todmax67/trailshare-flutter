/// Elenco delle regioni italiane (ISO 3166-2:IT) usato per le classifiche
/// regionali e per taggare le tracce pubbliche.
///
/// Ogni regione ha un `code` (slug usato come chiave in Firestore),
/// un `nameIt` e un `nameEn` pronti per la UI, oltre a una `flag` emoji.
///
/// È presente una regione sentinella `international` per utenti fuori Italia
/// o che non vogliono specificare la posizione.
class ItalianRegion {
  /// Slug lowercase stabile. Es. `lombardia`, `trentino_alto_adige`.
  final String code;
  final String nameIt;
  final String nameEn;
  final String flag;
  /// Bounding box approssimativo (lat_min, lat_max, lng_min, lng_max).
  /// Usato dal filtro regione del Discover (4.5) per restringere
  /// rapidamente le tracce alla regione corrispondente al loro punto di
  /// partenza. Valori "generosi" — l'obiettivo è UX, non geografia
  /// catastale. `international` ha bbox vuoto (== nessun filtro).
  final double latMin;
  final double latMax;
  final double lngMin;
  final double lngMax;

  const ItalianRegion({
    required this.code,
    required this.nameIt,
    required this.nameEn,
    required this.flag,
    this.latMin = 0,
    this.latMax = 0,
    this.lngMin = 0,
    this.lngMax = 0,
  });

  /// `true` se il punto cade dentro il bbox della regione. Per il bbox
  /// vuoto (international) ritorna sempre `false` (nessun trail viene
  /// filtrato come "internazionale", l'opzione esiste per il profilo
  /// utente, non per il filtro Discover).
  bool contains(double lat, double lng) {
    if (latMin == 0 && latMax == 0) return false;
    return lat >= latMin && lat <= latMax && lng >= lngMin && lng <= lngMax;
  }

  /// Nome localizzato data la locale (due lettere).
  String displayName(String locale) =>
      locale.toLowerCase().startsWith('it') ? nameIt : nameEn;

  @override
  bool operator ==(Object other) =>
      other is ItalianRegion && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

/// Lista ufficiale delle 20 regioni italiane + sentinella "internazionale".
/// L'ordine è alfabetico per la UI.
class ItalianRegions {
  ItalianRegions._();

  static const List<ItalianRegion> all = [
    ItalianRegion(code: 'abruzzo', nameIt: 'Abruzzo', nameEn: 'Abruzzo', flag: '🏔️',
        latMin: 41.7, latMax: 42.9, lngMin: 13.0, lngMax: 14.8),
    ItalianRegion(code: 'basilicata', nameIt: 'Basilicata', nameEn: 'Basilicata', flag: '🏞️',
        latMin: 39.9, latMax: 41.1, lngMin: 15.3, lngMax: 16.9),
    ItalianRegion(code: 'calabria', nameIt: 'Calabria', nameEn: 'Calabria', flag: '🌊',
        latMin: 37.9, latMax: 40.2, lngMin: 15.6, lngMax: 17.2),
    ItalianRegion(code: 'campania', nameIt: 'Campania', nameEn: 'Campania', flag: '🌋',
        latMin: 39.9, latMax: 41.5, lngMin: 13.7, lngMax: 15.8),
    ItalianRegion(code: 'emilia_romagna', nameIt: 'Emilia-Romagna', nameEn: 'Emilia-Romagna', flag: '🏛️',
        latMin: 43.7, latMax: 45.1, lngMin: 9.2, lngMax: 12.7),
    ItalianRegion(code: 'friuli_venezia_giulia', nameIt: 'Friuli-Venezia Giulia', nameEn: 'Friuli-Venezia Giulia', flag: '🏔️',
        latMin: 45.5, latMax: 46.6, lngMin: 12.3, lngMax: 13.9),
    ItalianRegion(code: 'lazio', nameIt: 'Lazio', nameEn: 'Lazio', flag: '🏛️',
        latMin: 41.2, latMax: 42.8, lngMin: 11.4, lngMax: 14.0),
    ItalianRegion(code: 'liguria', nameIt: 'Liguria', nameEn: 'Liguria', flag: '⛵',
        latMin: 43.7, latMax: 44.7, lngMin: 7.5, lngMax: 10.0),
    ItalianRegion(code: 'lombardia', nameIt: 'Lombardia', nameEn: 'Lombardy', flag: '🏔️',
        latMin: 44.6, latMax: 46.6, lngMin: 8.5, lngMax: 11.4),
    ItalianRegion(code: 'marche', nameIt: 'Marche', nameEn: 'Marche', flag: '🏞️',
        latMin: 42.6, latMax: 43.9, lngMin: 12.2, lngMax: 13.9),
    ItalianRegion(code: 'molise', nameIt: 'Molise', nameEn: 'Molise', flag: '🌄',
        latMin: 41.4, latMax: 42.1, lngMin: 14.0, lngMax: 15.1),
    ItalianRegion(code: 'piemonte', nameIt: 'Piemonte', nameEn: 'Piedmont', flag: '🏔️',
        latMin: 44.0, latMax: 46.5, lngMin: 6.6, lngMax: 9.2),
    ItalianRegion(code: 'puglia', nameIt: 'Puglia', nameEn: 'Apulia', flag: '🌊',
        latMin: 39.7, latMax: 42.2, lngMin: 15.0, lngMax: 18.5),
    ItalianRegion(code: 'sardegna', nameIt: 'Sardegna', nameEn: 'Sardinia', flag: '🏝️',
        latMin: 38.8, latMax: 41.3, lngMin: 8.1, lngMax: 9.9),
    ItalianRegion(code: 'sicilia', nameIt: 'Sicilia', nameEn: 'Sicily', flag: '🌋',
        latMin: 36.4, latMax: 38.4, lngMin: 12.4, lngMax: 15.7),
    ItalianRegion(code: 'toscana', nameIt: 'Toscana', nameEn: 'Tuscany', flag: '🌻',
        latMin: 42.2, latMax: 44.5, lngMin: 9.6, lngMax: 12.4),
    ItalianRegion(code: 'trentino_alto_adige', nameIt: 'Trentino-Alto Adige', nameEn: 'Trentino-Alto Adige', flag: '🏔️',
        latMin: 45.6, latMax: 47.1, lngMin: 10.4, lngMax: 12.5),
    ItalianRegion(code: 'umbria', nameIt: 'Umbria', nameEn: 'Umbria', flag: '🌳',
        latMin: 42.4, latMax: 43.6, lngMin: 11.9, lngMax: 13.2),
    ItalianRegion(code: "valle_d_aosta", nameIt: "Valle d'Aosta", nameEn: "Aosta Valley", flag: '⛰️',
        latMin: 45.4, latMax: 45.9, lngMin: 6.8, lngMax: 8.0),
    ItalianRegion(code: 'veneto', nameIt: 'Veneto', nameEn: 'Veneto', flag: '🚣',
        latMin: 44.7, latMax: 46.7, lngMin: 10.6, lngMax: 13.1),
    // Sentinella: bbox 0/0 = contains() ritorna sempre false.
    ItalianRegion(code: 'international', nameIt: 'Internazionale', nameEn: 'International', flag: '🌍'),
  ];

  /// Ritorna la regione dato il code, o null se non trovata.
  static ItalianRegion? byCode(String? code) {
    if (code == null || code.isEmpty) return null;
    for (final r in all) {
      if (r.code == code) return r;
    }
    return null;
  }
}
