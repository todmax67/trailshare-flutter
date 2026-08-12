import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/core/utils/dem_tile_codec.dart';

/// Il formato su disco decide se il terreno si può portare in montagna: a
/// 256 KB per tile un pacchetto alpino supera i cento megabyte ed è inservibile.
/// Qui si verifica che la codifica sia esatta (il viewshed decide cosa si vede
/// da questi numeri) e che comprima davvero su terreno realistico.

DemTileData tile(Float32List ele, {int w = 256, int h = 256}) => DemTileData(
      width: w,
      height: h,
      minLat: 45.9123456,
      maxLat: 45.9856789,
      minLng: 9.8123456,
      maxLng: 9.8987654,
      elevations: ele,
    );

/// Terreno sintetico ma realistico: creste, valli e un po' di rumore.
Float32List syntheticTerrain(int w, int h) {
  final ele = Float32List(w * h);
  final rnd = math.Random(42);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final ridge = 900 +
          600 * math.sin(x / 40) * math.cos(y / 55) +
          300 * math.sin((x + y) / 90);
      ele[y * w + x] = (ridge + rnd.nextDouble() * 6 - 3).roundToDouble();
    }
  }
  return ele;
}

void main() {
  test('andata e ritorno esatti al metro', () {
    final original = syntheticTerrain(64, 48);
    final decoded = decodeDemTile(encodeDemTile(tile(original, w: 64, h: 48)))!;
    expect(decoded.width, 64);
    expect(decoded.height, 48);
    for (var i = 0; i < original.length; i++) {
      expect(decoded.elevations[i], original[i].roundToDouble(),
          reason: 'campione $i alterato dalla codifica');
    }
  });

  test('la bbox sopravvive alla sesta cifra decimale', () {
    // In Float32 due tile adiacenti dichiarerebbero lo stesso confine con
    // valori diversi, e il mosaico lascerebbe una riga scoperta.
    final t = tile(syntheticTerrain(16, 16), w: 16, h: 16);
    final decoded = decodeDemTile(encodeDemTile(t))!;
    expect(decoded.minLat, closeTo(t.minLat, 1e-12));
    expect(decoded.maxLat, closeTo(t.maxLat, 1e-12));
    expect(decoded.minLng, closeTo(t.minLng, 1e-12));
    expect(decoded.maxLng, closeTo(t.maxLng, 1e-12));
  });

  test('quote negative e sotto il livello del mare', () {
    final ele = Float32List.fromList(
      List<double>.generate(64, (i) => (i - 40) * 7.0),
    );
    final decoded = decodeDemTile(encodeDemTile(tile(ele, w: 8, h: 8)))!;
    for (var i = 0; i < ele.length; i++) {
      expect(decoded.elevations[i], ele[i]);
    }
  });

  test('salti enormi fra campioni adiacenti non rompono il formato', () {
    // Una parete verticale nel DEM non esiste, ma un formato che si corrompe
    // "solo in teoria" resta un formato rotto.
    final ele = Float32List.fromList([
      -30000, 30000, -30000, 30000, //
      0, 0, 0, 0,
    ]);
    final decoded = decodeDemTile(encodeDemTile(tile(ele, w: 4, h: 2)))!;
    for (var i = 0; i < ele.length; i++) {
      expect(decoded.elevations[i], ele[i]);
    }
  });

  test('su terreno realistico un tile sta sotto i 60 KB invece di 256', () {
    final encoded = encodeDemTile(tile(syntheticTerrain(256, 256)));
    const rawFloat32 = 256 * 256 * 4;
    expect(encoded.length, lessThan(60 * 1024),
        reason: 'senza compressione un pacchetto alpino supera i 100 MB');
    expect(encoded.length, lessThan(rawFloat32 ~/ 4),
        reason: 'almeno quattro volte piu' 'piccolo del formato precedente');
  });

  group('compatibilità con la cache già sui telefoni', () {
    // Il formato precedente non va solo "tollerato": va letto correttamente.
    // I telefoni hanno decine di tile gia' scaricati, e un cambio di formato
    // non deve far ripagare all'utente una nostra decisione.

    test('il vecchio formato non viene scambiato per quello nuovo', () {
      final legacy = Uint8List(64);
      ByteData.sublistView(legacy).setUint32(0, 256, Endian.little);
      expect(decodeDemTile(legacy), isNull,
          reason: 'il magic deve distinguerli senza ambiguita\'');
    });

    test('un tile nel vecchio formato si rilegge con le stesse quote', () {
      final original = syntheticTerrain(32, 24);
      final t = tile(original, w: 32, h: 24);
      final decoded = decodeLegacyDemTile(encodeLegacyDemTile(t))!;
      expect(decoded.width, 32);
      expect(decoded.height, 24);
      for (var i = 0; i < original.length; i++) {
        expect(decoded.elevations[i], original[i]);
      }
      // La bbox del vecchio formato era in Float32: si accetta la sua
      // precisione, ma deve restare nell'ordine di grandezza giusto.
      expect(decoded.minLat, closeTo(t.minLat, 1e-4));
    });

    test('byte del nuovo formato non vengono letti come vecchi', () {
      final compact = encodeDemTile(tile(syntheticTerrain(16, 16), w: 16, h: 16));
      final asLegacy = decodeLegacyDemTile(compact);
      // Il magic 'TSD1' letto come uint32 darebbe una larghezza assurda.
      expect(asLegacy, isNull);
    });

    test('vecchio formato troncato → null', () {
      final good = encodeLegacyDemTile(tile(syntheticTerrain(16, 16), w: 16, h: 16));
      expect(
        decodeLegacyDemTile(Uint8List.sublistView(good, 0, good.length ~/ 2)),
        isNull,
      );
    });
  });

  test('byte troncati o corrotti → null', () {
    final good = encodeDemTile(tile(syntheticTerrain(32, 32), w: 32, h: 32));
    expect(decodeDemTile(Uint8List.sublistView(good, 0, good.length ~/ 2)),
        isNull);
    expect(decodeDemTile(Uint8List(10)), isNull);
  });
}
