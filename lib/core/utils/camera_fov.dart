import 'dart:math' as math;

/// Campo visivo **realmente inquadrato** sullo schermo.
///
/// Il numero che serve alla proiezione AR non è il campo dell'obiettivo, è
/// quello che sopravvive dopo che la preview è stata ruotata e ritagliata per
/// riempire il viewport. Fra i due c'è di mezzo un `BoxFit.cover` che butta via
/// una parte dell'immagine, e ignorarlo vuol dire sbagliare il campo di parecchi
/// gradi — cioè spostare tutte le etichette.
///
/// Tutto qui dentro è puro e testabile: è l'ultimo numero della catena AR che
/// era tirato a indovinare (60°×80° scritti a tavolino), e vale la pena che sia
/// verificabile con numeri invece che puntando il telefono verso una montagna.
class CameraFov {
  /// Campo orizzontale dello schermo, in gradi.
  final double horizontalDeg;

  /// Campo verticale dello schermo, in gradi.
  final double verticalDeg;

  const CameraFov({required this.horizontalDeg, required this.verticalDeg});

  @override
  String toString() => '${horizontalDeg.toStringAsFixed(1)}×'
      '${verticalDeg.toStringAsFixed(1)}°';
}

/// Ricava il campo visivo inquadrato a partire da quello del sensore.
///
/// - [sensorHorizontalDeg] / [sensorVerticalDeg]: campo del fotogramma pieno,
///   nell'orientamento **nativo** del sensore (orizzontale).
/// - [bufferWidth] / [bufferHeight]: dimensioni del buffer della preview, anche
///   queste nell'orientamento nativo.
/// - [viewportWidth] / [viewportHeight]: lo spazio a schermo in cui la preview
///   viene composta con `BoxFit.cover`.
///
/// Due passaggi, entrambi facili da sbagliare:
///
/// 1. **La rotazione.** In portrait la preview viene ruotata di 90°, quindi il
///    lato orizzontale dello schermo mostra il lato *corto* del sensore: i due
///    campi si scambiano.
/// 2. **Il ritaglio.** `BoxFit.cover` ingrandisce finché il viewport è coperto e
///    taglia l'eccesso. La porzione che resta visibile va applicata alla
///    **tangente** del semiangolo, non ai gradi: una fotocamera è una
///    proiezione prospettica, e dimezzare la larghezza inquadrata non dimezza
///    l'angolo.
CameraFov? screenFovFromSensor({
  required double sensorHorizontalDeg,
  required double sensorVerticalDeg,
  required double bufferWidth,
  required double bufferHeight,
  required double viewportWidth,
  required double viewportHeight,
}) {
  if (sensorHorizontalDeg <= 0 ||
      sensorVerticalDeg <= 0 ||
      sensorHorizontalDeg >= 180 ||
      sensorVerticalDeg >= 180 ||
      bufferWidth <= 0 ||
      bufferHeight <= 0 ||
      viewportWidth <= 0 ||
      viewportHeight <= 0) {
    return null;
  }

  final isPortrait = viewportHeight >= viewportWidth;

  // **Il buffer non è il sensore.** Il campo dichiarato dall'hardware è quello
  // del fotogramma pieno (4:3 sul telefono), mentre la preview è quasi sempre
  // 16:9, cioè un ritaglio verticale dello stesso array: la larghezza si
  // conserva, l'altezza no. Prendere il campo verticale del sensore per un
  // buffer 16:9 lo sovrastima di parecchio — su un caso reale, 57,8° dichiarati
  // contro 45,3° effettivi.
  //
  // Quindi si tiene per buono il campo orizzontale e si ricava il verticale dal
  // rapporto d'aspetto **del buffer**, sempre lavorando sulle tangenti.
  final bufferFovH = sensorHorizontalDeg;
  final bufferFovV = _fovForAspect(sensorHorizontalDeg, bufferHeight / bufferWidth);

  // Se il buffer fosse più "alto" del sensore la larghezza non potrebbe essere
  // conservata, e il ragionamento sopra non varrebbe: in quel caso ci si fida
  // dei valori dichiarati.
  final sensorAspect = sensorVerticalDeg > 0
      ? math.tan(sensorVerticalDeg / 2 * math.pi / 180) /
          math.tan(sensorHorizontalDeg / 2 * math.pi / 180)
      : 0.75;
  final bufferAspect = bufferHeight / bufferWidth;
  final usableFovH = bufferAspect <= sensorAspect + 0.01
      ? bufferFovH
      : sensorHorizontalDeg;
  final usableFovV = bufferAspect <= sensorAspect + 0.01
      ? bufferFovV
      : sensorVerticalDeg;

  // Dopo la rotazione: quanto è largo/alto il riquadro della preview e quale
  // campo corrisponde a ciascun lato.
  final boxW = isPortrait ? bufferHeight : bufferWidth;
  final boxH = isPortrait ? bufferWidth : bufferHeight;
  final boxFovH = isPortrait ? usableFovV : usableFovH;
  final boxFovV = isPortrait ? usableFovH : usableFovV;

  // BoxFit.cover: si ingrandisce quanto basta a coprire, il resto esce fuori.
  final scale = math.max(viewportWidth / boxW, viewportHeight / boxH);
  final visibleFractionW = (viewportWidth / (boxW * scale)).clamp(0.0, 1.0);
  final visibleFractionH = (viewportHeight / (boxH * scale)).clamp(0.0, 1.0);

  return CameraFov(
    horizontalDeg: _cropFov(boxFovH, visibleFractionW),
    verticalDeg: _cropFov(boxFovV, visibleFractionH),
  );
}

/// Campo lungo un lato lungo [aspect] volte l'altro, a parità di focale.
double _fovForAspect(double fovDeg, double aspect) =>
    2 *
    math.atan(math.tan(fovDeg / 2 * math.pi / 180) * aspect) *
    180 /
    math.pi;

/// Campo che resta dopo aver tenuto la frazione [fraction] centrale
/// dell'immagine. Si opera sulla tangente, perché la proiezione è prospettica.
double _cropFov(double fullFovDeg, double fraction) {
  final halfTan = math.tan(fullFovDeg / 2 * math.pi / 180) * fraction;
  return 2 * math.atan(halfTan) * 180 / math.pi;
}
