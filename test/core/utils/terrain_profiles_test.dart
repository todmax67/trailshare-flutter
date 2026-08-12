import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/core/utils/viewshed_compute.dart';

/// Il terreno diviso per fasce di distanza è ciò che trasforma la riga
/// dell'orizzonte in un paesaggio. Questi test bloccano le tre proprietà da cui
/// dipende tutto il disegno:
///
/// 1. le fasce **contengono** lo skyline di sempre (nessuna regressione);
/// 2. una fascia lontana può stare **sopra** una vicina, ed è il caso normale
///    in montagna: se una cima lontana si vede oltre una cresta vicina, deve per
///    forza sottendere un angolo maggiore;
/// 3. dove il terreno non lo conosciamo le fasce **tacciono**, invece di
///    dichiarare un orizzonte che finisce dove finiscono le tessere scaricate.
const double _obsLat = 45.0;
const double _obsLng = 9.0;
const double _mPerDegLat = 111320.0;

DemGrid _grid({
  required int rows,
  required int cols,
  required double Function(double lat, double lng) terrain,
  double minLat = 44.5,
  double maxLat = 45.5,
  double minLng = 8.5,
  double maxLng = 9.5,
}) {
  final ele = Float32List(rows * cols);
  final g = DemGrid(
    minLat: minLat,
    maxLat: maxLat,
    minLng: minLng,
    maxLng: maxLng,
    rows: rows,
    cols: cols,
    elevations: ele,
  );
  for (var r = 0; r < rows; r++) {
    final lat = g.latForRow(r);
    for (var c = 0; c < cols; c++) {
      ele[r * cols + c] = terrain(lat, g.lngForCol(c));
    }
  }
  return g;
}

ViewshedResult _run(DemGrid coarse, {double radiusKm = 40}) =>
    computeViewshed(ViewshedRequest(
      observerLat: _obsLat,
      observerLng: _obsLng,
      dem: LayeredDem(coarse: coarse),
      candidatePeaks: const [],
      computeSkyline: true,
      skylineRadiusM: radiusKm * 1000,
    ));

/// L'indice di azimut che guarda esattamente a nord.
const int _nord = 0;

void main() {
  _ombreggiatura();
  group('le fasce e lo skyline raccontano la stessa cosa', () {
    test('il massimo fra le fasce È lo skyline, azimut per azimut', () {
      // Se questo si rompe, il paesaggio disegnato e la riga usata per il
      // tramonto direbbero due cose diverse sullo stesso terreno.
      final dem = _grid(
        rows: 700,
        cols: 500,
        terrain: (lat, lng) {
          final dn = (lat - _obsLat) * _mPerDegLat;
          if (dn < 0) return 0;
          // Due creste una dietro l'altra: 4 km e 20 km.
          if (dn > 3500 && dn < 4500) return 900.0;
          if (dn > 19000 && dn < 21000) return 2600.0;
          return 200.0;
        },
      );

      final r = _run(dem);
      expect(r.profiles.isEmpty, isFalse);

      var confrontati = 0;
      for (var a = 0; a < r.skylineAngles.length; a++) {
        final sky = r.skylineAngles[a];
        // Solo i raggi interamente noti: dove il DEM finisce, le fasce oltre il
        // buco tacciono di proposito e il massimo non può più coincidere.
        if (sky.isNaN || r.profiles.knownUpToM[a].isFinite) continue;
        var max = double.negativeInfinity;
        for (final banda in r.profiles.byBand) {
          final v = banda[a];
          if (!v.isNaN && v > max) max = v;
        }
        expect(max, closeTo(sky, 1e-9),
            reason: 'azimut $a: fasce $max, skyline $sky');
        confrontati++;
      }
      expect(confrontati, greaterThan(150),
          reason: 'il confronto deve valere su una fetta consistente del giro, '
              'non su due raggi fortunati');
    });

    test('senza skyline richiesto non si calcola niente', () {
      final dem = _grid(rows: 100, cols: 100, terrain: (_, _) => 100);
      final r = computeViewshed(ViewshedRequest(
        observerLat: _obsLat,
        observerLng: _obsLng,
        dem: LayeredDem(coarse: dem),
        candidatePeaks: const [],
      ));
      expect(r.profiles.isEmpty, isTrue);
      expect(r.skylineAngles, isEmpty);
    });
  });

  group('la fascia lontana sta sopra quella vicina, se si vede', () {
    test('una cima lontana visibile oltre una cresta vicina è più in alto', () {
      // Geometria costruita apposta, e i numeri contano: la cresta a 4 km alta
      // 900 m sottende 10,9°, quindi per vedersi OLTRE, la montagna a 20 km
      // deve superarli — servono più di 4.100 m, non bastano 2.600 (che da lì
      // sottendono 6,8° e restano nascosti). Con 4.500 m siamo a 12,1°.
      final dem = _grid(
        rows: 700,
        cols: 500,
        terrain: (lat, lng) {
          final dn = (lat - _obsLat) * _mPerDegLat;
          if (dn > 3500 && dn < 4500) return 900.0;
          if (dn > 19000 && dn < 21000) return 4500.0;
          return 200.0;
        },
      );

      final p = _run(dem).profiles;
      // 4 km cade nella seconda fascia (2-6 km), 20 km nella quarta (15-35).
      final vicina = p.byBand[1][_nord];
      final lontana = p.byBand[3][_nord];

      expect(vicina.isNaN, isFalse, reason: 'la cresta a 4 km si deve vedere');
      expect(lontana.isNaN, isFalse, reason: 'la cima a 20 km si deve vedere');
      expect(lontana, greaterThan(vicina),
          reason: 'vicina $vicina°, lontana $lontana°');
    });

    test('una fascia interamente nascosta tace', () {
      // Muro altissimo a 4 km: oltre non si vede più niente, quindi le fasce
      // successive non devono inventarsi un profilo.
      final dem = _grid(
        rows: 700,
        cols: 500,
        terrain: (lat, lng) {
          final dn = (lat - _obsLat) * _mPerDegLat;
          if (dn > 3500 && dn < 4500) return 4000.0;
          if (dn > 19000 && dn < 21000) return 600.0;
          return 200.0;
        },
      );

      final p = _run(dem).profiles;
      expect(p.byBand[1][_nord].isNaN, isFalse, reason: 'il muro si vede');
      expect(p.byBand[3][_nord].isNaN, isTrue,
          reason: 'dietro un muro di 4000 m non si vede niente a 20 km');
    });
  });

  group('dove non sappiamo, si tace', () {
    test('le fasce oltre il buco nel DEM sono NaN', () {
      // Terreno noto solo entro 8 km: è la situazione di chi ha scaricato una
      // zona e guarda oltre il suo bordo.
      final dem = _grid(
        rows: 700,
        cols: 500,
        terrain: (lat, lng) {
          final dn = (lat - _obsLat) * _mPerDegLat;
          if (dn > 8000) return double.nan;
          if (dn > 3500 && dn < 4500) return 900.0;
          return 200.0;
        },
      );

      final r = _run(dem);
      final p = r.profiles;

      expect(p.knownUpToM[_nord], lessThan(9000),
          reason: 'il limite della conoscenza va riconosciuto');
      expect(p.byBand[1][_nord].isNaN, isFalse,
          reason: 'entro gli 8 km il terreno lo conosciamo');
      expect(p.byBand[3][_nord].isNaN, isTrue,
          reason: 'la fascia 15-35 km comincia oltre il buco: non va disegnata');
      expect(p.byBand[4][_nord].isNaN, isTrue);
    });

    test('con terreno completo il limite è infinito', () {
      final dem = _grid(rows: 400, cols: 300, terrain: (_, _) => 300);
      final p = _run(dem, radiusKm: 20).profiles;
      expect(p.knownUpToM.every((d) => d.isInfinite), isTrue);
    });

    test('lo skyline storico NON cambia comportamento coi buchi', () {
      // Il taglio vale per il disegno delle fasce, non per lo skyline: quello
      // resta il massimo di ciò che si è potuto misurare, perché altre parti
      // (il tramonto dietro la cresta) ci ragionano già sopra con le proprie
      // regole. Cambiarlo qui sarebbe una modifica silenziosa a due funzioni.
      final dem = _grid(
        rows: 700,
        cols: 500,
        terrain: (lat, lng) {
          final dn = (lat - _obsLat) * _mPerDegLat;
          if (dn > 8000) return double.nan;
          if (dn > 3500 && dn < 4500) return 900.0;
          return 200.0;
        },
      );
      final r = _run(dem);
      expect(r.skylineAngles[_nord].isNaN, isFalse);
      expect(r.skylineAngles[_nord], greaterThan(0),
          reason: 'la cresta a 4 km resta nello skyline');
    });
  });

  group('le fasce', () {
    test('bandFor mette ogni distanza nella sua', () {
      expect(TerrainProfiles.bandFor(500), 0);
      expect(TerrainProfiles.bandFor(2000), 0);
      expect(TerrainProfiles.bandFor(2001), 1);
      expect(TerrainProfiles.bandFor(6000), 1);
      expect(TerrainProfiles.bandFor(15000), 2);
      expect(TerrainProfiles.bandFor(35000), 3);
      expect(TerrainProfiles.bandFor(80000), 4);
      expect(TerrainProfiles.bandFor(1e12), TerrainProfiles.bandCount - 1,
          reason: 'nessuna distanza deve cadere fuori da tutte le fasce');
    });

    test('i confini sono crescenti', () {
      final l = TerrainProfiles.bandLimitsM;
      for (var i = 1; i < l.length; i++) {
        expect(l[i], greaterThan(l[i - 1]));
      }
    });

    test('ogni fascia ha un valore per ogni azimut', () {
      final dem = _grid(rows: 300, cols: 220, terrain: (_, _) => 400);
      final r = _run(dem, radiusKm: 15);
      for (final banda in r.profiles.byBand) {
        expect(banda.length, r.skylineAngles.length);
      }
      expect(r.profiles.byBand.length, TerrainProfiles.bandCount);
      expect(r.profiles.knownUpToM.length, r.skylineAngles.length);
    });
  });
}

/// L'ombreggiatura è la parte che vende la funzione a chi fotografa: non «che
/// bel rilievo» ma *quale versante avrà luce alle sette*. Perché quella
/// risposta sia vera, la geometria deve essere giusta nel verso giusto — un
/// segno invertito produce un paesaggio dall'aria perfettamente plausibile con
/// il sole dalla parte sbagliata.
void _ombreggiatura() {
  group('lambertShade', () {
    test('terreno piatto: pieno sole allo zenit, niente all\'orizzonte', () {
      expect(
        lambertShade(
            slopeE: 0, slopeN: 0, sunAzimuthDeg: 180, sunElevationDeg: 90),
        closeTo(1, 1e-9),
      );
      expect(
        lambertShade(
            slopeE: 0, slopeN: 0, sunAzimuthDeg: 180, sunElevationDeg: 0),
        closeTo(0, 1e-9),
      );
    });

    test('un versante a est prende il sole del mattino, non quello della sera',
        () {
      // Pendenza che scende verso est => la normale punta a est.
      const versanteEst = -1.0; // dz/de negativo = si scende andando a est
      final mattino = lambertShade(
          slopeE: versanteEst,
          slopeN: 0,
          sunAzimuthDeg: 90, // sole a est
          sunElevationDeg: 20);
      final sera = lambertShade(
          slopeE: versanteEst,
          slopeN: 0,
          sunAzimuthDeg: 270, // sole a ovest
          sunElevationDeg: 20);
      expect(mattino, greaterThan(0.5));
      expect(sera, 0, reason: 'alle spalle del sole non arriva niente');
    });

    test('un versante a sud è più illuminato di uno a nord, da noi', () {
      const sole = (az: 180.0, el: 40.0); // mezzogiorno alle nostre latitudini
      final sud = lambertShade(
          slopeE: 0,
          slopeN: 1.0, // salendo verso nord => guarda a sud
          sunAzimuthDeg: sole.az,
          sunElevationDeg: sole.el);
      final nord = lambertShade(
          slopeE: 0,
          slopeN: -1.0,
          sunAzimuthDeg: sole.az,
          sunElevationDeg: sole.el);
      expect(sud, greaterThan(nord));
      expect(nord, 0, reason: 'il versante nord a mezzogiorno resta in ombra');
    });

    test('non esce mai dall\'intervallo 0-1', () {
      for (final se in [-3.0, -0.4, 0.0, 0.4, 3.0]) {
        for (final sn in [-3.0, -0.4, 0.0, 0.4, 3.0]) {
          for (final az in [0.0, 77.0, 180.0, 300.0]) {
            for (final el in [-10.0, 0.0, 15.0, 89.0]) {
              final v = lambertShade(
                  slopeE: se,
                  slopeN: sn,
                  sunAzimuthDeg: az,
                  sunElevationDeg: el);
              expect(v, inInclusiveRange(0, 1));
            }
          }
        }
      }
    });

    test('pendenza ignota = piatto = nessuna ombra inventata', () {
      // Il calcolo delle pendenze restituisce (0,0) dove il DEM ha buchi:
      // significa "non lo so", e deve produrre lo stesso valore ovunque, non
      // una parete che non esiste.
      final a = lambertShade(
          slopeE: 0, slopeN: 0, sunAzimuthDeg: 45, sunElevationDeg: 30);
      final b = lambertShade(
          slopeE: 0, slopeN: 0, sunAzimuthDeg: 200, sunElevationDeg: 30);
      expect(a, closeTo(b, 1e-12));
    });
  });

  group('le pendenze arrivano fino al disegno', () {
    test('su terreno inclinato le pendenze non sono tutte zero', () {
      final dem = _grid(
        rows: 500,
        cols: 360,
        terrain: (lat, lng) {
          // Un cono attorno all'osservatore: ogni direzione ha una pendenza.
          final dn = (lat - _obsLat) * _mPerDegLat;
          final de = (lng - _obsLng) * _mPerDegLat * 0.707;
          final r = math.sqrt(dn * dn + de * de);
          return 2500 - r * 0.15;
        },
      );
      final p = _run(dem, radiusKm: 12).profiles;
      expect(p.hasSlopes, isTrue);

      var conPendenza = 0;
      for (var b = 0; b < p.byBand.length; b++) {
        for (var a = 0; a < p.byBand[b].length; a++) {
          if (p.byBand[b][a].isNaN) continue;
          if (p.slopeE[b][a].abs() > 1e-6 || p.slopeN[b][a].abs() > 1e-6) {
            conPendenza++;
          }
        }
      }
      expect(conPendenza, greaterThan(100),
          reason: 'su un cono la pendenza c\'è quasi ovunque, invece '
              '$conPendenza punti');
    });

    test('su terreno perfettamente piatto le pendenze sono zero', () {
      final dem = _grid(rows: 300, cols: 220, terrain: (_, _) => 800);
      final p = _run(dem, radiusKm: 10).profiles;
      for (var b = 0; b < p.byBand.length; b++) {
        for (var a = 0; a < p.byBand[b].length; a++) {
          expect(p.slopeE[b][a].abs(), lessThan(1e-6));
          expect(p.slopeN[b][a].abs(), lessThan(1e-6));
        }
      }
    });
  });
}
