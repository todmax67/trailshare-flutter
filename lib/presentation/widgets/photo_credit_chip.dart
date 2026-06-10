import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Chip discreta col credito fotografico, mostrata sopra le hero photo
/// provenienti da Wikimedia Commons (pipeline di arricchimento schede).
/// Le licenze CC richiedono l'attribuzione visibile: autore + licenza,
/// tap → pagina del file su Commons.
///
/// `attribution` è la mappa `photoAttribution` del doc business:
/// {author, license, source, sourceUrl, file}.
class PhotoCreditChip extends StatelessWidget {
  final Map<String, dynamic> attribution;
  const PhotoCreditChip({super.key, required this.attribution});

  @override
  Widget build(BuildContext context) {
    final author = attribution['author']?.toString() ?? 'Wikimedia Commons';
    final license = attribution['license']?.toString() ?? 'CC';
    final sourceUrl = attribution['sourceUrl']?.toString();
    return GestureDetector(
      onTap: sourceUrl == null
          ? null
          : () => launchUrl(Uri.parse(sourceUrl),
              mode: LaunchMode.externalApplication),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'Foto: $author · $license',
          style: const TextStyle(color: Colors.white, fontSize: 9),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
