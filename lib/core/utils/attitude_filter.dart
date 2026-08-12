import 'dart:math' as math;

/// Il compromesso fra tremolio e ritardo, risolto meglio di un passa-basso.
///
/// Ogni filtro che smorza introduce ritardo: è la stessa manopola. Un
/// passa-basso con coefficiente fisso costringe a scegliere una volta per tutte
/// fra «fermo ma in ritardo» e «reattivo ma tremolante», e nessuna delle due
/// scelte va bene per un mirino che si tiene in mano ferma e poi si ruota.
///
/// Il **One Euro Filter** (Casiez, Roussel, Vogel, 2012) rende il taglio
/// funzione della velocità del segnale: fermo taglia basso — il tremolio dei
/// sensori sparisce — e in movimento apre, così il ritardo si annulla proprio
/// quando si noterebbe.
///
/// La differenza con l'EMA adattivo che c'era prima non è solo di curva. Quello
/// ricavava un unico coefficiente dalla velocità dell'**azimut** e lo applicava
/// anche a beccheggio e rollio: alzare il telefono verso una cima senza ruotare
/// prendeva il coefficiente più lento, cioè un ritardo di un decimo di secondo
/// sul movimento che si stava facendo. Qui ogni angolo ha la sua derivata e il
/// suo taglio, e quel difetto non può ripresentarsi.
class OneEuroFilter {
  /// Taglio a riposo, in hertz. Più basso = più fermo da fermi, più ritardo.
  final double minCutoff;

  /// Quanto il taglio si apre con la velocità. Più alto = meno ritardo in
  /// movimento, più tremolio lasciato passare.
  final double beta;

  /// Taglio applicato alla stima della velocità. Serve a non far sobbalzare il
  /// taglio stesso a ogni campione rumoroso.
  final double dCutoff;

  double? _value;
  double? _dValue;

  OneEuroFilter({
    this.minCutoff = 0.8,
    this.beta = 0.4,
    this.dCutoff = 1.0,
  });

  bool get hasValue => _value != null;
  double? get value => _value;

  static double _alpha(double cutoff, double dt) {
    final tau = 1 / (2 * math.pi * cutoff);
    return 1 / (1 + tau / dt);
  }

  /// Filtra un campione arrivato dopo [dt] secondi dal precedente.
  double filter(double x, double dt) {
    final prev = _value;
    if (prev == null || dt <= 0) {
      _value = x;
      _dValue = 0;
      return x;
    }

    final dx = (x - prev) / dt;
    final ed = _dValue = _dValue! +
        _alpha(dCutoff, dt) * (dx - _dValue!);

    final cutoff = minCutoff + beta * ed.abs();
    final a = _alpha(cutoff, dt);
    return _value = prev + a * (x - prev);
  }

  void reset() {
    _value = null;
    _dValue = null;
  }
}

/// [OneEuroFilter] per un angolo in gradi, con il giro chiuso.
///
/// Senza questo, passando da 359° a 1° il filtro attraverserebbe tutto il
/// quadrante nel verso sbagliato: la scena farebbe un giro completo su sé stessa
/// ogni volta che si punta a nord. È il difetto che si vede solo guardando
/// nell'unica direzione che tutti guardano per prima.
class AngleOneEuroFilter {
  final OneEuroFilter _inner;

  /// `true` per l'azimut, che si esprime in [0, 360); `false` per il rollio,
  /// che vive in (-180, 180] e col segno vuol dire da che parte è inclinato.
  final bool wrapTo360;

  AngleOneEuroFilter({
    double minCutoff = 0.8,
    double beta = 0.4,
    double dCutoff = 1.0,
    this.wrapTo360 = true,
  }) : _inner = OneEuroFilter(
          minCutoff: minCutoff,
          beta: beta,
          dCutoff: dCutoff,
        );

  bool get hasValue => _inner.hasValue;

  double? get value {
    final v = _inner.value;
    return v == null ? null : _normalize(v);
  }

  double filter(double angleDeg, double dt) {
    final prev = _inner.value;
    if (prev == null) return _normalize(_inner.filter(angleDeg, dt));

    // Si porta il campione sul ramo continuo più vicino al valore corrente, si
    // filtra su una retta, e si richiude alla fine. Il filtro non sa niente
    // degli angoli, ed è giusto che resti così.
    var delta = angleDeg - prev;
    delta -= 360 * (delta / 360).roundToDouble();
    return _normalize(_inner.filter(prev + delta, dt));
  }

  void reset() => _inner.reset();

  double _normalize(double d) {
    final r = ((d % 360) + 360) % 360;
    if (wrapTo360) return r;
    return r > 180 ? r - 360 : r;
  }
}

/// I tre angoli dell'assetto, ciascuno col proprio filtro.
class AttitudeFilter {
  final AngleOneEuroFilter azimuth;

  /// Il beccheggio **non** è un angolo che gira: sta fra -90 e +90 e non passa
  /// mai per il giro. Trattarlo come gli altri lo farebbe uscire a 348° invece
  /// che a -12°, con lo stesso coseno e un significato diverso per chiunque lo
  /// legga o lo confronti.
  final OneEuroFilter pitch;

  final AngleOneEuroFilter roll;

  /// Istante dell'ultimo campione, in **millisecondi di un orologio monotono**.
  ///
  /// Deve venire dal sensore, non da `DateTime.now()` all'arrivo: quest'ultimo
  /// include la coda del canale verso Dart, che è variabile e non ha niente a
  /// che fare con quando la misura è stata presa. Un `dt` sporco entra
  /// direttamente nella stima della velocità, cioè nel cuore del filtro.
  double? _lastMs;

  AttitudeFilter({
    double minCutoff = 0.8,
    double beta = 0.4,
    double dCutoff = 1.0,
  })  : azimuth = AngleOneEuroFilter(
            minCutoff: minCutoff,
            beta: beta,
            dCutoff: dCutoff,
            wrapTo360: true),
        pitch = OneEuroFilter(
            minCutoff: minCutoff, beta: beta, dCutoff: dCutoff),
        roll = AngleOneEuroFilter(
            minCutoff: minCutoff,
            beta: beta,
            dCutoff: dCutoff,
            wrapTo360: false);

  /// Filtra un assetto. [timestampMs] è l'orologio del sensore; se manca si
  /// ripiega su un passo nominale, che è meglio di un `dt` inventato dalla coda
  /// del canale.
  ({double azimuthDeg, double pitchDeg, double rollDeg}) filter({
    required double azimuthDeg,
    required double pitchDeg,
    required double rollDeg,
    double? timestampMs,
    double fallbackDt = 0.02,
  }) {
    var dt = fallbackDt;
    final last = _lastMs;
    if (timestampMs != null) {
      if (last != null) {
        final d = (timestampMs - last) / 1000.0;
        // Un salto all'indietro o un buco lungo (app in sottofondo, sensore
        // riavviato) non deve produrre un dt assurdo: si ricade sul nominale.
        dt = (d > 0 && d < 0.5) ? d : fallbackDt;
      }
      _lastMs = timestampMs;
    }

    return (
      azimuthDeg: azimuth.filter(azimuthDeg, dt),
      pitchDeg: pitch.filter(pitchDeg, dt),
      rollDeg: roll.filter(rollDeg, dt),
    );
  }

  void reset() {
    azimuth.reset();
    pitch.reset();
    roll.reset();
    _lastMs = null;
  }
}
