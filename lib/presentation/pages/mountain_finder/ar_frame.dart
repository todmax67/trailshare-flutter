import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Size;

import '../../../core/utils/camera_orientation.dart';
import '../../../core/utils/mountain_projection.dart';
import '../../../data/models/mountain_peak.dart';

/// Lo stato che cambia a ogni campione dei sensori, separato dall'albero dei
/// widget.
///
/// **Perché esiste.** Prima ogni evento dell'assetto chiamava `setState` sulla
/// pagina intera: circa 1.188 elementi ricostruiti venticinque volte al secondo,
/// compresi la barra dei comandi, la card e il mirino, che non si muovono. E
/// dentro `build` giravano anche la proiezione di 1.200 cime e il layout
/// anti-collisione delle etichette, cioè lavoro pesante nel punto del
/// fotogramma in cui costa di più.
///
/// Un `Listenable` passato a `CustomPaint` come `repaint:` chiama direttamente
/// `markNeedsPaint`: salta `build` **e** `layout`. Da qui la regola di questa
/// classe — è un contenitore mutato sul posto, non un valore immutabile
/// riallocato a ogni fotogramma: allocare trenta oggetti venticinque volte al
/// secondo sarebbe un altro modo di sprecare lo stesso tempo.
///
/// Per la stessa ragione non è un `ValueNotifier`: la semantica di `==`
/// qui sarebbe sbagliata, perché l'oggetto è sempre lo stesso e va notificato
/// comunque.
class ArFrame extends ChangeNotifier {
  /// Orientamento della fotocamera, già corretto dall'allineamento manuale.
  /// `null` finché i sensori non hanno risposto.
  CameraBasis? basis;

  /// Campo visivo effettivo dello schermo, in gradi.
  double horizontalFovDeg = 60;
  double verticalFovDeg = 80;

  double zoom = 1;

  Size viewport = Size.zero;

  /// Le cime nel cono, già proiettate e ordinate per centratura.
  List<ProjectedPeak> projected = const [];

  /// Dove finiscono le etichette dopo l'anti-collisione. Sottoinsieme di
  /// [projected]: le cime che non trovano posto restano solo come punto.
  List<PinLayout> layouts = const [];

  /// La cima più centrata, quella che l'utente sta inquadrando.
  String? centeredId;

  /// La cima cercata per nome, se ce n'è una. È il bersaglio verso cui girarsi.
  MountainPeak? target;

  /// Di quanto e da che parte girarsi per averla davanti. Positivo = a destra.
  double targetTurnDeg = 0;

  double targetDistanceM = 0;

  /// Dove cade sullo schermo, se è già nell'inquadratura. `null` = va cercata
  /// girandosi, ed è il caso per cui esiste la funzione.
  ProjectedPeak? targetProjected;

  /// Da chiamare dopo aver aggiornato i campi. Un solo punto di notifica, così
  /// non si finisce a notificare tre volte per fotogramma.
  void commit() => notifyListeners();
}

/// Posizione di un punto e della sua etichetta sullo schermo.
class PinLayout {
  final ProjectedPeak peak;
  final double dotX;
  final double dotY;

  /// Ancoraggio dell'etichetta: è il punto attorno a cui il testo ruota, non il
  /// suo centro.
  final double labelX;
  final double labelY;

  const PinLayout({
    required this.peak,
    required this.dotX,
    required this.dotY,
    required this.labelX,
    required this.labelY,
  });
}
