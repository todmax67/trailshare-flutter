// Conditional import: su web carica l'implementazione dart:html,
// su mobile il no-op stub. Questo evita errori di compilazione mobile
// quando i file web vengono inclusi staticamente nel grafo di
// `main.dart` (anche se a runtime non sono raggiunti).
//
// Pattern Flutter standard:
// https://docs.flutter.dev/platform-integration/web/initialization

export 'csv_downloader_io.dart'
    if (dart.library.html) 'csv_downloader_web.dart';
