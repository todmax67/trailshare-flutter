// Stub mobile/desktop: il download CSV è una feature solo web (usa
// dart:html per generare Blob + anchor click). Su mobile non viene
// mai chiamato (le pagine che lo invocano sono dentro la shell web,
// dispatchata da `kIsWeb ? BusinessWebApp() : TrailShareApp()`).
// Lasciamo throw esplicito per detection in caso di chiamata errata.

void downloadCsv(String filename, String content, {String mime = 'text/csv'}) {
  throw UnsupportedError(
    'downloadCsv è disponibile solo sul web (dart:html).',
  );
}
