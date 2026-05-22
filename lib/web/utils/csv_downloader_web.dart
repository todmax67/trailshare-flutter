import 'dart:html' as html;

/// Implementazione web del download CSV. Crea un Blob in memoria,
/// un anchor temporaneo `<a download>` che si auto-clicca, poi
/// revoca l'object URL. Funziona senza interazione del browser
/// (no popup) perché parte da un user gesture (il click del bottone
/// nel chiamante).
void downloadCsv(String filename, String content, {String mime = 'text/csv'}) {
  final blob = html.Blob([content], '$mime;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
