/// Regioni geografiche usate per classifiche, filtri e tagging dei
/// contenuti. Sostituisce il vecchio `ItalianRegions`, che assumeva
/// implicitamente l'Italia.
///
/// ## Perché esiste `countryCode`
///
/// I bounding box NON sanno fare i confini: sono rettangoli, e sulle
/// Alpi i rettangoli si accavallano tra stati. Esempi reali misurati:
/// Chamonix (Francia) cade dentro il bbox del Piemonte, e la Val Trient
/// (Svizzera) cade dentro quello dell'Alta Savoia. Per mesi questo ha
/// prodotto sentieri francesi e svizzeri etichettati "Piemonte".
///
/// Quindi: il **paese è un dato memorizzato** sul contenuto (campo
/// `country`, ISO 3166-1 alpha-2), non dedotto a runtime. Si ricava una
/// volta sola con un reverse geocoding autorevole e si salva. I bbox qui
/// sotto restano solo come ripiego grossolano per i contenuti storici
/// che quel campo non ce l'hanno ancora.
class GeoRegion {
  /// Slug lowercase stabile, chiave in Firestore. Es. `lombardia`,
  /// `haute_savoie`. Unico su tutti i paesi.
  final String code;

  /// ISO 3166-1 alpha-2 del paese. `''` per la sentinella.
  final String countryCode;

  final String nameIt;
  final String nameEn;

  /// Emoji che caratterizza la regione (terreno, non bandiera: la
  /// bandiera del paese si ottiene da [countryFlag]).
  final String flag;

  /// Bounding box approssimativo. Ripiego per i contenuti senza
  /// `country`/`region` salvati — vedi nota di classe sui suoi limiti.
  /// La sentinella ha bbox 0/0 = non contiene mai nulla.
  final double latMin;
  final double latMax;
  final double lngMin;
  final double lngMax;

  const GeoRegion({
    required this.code,
    required this.countryCode,
    required this.nameIt,
    required this.nameEn,
    required this.flag,
    this.latMin = 0,
    this.latMax = 0,
    this.lngMin = 0,
    this.lngMax = 0,
  });

  bool get isSentinel => latMin == 0 && latMax == 0;

  bool contains(double lat, double lng) {
    if (isSentinel) return false;
    return lat >= latMin && lat <= latMax && lng >= lngMin && lng <= lngMax;
  }

  /// Area del bbox in gradi quadri — serve a [GeoRegions.resolveByBbox]
  /// per preferire la regione più specifica quando i rettangoli si
  /// sovrappongono.
  double get bboxArea =>
      isSentinel ? double.infinity : (latMax - latMin) * (lngMax - lngMin);

  /// Bandiera del paese come emoji, derivata dal codice ISO.
  String get countryFlag {
    if (countryCode.length != 2) return '🌍';
    const base = 0x1F1E6; // 🇦
    return String.fromCharCodes(
      countryCode.toUpperCase().codeUnits.map((c) => base + (c - 0x41)),
    );
  }

  String displayName(String locale) =>
      locale.toLowerCase().startsWith('it') ? nameIt : nameEn;

  /// Etichetta con bandiera del paese, per distinguere a colpo d'occhio
  /// le regioni estere nei picker.
  String displayNameWithCountry(String locale) =>
      '$countryFlag ${displayName(locale)}';

  @override
  bool operator ==(Object other) => other is GeoRegion && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

/// Registro delle regioni conosciute. Italia completa; dei paesi alpini
/// confinanti sono presenti per ora solo le regioni effettivamente
/// coperte dai contenuti (espansione incrementale — vedi ROADMAP).
class GeoRegions {
  GeoRegions._();

  /// Paesi con almeno una regione a catalogo, in ordine di priorità.
  static const List<String> countries = ['IT', 'FR', 'CH', 'AT', 'SI', 'HR', 'HU'];

  static const Map<String, String> countryNamesIt = {
    'IT': 'Italia',
    'FR': 'Francia',
    'CH': 'Svizzera',
    'AT': 'Austria',
    'SI': 'Slovenia',
    'HR': 'Croazia',
    'HU': 'Ungheria',
    'DE': 'Germania',
  };

  static const Map<String, String> countryNamesEn = {
    'IT': 'Italy',
    'FR': 'France',
    'CH': 'Switzerland',
    'AT': 'Austria',
    'SI': 'Slovenia',
    'HR': 'Croatia',
    'HU': 'Hungary',
    'DE': 'Germany',
  };

  static const List<GeoRegion> all = [
    // ─── Italia (ISO 3166-2:IT) ──────────────────────────────────────
    GeoRegion(code: 'abruzzo', countryCode: 'IT', nameIt: 'Abruzzo', nameEn: 'Abruzzo', flag: '🏔️',
        latMin: 41.7, latMax: 42.9, lngMin: 13.0, lngMax: 14.8),
    GeoRegion(code: 'basilicata', countryCode: 'IT', nameIt: 'Basilicata', nameEn: 'Basilicata', flag: '🏞️',
        latMin: 39.9, latMax: 41.1, lngMin: 15.3, lngMax: 16.9),
    GeoRegion(code: 'calabria', countryCode: 'IT', nameIt: 'Calabria', nameEn: 'Calabria', flag: '🌊',
        latMin: 37.9, latMax: 40.2, lngMin: 15.6, lngMax: 17.2),
    GeoRegion(code: 'campania', countryCode: 'IT', nameIt: 'Campania', nameEn: 'Campania', flag: '🌋',
        latMin: 39.9, latMax: 41.5, lngMin: 13.7, lngMax: 15.8),
    GeoRegion(code: 'emilia_romagna', countryCode: 'IT', nameIt: 'Emilia-Romagna', nameEn: 'Emilia-Romagna', flag: '🏛️',
        latMin: 43.7, latMax: 45.1, lngMin: 9.2, lngMax: 12.7),
    GeoRegion(code: 'friuli_venezia_giulia', countryCode: 'IT', nameIt: 'Friuli-Venezia Giulia', nameEn: 'Friuli-Venezia Giulia', flag: '🏔️',
        latMin: 45.5, latMax: 46.6, lngMin: 12.3, lngMax: 13.9),
    GeoRegion(code: 'lazio', countryCode: 'IT', nameIt: 'Lazio', nameEn: 'Lazio', flag: '🏛️',
        latMin: 41.2, latMax: 42.8, lngMin: 11.4, lngMax: 14.0),
    GeoRegion(code: 'liguria', countryCode: 'IT', nameIt: 'Liguria', nameEn: 'Liguria', flag: '⛵',
        latMin: 43.7, latMax: 44.7, lngMin: 7.5, lngMax: 10.0),
    GeoRegion(code: 'lombardia', countryCode: 'IT', nameIt: 'Lombardia', nameEn: 'Lombardy', flag: '🏔️',
        latMin: 44.6, latMax: 46.6, lngMin: 8.5, lngMax: 11.4),
    GeoRegion(code: 'marche', countryCode: 'IT', nameIt: 'Marche', nameEn: 'Marche', flag: '🏞️',
        latMin: 42.6, latMax: 43.9, lngMin: 12.2, lngMax: 13.9),
    GeoRegion(code: 'molise', countryCode: 'IT', nameIt: 'Molise', nameEn: 'Molise', flag: '🌄',
        latMin: 41.4, latMax: 42.1, lngMin: 14.0, lngMax: 15.1),
    GeoRegion(code: 'piemonte', countryCode: 'IT', nameIt: 'Piemonte', nameEn: 'Piedmont', flag: '🏔️',
        latMin: 44.0, latMax: 46.5, lngMin: 6.6, lngMax: 9.2),
    GeoRegion(code: 'puglia', countryCode: 'IT', nameIt: 'Puglia', nameEn: 'Apulia', flag: '🌊',
        latMin: 39.7, latMax: 42.2, lngMin: 15.0, lngMax: 18.5),
    GeoRegion(code: 'sardegna', countryCode: 'IT', nameIt: 'Sardegna', nameEn: 'Sardinia', flag: '🏝️',
        latMin: 38.8, latMax: 41.3, lngMin: 8.1, lngMax: 9.9),
    GeoRegion(code: 'sicilia', countryCode: 'IT', nameIt: 'Sicilia', nameEn: 'Sicily', flag: '🌋',
        latMin: 36.4, latMax: 38.4, lngMin: 12.4, lngMax: 15.7),
    GeoRegion(code: 'toscana', countryCode: 'IT', nameIt: 'Toscana', nameEn: 'Tuscany', flag: '🌻',
        latMin: 42.2, latMax: 44.5, lngMin: 9.6, lngMax: 12.4),
    GeoRegion(code: 'trentino_alto_adige', countryCode: 'IT', nameIt: 'Trentino-Alto Adige', nameEn: 'Trentino-Alto Adige', flag: '🏔️',
        latMin: 45.6, latMax: 47.1, lngMin: 10.4, lngMax: 12.5),
    GeoRegion(code: 'umbria', countryCode: 'IT', nameIt: 'Umbria', nameEn: 'Umbria', flag: '🌳',
        latMin: 42.4, latMax: 43.6, lngMin: 11.9, lngMax: 13.2),
    GeoRegion(code: "valle_d_aosta", countryCode: 'IT', nameIt: "Valle d'Aosta", nameEn: "Aosta Valley", flag: '⛰️',
        latMin: 45.4, latMax: 45.9, lngMin: 6.8, lngMax: 8.0),
    GeoRegion(code: 'veneto', countryCode: 'IT', nameIt: 'Veneto', nameEn: 'Veneto', flag: '🚣',
        latMin: 44.7, latMax: 46.7, lngMin: 10.6, lngMax: 13.1),

    // ─── Francia (ISO 3166-2:FR) ─────────────────────────────────────
    // Bbox dai confini amministrativi reali (Nominatim, lug 2026).
    GeoRegion(code: 'haute_savoie', countryCode: 'FR', nameIt: 'Alta Savoia', nameEn: 'Haute-Savoie', flag: '🏔️',
        latMin: 45.6817, latMax: 46.4564, lngMin: 5.8051, lngMax: 7.0445),
    GeoRegion(code: 'savoie', countryCode: 'FR', nameIt: 'Savoia', nameEn: 'Savoie', flag: '🏔️',
        latMin: 45.0516, latMax: 45.9383, lngMin: 5.6218, lngMax: 7.1859),

    // ─── Svizzera (ISO 3166-2:CH) ────────────────────────────────────
    GeoRegion(code: 'valais', countryCode: 'CH', nameIt: 'Vallese', nameEn: 'Valais', flag: '⛰️',
        latMin: 45.8582, latMax: 46.6540, lngMin: 6.7706, lngMax: 8.4785),


    // ── Francia (dipartimenti alpini) ──
    GeoRegion(code: 'isere', countryCode: 'FR', nameIt: 'Isère', nameEn: 'Isère', flag: '🏔️',
        latMin: 44.6959, latMax: 45.8836, lngMin: 4.7416, lngMax: 6.3591),
    GeoRegion(code: 'hautes_alpes', countryCode: 'FR', nameIt: 'Alte Alpi', nameEn: 'Hautes-Alpes', flag: '🏔️',
        latMin: 44.1864, latMax: 45.1266, lngMin: 5.4184, lngMax: 7.0771),
    GeoRegion(code: 'alpes_maritimes', countryCode: 'FR', nameIt: 'Alpi Marittime', nameEn: 'Alpes-Maritimes', flag: '🏔️',
        latMin: 43.4801, latMax: 44.3625, lngMin: 6.6352, lngMax: 7.719),
    GeoRegion(code: 'alpes_hte_provence', countryCode: 'FR', nameIt: 'Alpi dell\'Alta Provenza', nameEn: 'Alpes-de-Haute-Provence', flag: '🏔️',
        latMin: 43.6682, latMax: 44.6599, lngMin: 5.4964, lngMax: 6.9691),

    // ── Svizzera (cantoni) ──
    GeoRegion(code: 'ticino', countryCode: 'CH', nameIt: 'Ticino', nameEn: 'Ticino', flag: '⛰️',
        latMin: 45.818, latMax: 46.6325, lngMin: 8.3822, lngMax: 9.1597),
    GeoRegion(code: 'grigioni', countryCode: 'CH', nameIt: 'Grigioni', nameEn: 'Grisons', flag: '⛰️',
        latMin: 46.1691, latMax: 47.0651, lngMin: 8.6511, lngMax: 10.4922),
    GeoRegion(code: 'vaud', countryCode: 'CH', nameIt: 'Vaud', nameEn: 'Vaud', flag: '⛰️',
        latMin: 46.1871, latMax: 46.9869, lngMin: 6.0639, lngMax: 7.2492),
    GeoRegion(code: 'berna', countryCode: 'CH', nameIt: 'Berna', nameEn: 'Bern', flag: '⛰️',
        latMin: 46.3265, latMax: 47.3453, lngMin: 6.8615, lngMax: 8.4552),
    GeoRegion(code: 'friburgo', countryCode: 'CH', nameIt: 'Friburgo', nameEn: 'Fribourg', flag: '⛰️',
        latMin: 46.4379, latMax: 47.0068, lngMin: 6.7419, lngMax: 7.3802),

    // ── Austria (Länder) ──
    GeoRegion(code: 'tirolo', countryCode: 'AT', nameIt: 'Tirolo', nameEn: 'Tyrol', flag: '🏔️',
        latMin: 46.6514, latMax: 47.743, lngMin: 10.0978, lngMax: 12.966),
    GeoRegion(code: 'carinzia', countryCode: 'AT', nameIt: 'Carinzia', nameEn: 'Carinthia', flag: '🏔️',
        latMin: 46.3723, latMax: 47.1313, lngMin: 12.6568, lngMax: 15.0652),
    GeoRegion(code: 'vorarlberg', countryCode: 'AT', nameIt: 'Vorarlberg', nameEn: 'Vorarlberg', flag: '🏔️',
        latMin: 46.8409, latMax: 47.5961, lngMin: 9.5307, lngMax: 10.2372),
    GeoRegion(code: 'stiria', countryCode: 'AT', nameIt: 'Stiria', nameEn: 'Styria', flag: '🏔️',
        latMin: 46.612, latMax: 47.8279, lngMin: 13.5633, lngMax: 16.1718),

    // ── Slovenia ──
    GeoRegion(code: 'slovenia', countryCode: 'SI', nameIt: 'Slovenia', nameEn: 'Slovenia', flag: '🏔️',
        latMin: 45.4215, latMax: 46.8767, lngMin: 13.3755, lngMax: 16.5967),

    // ── Croazia (ISO 3166-2:HR) ──
    // Arrivata di rimbalzo: gli sweep di Slovenia e Stiria sfiorano il
    // confine e hanno portato 215 sentieri croati. Copertura PARZIALE,
    // sulle contee dove i contenuti ci sono davvero — chi cade fuori
    // resta con `country` e senza regione, che e' meglio di un'etichetta
    // sbagliata.
    GeoRegion(code: 'zagabria', countryCode: 'HR', nameIt: 'Regione di Zagabria', nameEn: 'Zagreb County', flag: '🏞️',
        latMin: 45.4671, latMax: 46.0717, lngMin: 15.3279, lngMax: 16.7141),
    GeoRegion(code: 'karlovac', countryCode: 'HR', nameIt: 'Karlovac', nameEn: 'Karlovac', flag: '🏞️',
        latMin: 44.8797, latMax: 45.7625, lngMin: 14.9612, lngMax: 15.9251),
    GeoRegion(code: 'primorje_gorski', countryCode: 'HR', nameIt: 'Litorale-Gorski Kotar', nameEn: 'Primorje-Gorski Kotar', flag: '⛰️',
        latMin: 44.2603, latMax: 45.6729, lngMin: 13.9172, lngMax: 15.2352),
    GeoRegion(code: 'istria', countryCode: 'HR', nameIt: 'Istria', nameEn: 'Istria', flag: '🌊',
        latMin: 44.4689, latMax: 45.5884, lngMin: 13.2125, lngMax: 14.2586),

    // ── Ungheria (ISO 3166-2:HU) ──
    // Solo la fascia occidentale confinante: 9 sentieri in tutto.
    GeoRegion(code: 'vas', countryCode: 'HU', nameIt: 'Vas', nameEn: 'Vas', flag: '🌳',
        latMin: 46.7142, latMax: 47.4608, lngMin: 16.1139, lngMax: 17.2957),
    GeoRegion(code: 'zala', countryCode: 'HU', nameIt: 'Zala', nameEn: 'Zala', flag: '🌳',
        latMin: 46.2912, latMax: 47.0491, lngMin: 16.3626, lngMax: 17.4191),

    // Sentinella per chi non vuole dichiarare la posizione.
    GeoRegion(code: 'international', countryCode: '', nameIt: 'Internazionale', nameEn: 'International', flag: '🌍'),
  ];

  static GeoRegion? byCode(String? code) {
    if (code == null || code.isEmpty) return null;
    for (final r in all) {
      if (r.code == code) return r;
    }
    return null;
  }

  /// Regioni di un paese, nell'ordine di dichiarazione.
  static List<GeoRegion> byCountry(String countryCode) =>
      all.where((r) => r.countryCode == countryCode).toList();

  /// Ripiego per i contenuti che non hanno ancora `country`/`region`
  /// salvati: sceglie la regione col bbox PIÙ PICCOLO tra quelle che
  /// contengono il punto, così un'area piccola vince su una grande che
  /// la ingloba (Valle d'Aosta batte Piemonte).
  ///
  /// ⚠️ Resta un'approssimazione: sui confini i rettangoli si
  /// accavallano e può sbagliare paese. Da usare solo per i dati
  /// storici — per i contenuti nuovi il paese va salvato all'origine.
  static GeoRegion? resolveByBbox(double lat, double lng) {
    GeoRegion? best;
    for (final r in all) {
      if (!r.contains(lat, lng)) continue;
      if (best == null || r.bboxArea < best.bboxArea) best = r;
    }
    return best;
  }

  static String countryName(String countryCode, String locale) {
    final map = locale.toLowerCase().startsWith('it')
        ? countryNamesIt
        : countryNamesEn;
    return map[countryCode.toUpperCase()] ?? countryCode;
  }
}
