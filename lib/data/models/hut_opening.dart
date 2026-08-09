/// Apertura stagionale di rifugi e bivacchi.
///
/// Perche' non si riusa `openingHours` di [Business]: quello e' una
/// `Map<giorno, DayHours>`, cioe' il modello del negozio che chiude il
/// martedi'. Un rifugio non e' chiuso il martedi': e' aperto dal 20 giugno al
/// 20 settembre. Sono due assi diversi e il secondo non e' esprimibile nel
/// primo.
///
/// Il vincolo che governa tutto il file: **un dato di una stagione passata non
/// deve poter produrre la parola "aperto"**. Non per attenzione di chi scrive
/// la UI, ma per costruzione — [HutOpening.resolve] non ha un ramo che lo
/// permetta. Il motivo e' misurato: su OSM Italia dodici rifugi hanno l'orario
/// congelato al 2024 (`2024 Jun-Oct`), e due stagioni dopo quel dato non e'
/// impreciso, e' falso. Mostrarlo come "aperto" manda qualcuno a duemila metri
/// davanti a una porta sbarrata.
///
/// Vedi docs/rifugi_aperture.md per la misura completa.
library;

/// Da dove viene l'informazione, in ordine di fiducia decrescente.
enum OpeningSource {
  /// Il gestore del rifugio, dalla sua scheda. L'unica fonte che sa davvero.
  gestore,

  /// Inserita da noi verificando una fonte (sito del rifugio, sezione CAI).
  redazione,

  /// Segnalata da chi c'e' stato.
  community,

  /// Importata da OpenStreetMap. Copre l'8% ed e' spesso ferma da anni.
  osm,
}

/// Che tipo di struttura e'. Determina se la domanda "e' aperto?" ha senso.
enum HutKind {
  /// Rifugio gestito: apre e chiude, ha un custode, si prenota.
  gestito,

  /// Bivacco: non gestito, sempre accessibile, nessun servizio. Per questi la
  /// domanda non si pone — sono 2.662 punti su 6.468 in Italia, il 41%.
  bivacco,
}

/// Un giorno dell'anno senza anno: il 20 giugno, non il 20 giugno 2026.
class SeasonDay implements Comparable<SeasonDay> {
  final int month;
  final int day;

  const SeasonDay(this.month, this.day);

  /// Ordinale grezzo per il confronto: non e' un giorno giuliano, serve solo a
  /// ordinare date dentro lo stesso anno.
  int get _ord => month * 100 + day;

  @override
  int compareTo(SeasonDay other) => _ord.compareTo(other._ord);

  bool get isValid => month >= 1 && month <= 12 && day >= 1 && day <= 31;

  Map<String, dynamic> toMap() => {'m': month, 'd': day};

  factory SeasonDay.fromMap(Map<String, dynamic> m) =>
      SeasonDay((m['m'] as num).toInt(), (m['d'] as num).toInt());

  factory SeasonDay.fromDateTime(DateTime t) => SeasonDay(t.month, t.day);

  @override
  bool operator ==(Object other) =>
      other is SeasonDay && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(month, day);

  @override
  String toString() => '$day/$month';
}

/// Un intervallo di apertura.
///
/// [year] e' la distinzione che regge tutto il modello:
/// - **null** → stagione *tipica*: "di solito da giugno a ottobre". Non scade,
///   ma non e' una promessa: nessuno l'ha confermata per quest'anno.
/// - **valorizzato** → stagione *dichiarata* per quell'anno preciso. Vale
///   quanto oro finche' e' l'anno corrente, e non vale piu' niente dopo.
class OpeningPeriod {
  final int? year;
  final SeasonDay from;
  final SeasonDay to;

  const OpeningPeriod({this.year, required this.from, required this.to});

  bool get isDeclared => year != null;
  bool get isTypical => year == null;

  /// L'intervallo scavalca il capodanno (es. 1 dicembre → 31 marzo).
  bool get wrapsNewYear => to.compareTo(from) < 0;

  /// Il giorno cade dentro l'intervallo, gestendo lo scavalco.
  bool containsDay(SeasonDay d) {
    if (!wrapsNewYear) {
      return d.compareTo(from) >= 0 && d.compareTo(to) <= 0;
    }
    return d.compareTo(from) >= 0 || d.compareTo(to) <= 0;
  }

  Map<String, dynamic> toMap() => {
        if (year != null) 'year': year,
        'from': from.toMap(),
        'to': to.toMap(),
      };

  factory OpeningPeriod.fromMap(Map<String, dynamic> m) => OpeningPeriod(
        year: (m['year'] as num?)?.toInt(),
        from: SeasonDay.fromMap(Map<String, dynamic>.from(m['from'] as Map)),
        to: SeasonDay.fromMap(Map<String, dynamic>.from(m['to'] as Map)),
      );

  @override
  String toString() => '${year ?? 'ogni anno'} $from→$to';
}

/// Il verdetto mostrabile all'utente. Ogni valore corrisponde a una frase
/// diversa: nessuno di questi puo' essere reso con "aperto" tranne i primi due.
enum OpeningVerdict {
  /// Bivacco: sempre accessibile, non gestito. Certezza strutturale.
  sempreAccessibile,

  /// Dichiarato per la stagione in corso, e oggi siamo dentro.
  aperto,

  /// Dichiarato per la stagione in corso, e oggi siamo fuori.
  chiuso,

  /// Solo una stagione tipica, e oggi cade dentro. "Di solito aperto."
  probabilmenteAperto,

  /// Solo una stagione tipica, e oggi cade fuori. "Di solito chiuso."
  probabilmenteChiuso,

  /// Esiste solo un dato di stagioni passate. Non dice niente su oggi.
  soloStagioniPassate,

  /// Nessuna informazione.
  ignoto,
}

/// L'esito di [HutOpening.resolve]: il verdetto piu' il contesto che la UI deve
/// mostrare accanto, mai da solo.
class OpeningStatus {
  final OpeningVerdict verdict;

  /// Il periodo su cui si basa il verdetto, se ce n'e' uno.
  final OpeningPeriod? basedOn;

  /// Da dove viene il dato usato.
  final OpeningSource? source;

  /// Quando e' stato aggiornato l'ultima volta.
  final DateTime? updatedAt;

  /// Da quanti giorni non viene toccato. `null` se non lo sappiamo.
  final int? ageInDays;

  const OpeningStatus({
    required this.verdict,
    this.basedOn,
    this.source,
    this.updatedAt,
    this.ageInDays,
  });

  /// Vero solo quando possiamo dire "aperto" senza mentire.
  bool get canSayOpen =>
      verdict == OpeningVerdict.aperto ||
      verdict == OpeningVerdict.sempreAccessibile;

  /// La UI deve mostrare un avviso sull'affidabilita' accanto al verdetto.
  bool get needsCaveat =>
      verdict != OpeningVerdict.sempreAccessibile &&
      verdict != OpeningVerdict.aperto;

  @override
  String toString() => 'OpeningStatus($verdict, da: $basedOn, fonte: $source)';
}

/// L'apertura di una struttura, con dentro tutto ciò che serve a non mentire.
class HutOpening {
  final HutKind kind;
  final List<OpeningPeriod> periods;
  final OpeningSource? source;
  final DateTime? updatedAt;

  /// Testo libero del gestore: "a settembre solo nei weekend", "prenotazione
  /// obbligatoria". Non viene interpretato, solo mostrato.
  final String? note;

  const HutOpening({
    required this.kind,
    this.periods = const [],
    this.source,
    this.updatedAt,
    this.note,
  });

  /// Un bivacco, che non ha bisogno di dati: la categoria e' la risposta.
  const HutOpening.bivacco()
      : kind = HutKind.bivacco,
        periods = const [],
        source = null,
        updatedAt = null,
        note = null;

  /// Che cosa possiamo onestamente dire oggi.
  ///
  /// [now] e' iniettabile per i test. [seasonYear] permette di trattare una
  /// stagione invernale a cavallo d'anno come una sola: se non passato, e'
  /// semplicemente l'anno di [now].
  OpeningStatus resolve({DateTime? now, int? seasonYear}) {
    final today = now ?? DateTime.now();
    final year = seasonYear ?? today.year;
    final age = updatedAt == null ? null : today.difference(updatedAt!).inDays;

    if (kind == HutKind.bivacco) {
      return const OpeningStatus(verdict: OpeningVerdict.sempreAccessibile);
    }

    if (periods.isEmpty) {
      return OpeningStatus(
        verdict: OpeningVerdict.ignoto,
        source: source,
        updatedAt: updatedAt,
        ageInDays: age,
      );
    }

    final d = SeasonDay.fromDateTime(today);

    // 1. Stagione dichiarata per l'anno corrente: e' l'unica che autorizza
    //    "aperto" o "chiuso" secchi.
    final declaredNow = periods.where((p) => p.year == year).toList();
    if (declaredNow.isNotEmpty) {
      final hit = declaredNow.where((p) => p.containsDay(d)).firstOrNull;
      return OpeningStatus(
        verdict: hit != null ? OpeningVerdict.aperto : OpeningVerdict.chiuso,
        basedOn: hit ?? declaredNow.first,
        source: source,
        updatedAt: updatedAt,
        ageInDays: age,
      );
    }

    // 2. Stagione tipica: si puo' solo ipotizzare.
    final typical = periods.where((p) => p.isTypical).toList();
    if (typical.isNotEmpty) {
      final hit = typical.where((p) => p.containsDay(d)).firstOrNull;
      return OpeningStatus(
        verdict: hit != null
            ? OpeningVerdict.probabilmenteAperto
            : OpeningVerdict.probabilmenteChiuso,
        basedOn: hit ?? typical.first,
        source: source,
        updatedAt: updatedAt,
        ageInDays: age,
      );
    }

    // 3. Restano solo stagioni di anni passati (o futuri non ancora iniziati).
    //    Qui NON esiste un ramo che dica "aperto": e' il punto di tutto il file.
    final past = periods.where((p) => p.isDeclared).toList()
      ..sort((a, b) => b.year!.compareTo(a.year!));
    return OpeningStatus(
      verdict: OpeningVerdict.soloStagioniPassate,
      basedOn: past.first,
      source: source,
      updatedAt: updatedAt,
      ageInDays: age,
    );
  }

  Map<String, dynamic> toMap() => {
        'kind': kind.name,
        if (periods.isNotEmpty)
          'periods': periods.map((p) => p.toMap()).toList(),
        if (source != null) 'source': source!.name,
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
        if (note != null && note!.isNotEmpty) 'note': note,
      };

  factory HutOpening.fromMap(Map<String, dynamic> m) {
    final rawPeriods = (m['periods'] as List?) ?? const [];
    return HutOpening(
      kind: HutKind.values.firstWhere(
        (k) => k.name == m['kind'],
        orElse: () => HutKind.gestito,
      ),
      periods: rawPeriods
          .map((p) => OpeningPeriod.fromMap(Map<String, dynamic>.from(p as Map)))
          .toList(),
      source: m['source'] == null
          ? null
          : OpeningSource.values.firstWhere(
              (s) => s.name == m['source'],
              orElse: () => OpeningSource.osm,
            ),
      updatedAt:
          m['updatedAt'] == null ? null : DateTime.tryParse(m['updatedAt'] as String),
      note: m['note'] as String?,
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
