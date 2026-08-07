/// Riduce i punti di una traccia **per forma**, non per posizione nella lista.
///
/// ## Cosa non andava nella decimazione uniforme
///
/// Prendere un punto ogni N tratta un tornante e un rettilineo allo stesso
/// modo: sul rettilineo butta punti che non servivano, sul tornante butta
/// proprio quelli che descrivono la curva. Il risultato e' una traccia che
/// taglia gli angoli — e siccome la distanza si misura sui segmenti, tagliare
/// gli angoli **accorcia il percorso**. E' il bug segnalato da un utente Pro:
/// un GPX da 34 km mostrato come 26,6.
///
/// Le statistiche oggi si calcolano sui punti completi, quindi i numeri sono
/// salvi. Ma la traccia **che si vede sulla mappa, che si esporta in GPX e che
/// si condivide** e' quella ridotta: su quella il difetto resta visibile.
///
/// ## Perche' Douglas-Peucker
///
/// Tiene un punto in base a quanto si discosta dalla linea che unisce i suoi
/// vicini. Su un rettilineo lo scarto e' quasi nullo e i punti cadono; su una
/// curva e' grande e i punti restano. A parita' di punti conservati la forma e'
/// molto piu' fedele — e con essa la lunghezza.
///
/// Ha anche un effetto utile di riflesso: il rumore GPS su un rettilineo
/// produce zig-zag di pochi metri che, sotto la tolleranza, spariscono. Non e'
/// un filtro sul rumore, ma ne toglie una parte gratis.
library;

import 'dart:math' as math;

import '../../data/models/track.dart';

/// Scostamento sotto il quale un punto e' considerato superfluo.
///
/// Due metri, non quattro. Il primo valore stava appena sopra l'accuratezza di
/// un fix buono (~3 m) col ragionamento che sotto quella soglia si butta solo
/// rumore — ma sul campo, alle Scale del Miller (2026-08-06, tornanti quasi
/// verticali uno dietro l'altro), la traccia disegnata restava piu' povera del
/// dovuto.
///
/// Abbassarla non tocca i numeri: distanza, dislivello e tempo si calcolano sui
/// punti completi, prima di arrivare qui. Cambia solo cosa si vede, si esporta
/// e si condivide — e li' piu' fedelta' e' sempre meglio, finche' il documento
/// ci sta.
///
/// Misurato sulla traccia del 2026-08-05: a 4 m restavano 326 punti con uno
/// scarto di lunghezza dell'1,1%; a 2 m ne restano 508 con lo 0,3%. Il costo e'
/// una sessantina di KB in piu' su un budget da 1 MiB.
const double _defaultToleranceMetres = 2.0;

/// Tetto di sicurezza sui punti conservati.
///
/// Era 1000, uniforme. Il vincolo vero e' il limite di 1 MiB per documento
/// Firestore: a ~155 byte per punto (misurati su una traccia reale) tremila
/// punti sono circa 465 KB, meno della meta' del budget — e il vecchio tetto
/// ne usava appena il 15%, buttando forma senza guadagnarci nulla.
///
/// Alla traccia tipica questo numero non serve: misurata su un giro reale di
/// 12 km, la tolleranza sopra ne conserva poche centinaia. Il tetto esiste per
/// le attivita' lunghissime, dove nessuna tolleranza ragionevole basterebbe da
/// sola a rientrare.
const int _defaultMaxPoints = 3000;

/// Semplifica la traccia conservandone la forma.
///
/// Se dopo la semplificazione i punti sono ancora oltre [maxPoints], la
/// tolleranza raddoppia e si riprova: meglio una traccia un po' piu' grezza di
/// un documento che Firestore rifiuta.
List<TrackPoint> simplifyTrack(
  List<TrackPoint> points, {
  double toleranceMetres = _defaultToleranceMetres,
  int maxPoints = _defaultMaxPoints,
}) {
  if (points.length <= 2) return points;

  var tolerance = toleranceMetres;
  var result = _douglasPeucker(points, tolerance);

  // Raddoppi successivi: 12 giri portano 4 m oltre i 16 km di tolleranza,
  // quindi il ciclo termina sempre molto prima. La guardia c'e' per non
  // dipendere da quel ragionamento.
  var guard = 0;
  while (result.length > maxPoints && guard++ < 12) {
    tolerance *= 2;
    result = _douglasPeucker(points, tolerance);
  }

  // Rete di sicurezza: se anche cosi' non rientra (traccia patologica, punti
  // tutti distinti oltre ogni tolleranza), si taglia uniformemente. Peggio
  // per la forma, ma il documento deve poter essere scritto.
  if (result.length > maxPoints) {
    result = _uniformFallback(result, maxPoints);
  }
  return result;
}

/// Douglas-Peucker iterativo.
///
/// Iterativo e non ricorsivo di proposito: la versione ricorsiva scende in
/// profondita' proporzionale ai punti e una traccia lunga puo' esaurire lo
/// stack proprio sul dispositivo piu' modesto.
List<TrackPoint> _douglasPeucker(List<TrackPoint> points, double tolerance) {
  final keep = List<bool>.filled(points.length, false);
  keep[0] = true;
  keep[points.length - 1] = true;

  final stack = <List<int>>[
    [0, points.length - 1],
  ];

  while (stack.isNotEmpty) {
    final range = stack.removeLast();
    final first = range[0];
    final last = range[1];
    if (last <= first + 1) continue;

    var maxDistance = 0.0;
    var index = first;
    for (var i = first + 1; i < last; i++) {
      final d = _perpendicularDistance(points[i], points[first], points[last]);
      if (d > maxDistance) {
        maxDistance = d;
        index = i;
      }
    }

    if (maxDistance > tolerance) {
      keep[index] = true;
      stack.add([first, index]);
      stack.add([index, last]);
    }
  }

  final out = <TrackPoint>[];
  for (var i = 0; i < points.length; i++) {
    if (keep[i]) out.add(points[i]);
  }
  return out;
}

/// Distanza in metri fra [p] e il segmento [a]–[b].
///
/// Proiezione equirettangolare locale: su qualche chilometro l'errore e'
/// trascurabile rispetto alla tolleranza, e costa una frazione della formula
/// esatta — che qui verrebbe chiamata milioni di volte.
double _perpendicularDistance(TrackPoint p, TrackPoint a, TrackPoint b) {
  const metresPerDegreeLat = 111320.0;
  final metresPerDegreeLon =
      metresPerDegreeLat * math.cos(a.latitude * math.pi / 180);

  final bx = (b.longitude - a.longitude) * metresPerDegreeLon;
  final by = (b.latitude - a.latitude) * metresPerDegreeLat;
  final px = (p.longitude - a.longitude) * metresPerDegreeLon;
  final py = (p.latitude - a.latitude) * metresPerDegreeLat;

  final segmentLength2 = bx * bx + by * by;
  if (segmentLength2 == 0) {
    return math.sqrt(px * px + py * py);
  }

  var t = (px * bx + py * by) / segmentLength2;
  t = t.clamp(0.0, 1.0);
  final cx = bx * t;
  final cy = by * t;
  final dx = px - cx;
  final dy = py - cy;
  return math.sqrt(dx * dx + dy * dy);
}

/// L'ultima risorsa: un punto ogni N, primo e ultimo garantiti.
List<TrackPoint> _uniformFallback(List<TrackPoint> points, int maxPoints) {
  if (points.length <= maxPoints) return points;
  final out = <TrackPoint>[points.first];
  final step = points.length / (maxPoints - 2);
  for (var i = 1; i < maxPoints - 1; i++) {
    final index = (i * step).round();
    if (index < points.length - 1) out.add(points[index]);
  }
  out.add(points.last);
  return out;
}
