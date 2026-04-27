import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../core/extensions/theme_colors_extension.dart';
import '../../../core/utils/mountain_projection.dart';
import '../../widgets/app_snackbar.dart';

/// Pagina che mostra la **foto annotata** prodotta da Photo Mode con sopra
/// tutte le cime identificate. L'utente può:
///
/// - vedere la lista completa delle cime presenti nello scatto
/// - condividere la foto annotata via share sheet di sistema (l'utente
///   può scegliere "Salva nelle foto", Whatsapp, Instagram, etc.)
/// - ri-scattare (torna indietro al viewfinder live)
class MountainPhotoResultPage extends StatefulWidget {
  /// PNG bytes dell'immagine annotata.
  final Uint8List annotatedImage;

  /// Lista di peak presenti nell'immagine.
  final List<ProjectedPeak> peaks;

  const MountainPhotoResultPage({
    super.key,
    required this.annotatedImage,
    required this.peaks,
  });

  @override
  State<MountainPhotoResultPage> createState() =>
      _MountainPhotoResultPageState();
}

class _MountainPhotoResultPageState extends State<MountainPhotoResultPage> {
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    // Cattura l10n prima dell'await per evitare context-async lint warning.
    final shareText = context.l10n.mfPhotoShareText(widget.peaks.length);
    final shareSubject = context.l10n.mfPhotoShareSubject;
    try {
      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/trailshare_peaks_$ts.png');
      await file.writeAsBytes(widget.annotatedImage);

      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: shareText,
          subject: shareSubject,
        ),
      );
      debugPrint('[MountainPhoto] share result: ${result.status}');
    } catch (e) {
      debugPrint('[MountainPhoto] share error: $e');
      if (mounted) {
        AppSnackBar.error(context, context.l10n.mfPhotoShareError);
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(context.l10n.mfPhotoResultTitle),
        actions: [
          if (_sharing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else
            IconButton(
              onPressed: _share,
              icon: const Icon(Icons.ios_share),
              tooltip: context.l10n.share,
            ),
        ],
      ),
      body: Column(
        children: [
          // Preview foto annotata, fit-cover dentro l'area available.
          Expanded(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: Image.memory(
                  widget.annotatedImage,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          // Card con lista cime + bottone share full-width
          Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: EdgeInsets.fromLTRB(
              16,
              14,
              16,
              16 + MediaQuery.of(context).padding.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.terrain, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.l10n
                            .mfPhotoIdentifiedCount(widget.peaks.length),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                if (widget.peaks.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final p in widget.peaks)
                            _PeakChip(projected: p),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _sharing ? null : _share,
                    icon: const Icon(Icons.ios_share),
                    label: Text(context.l10n.mfPhotoShareButton),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PeakChip extends StatelessWidget {
  final ProjectedPeak projected;

  const _PeakChip({required this.projected});

  @override
  Widget build(BuildContext context) {
    final isVolcano = projected.peak.type == 'volcano';
    final color = isVolcano ? AppColors.danger : AppColors.primary;
    final ele = projected.peak.elevation?.round();
    final dist = (projected.distanceMeters / 1000);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isVolcano ? Icons.local_fire_department : Icons.terrain,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              projected.peak.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (ele != null) ...[
            const SizedBox(width: 6),
            Text(
              '${ele}m',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
          const SizedBox(width: 4),
          Text(
            '· ${dist < 10 ? dist.toStringAsFixed(1) : dist.toStringAsFixed(0)}km',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.textMuted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
