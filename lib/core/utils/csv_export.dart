/// Export CSV cross-platform.
///
/// - Su web: crea un Blob e triggera download via anchor element
/// - Su mobile/desktop: scrive file temporaneo e apre share sheet
///
/// Pattern di conditional import: la dipendenza specifica della
/// piattaforma viene risolta a compile time, evitando che `dart:html`
/// finisca nel build mobile e che `dart:io` finisca nel build web.
import 'csv_export_stub.dart'
    if (dart.library.html) 'csv_export_web.dart'
    if (dart.library.io) 'csv_export_io.dart';

/// Salva o condivide un CSV in base alla piattaforma.
Future<void> exportCsv(String csv, String filename) =>
    doExportCsv(csv, filename);

/// Helper per costruire una riga CSV correttamente quotata.
///
/// Regole RFC 4180: se un valore contiene virgola, newline o doppio
/// apice, deve essere racchiuso tra doppi apici, e i doppi apici
/// interni vengono raddoppiati ("a"b" diventa "a""b").
String csvRow(List<dynamic> values) {
  return values.map((v) {
    final s = v?.toString() ?? '';
    final needsQuoting = s.contains(',') ||
        s.contains('"') ||
        s.contains('\n') ||
        s.contains('\r');
    if (!needsQuoting) return s;
    return '"${s.replaceAll('"', '""')}"';
  }).join(',');
}
