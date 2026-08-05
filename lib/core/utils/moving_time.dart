import '../../data/models/track.dart';

/// Tempo effettivamente passato in movimento, distinto dal tempo totale.
///
/// ## Perche' non si giudica campione per campione
///
/// La prima versione confrontava la velocita' di **ogni coppia di punti**
/// consecutivi con una soglia. Sul campo ha prodotto 1h23 su un giro di 3h44 in
/// cui il tempo vero era circa 3h00 (2026-08-05, 12,3 km e +1057 m): meno della
/// meta'.
///
/// La causa non era la soglia, era la risoluzione. Applicando gli **stessi
/// parametri** ai punti decimati della stessa traccia — uno ogni ~13 secondi
/// invece che ogni pochi — il risultato era 2h57, cioe' quello giusto.
///
/// Fra due punti distanti pochi metri (il `distanceFilter` della registrazione,
/// 5 m all'epoca della misura, oggi 10) un
/// errore GPS di 3 metri e' piu' grande del segnale: a volte accorcia il
/// tratto, la velocita' istantanea crolla sotto soglia, e un pezzo di
/// camminata vera viene archiviato come sosta. Ripetuto su migliaia di
/// segmenti, dimezza il risultato.
///
/// E' lo stesso rumore che gonfia la distanza quando si campiona fitto, visto
/// dall'altro lato: li' somma metri che non hai percorso, qui toglie minuti in
/// cui ti stavi muovendo.
///
/// La cura e' valutare la velocita' su una **finestra** abbastanza lunga
/// perche' lo spostamento reale superi il rumore, e decidere per l'intero
/// blocco. Cosi' la misura non dipende piu' da quanto fitto ha campionato il
/// telefono — che e' la proprieta' che serve: la stessa camminata non puo'
/// dare tempi diversi a seconda del dispositivo.
const double _minSpeedMs = 0.5; // ~1,8 km/h: sotto questa soglia si e' fermi

/// Finestra minima su cui si giudica se ci si stava muovendo.
///
/// Quindici secondi sono il compromesso: a passo di camminata sono una
/// trentina di metri, abbastanza perche' un errore di 3 metri non decida
/// l'esito. Allungarla renderebbe la stima piu' stabile ma comincerebbe a
/// inghiottire le soste brevi dentro i blocchi in movimento.
///
/// Il valore e' sostenuto dai dati: sulla traccia di riferimento i punti
/// decimati distavano ~13 secondi e davano il risultato corretto.
const Duration _judgeWindow = Duration(seconds: 15);

/// Oltre questo intervallo fra due punti non c'e' piu' una misura di movimento:
/// c'e' un buco.
///
/// Col `distanceFilter` della registrazione due punti consecutivi distano
/// secondi quando ci
/// si muove. Se distano minuti, o si era fermi — e allora la soglia di
/// velocita' li scarta gia' — oppure la registrazione si era interrotta, e quel
/// tempo non e' stato misurato affatto.
///
/// Il caso che ha reso necessaria questa guardia: il 2026-08-03 il sistema ha
/// sospeso l'app per 37 minuti, durante i quali si sono percorsi 1231 m in
/// linea d'aria. Sono **0,553 m/s**, cioe' *sopra* [_minSpeedMs]: con la sola
/// soglia di velocita' l'intero blackout sarebbe finito nel tempo di
/// movimento, spacciando per camminata un tratto che nessuno ha misurato.
const Duration _maxSampleGap = Duration(seconds: 90);

/// Somma il tempo passato in movimento lungo una traccia completa.
Duration computeMovingTime(List<TrackPoint> points) {
  if (points.length < 2) return Duration.zero;
  final acc = MovingTimeAccumulator();
  for (var i = 1; i < points.length; i++) {
    acc.add(points[i - 1], points[i]);
  }
  // Senza questa la finestra ancora aperta a fine traccia andrebbe persa: su
  // una traccia corta puo' essere tutto il risultato.
  acc.finish();
  return acc.value;
}

/// Accumula il tempo in movimento mentre i punti arrivano.
///
/// Esiste separata da [computeMovingTime] perche' durante la registrazione i
/// punti arrivano uno alla volta: ricalcolare l'intera lista a ogni punto
/// sarebbe quadratico sulla durata dell'uscita, e su sei ore di cammino sono
/// milioni di operazioni su un dispositivo che si sta gia' cercando di non far
/// spegnere.
class MovingTimeAccumulator {
  Duration _settled = Duration.zero;

  // Finestra in costruzione: tempo e distanza accumulati finche' non e' lunga
  // abbastanza da poter essere giudicata.
  Duration _windowTime = Duration.zero;
  double _windowMetres = 0;

  /// Il tempo in movimento riconosciuto finora.
  ///
  /// Non include la finestra ancora aperta: durante la registrazione il valore
  /// puo' restare indietro di una quindicina di secondi, che a schermo non si
  /// vede.
  Duration get value => _settled;

  /// Aggiunge il tratto fra due punti consecutivi.
  void add(TrackPoint prev, TrackPoint curr) {
    // Timestamp di default (epoch, o comunque assurdi) su tracce importate da
    // sorgenti che non li portano: non si puo' dedurne alcuna durata.
    if (prev.timestamp.year <= 2000 || curr.timestamp.year <= 2000) return;

    final dt = curr.timestamp.difference(prev.timestamp);
    if (dt <= Duration.zero) return;

    // Un buco interrompe la finestra in corso: i due lati non sono un unico
    // tratto continuo e non vanno mediati insieme.
    if (dt > _maxSampleGap) {
      _closeWindow();
      return;
    }

    _windowTime += dt;
    _windowMetres += prev.distanceTo(curr);
    if (_windowTime >= _judgeWindow) _closeWindow();
  }

  /// Chiude la finestra corrente e decide se contarla.
  void _closeWindow() {
    if (_windowTime > Duration.zero) {
      final speed = _windowMetres / (_windowTime.inMilliseconds / 1000);
      if (speed >= _minSpeedMs) _settled += _windowTime;
    }
    _windowTime = Duration.zero;
    _windowMetres = 0;
  }

  /// Chiude i conti a fine registrazione, contando anche l'ultima finestra
  /// rimasta aperta.
  void finish() => _closeWindow();

  void reset() {
    _settled = Duration.zero;
    _windowTime = Duration.zero;
    _windowMetres = 0;
  }
}
