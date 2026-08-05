import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Chiude la fotocamera senza far esplodere l'uscita dalla schermata.
///
/// Il crash che ha reso necessaria questa funzione (fatale, 2026-08-05, sul
/// mountain finder): `CameraController` viene assegnato al campo **prima** che
/// `initialize()` sia finito. Se in quella finestra si esce dalla pagina,
/// `dispose()` chiude un controller la cui superficie nativa non e' mai stata
/// creata; CameraX solleva `IllegalStateException` da
/// `releaseFlutterSurfaceTexture`, che arriva in Dart come `PlatformException`
/// non gestita.
///
/// La finestra e' breve ma reale, e si allarga sui dispositivi lenti ad
/// accendere il sensore — il crash e' arrivato da un Motorola.
///
/// ## Perche' non basta un try/catch
///
/// Perche' il problema e' l'ordine, non l'eccezione: si aspetta che
/// l'inizializzazione **finisca o fallisca** e solo dopo si chiude. Chiudere a
/// meta' e' esattamente la condizione che CameraX rifiuta. Il try/catch resta
/// come rete, per il caso in cui la chiusura fallisca comunque: a quel punto
/// si sta smontando la schermata, e non c'e' niente che l'utente possa fare
/// con quell'errore.
///
/// ## Perche' non si fa dentro `dispose()`
///
/// Perche' `State.dispose()` e' sincrono per contratto: dichiararlo `async` e
/// mettere un `await` prima di `super.dispose()` non fa aspettare il framework
/// — smonta il widget lo stesso, e nel frattempo si e' rotto il ciclo di vita.
/// Il modo corretto e' staccare il controller dal campo e chiuderlo fuori,
/// senza attendere:
///
/// ```dart
/// @override
/// void dispose() {
///   final camera = _camera;
///   final init = _cameraInit;
///   _camera = null;
///   unawaited(closeCameraSafely(camera, init));
///   super.dispose();
/// }
/// ```
Future<void> closeCameraSafely(
  CameraController? camera,
  Future<void>? initialization,
) async {
  if (camera == null) return;

  // Se l'inizializzazione e' ancora in volo si aspetta il suo esito. Un
  // fallimento qui non interessa: serve solo sapere che non e' piu' in corso.
  if (initialization != null) {
    try {
      await initialization;
    } catch (_) {
      // Gia' loggato da chi ha avviato la fotocamera.
    }
  }

  try {
    await camera.dispose();
  } catch (e) {
    debugPrint('[Camera] chiusura fallita: $e');
  }
}
