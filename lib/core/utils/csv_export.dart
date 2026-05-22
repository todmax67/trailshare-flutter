/// Export CSV cross-platform.
///
/// - Su web: crea un Blob e triggera download via anchor element
/// - Su mobile/desktop: scrive file temporaneo e apre share sheet
///
/// Pattern di conditional import: la dipendenza specifica della
/// piattaforma viene risolta a compile time, evitando che `dart:html`
/// finisca nel build mobile e che `dart:io` finisca nel build web.
library;
import 'dart:typed_data';

import 'csv_export_stub.dart'
    if (dart.library.html) 'csv_export_web.dart'
    if (dart.library.io) 'csv_export_io.dart';

/// Salva o condivide un CSV in base alla piattaforma.
Future<void> exportCsv(String csv, String filename) =>
    doExportCsv(csv, filename);

/// Download/share generico di un contenuto testuale (GPX, JSON, ecc).
/// Su web triggera download via Blob, su mobile salva temp e share sheet.
Future<void> downloadString(
  String content,
  String filename,
  String mime,
) =>
    doDownloadString(content, filename, mime);

/// Download/share generico di bytes binari (PNG, PDF, ZIP, ecc.).
/// - Su web: Blob + anchor download (immediato, no dialog)
/// - Su mobile: file temp + share sheet via share_plus
Future<void> downloadBytes(
  Uint8List bytes,
  String filename,
  String mime, {
  String? shareSubject,
  String? shareText,
}) =>
    doDownloadBytes(bytes, filename, mime,
        shareSubject: shareSubject, shareText: shareText);

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
