import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/core/services/terrain_tile_service.dart';

/// Il mosaico dei tile è il punto in cui un errore di indici scrive quote nel
/// posto sbagliato — ed è già successo: riempiva le righe al contrario e il DEM
/// veniva riletto specchiato nord-sud, con il viewshed che guardava a nord e
/// trovava il terreno di sud. Questi test bloccano la parte aritmetica.
void main() {
  // Griglia di destinazione: 1° × 1°, 101 × 101 celle (passo 0,01°).
  ({int rowFrom, int rowTo, int colFrom, int colTo})? range({
    required double tMinLat,
    required double tMaxLat,
    required double tMinLng,
    required double tMaxLng,
  }) =>
      destinationRangeFor(
        gridMinLat: 45, gridMaxLat: 46,
        gridMinLng: 9, gridMaxLng: 10,
        rows: 101, cols: 101,
        tileMinLat: tMinLat, tileMaxLat: tMaxLat,
        tileMinLng: tMinLng, tileMaxLng: tMaxLng,
      );

  test('un tile che copre tutto prende tutte le righe e colonne', () {
    final r = range(tMinLat: 44, tMaxLat: 47, tMinLng: 8, tMaxLng: 11)!;
    expect(r.rowFrom, 0);
    expect(r.rowTo, 100);
    expect(r.colFrom, 0);
    expect(r.colTo, 100);
  });

  test('la metà sud prende le righe basse, non le alte', () {
    // Riga 0 = bordo sud: un tile sulla metà meridionale deve prendere 0..50.
    final r = range(tMinLat: 45, tMaxLat: 45.5, tMinLng: 9, tMaxLng: 10)!;
    expect(r.rowFrom, 0);
    expect(r.rowTo, 50);
  });

  test('la metà nord prende le righe alte', () {
    final r = range(tMinLat: 45.5, tMaxLat: 46, tMinLng: 9, tMaxLng: 10)!;
    expect(r.rowFrom, 50);
    expect(r.rowTo, 100);
  });

  test('la metà ovest prende le colonne basse', () {
    final r = range(tMinLat: 45, tMaxLat: 46, tMinLng: 9, tMaxLng: 9.5)!;
    expect(r.colFrom, 0);
    expect(r.colTo, 50);
  });

  test('due tile adiacenti coprono tutte le righe senza lasciarne fuori', () {
    final sud = range(tMinLat: 45, tMaxLat: 45.5, tMinLng: 9, tMaxLng: 10)!;
    final nord = range(tMinLat: 45.5, tMaxLat: 46, tMinLng: 9, tMaxLng: 10)!;
    expect(sud.rowTo + 1, greaterThanOrEqualTo(nord.rowFrom),
        reason: 'non deve restare una riga scoperta fra i due tile');
  });

  test('un tile fuori dalla griglia viene scartato, non schiacciato sul bordo',
      () {
    // Prima veniva solo limitato agli estremi, e un tile tutto a nord finiva a
    // scrivere quote di un altro posto sull'ultima riga.
    expect(range(tMinLat: 47, tMaxLat: 48, tMinLng: 9, tMaxLng: 10), isNull);
    expect(range(tMinLat: 43, tMaxLat: 44, tMinLng: 9, tMaxLng: 10), isNull);
    expect(range(tMinLat: 45, tMaxLat: 46, tMinLng: 11, tMaxLng: 12), isNull);
    expect(range(tMinLat: 45, tMaxLat: 46, tMinLng: 6, tMaxLng: 7), isNull);
  });

  test('griglia degenere → nessun intervallo invece di indici assurdi', () {
    expect(
      destinationRangeFor(
        gridMinLat: 45, gridMaxLat: 45,
        gridMinLng: 9, gridMaxLng: 10,
        rows: 10, cols: 10,
        tileMinLat: 45, tileMaxLat: 45,
        tileMinLng: 9, tileMaxLng: 10,
      ),
      isNull,
    );
  });
}
