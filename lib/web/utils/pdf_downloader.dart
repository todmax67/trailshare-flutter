// Conditional import: su web carica l'implementazione dart:html
// (Blob + anchor click), su mobile uno stub no-op. Bypassa il
// plugin `printing` su web che richiederebbe setup JS aggiuntivo
// nel web/index.html.

export 'pdf_downloader_io.dart'
    if (dart.library.html) 'pdf_downloader_web.dart';
