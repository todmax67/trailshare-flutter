import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/data/models/hut_opening.dart';

/// Il test che conta e' il primo gruppo: un dato di stagioni passate non deve
/// poter produrre "aperto". Gli altri servono a non romperlo per sbaglio.
void main() {
  // Un rifugio che nel 2024 apriva da giugno a ottobre e non e' piu' stato
  // toccato. E' un caso reale: su OSM Italia sono dodici, scritti '2024 Jun-Oct'.
  final abbandonato = HutOpening(
    kind: HutKind.gestito,
    source: OpeningSource.osm,
    updatedAt: DateTime(2024, 5, 2),
    periods: const [
      OpeningPeriod(
        year: 2024,
        from: SeasonDay(6, 1),
        to: SeasonDay(10, 31),
      ),
    ],
  );

  group('un dato scaduto non puo' ' diventare "aperto"', () {
    test('in pieno agosto 2026, quando il periodo 2024 conterrebbe oggi', () {
      final s = abbandonato.resolve(now: DateTime(2026, 8, 9));

      // Il 9 agosto cade dentro giugno-ottobre: se il modello guardasse solo
      // i giorni direbbe "aperto". Deve invece dire che sa solo del passato.
      expect(s.verdict, OpeningVerdict.soloStagioniPassate);
      expect(s.canSayOpen, isFalse);
      expect(s.needsCaveat, isTrue);
    });

    test('e nemmeno in un giorno fuori stagione', () {
      final s = abbandonato.resolve(now: DateTime(2026, 1, 15));
      expect(s.verdict, OpeningVerdict.soloStagioniPassate);
      expect(s.canSayOpen, isFalse);
    });

    test('porta con se\' la fonte e l\'eta\' del dato', () {
      final s = abbandonato.resolve(now: DateTime(2026, 8, 9));
      expect(s.source, OpeningSource.osm);
      expect(s.basedOn?.year, 2024);
      expect(s.ageInDays, greaterThan(700));
    });

    test('nessun giorno dell\'anno lo fa passare per aperto', () {
      // Forza bruta su tutti i 365 giorni: nessuno deve produrre canSayOpen.
      for (var i = 0; i < 365; i++) {
        final day = DateTime(2026, 1, 1).add(Duration(days: i));
        expect(
          abbandonato.resolve(now: day).canSayOpen,
          isFalse,
          reason: 'ha detto "aperto" il ${day.day}/${day.month}',
        );
      }
    });
  });

  group('bivacco', () {
    test('e\' sempre accessibile senza bisogno di alcun dato', () {
      const b = HutOpening.bivacco();
      final s = b.resolve(now: DateTime(2026, 2, 3));
      expect(s.verdict, OpeningVerdict.sempreAccessibile);
      expect(s.canSayOpen, isTrue);
      expect(s.needsCaveat, isFalse);
    });

    test('lo e\' anche a gennaio, che e\' il punto', () {
      const b = HutOpening.bivacco();
      expect(b.resolve(now: DateTime(2026, 1, 1)).canSayOpen, isTrue);
    });
  });

  group('stagione dichiarata per l\'anno in corso', () {
    final dichiarato = HutOpening(
      kind: HutKind.gestito,
      source: OpeningSource.gestore,
      updatedAt: DateTime(2026, 5, 20),
      periods: const [
        OpeningPeriod(year: 2026, from: SeasonDay(6, 20), to: SeasonDay(9, 20)),
      ],
    );

    test('dentro la finestra: aperto, senza riserve', () {
      final s = dichiarato.resolve(now: DateTime(2026, 8, 9));
      expect(s.verdict, OpeningVerdict.aperto);
      expect(s.canSayOpen, isTrue);
      expect(s.needsCaveat, isFalse);
    });

    test('fuori dalla finestra: chiuso, non "non sappiamo"', () {
      final s = dichiarato.resolve(now: DateTime(2026, 11, 2));
      expect(s.verdict, OpeningVerdict.chiuso);
      expect(s.canSayOpen, isFalse);
    });

    test('sui bordi, che sono inclusi', () {
      expect(dichiarato.resolve(now: DateTime(2026, 6, 20)).verdict,
          OpeningVerdict.aperto);
      expect(dichiarato.resolve(now: DateTime(2026, 9, 20)).verdict,
          OpeningVerdict.aperto);
      expect(dichiarato.resolve(now: DateTime(2026, 6, 19)).verdict,
          OpeningVerdict.chiuso);
    });
  });

  group('stagione tipica (senza anno)', () {
    final tipico = HutOpening(
      kind: HutKind.gestito,
      source: OpeningSource.osm,
      periods: const [
        OpeningPeriod(from: SeasonDay(6, 1), to: SeasonDay(10, 31)),
      ],
    );

    test('dentro la finestra dice "probabilmente", mai "aperto"', () {
      final s = tipico.resolve(now: DateTime(2026, 8, 9));
      expect(s.verdict, OpeningVerdict.probabilmenteAperto);
      expect(s.canSayOpen, isFalse, reason: 'nessuno l\'ha confermato per il 2026');
      expect(s.needsCaveat, isTrue);
    });

    test('fuori dalla finestra', () {
      expect(tipico.resolve(now: DateTime(2026, 1, 5)).verdict,
          OpeningVerdict.probabilmenteChiuso);
    });

    test('non scade mai, perche\' non ha un anno da superare', () {
      expect(tipico.resolve(now: DateTime(2031, 8, 9)).verdict,
          OpeningVerdict.probabilmenteAperto);
    });
  });

  group('una dichiarazione per l\'anno in corso batte il resto', () {
    test('coesistendo con una tipica, vince la dichiarata', () {
      final misto = HutOpening(
        kind: HutKind.gestito,
        periods: const [
          OpeningPeriod(from: SeasonDay(6, 1), to: SeasonDay(10, 31)),
          OpeningPeriod(
              year: 2026, from: SeasonDay(7, 1), to: SeasonDay(8, 31)),
        ],
      );
      // Il 15 settembre e' dentro la tipica ma fuori dalla dichiarata 2026:
      // deve dire chiuso, non "probabilmente aperto".
      final s = misto.resolve(now: DateTime(2026, 9, 15));
      expect(s.verdict, OpeningVerdict.chiuso);
    });
  });

  group('stagione a cavallo di capodanno', () {
    final invernale = HutOpening(
      kind: HutKind.gestito,
      periods: const [
        OpeningPeriod(year: 2026, from: SeasonDay(12, 1), to: SeasonDay(3, 31)),
      ],
    );

    test('riconosce lo scavalco', () {
      expect(
        const OpeningPeriod(from: SeasonDay(12, 1), to: SeasonDay(3, 31))
            .wrapsNewYear,
        isTrue,
      );
    });

    test('dicembre e febbraio sono dentro, luglio fuori', () {
      expect(invernale.resolve(now: DateTime(2026, 12, 15)).verdict,
          OpeningVerdict.aperto);
      expect(invernale.resolve(now: DateTime(2026, 2, 10)).verdict,
          OpeningVerdict.aperto);
      expect(invernale.resolve(now: DateTime(2026, 7, 10)).verdict,
          OpeningVerdict.chiuso);
    });
  });

  group('nessuna informazione', () {
    test('resta ignoto, che e\' un\'informazione anche quella', () {
      const vuoto = HutOpening(kind: HutKind.gestito);
      final s = vuoto.resolve(now: DateTime(2026, 8, 9));
      expect(s.verdict, OpeningVerdict.ignoto);
      expect(s.canSayOpen, isFalse);
      expect(s.basedOn, isNull);
    });
  });

  group('serializzazione', () {
    test('sopravvive al giro su Firestore', () {
      final o = HutOpening(
        kind: HutKind.gestito,
        source: OpeningSource.gestore,
        updatedAt: DateTime(2026, 5, 20),
        note: 'A settembre solo nei weekend.',
        periods: const [
          OpeningPeriod(
              year: 2026, from: SeasonDay(6, 20), to: SeasonDay(9, 20)),
          OpeningPeriod(from: SeasonDay(6, 1), to: SeasonDay(10, 31)),
        ],
      );

      final back = HutOpening.fromMap(o.toMap());

      expect(back.kind, o.kind);
      expect(back.source, o.source);
      expect(back.note, o.note);
      expect(back.updatedAt, o.updatedAt);
      expect(back.periods.length, 2);
      expect(back.periods.first.year, 2026);
      expect(back.periods.first.from, const SeasonDay(6, 20));
      expect(back.periods.last.isTypical, isTrue);
      // E soprattutto: il verdetto non cambia dopo il giro.
      expect(back.resolve(now: DateTime(2026, 8, 9)).verdict,
          o.resolve(now: DateTime(2026, 8, 9)).verdict);
    });

    test('un bivacco serializzato resta un bivacco', () {
      const b = HutOpening.bivacco();
      expect(HutOpening.fromMap(b.toMap()).resolve().verdict,
          OpeningVerdict.sempreAccessibile);
    });
  });
}
