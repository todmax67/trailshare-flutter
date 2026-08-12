import 'dart:math' as math;

import '../../data/models/mountain_peak.dart';

/// Ricerca di una cima per nome, in un catalogo di trentasettemila.
///
/// Il problema non è trovare: è **ordinare**. Cercando «monte» le
/// corrispondenze sono migliaia, e un elenco in ordine di file è inutile quanto
/// nessun elenco. L'ordine qui è a due chiavi: prima quanto bene il nome
/// corrisponde, poi quanto la cima è vicina a chi cerca — perché chi digita
/// «monte nero» intende quasi sempre quello che ha davanti, non uno dei
/// venticinque omonimi sparsi per la penisola.
///
/// Prima la qualità e poi la distanza, e non il contrario: una corrispondenza
/// esatta dall'altra parte d'Italia deve comunque battere un vago somigliare
/// dietro casa. Chi scrive «Monte Rosa» sa cosa vuole.

/// Riduce un nome alla forma su cui si confronta.
///
/// Il catalogo è italiano, tedesco, francese e ladino insieme — *Tête de
/// Chabrière*, *Piz de las Cavigliadas*, *Durcheckkopf* — quindi senza togliere
/// gli accenti la ricerca funzionerebbe solo per chi sa comporli sulla tastiera.
/// E il carattere di apostrofo che produce un telefono non è quello che sta nel
/// dataset, quindi anche quelli vanno uniformati.
String foldForSearch(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    b.write(_folded[c] ?? c);
  }
  return b.toString().trim();
}

const Map<String, String> _folded = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  'ñ': 'n', 'ç': 'c', 'ß': 'ss',
  '’': "'", '‘': "'", '`': "'", '´': "'",
  '–': '-', '—': '-',
};

/// Quanto bene un nome risponde alla ricerca. Più basso = meglio.
///
/// `null` quando non risponde affatto.
int? matchQuality(String foldedName, String foldedQuery) {
  if (foldedQuery.isEmpty) return null;
  if (foldedName == foldedQuery) return 0;
  if (foldedName.startsWith(foldedQuery)) return 1;

  // Inizio di una parola: cercando «coca» si vuole trovare «Pizzo di Coca».
  // È il caso più comune di tutti, perché il nome proprio della montagna sta
  // quasi sempre dopo il suo tipo.
  var i = foldedName.indexOf(foldedQuery);
  while (i > 0) {
    final prima = foldedName[i - 1];
    if (prima == ' ' || prima == '-' || prima == "'") return 2;
    i = foldedName.indexOf(foldedQuery, i + 1);
  }
  return foldedName.contains(foldedQuery) ? 3 : null;
}

/// Una cima trovata, con quanto dista da chi cerca.
class PeakSearchHit {
  final MountainPeak peak;

  /// Distanza in metri dall'osservatore, o `null` se non si sa dove sia.
  final double? distanceMeters;

  const PeakSearchHit({required this.peak, this.distanceMeters});
}

/// Cerca [query] fra [peaks].
///
/// [observerLat]/[observerLng] servono solo a ordinare: senza, si ripiega sulla
/// quota, che è il modo meno arbitrario di scegliere quando non si sa da dove
/// si sta guardando.
List<PeakSearchHit> searchPeaksByName(
  Iterable<MountainPeak> peaks,
  String query, {
  double? observerLat,
  double? observerLng,
  int limit = 40,
}) {
  final q = foldForSearch(query);
  // Una lettera sola su trentasettemila cime restituirebbe l'elenco quasi
  // intero, ordinato per distanza: non è una ricerca, è una lista.
  if (q.length < 2) return const [];

  final haveObserver = observerLat != null && observerLng != null;
  final scored = <(int, double, MountainPeak)>[];

  for (final p in peaks) {
    final quality = matchQuality(foldForSearch(p.name), q);
    if (quality == null) continue;
    final d = haveObserver
        ? _haversine(observerLat, observerLng, p.latitude, p.longitude)
        : -(p.elevation ?? 0);
    scored.add((quality, d, p));
  }

  scored.sort((a, b) {
    final c = a.$1.compareTo(b.$1);
    return c != 0 ? c : a.$2.compareTo(b.$2);
  });

  return [
    for (final s in scored.take(limit))
      PeakSearchHit(
        peak: s.$3,
        distanceMeters: haveObserver ? s.$2 : null,
      ),
  ];
}

double _haversine(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final p1 = lat1 * math.pi / 180;
  final p2 = lat2 * math.pi / 180;
  final dp = (lat2 - lat1) * math.pi / 180;
  final dl = (lng2 - lng1) * math.pi / 180;
  final a = math.sin(dp / 2) * math.sin(dp / 2) +
      math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Di quanto e da che parte girarsi per avere una direzione davanti.
///
/// Positivo = a destra. Il segno è la metà del valore dell'indicazione: «47°»
/// non dice niente, «47° a destra» sì.
double relativeTurnDeg(double fromAzimuthDeg, double toAzimuthDeg) {
  var d = toAzimuthDeg - fromAzimuthDeg;
  d -= 360 * (d / 360).roundToDouble();
  return d;
}
