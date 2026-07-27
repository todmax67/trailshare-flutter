import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/presentation/widgets/terrain_cover.dart';

/// Profilo vero, preso dalla produzione: Rifugio Monte Foldone, 1.440 m,
/// sezione est-ovest di 6 km dal DEM europeo a 25 m.
const _foldone = {
  'p': 'MzMxNCoZBgANISwiEhEbJzA7TFtjaG9+kbDC1Ob3///88N3Kw76vpZ6VkJCOhXhxb25rYU0+MCQdFQwE',
  'n': 60,
  'widthKm': 6,
  'minM': 641,
  'maxM': 1451,
  'source': 'eudem25m',
};

void main() {
  group('TerrainProfile.fromMap', () {
    test('decodifica un profilo vero di produzione', () {
      final p = TerrainProfile.fromMap(Map<String, dynamic>.from(_foldone));
      expect(p, isNotNull);
      expect(p!.samples.length, 60);
      expect(p.minM, 641);
      expect(p.maxM, 1451);
      expect(p.relief, 810);
      expect(p.widthKm, 6);
    });

    test('i campioni restano normalizzati fra 0 e 1', () {
      final p = TerrainProfile.fromMap(Map<String, dynamic>.from(_foldone))!;
      expect(p.samples.every((s) => s >= 0 && s <= 1), isTrue);
      // Il quantizzatore ancora gli estremi: almeno un punto tocca il fondo
      // e almeno uno la cima, altrimenti il disegno non riempirebbe la fascia.
      expect(p.samples.reduce((a, b) => a < b ? a : b), lessThan(0.02));
      expect(p.samples.reduce((a, b) => a > b ? a : b), greaterThan(0.98));
    });

    test('un dato mancante o malformato non fa esplodere niente', () {
      expect(TerrainProfile.fromMap(null), isNull);
      expect(TerrainProfile.fromMap({}), isNull);
      expect(TerrainProfile.fromMap({'p': '', 'minM': 0, 'maxM': 1}), isNull);
      // base64 non valido: si ricade sul ripiego, non si solleva
      expect(
        TerrainProfile.fromMap({'p': 'non-è-base64!!', 'minM': 0, 'maxM': 1}),
        isNull,
      );
      // quote assenti: senza minM/maxM la quota non si potrebbe scrivere
      expect(TerrainProfile.fromMap({'p': _foldone['p']}), isNull);
    });
  });

  group('TerrainCover', () {
    Widget wrap(Widget child) => MaterialApp(
          home: Scaffold(body: SizedBox(width: 390, height: 220, child: child)),
        );

    testWidgets('mostra quota e sottotitolo, non il nome se non glielo passi',
        (tester) async {
      final p = TerrainProfile.fromMap(Map<String, dynamic>.from(_foldone))!;
      await tester.pumpWidget(wrap(
        TerrainCover(profile: p, elevationM: 1440, subtitle: 'Lombardia'),
      ));
      expect(find.text('1440 m · Lombardia'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('il nome compare solo dove serve', (tester) async {
      final p = TerrainProfile.fromMap(Map<String, dynamic>.from(_foldone))!;
      await tester.pumpWidget(wrap(
        TerrainCover(profile: p, name: 'Rifugio Monte Foldone', elevationM: 1440),
      ));
      expect(find.text('Rifugio Monte Foldone'), findsOneWidget);
      expect(find.text('1440 m'), findsOneWidget);
    });

    testWidgets('in versione compatta resta solo la quota', (tester) async {
      final p = TerrainProfile.fromMap(Map<String, dynamic>.from(_foldone))!;
      await tester.pumpWidget(wrap(
        TerrainCover(
          profile: p,
          name: 'Rifugio Monte Foldone',
          elevationM: 1440,
          compact: true,
        ),
      ));
      expect(find.text('Rifugio Monte Foldone'), findsNothing);
      expect(find.text('1440 m'), findsOneWidget);
    });

    testWidgets('senza quota esplicita ripiega sul punto piu alto della sezione',
        (tester) async {
      final p = TerrainProfile.fromMap(Map<String, dynamic>.from(_foldone))!;
      await tester.pumpWidget(wrap(TerrainCover(profile: p)));
      expect(find.text('1451 m'), findsOneWidget);
    });

    testWidgets('si disegna anche in spazi minuscoli senza eccezioni',
        (tester) async {
      final p = TerrainProfile.fromMap(Map<String, dynamic>.from(_foldone))!;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 60,
            height: 40,
            child: TerrainCover(profile: p, compact: true, elevationM: 1440),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });
}
