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

  const ItalianRegion({
    required this.code,
    required this.nameIt,
    required this.nameEn,
    required this.flag,
  });

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
    ItalianRegion(code: 'abruzzo', nameIt: 'Abruzzo', nameEn: 'Abruzzo', flag: '🏔️'),
    ItalianRegion(code: 'basilicata', nameIt: 'Basilicata', nameEn: 'Basilicata', flag: '🏞️'),
    ItalianRegion(code: 'calabria', nameIt: 'Calabria', nameEn: 'Calabria', flag: '🌊'),
    ItalianRegion(code: 'campania', nameIt: 'Campania', nameEn: 'Campania', flag: '🌋'),
    ItalianRegion(code: 'emilia_romagna', nameIt: 'Emilia-Romagna', nameEn: 'Emilia-Romagna', flag: '🏛️'),
    ItalianRegion(code: 'friuli_venezia_giulia', nameIt: 'Friuli-Venezia Giulia', nameEn: 'Friuli-Venezia Giulia', flag: '🏔️'),
    ItalianRegion(code: 'lazio', nameIt: 'Lazio', nameEn: 'Lazio', flag: '🏛️'),
    ItalianRegion(code: 'liguria', nameIt: 'Liguria', nameEn: 'Liguria', flag: '⛵'),
    ItalianRegion(code: 'lombardia', nameIt: 'Lombardia', nameEn: 'Lombardy', flag: '🏔️'),
    ItalianRegion(code: 'marche', nameIt: 'Marche', nameEn: 'Marche', flag: '🏞️'),
    ItalianRegion(code: 'molise', nameIt: 'Molise', nameEn: 'Molise', flag: '🌄'),
    ItalianRegion(code: 'piemonte', nameIt: 'Piemonte', nameEn: 'Piedmont', flag: '🏔️'),
    ItalianRegion(code: 'puglia', nameIt: 'Puglia', nameEn: 'Apulia', flag: '🌊'),
    ItalianRegion(code: 'sardegna', nameIt: 'Sardegna', nameEn: 'Sardinia', flag: '🏝️'),
    ItalianRegion(code: 'sicilia', nameIt: 'Sicilia', nameEn: 'Sicily', flag: '🌋'),
    ItalianRegion(code: 'toscana', nameIt: 'Toscana', nameEn: 'Tuscany', flag: '🌻'),
    ItalianRegion(code: 'trentino_alto_adige', nameIt: 'Trentino-Alto Adige', nameEn: 'Trentino-Alto Adige', flag: '🏔️'),
    ItalianRegion(code: 'umbria', nameIt: 'Umbria', nameEn: 'Umbria', flag: '🌳'),
    ItalianRegion(code: "valle_d_aosta", nameIt: "Valle d'Aosta", nameEn: "Aosta Valley", flag: '⛰️'),
    ItalianRegion(code: 'veneto', nameIt: 'Veneto', nameEn: 'Veneto', flag: '🚣'),
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
