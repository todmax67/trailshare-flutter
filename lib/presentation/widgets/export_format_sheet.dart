import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/extensions/l10n_extension.dart';
import '../../core/services/track_export_service.dart';

/// Bottom sheet che permette all'utente di scegliere in quale formato
/// esportare una traccia (GPX, TCX, KML, FIT).
///
/// Ritorna il [ExportFormat] scelto o `null` se l'utente chiude.
class ExportFormatSheet {
  static Future<ExportFormat?> show(BuildContext context) {
    return showModalBottomSheet<ExportFormat>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grabber
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16, top: 8),
                decoration: BoxDecoration(
                  color: AppColors.textMuted.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.exportFormatTitle,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            context.l10n.exportFormatSubtitle,
                            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _FormatTile(
                format: ExportFormat.gpx,
                icon: Icons.map_outlined,
                description: context.l10n.exportGpxDescription,
              ),
              _FormatTile(
                format: ExportFormat.tcx,
                icon: Icons.fitness_center,
                description: context.l10n.exportTcxDescription,
              ),
              _FormatTile(
                format: ExportFormat.fit,
                icon: Icons.watch,
                description: context.l10n.exportFitDescription,
              ),
              _FormatTile(
                format: ExportFormat.kml,
                icon: Icons.public,
                description: context.l10n.exportKmlDescription,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormatTile extends StatelessWidget {
  final ExportFormat format;
  final IconData icon;
  final String description;

  const _FormatTile({
    required this.format,
    required this.icon,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppColors.primary),
      ),
      title: Text(
        format.displayName,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: Text(
        description,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.pop(context, format),
    );
  }
}
