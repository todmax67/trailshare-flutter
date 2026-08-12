import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/core/services/peak_context_service.dart';
import 'package:trailshare_flutter/data/models/hut_opening.dart';

/// La scheda di una cima dice cose all'utente che poi salirà lassù. Queste
/// funzioni decidono *cosa* dice, ed è il punto dove si può mentire senza
/// accorgersene — dichiarando aperto un rifugio chiuso, o una precisione che
/// non abbiamo.
void main() {
  group('stato di apertura', () {
    OpeningStatus s(OpeningVerdict v) => OpeningStatus(verdict: v);

    test('un dato di sole stagioni passate non diventa una risposta', () {
      // È la regola che conta: sapere com'era l'anno scorso non dice niente su
      // oggi, e mostrarlo comunque farebbe salire qualcuno verso una porta
      // chiusa.
      expect(openingLabel(s(OpeningVerdict.soloStagioniPassate)), isNull);
      expect(openingLabel(s(OpeningVerdict.ignoto)), isNull);
      expect(openingLabel(null), isNull);
    });

    test('le stime si riconoscono dal linguaggio', () {
      expect(openingLabel(s(OpeningVerdict.aperto)), 'aperto');
      expect(openingLabel(s(OpeningVerdict.probabilmenteAperto)),
          'di solito aperto');
      expect(openingLabel(s(OpeningVerdict.chiuso)), 'chiuso');
      expect(openingLabel(s(OpeningVerdict.probabilmenteChiuso)),
          'di solito chiuso');
    });

    test('solo certezze possono dire "aperto" senza riserve', () {
      expect(s(OpeningVerdict.aperto).canSayOpen, isTrue);
      expect(s(OpeningVerdict.sempreAccessibile).canSayOpen, isTrue);
      expect(s(OpeningVerdict.probabilmenteAperto).canSayOpen, isFalse);
    });
  });

  group('distanze e dislivelli', () {
    test('sotto il chilometro si arrotonda alle decine di metri', () {
      // Dire "487 m" da una geometria semplificata sarebbe una precisione
      // inventata.
      expect(formatShortDistance(487), '490 m');
      expect(formatShortDistance(52), '50 m');
    });

    test('sopra il chilometro si passa ai km', () {
      expect(formatShortDistance(1240), '1.2 km');
      expect(formatShortDistance(15300), '15 km');
    });

    test('il dislivello dice da che parte', () {
      expect(formatElevationDelta(-312), '312 m più in basso');
      expect(formatElevationDelta(48), '48 m più in alto');
    });
  });
}
