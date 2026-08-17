import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/core/services/growth_analytics_service.dart';

/// Le fasce non sono un dettaglio estetico: GA4 tratta ogni valore distinto
/// come una riga, quindi mandare il numero esatto produce un report con mille
/// righe da un evento ciascuna — cioe' un dato che c'e' e non si guarda.
void main() {
  const soglie = [15, 45, 120, 300];

  test('zero e negativi collassano su "0", non su "<15"', () {
    // Una registrazione da zero minuti e una da dieci sono cose diverse, e
    // "meno di quindici" le confonderebbe.
    expect(GrowthAnalyticsService.fasciaPerTest(0, soglie), '0');
    expect(GrowthAnalyticsService.fasciaPerTest(-3, soglie), '0');
  });

  test('sotto la prima soglia', () {
    expect(GrowthAnalyticsService.fasciaPerTest(1, soglie), '<15');
    expect(GrowthAnalyticsService.fasciaPerTest(14, soglie), '<15');
  });

  test('gli estremi stanno nella fascia sopra, non in quella sotto', () {
    expect(GrowthAnalyticsService.fasciaPerTest(15, soglie), '15-45');
    expect(GrowthAnalyticsService.fasciaPerTest(44, soglie), '15-45');
    expect(GrowthAnalyticsService.fasciaPerTest(45, soglie), '45-120');
  });

  test('oltre l\'ultima soglia resta aperta verso l\'alto', () {
    expect(GrowthAnalyticsService.fasciaPerTest(300, soglie), '300+');
    expect(GrowthAnalyticsService.fasciaPerTest(99999, soglie), '300+');
  });

  test('il numero di fasce distinte resta piccolo', () {
    // Il punto di tutta l'operazione: qualunque input, poche righe.
    final viste = <String>{};
    for (var i = -5; i < 2000; i++) {
      viste.add(GrowthAnalyticsService.fasciaPerTest(i, soglie));
    }
    expect(viste.length, soglie.length + 2,
        reason: '0, una per intervallo, e la coda aperta');
  });
}
