import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/core/services/hut_openings_service.dart';
import 'package:trailshare_flutter/data/models/hut_opening.dart';

/// Test di integrazione sul seed VERO (assets/data/hut_openings.json).
///
/// E' la giuntura fra due linguaggi: lo script Python scrive, il modello Dart
/// legge. Un test su dati inventati non direbbe niente su quel punto, che e'
/// esattamente dove le cose si rompono in silenzio.
///
/// Gli id si rileggono dall'asset in modo indipendente dal servizio, cosi' il
/// test verifica anche che i due siano d'accordo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final svc = HutOpeningsService();
  late List<String> ids;

  setUpAll(() async {
    svc.resetForTest();
    await svc.ensureLoaded();

    final raw = await rootBundle.loadString('assets/data/hut_openings.json');
    final doc = json.decode(raw) as Map<String, dynamic>;
    ids = (doc['openings'] as Map<String, dynamic>).keys.toList();
  });

  test('il seed si carica, e servizio e file sono d\'accordo', () {
    expect(ids.length, greaterThan(1000),
        reason: 'l\'asset dovrebbe contenere ~1.469 voci');
    expect(svc.count, ids.length);
    expect(svc.generatedAt, isNotNull);
  });

  test('ogni voce del file e\' leggibile dal modello Dart', () {
    for (final id in ids) {
      expect(svc.forPoi(id), isNotNull, reason: 'voce $id non deserializzata');
    }
  });

  test('un bivacco risponde "sempre accessibile"', () {
    final id = ids.firstWhere(
      (i) => svc.forPoi(i)!.kind == HutKind.bivacco,
      orElse: () => '',
    );
    expect(id, isNotEmpty, reason: 'nessun bivacco nel seed');

    final s = svc.forPoi(id)!.resolve(now: DateTime(2026, 1, 20));
    expect(s.verdict, OpeningVerdict.sempreAccessibile);
    expect(s.canSayOpen, isTrue);
    expect(s.needsCaveat, isFalse);
  });

  group('nessuna voce del seed puo\' mentire', () {
    test('chi dice "aperto" sa giustificarlo, in ogni giorno provato', () {
      final date = [
        DateTime(2026, 1, 15),
        DateTime(2026, 4, 20),
        DateTime(2026, 8, 9),
        DateTime(2026, 11, 3),
      ];

      var controllate = 0;
      for (final id in ids) {
        final o = svc.forPoi(id)!;
        for (final d in date) {
          controllate++;
          if (!o.resolve(now: d).canSayOpen) continue;

          // Se dice "aperto" deve essere un bivacco, oppure avere una stagione
          // dichiarata proprio per quell'anno. Nessuna terza possibilita'.
          final giustificato = o.kind == HutKind.bivacco ||
              o.periods.any((p) => p.year == d.year);
          expect(giustificato, isTrue,
              reason: '$id ha detto "aperto" il ${d.day}/${d.month}/${d.year} '
                  'senza una stagione dichiarata per quell\'anno');
        }
      }
      expect(controllate, greaterThan(4000));
    });

    test('le voci congelate ad anni passati lo dichiarano', () {
      final scadute = ids.where((id) {
        final o = svc.forPoi(id)!;
        return o.kind == HutKind.gestito &&
            o.periods.isNotEmpty &&
            o.periods.every((p) => p.year != null && p.year! < 2026);
      }).toList();

      // Nell'estratto del 2026-08-09 sono sei rifugi fermi al 2024.
      expect(scadute, isNotEmpty,
          reason: 'attese alcune voci ferme ad anni passati');

      for (final id in scadute) {
        final s = svc.forPoi(id)!.resolve(now: DateTime(2026, 8, 9));
        expect(s.verdict, OpeningVerdict.soloStagioniPassate);
        expect(s.canSayOpen, isFalse);
        expect(s.needsCaveat, isTrue);
      }
    });
  });

  test('ogni periodo importato ha date esistenti', () {
    for (final id in ids) {
      for (final p in svc.forPoi(id)!.periods) {
        expect(p.from.isValid, isTrue, reason: 'inizio non valido in $id');
        expect(p.to.isValid, isTrue, reason: 'fine non valida in $id');
      }
    }
  });

  test('i rifugi importati da OSM portano la fonte con se\'', () {
    final gestiti =
        ids.where((i) => svc.forPoi(i)!.kind == HutKind.gestito).toList();
    expect(gestiti, isNotEmpty);
    for (final id in gestiti) {
      expect(svc.forPoi(id)!.source, OpeningSource.osm);
    }
  });

  test('un id sconosciuto non e\' un errore, e\' "non sappiamo"', () {
    expect(svc.forPoi('n000000000'), isNull);
  });
}
