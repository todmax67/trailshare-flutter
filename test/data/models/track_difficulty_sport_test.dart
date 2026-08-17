import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/data/models/track.dart';

/// La scala della difficolta' non e' la stessa per tutti gli sport: una T3 da
/// trekking su una traccia diventata ciclistica e' la misura di un'altra
/// scala. Il repository ricalcola e riscrive il valore giusto, ma finche' non
/// torna la scheda non deve mostrare il vecchio — e chi pubblica subito non
/// deve mandarlo in published_tracks.
void main() {
  final t = Track(
    name: 'Giro',
    points: const [],
    createdAt: DateTime.utc(2026, 8, 16),
    activityType: ActivityType.trekking,
    computedDifficulty: 't3',
  );

  test('copyWith conserva la difficolta\' quando lo sport non cambia', () {
    expect(t.copyWith(name: 'Altro').computedDifficulty, 't3');
  });

  test('clearComputedDifficulty la azzera', () {
    final b = t.copyWith(
      activityType: ActivityType.cycling,
      clearComputedDifficulty: true,
    );
    expect(b.computedDifficulty, isNull);
    expect(b.activityType, ActivityType.cycling);
  });

  test('azzerarla non tocca quella dichiarata a mano dal proprietario', () {
    final manuale = t.copyWith(manualDifficulty: 't4');
    final b = manuale.copyWith(clearComputedDifficulty: true);
    expect(b.manualDifficulty, 't4',
        reason: 'il giudizio del proprietario non dipende dallo sport');
    expect(b.effectiveDifficulty, 't4');
  });
}
