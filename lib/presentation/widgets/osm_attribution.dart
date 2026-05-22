import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Widget attribuzione OpenStreetMap conforme a ODbL 1.0.
///
/// Da posizionare come `Positioned` (es. bottom-right) sopra una
/// FlutterMap. Tap apre la pagina ufficiale OSM con i copyright
/// contributors.
///
/// Usage:
/// ```dart
/// Stack(
///   children: [
///     FlutterMap(...),
///     Positioned(
///       bottom: 4, right: 4,
///       child: OsmAttribution(),
///     ),
///   ],
/// )
/// ```
class OsmAttribution extends StatelessWidget {
  /// Se true, usa testo bianco su sfondo nero semi-opaco
  /// (per mappe scure / fullscreen). Default: nero su sfondo chiaro.
  final bool darkBackground;

  const OsmAttribution({super.key, this.darkBackground = false});

  Future<void> _openCopyright() async {
    final uri = Uri.parse('https://www.openstreetmap.org/copyright');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = darkBackground
        ? Colors.black.withValues(alpha: 0.55)
        : Colors.white.withValues(alpha: 0.85);
    final fg = darkBackground ? Colors.white : Colors.black87;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openCopyright,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '© OpenStreetMap',
            style: TextStyle(
              fontSize: 9,
              color: fg,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
