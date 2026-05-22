import 'dart:html' as html;
import 'package:flutter/foundation.dart';

/// Scarica un PDF in-browser senza dipendere dal plugin `printing`
/// (che richiederebbe setup JS in web/index.html). Crea un Blob
/// application/pdf, un anchor `<a download>`, lo auto-clicca, e
/// rilascia la object URL.
void downloadPdfBytes(Uint8List bytes, String filename) {
  final blob = html.Blob([bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
