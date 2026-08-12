import 'dart:math' as math;
import 'dart:typed_data';

/// Calcolo di visibilità delle cime — puro (no I/O), eseguibile in Isolate.
///
/// **Come funziona ora**: per ogni cima si percorre la *linea di vista* che
/// va dall'occhio dell'osservatore alla vetta, campionando il terreno lungo il
/// tragitto. Se in un punto il terreno sta più in alto della congiungente, la
/// cima è nascosta.
///
/// **Come funzionava prima, e perché era sbagliato**: si calcolava una volta lo
/// skyline a 360 raggi (uno per grado) e si confrontava ogni cima con il raggio
/// più vicino al suo azimut. Ma un raggio "vicino" a 1° di distanza passa 1,7 km
/// di lato a 100 km: su un crinale articolato è tutta un'altra montagna. Il
/// confronto per settori produceva sia falsi positivi sia falsi negativi, e
/// nessuna delle due cose è accettabile in una funzione che serve proprio a dire
/// cosa si vede.
///
/// Il costo del metodo diretto è irrisorio: qualche centinaio di campioni per
/// cima, cioè decine di millisecondi per un migliaio di cime.
///
/// Curvatura terrestre e rifrazione sono applicate sia alle quote del terreno
/// sia a quella della cima:
///   abbassamento_apparente = (1 - k) * d² / (2 * R)
/// con k=0.13 (rifrazione standard) e R=6371 km.

/// Raggio medio della Terra in metri.
const double _earthRadiusM = 6371000.0;

/// Coefficiente di rifrazione atmosferica standard.
const double _refractionK = 0.13;

class ViewshedRequest {
  final double observerLat;
  final double observerLng;

  /// Altezza dell'osservatore sopra il terreno (m). 1,7 m = persona in piedi.
  final double observerHeightM;

  /// Tolleranza sotto la quale una cima si considera comunque nascosta, in
  /// gradi di scarto angolare dall'ostacolo peggiore.
  ///
  /// Il confronto è **in angolo, misurato dall'occhio**, e non in metri di
  /// quota: un franco in metri sembra più intuitivo ma vicino all'osservatore è
  /// spropositato — a 100 m di distanza venti metri valgono undici gradi, e
  /// qualunque prato in leggera salita "occluderebbe" tutto l'orizzonte.
  ///
  /// Il valore serve solo a non far sfarfallare le cime esattamente radenti a
  /// una cresta, per il rumore di interpolazione del DEM. Il vecchio margine
  /// era 0,5°, cioè 175 m di stacco richiesti a 20 km e 436 m a 50 km: era
  /// quello a nascondere cime perfettamente visibili.
  final double visibilityToleranceDeg;

  /// Quanto prima della vetta si smette di campionare, in metri.
  ///
  /// Il terreno immediatamente sotto una cima è il pendio della cima stessa, e
  /// senza questo taglio la vetta risulterebbe occlusa da sé — soprattutto con
  /// DEM grossolani, dove la cella che contiene la vetta è una media dell'area
  /// e può stare più in alto del punto quotato.
  final double peakClearanceM;

  /// Cime candidate da testare: `[{id, lat, lng, ele}, ...]`.
  final List<Map<String, dynamic>> candidatePeaks;

  /// Terreno, eventualmente a due risoluzioni.
  final LayeredDem dem;

  /// Skyline a 360°: **non** serve più alla visibilità, serve a disegnare il
  /// profilo dell'orizzonte sopra l'immagine della camera — il riferimento che
  /// permette all'utente di vedere con i propri occhi se il puntamento combacia.
  /// Di default non si calcola, per non pagarlo quando non lo si usa.
  final bool computeSkyline;

  /// Numero di direzioni campionate per lo skyline. 720 = mezzo grado, che a
  /// 20 km sono 175 m di risoluzione laterale: abbastanza per non arrotondare
  /// le vette, senza il costo di un campionamento più fitto.
  final int azimuthSteps;

  /// Fin dove spingere i raggi dello skyline, in metri.
  final double skylineRadiusM;

  const ViewshedRequest({
    required this.observerLat,
    required this.observerLng,
    required this.dem,
    required this.candidatePeaks,
    this.observerHeightM = 1.7,
    this.visibilityToleranceDeg = 0.05,
    this.peakClearanceM = 250,
    this.computeSkyline = false,
    this.azimuthSteps = 720,
    this.skylineRadiusM = 60000,
  });
}

/// Rappresentazione "flat" di una griglia DEM regolare in lat/lng, passabile
/// fra Isolate (solo tipi primitivi + [Float32List]).
///
/// La griglia copre la bbox [minLat..maxLat, minLng..maxLng] con `rows × cols`
/// celle. `elevations[row * cols + col]` = quota in metri.
///
/// **Riga 0 = bordo sud, colonna 0 = bordo ovest.** Chi riempie la griglia deve
/// usare [latForRow] e [lngForCol]: scrivere la formula a mano è già costato un
/// difetto in cui il mosaico riempiva al contrario e il DEM veniva riletto
/// specchiato nord-sud.
class DemGrid {
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;
  final int rows;
  final int cols;

  /// Quote in metri, `Float32List` e non `List<double>`: su una griglia da 2,5
  /// milioni di celle la seconda pesa ~50 MB di double incassettati e viene
  /// serializzata elemento per elemento verso l'isolate, la prima ne pesa 10 e
  /// si trasferisce come un blocco di memoria.
  final Float32List elevations;

  const DemGrid({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
    required this.rows,
    required this.cols,
    required this.elevations,
  });

  /// Latitudine del centro della riga [row]. Riga 0 = bordo sud.
  double latForRow(int row) =>
      rows <= 1 ? minLat : minLat + row * (maxLat - minLat) / (rows - 1);

  /// Longitudine del centro della colonna [col]. Colonna 0 = bordo ovest.
  double lngForCol(int col) =>
      cols <= 1 ? minLng : minLng + col * (maxLng - minLng) / (cols - 1);

  /// Lato approssimato di una cella in metri: serve a scegliere un passo di
  /// campionamento che non scavalchi le creste.
  double get cellSizeMeters {
    if (rows <= 1) return 100;
    final latSpanM = (maxLat - minLat) * 111320.0;
    return latSpanM / (rows - 1);
  }

  /// True se il punto cade dentro la bbox.
  bool contains(double lat, double lng) =>
      lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng;

  /// Lookup bilineare (lat,lng) → quota in metri. Restituisce [double.nan] se
  /// fuori bbox o se una delle celle vicine non ha dato — così chi legge sa
  /// distinguere "non lo so" da "livello del mare".
  double elevationAt(double lat, double lng) {
    if (!contains(lat, lng)) return double.nan;
    final fy = (lat - minLat) / (maxLat - minLat) * (rows - 1);
    final fx = (lng - minLng) / (maxLng - minLng) * (cols - 1);
    final r0 = fy.floor().clamp(0, rows - 1);
    final r1 = math.min(r0 + 1, rows - 1);
    final c0 = fx.floor().clamp(0, cols - 1);
    final c1 = math.min(c0 + 1, cols - 1);
    final dy = fy - r0;
    final dx = fx - c0;
    final e00 = elevations[r0 * cols + c0];
    final e01 = elevations[r0 * cols + c1];
    final e10 = elevations[r1 * cols + c0];
    final e11 = elevations[r1 * cols + c1];
    final e0 = e00 * (1 - dx) + e01 * dx;
    final e1 = e10 * (1 - dx) + e11 * dx;
    return e0 * (1 - dy) + e1 * dy;
  }
}

/// Terreno a due risoluzioni: una griglia fitta nel campo vicino e una larga
/// per il resto.
///
/// Il motivo è che le occlusioni si decidono soprattutto vicino: un dosso a
/// 200 metri nasconde mezzo orizzonte, ma su una griglia a 110 m/cella è tre
/// pixel e sparisce nella media. Lontano invece la risoluzione conta poco,
/// perché a 50 km un dettaglio di 100 m sottende 0,1°.
class LayeredDem {
  /// Griglia fitta attorno all'osservatore. Può mancare (offline, o fallita).
  final DemGrid? fine;

  /// Griglia larga, che copre tutto il raggio.
  final DemGrid coarse;

  const LayeredDem({required this.coarse, this.fine});

  /// Quota nel punto, preferendo la griglia fitta dove c'è.
  double elevationAt(double lat, double lng) {
    final f = fine;
    if (f != null && f.contains(lat, lng)) {
      final e = f.elevationAt(lat, lng);
      if (!e.isNaN) return e;
    }
    return coarse.elevationAt(lat, lng);
  }

  /// Passo di campionamento consigliato a distanza [d] dall'osservatore.
  ///
  /// Vicino serve un passo fine come la griglia fitta, lontano si può allargare:
  /// il passo fisso di 250 m su celle da 110 m scavalcava le creste sottili, e
  /// avendo il primo campione a 250 m rendeva invisibile qualunque dosso più
  /// vicino di così.
  double stepAt(double d) {
    // Mezza cella, non una e mezza: campionare più larghi della griglia
    // significa scavalcare le creste sottili senza vederle. Misurato su
    // terreno reale delle Alpi, con passo a 1,2 celle il risultato conteneva
    // l'11% di cime dichiarate visibili che a campionamento fine risultano
    // nascoste — tutte a lunga distanza e con margini risicati, cioè proprio
    // quelle che il filtro dovrebbe distinguere. Costa più campioni, ma il
    // calcolo è la parte economica: il tempo se ne va nello scaricare i tile.
    const nyquist = 0.5;
    final f = fine;
    final near =
        f != null ? math.max(12.0, f.cellSizeMeters * nyquist) : 40.0;
    final far = math.max(30.0, coarse.cellSizeMeters * nyquist);
    if (f != null && d <= 2000) return near;
    // Crescita graduale, per non avere un salto netto al bordo della griglia fitta.
    final t = ((d - 2000) / 8000).clamp(0.0, 1.0);
    return near + (far - near) * t;
  }
}

/// Il terreno visibile diviso in **fasce di distanza**.
///
/// È ciò che trasforma una riga in un paesaggio. Finora di ogni direzione
/// tenevamo un solo numero — l'angolo del punto più alto — e buttavamo tutto il
/// resto: da una vetta alpina lungo ogni raggio ci sono in media cinque creste
/// visibili una dietro l'altra, e ne disegnavamo una.
///
/// **Perché per fasce e non per creste.** L'alternativa ovvia è emettere ogni
/// cresta e poi cucire quelle di azimut adiacenti in linee continue. Sembra più
/// naturale ma non lo è: due creste su raggi vicini non hanno nessuna identità
/// che le leghi, e l'abbinamento va indovinato — un abbinamento sbagliato
/// produce linee che si incrociano e sfarfallano, e circa metà dei frammenti
/// risulta lungo due punti, cioè sporcizia. Le fasce invece sono definite per
/// costruzione: sono sempre continue lungo l'azimut, non c'è niente da
/// indovinare, e l'ordine di disegno è esatto perché una fascia vicina copre
/// sempre quella lontana.
///
/// In più danno gratis la cosa che fa leggere la profondità a colpo d'occhio: la
/// prospettiva aerea. Il colore per fascia *è* la distanza.
class TerrainProfiles {
  /// Confine esterno di ogni fascia, in metri. L'ultima arriva all'infinito.
  ///
  /// Spaziatura quasi logaritmica: da vicino un chilometro cambia il panorama,
  /// a cinquanta no.
  static const List<double> bandLimitsM = [2000, 6000, 15000, 35000, 1e9];

  static int bandFor(double distanceM) {
    for (var i = 0; i < bandLimitsM.length; i++) {
      if (distanceM <= bandLimitsM[i]) return i;
    }
    return bandLimitsM.length - 1;
  }

  static int get bandCount => bandLimitsM.length;

  /// `byBand[fascia][azimut]` = angolo massimo di terreno **visibile** in quella
  /// fascia, in gradi. `NaN` dove quella fascia non ha terreno visibile, oppure
  /// dove non sappiamo cosa ci sia.
  final List<List<double>> byBand;

  /// Fin dove arriva la nostra conoscenza lungo ogni azimut, in metri.
  ///
  /// Oltre questa distanza il DEM non ha risposto, quindi lì non si disegna
  /// niente: potrebbe esserci una montagna che non abbiamo scaricato. È la
  /// differenza fra dire «l'orizzonte è questo» e «l'orizzonte è questo fino a
  /// dove ho guardato».
  final List<double> knownUpToM;

  const TerrainProfiles({required this.byBand, required this.knownUpToM});

  static const TerrainProfiles empty =
      TerrainProfiles(byBand: [], knownUpToM: []);

  bool get isEmpty => byBand.isEmpty;
}

class ViewshedResult {
  /// Skyline in gradi per ogni step di azimut, vuoto se non richiesto.
  final List<double> skylineAngles;

  /// Il terreno per fasce di distanza, vuoto se lo skyline non era richiesto.
  final TerrainProfiles profiles;

  /// Risultati per ogni cima candidata, stessi indici input.
  final List<PeakResult> peaks;

  const ViewshedResult({
    required this.skylineAngles,
    required this.peaks,
    this.profiles = TerrainProfiles.empty,
  });
}

class PeakResult {
  final String id;
  final double azimuthDeg;
  final double distanceMeters;

  /// Angolo di elevazione apparente della cima sull'orizzonte dell'osservatore.
  final double elevationAngleDeg;

  /// Di quanti gradi la cima sta sopra l'ostacolo peggiore lungo il tragitto.
  /// Negativo = occlusa. Vicino a zero = "spunta appena dietro la cresta".
  final double clearanceDeg;

  final bool visible;

  /// True quando la dichiariamo visibile ma parte del terreno che sta in mezzo
  /// è sconosciuta: potrebbe esserci un crinale che non abbiamo scaricato.
  final bool uncertain;

  const PeakResult({
    required this.id,
    required this.azimuthDeg,
    required this.distanceMeters,
    required this.elevationAngleDeg,
    required this.clearanceDeg,
    required this.visible,
    this.uncertain = false,
  });
}

/// Calcola la visibilità delle cime. Top-level = passabile a `compute()`.
ViewshedResult computeViewshed(ViewshedRequest req) {
  final dem = req.dem;

  // Quota dell'occhio = terreno sotto l'osservatore + altezza persona.
  final ground = dem.elevationAt(req.observerLat, req.observerLng);
  if (ground.isNaN) {
    // Senza sapere dove siamo non si può dire nulla: meglio dichiarare tutto
    // incerto che restituire "nessuna cima visibile", che è indistinguibile da
    // una risposta legittima.
    return ViewshedResult(
      skylineAngles: const [],
      peaks: [
        for (final p in req.candidatePeaks)
          PeakResult(
            id: p['id']?.toString() ?? '',
            azimuthDeg: 0,
            distanceMeters: 0,
            elevationAngleDeg: 0,
            clearanceDeg: 0,
            visible: true,
            uncertain: true,
          ),
      ],
    );
  }
  final eyeElev = ground + req.observerHeightM;

  final peaks = <PeakResult>[];
  for (final peak in req.candidatePeaks) {
    final pLat = (peak['lat'] as num).toDouble();
    final pLng = (peak['lng'] as num).toDouble();
    final pEle = (peak['ele'] as num?)?.toDouble() ?? 0.0;
    final id = peak['id']?.toString() ?? '';

    final dist = _haversineMeters(req.observerLat, req.observerLng, pLat, pLng);
    final az = _bearingDeg(req.observerLat, req.observerLng, pLat, pLng);
    final peakApparent = pEle - _earthDropMeters(dist);
    final elevationAngle =
        math.atan2(peakApparent - eyeElev, dist) * 180 / math.pi;

    if (dist < 1) {
      // Siamo praticamente sulla vetta.
      peaks.add(PeakResult(
        id: id,
        azimuthDeg: az,
        distanceMeters: dist,
        elevationAngleDeg: elevationAngle,
        clearanceDeg: 90,
        visible: true,
      ));
      continue;
    }

    // Si campiona fino a poco prima della vetta: l'ultimo tratto è il pendio
    // della cima stessa e non può nasconderla.
    final endD = math.max(dist * 0.5, dist - req.peakClearanceM);

    double worstMarginDeg = double.infinity;
    double firstUnknownAt = double.infinity;
    bool occluded = false;

    double d = dem.stepAt(0);
    while (d < endD) {
      final pt = _destinationPoint(req.observerLat, req.observerLng, az, d);
      final ele = dem.elevationAt(pt[0], pt[1]);
      if (ele.isNaN) {
        // Terreno sconosciuto: non possiamo inventarci una quota, ma non è
        // nemmeno "via libera" — ce ne ricordiamo per marcare l'esito incerto.
        if (d < firstUnknownAt) firstUnknownAt = d;
      } else {
        // Confronto in ANGOLO visto dall'occhio: è la stessa cosa che
        // confrontare le quote sulla congiungente, ma resta sensato anche a
        // pochi metri dall'osservatore, dove la linea di vista sfiora il suolo.
        final terrainApparent = ele - _earthDropMeters(d);
        final terrainAngle =
            math.atan2(terrainApparent - eyeElev, d) * 180 / math.pi;
        final margin = elevationAngle - terrainAngle;
        if (margin < worstMarginDeg) worstMarginDeg = margin;
        if (margin < req.visibilityToleranceDeg) {
          occluded = true;
          break;
        }
      }
      d += dem.stepAt(d);
    }

    if (!worstMarginDeg.isFinite) worstMarginDeg = 90;
    final visible = !occluded;
    peaks.add(PeakResult(
      id: id,
      azimuthDeg: az,
      distanceMeters: dist,
      elevationAngleDeg: elevationAngle,
      clearanceDeg: worstMarginDeg,
      visible: visible,
      // Se il terreno ignoto sta *prima* della cima, il fatto che nulla la
      // occluda non dimostra niente. Se è già occlusa dal terreno noto, il
      // buco più in là non cambia la conclusione.
      uncertain: visible && firstUnknownAt < dist,
    ));
  }

  final terrain = req.computeSkyline ? _computeSkyline(req, eyeElev) : null;

  return ViewshedResult(
    skylineAngles: terrain?.skyline ?? const <double>[],
    profiles: terrain?.profiles ?? TerrainProfiles.empty,
    peaks: peaks,
  );
}

/// Profilo dell'orizzonte a 360° **e** il terreno per fasce di distanza.
///
/// Una sola marcia di raggi produce entrambi, perché sono la stessa passeggiata
/// con una contabilità in più: ogni volta che il terreno supera il massimo
/// corrente quel punto è *visibile*, e si annota nella fascia di distanza in cui
/// cade. Il massimo finale di ogni raggio è lo skyline di sempre.
///
/// Il costo aggiunto è un confronto e una scrittura per campione visibile, cioè
/// pochi punti percentuali: la marcia dei raggi resta il grosso, e resta
/// invariata.
({List<double> skyline, TerrainProfiles profiles}) _computeSkyline(
  ViewshedRequest req,
  double eyeElev,
) {
  final dem = req.dem;
  final steps = req.azimuthSteps;
  final skyline = List<double>.filled(steps, double.nan);
  final maxRangeM = req.skylineRadiusM;

  final bands = TerrainProfiles.bandCount;
  final byBand = [
    for (var b = 0; b < bands; b++) List<double>.filled(steps, double.nan),
  ];
  final knownUpTo = List<double>.filled(steps, double.infinity);

  for (int aIdx = 0; aIdx < steps; aIdx++) {
    final azDeg = aIdx * 360.0 / steps;
    double maxAngle = double.nan;
    double firstUnknown = double.infinity;
    double d = dem.stepAt(0);
    while (d <= maxRangeM) {
      final pt = _destinationPoint(req.observerLat, req.observerLng, azDeg, d);
      final ele = dem.elevationAt(pt[0], pt[1]);
      if (ele.isNaN) {
        // Qui finisce quello che sappiamo di questa direzione. Si continua a
        // marciare — lo skyline storico non cambia comportamento — ma da qui in
        // poi il disegno non ha più diritto di affermare niente.
        if (firstUnknown.isInfinite) firstUnknown = d;
      } else {
        final apparent = ele - _earthDropMeters(d);
        final angle = math.atan2(apparent - eyeElev, d) * 180 / math.pi;
        // NaN in un confronto è sempre falso, quindi la prima quota valida
        // vince comunque: non serve un sentinella tipo -90, che invece
        // finirebbe disegnata come una riga piatta sotto i piedi.
        if (!(angle <= maxAngle)) {
          // Superare il massimo corrente *è* la definizione di visibile: tutto
          // ciò che sta più in basso è nascosto da qualcosa di più vicino.
          maxAngle = angle;
          final b = TerrainProfiles.bandFor(d);
          if (!(angle <= byBand[b][aIdx])) byBand[b][aIdx] = angle;
        }
      }
      d += dem.stepAt(d);
    }
    skyline[aIdx] = maxAngle;
    knownUpTo[aIdx] = firstUnknown;

    // Le fasce che cominciano oltre il limite della conoscenza non si
    // disegnano. È l'inverso della regola che vale per le cime — una cima è
    // nascosta da ciò che ha *davanti*, una cresta è l'orizzonte per ciò che ha
    // *dietro* — e confondere le due significa dichiarare certo un orizzonte
    // che finisce dove finiscono le tessere scaricate.
    if (firstUnknown.isFinite) {
      for (var b = 0; b < bands; b++) {
        final inizioFascia = b == 0 ? 0.0 : TerrainProfiles.bandLimitsM[b - 1];
        if (inizioFascia >= firstUnknown) byBand[b][aIdx] = double.nan;
      }
    }
  }

  return (
    skyline: skyline,
    profiles: TerrainProfiles(byBand: byBand, knownUpToM: knownUpTo),
  );
}

/// Altezza del terreno a un azimut qualsiasi, interpolata fra i campioni dello
/// skyline.
///
/// Lo skyline è un array **circolare**: il campione dopo l'ultimo è il primo, e
/// l'azimut 359,9° sta fra i due. Chi lo indicizza a mano lo dimentica, e il
/// difetto si vede solo guardando a nord.
///
/// Restituisce `NaN` dove il terreno non è noto, propagando l'ignoranza invece
/// di appiattirla su uno zero che sembrerebbe un orizzonte piatto vero.
double skylineElevationAt(List<double> skyline, double azDeg) {
  final n = skyline.length;
  if (n == 0) return double.nan;
  final f = (azDeg % 360) / 360 * n;
  final i0 = f.floor() % n;
  final i1 = (i0 + 1) % n;
  final a = skyline[i0];
  final b = skyline[i1];
  if (a.isNaN || b.isNaN) return double.nan;
  return a + (b - a) * (f - f.floorToDouble());
}

/// Quale cima può nascondere qualcosa che si trova in una certa direzione.
///
/// Restituisce l'indice nella lista, o `null` se nessuna cima è candidata.
///
/// Il vincolo che conta non è la vicinanza in azimut ma l'**altezza**: una cima
/// più bassa del punto in cui il sole sparisce non può essere lei a nasconderlo,
/// per quanto sia allineata. Senza questo controllo si finisce a dire «il sole
/// tramonta dietro il Monte Tal dei Tali» indicando una collinetta che in quel
/// momento sta dieci gradi più in basso.
int? occluderIndex(
  List<double> azimuthsDeg,
  List<double> elevationAnglesDeg,
  double azDeg,
  double elevDeg, {
  double maxDeltaDeg = 4,
  double toleranceDeg = 0.5,
}) {
  int? best;
  var bestDelta = maxDeltaDeg;
  for (var i = 0; i < azimuthsDeg.length; i++) {
    if (elevationAnglesDeg[i] < elevDeg - toleranceDeg) continue;
    var d = (azimuthsDeg[i] - azDeg).abs();
    if (d > 180) d = 360 - d;
    if (d < bestDelta) {
      bestDelta = d;
      best = i;
    }
  }
  return best;
}

/// Drop apparente dovuto a curvatura terrestre + rifrazione atmosferica.
double _earthDropMeters(double distanceM) {
  return (1 - _refractionK) * distanceM * distanceM / (2 * _earthRadiusM);
}

/// Distanza haversine in metri tra due coordinate WGS84.
double _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return 2 * _earthRadiusM * math.asin(math.min(1.0, math.sqrt(a)));
}

/// Bearing iniziale in gradi (0 = nord, 90 = est) da P1 a P2.
double _bearingDeg(double lat1, double lng1, double lat2, double lng2) {
  final phi1 = lat1 * math.pi / 180;
  final phi2 = lat2 * math.pi / 180;
  final dl = (lng2 - lng1) * math.pi / 180;
  final y = math.sin(dl) * math.cos(phi2);
  final x = math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(dl);
  final brng = math.atan2(y, x) * 180 / math.pi;
  return (brng + 360) % 360;
}

/// Punto di arrivo dato origine + bearing + distanza (great-circle).
/// Restituisce [lat, lng].
List<double> _destinationPoint(
    double lat, double lng, double bearingDeg, double distanceM) {
  final phi1 = lat * math.pi / 180;
  final lambda1 = lng * math.pi / 180;
  final theta = bearingDeg * math.pi / 180;
  final delta = distanceM / _earthRadiusM;
  final phi2 = math.asin(math.sin(phi1) * math.cos(delta) +
      math.cos(phi1) * math.sin(delta) * math.cos(theta));
  final lambda2 = lambda1 +
      math.atan2(
        math.sin(theta) * math.sin(delta) * math.cos(phi1),
        math.cos(delta) - math.sin(phi1) * math.sin(phi2),
      );
  return [phi2 * 180 / math.pi, ((lambda2 * 180 / math.pi) + 540) % 360 - 180];
}
