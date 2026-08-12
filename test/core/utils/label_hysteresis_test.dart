import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/core/utils/mountain_projection.dart';
import 'package:trailshare_flutter/data/models/mountain_peak.dart';

/// L'isteresi non si giudica guardando un fotogramma: si giudica contando
/// quante etichette cambiano *fra* un fotogramma e il successivo.
///
/// Per questo l'ultimo gruppo simula il movimento vero e misura il ricambio,
/// che è la grandezza che l'occhio percepisce come sfarfallio. Quella misura
/// dice anche **cosa l'isteresi non fa**, ed è la parte più utile da tenere a
/// mente prima di aspettarsi troppo.
void main() {
  ProjectedPeak peakAt(int i, double relBearingDeg) => ProjectedPeak(
        peak: MountainPeak(
          id: 'p$i',
          name: 'Cima $i',
          latitude: 46,
          longitude: 10,
          elevation: 2000,
        ),
        screenX: 0,
        screenY: 0,
        distanceMeters: 10000,
        bearingDeg: 0,
        relativeBearingDeg: relBearingDeg,
        relativePitchDeg: 0,
      );

  /// Cinquanta cime già in ordine di classifica: p0 la più centrata.
  List<ProjectedPeak> rankedList([int n = 50]) =>
      [for (var i = 0; i < n; i++) peakAt(i, i.toDouble())];

  group('selectStable — le due soglie', () {
    test('senza veterani si comporta come il vecchio troncamento', () {
      final out = MountainProjection.selectStable(
        ranked: rankedList(),
        previouslyShownIds: const {},
        maxVisible: 30,
      );
      expect(out.length, 30);
      expect(out.first.peak.id, 'p0');
      expect(out.last.peak.id, 'p29');
    });

    test('un veterano sceso al 35° posto RESTA (prima spariva)', () {
      // p35 c'era; entrare richiede il 30°, restare basta il 42°.
      final out = MountainProjection.selectStable(
        ranked: rankedList(),
        previouslyShownIds: {'p35'},
        maxVisible: 30,
      );
      expect(out.map((p) => p.peak.id), contains('p35'));
      expect(out.length, 30, reason: 'il tetto resta rispettato');
    });

    test('un veterano sceso oltre la banda morta esce', () {
      final out = MountainProjection.selectStable(
        ranked: rankedList(),
        previouslyShownIds: {'p45'},
        maxVisible: 30,
      );
      expect(out.map((p) => p.peak.id), isNot(contains('p45')));
    });

    test('il confine è il 42° posto, non il 30°', () {
      final ids = MountainProjection.selectStable(
        ranked: rankedList(),
        previouslyShownIds: {'p41', 'p42'},
        maxVisible: 30,
      ).map((p) => p.peak.id);
      expect(ids, contains('p41'));
      expect(ids, isNot(contains('p42')));
    });

    test('una cima nuova NON entra al 35°: la banda morta vale nei due versi',
        () {
      // Senza questa asimmetria non ci sarebbe isteresi ma solo un tetto più
      // alto, e lo sfarfallio si sposterebbe di dodici posizioni.
      final out = MountainProjection.selectStable(
        ranked: rankedList(),
        previouslyShownIds: const {},
        maxVisible: 30,
      );
      expect(out.map((p) => p.peak.id), isNot(contains('p35')));
    });
  });

  group('selectStable — le invarianti che non si possono rompere', () {
    test('la cima più centrata ha il nome anche con la lista piena di veterani',
        () {
      // Trenta veterani occupano tutti i posti: senza la garanzia esplicita,
      // l'utente resterebbe senza nome proprio sulla montagna che inquadra.
      final veterani = {for (var i = 1; i <= 30; i++) 'p$i'};
      final out = MountainProjection.selectStable(
        ranked: rankedList(),
        previouslyShownIds: veterani,
        maxVisible: 30,
      );
      expect(out.first.peak.id, 'p0');
      expect(out.length, 30);
    });

    test('l\'ordine resta quello di classifica', () {
      final out = MountainProjection.selectStable(
        ranked: rankedList(),
        previouslyShownIds: {'p35', 'p38', 'p2'},
        maxVisible: 30,
      );
      final indici = [
        for (final p in out) int.parse(p.peak.id.substring(1)),
      ];
      final ordinati = [...indici]..sort();
      expect(indici, ordinati,
          reason: 'chi chiama si aspetta la più centrata in testa');
    });

    test('la lista resta piena: i posti liberati vanno ai nuovi arrivati', () {
      // Un solo veterano, e nessuno degli altri era mostrato prima.
      final out = MountainProjection.selectStable(
        ranked: rankedList(),
        previouslyShownIds: {'p40'},
        maxVisible: 30,
      );
      expect(out.length, 30,
          reason: 'girandosi non ci si deve ritrovare lo schermo vuoto');
    });

    test('con meno cime del tetto le restituisce tutte', () {
      final out = MountainProjection.selectStable(
        ranked: rankedList(12),
        previouslyShownIds: const {},
        maxVisible: 30,
      );
      expect(out.length, 12);
    });

    test('nessun duplicato', () {
      final out = MountainProjection.selectStable(
        ranked: rankedList(),
        previouslyShownIds: {'p0', 'p1', 'p35'},
        maxVisible: 30,
      );
      expect(out.map((p) => p.peak.id).toSet().length, out.length);
    });
  });

  group('la misura che conta: quante etichette cambiano per fotogramma', () {
    /// Le cime stanno ferme sull'orizzonte, la testa gira. Il punteggio di
    /// centratura è la distanza angolare dall'asse ottico, quindi la classifica
    /// si rimescola a ogni campione dei sensori.
    ///
    /// Il rumore non è un dettaglio del test, è il fenomeno: l'assetto fuso
    /// trema di qualche centesimo di grado anche col telefono appoggiato, ed è
    /// quel tremolio a far oscillare le cime attorno alla soglia.
    ({int senza, int con}) simula({
      required double gradiPerCampione,
      required int campioni,
      required double rumoreGradi,
    }) {
      final rnd = math.Random(42);
      // 168 cime nel cono, come misurato puntando verso le Orobie.
      final azimut = [for (var i = 0; i < 168; i++) rnd.nextDouble() * 40 - 20];

      List<ProjectedPeak> classifica(double puntamento, double rumore) {
        final l = <ProjectedPeak>[
          for (var i = 0; i < azimut.length; i++)
            peakAt(i, (azimut[i] - puntamento + rumore).abs()),
        ];
        l.sort((a, b) => a.relativeBearingDeg.compareTo(b.relativeBearingDeg));
        return l;
      }

      var ricambioSenza = 0;
      var ricambioCon = 0;
      var precSenza = <String>{};
      var precCon = <String>{};

      for (var k = 0; k < campioni; k++) {
        final rumore = (rnd.nextDouble() - 0.5) * 2 * rumoreGradi;
        final ranked = classifica(k * gradiPerCampione, rumore);

        final senza = ranked.take(30).map((p) => p.peak.id).toSet();
        final con = MountainProjection.selectStable(
          ranked: ranked,
          previouslyShownIds: precCon,
          maxVisible: 30,
        ).map((p) => p.peak.id).toSet();

        if (k > 0) {
          ricambioSenza += senza.difference(precSenza).length +
              precSenza.difference(senza).length;
          ricambioCon +=
              con.difference(precCon).length + precCon.difference(con).length;
        }
        precSenza = senza;
        precCon = con;
      }
      return (senza: ricambioSenza, con: ricambioCon);
    }

    test('col telefono FERMO lo sfarfallio sparisce del tutto', () {
      // È il caso che conta: si tiene il telefono puntato su una cima per
      // leggerne il nome, e le etichette lampeggiano lo stesso perché la
      // classifica balla col tremolio dei sensori. Su 199 transizioni il
      // comportamento vecchio produce 360 cambi — quasi due per campione, a
      // telefono immobile — e l'isteresi li porta a zero.
      final r = simula(gradiPerCampione: 0, campioni: 200, rumoreGradi: 0.15);
      expect(r.senza, greaterThan(300),
          reason: 'il tremolio da solo basta a far sfarfallare: ${r.senza}');
      expect(r.con, 0,
          reason: 'a telefono fermo non deve cambiare NIENTE, invece ${r.con}');
    });

    test('in panoramica il guadagno è modesto, e deve esserlo', () {
      // Qui l'isteresi non può fare miracoli, e non deve: se giro il telefono
      // le cime escono davvero dall'inquadratura, e trattenerle sarebbe
      // mentire. Il ricambio che resta è movimento vero, non sfarfallio.
      final lento = simula(
          gradiPerCampione: 0.2, campioni: 200, rumoreGradi: 0.15); // ~5°/s
      final veloce = simula(
          gradiPerCampione: 1.6, campioni: 200, rumoreGradi: 0.15); // ~40°/s

      expect(lento.con, lessThan(lento.senza),
          reason: 'lento: con ${lento.con}, senza ${lento.senza}');
      expect(veloce.con, lessThan(veloce.senza),
          reason: 'veloce: con ${veloce.con}, senza ${veloce.senza}');

      // E il ricambio residuo in panoramica resta ben SOTTO quello che il
      // comportamento vecchio produceva stando fermi: la parte spuria è andata,
      // quella legittima e' rimasta.
      final fermoVecchio =
          simula(gradiPerCampione: 0, campioni: 200, rumoreGradi: 0.15).senza;
      expect(veloce.con, lessThan(fermoVecchio));
    });
  });
}
