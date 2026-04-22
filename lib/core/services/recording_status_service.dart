import 'package:flutter/foundation.dart';

/// Stato macro della registrazione, condiviso tra RecordPage e navigation bar.
///
/// Il [TrackingBloc] della RecordPage è la sorgente di verità operativa
/// (GPS, punti, metriche); questo servizio è un **mirror leggero** dello
/// status per widget fuori scope (es. il `_RecordButton` nella navbar).
enum RecordingStatusSnapshot { idle, recording, paused }

/// Singleton che espone lo stato di registrazione corrente come
/// [ChangeNotifier], così widget a scope ampio (bottom nav) possono
/// reagire a cambi di stato senza passare dal TrackingBloc.
class RecordingStatusService extends ChangeNotifier {
  RecordingStatusService._();
  static final RecordingStatusService _instance = RecordingStatusService._();
  factory RecordingStatusService() => _instance;

  RecordingStatusSnapshot _status = RecordingStatusSnapshot.idle;

  RecordingStatusSnapshot get status => _status;
  bool get isIdle => _status == RecordingStatusSnapshot.idle;
  bool get isRecording => _status == RecordingStatusSnapshot.recording;
  bool get isPaused => _status == RecordingStatusSnapshot.paused;

  void setStatus(RecordingStatusSnapshot s) {
    if (_status == s) return;
    _status = s;
    notifyListeners();
  }

  void markIdle() => setStatus(RecordingStatusSnapshot.idle);
  void markRecording() => setStatus(RecordingStatusSnapshot.recording);
  void markPaused() => setStatus(RecordingStatusSnapshot.paused);
}
