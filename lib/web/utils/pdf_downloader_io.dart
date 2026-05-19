import 'package:flutter/foundation.dart';

/// Stub mobile: il download PDF in-browser è una feature web-only.
/// Su mobile useremmo Printing.sharePdf nativo (TODO se serve in app
/// mobile). Per ora, lo chiamante (WebOutreachPdfPage) gira solo nella
/// shell web di TrailShare, quindi questa funzione non viene mai
/// chiamata su mobile.
void downloadPdfBytes(Uint8List bytes, String filename) {
  throw UnsupportedError(
    'downloadPdfBytes è disponibile solo sul web (dart:html).',
  );
}
