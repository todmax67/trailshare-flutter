/// Stub di fallback per piattaforme non supportate. Non dovrebbe mai
/// essere effettivamente caricato (il pattern di conditional import
/// risolve a `csv_export_web.dart` su web e `csv_export_io.dart` su
/// mobile/desktop).
Future<void> doExportCsv(String csv, String filename) async {
  throw UnsupportedError('CSV export non supportato su questa piattaforma');
}
