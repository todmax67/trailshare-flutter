import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Implementazione mobile/desktop del CSV export: scrive un file
/// temporaneo e lo passa al sistema di condivisione (share sheet).
Future<void> doExportCsv(String csv, String filename) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsString(csv);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'text/csv', name: filename)],
      subject: filename,
    ),
  );
}
