import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Implementazione mobile/desktop del CSV export: scrive un file
/// temporaneo e lo passa al sistema di condivisione (share sheet).
Future<void> doExportCsv(String csv, String filename) async {
  await doDownloadString(csv, filename, 'text/csv');
}

Future<void> doDownloadString(
  String content,
  String filename,
  String mime,
) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsString(content);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: mime, name: filename)],
      subject: filename,
    ),
  );
}
