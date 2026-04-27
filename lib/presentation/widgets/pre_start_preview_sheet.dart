import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/extensions/l10n_extension.dart';
import '../../core/extensions/theme_colors_extension.dart';
import '../../core/utils/eta_estimator.dart';
import '../../data/models/recording_reference.dart';
import '../../data/models/track.dart';
import 'stat_number.dart';

/// Sheet di anteprima pre-partenza visualizzata in modalità guidata
/// ([RecordPage] con `reference != null`) prima dell'avvio della
/// registrazione.
///
/// Mostra all'utente:
/// - nome del percorso
/// - distanza totale
/// - dislivello positivo
/// - ETA stimato (Naismith-style, vedi [EtaEstimator])
///
/// e un pulsante grande "Inizia" che chiama [onStart], oppure il chevron
/// indietro che chiama [onCancel].
///
/// È pensato per essere annegato come overlay [Positioned] nello Stack di
/// RecordPage in basso, sopra la mappa, finché lo stato è "preview".
class PreStartPreviewSheet extends StatelessWidget {
  final RecordingReference reference;
  final ActivityType activityType;
  final VoidCallback onStart;
  final VoidCallback onCancel;

  /// Stato del toggle Lifeline. Quando l'utente tappa il toggle viene
  /// chiamato [onLifelineToggle]. Se [hasLifelineContacts] è false il
  /// toggle è in stato disabilitato e mostra una CTA per impostare i
  /// contatti.
  final bool lifelineEnabled;
  final bool hasLifelineContacts;
  final int contactsCount;
  final VoidCallback? onLifelineToggle;
  final VoidCallback? onLifelineSetup;

  const PreStartPreviewSheet({
    super.key,
    required this.reference,
    required this.activityType,
    required this.onStart,
    required this.onCancel,
    this.lifelineEnabled = false,
    this.hasLifelineContacts = false,
    this.contactsCount = 0,
    this.onLifelineToggle,
    this.onLifelineSetup,
  });

  @override
  Widget build(BuildContext context) {
    final distance = reference.totalDistance ?? 0;
    final elevation = reference.totalElevationGain ?? 0;

    // Se la fonte è il planner e ha già una stima durata da ORS, preferiamola.
    final eta = (reference.estimatedDuration != null &&
            reference.estimatedDuration! > 0)
        ? Duration(seconds: reference.estimatedDuration!.round())
        : EtaEstimator.estimate(
            distanceMeters: distance,
            elevationGainMeters: elevation,
            activityType: activityType,
          );

    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(context).padding.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.themedBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Header con icona attività + nome
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    activityType.icon,
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.preStartReadyToGo,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        reference.name,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  color: context.textSecondary,
                  tooltip: context.l10n.cancel,
                  onPressed: onCancel,
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Stats grid: distanza · D+ · ETA
            Row(
              children: [
                Expanded(
                  child: _StatCell(
                    icon: Icons.straighten,
                    color: AppColors.primary,
                    label: context.l10n.preStartDistance,
                    value: _formatDistanceKm(distance),
                    unit: 'km',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCell(
                    icon: Icons.trending_up,
                    color: AppColors.success,
                    label: context.l10n.preStartElevation,
                    value: elevation.toStringAsFixed(0),
                    unit: 'm',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCell(
                    icon: Icons.schedule,
                    color: const Color(0xFFE07B4C),
                    label: context.l10n.preStartEta,
                    value: EtaEstimator.formatCompact(eta),
                    unit: '',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Toggle Lifeline: visibile sempre. Se l'utente non ha
            // contatti la riga porta direttamente al setup.
            _buildLifelineRow(context),
            const SizedBox(height: 14),

            // Pulsante Inizia (full-width primario)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.fiber_manual_record),
                label: Text(
                  context.l10n.preStartStartButton,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Hint sull'ETA: ricordiamo che è una stima
            Text(
              context.l10n.preStartEtaDisclaimer,
              style: TextStyle(
                fontSize: 11,
                color: context.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLifelineRow(BuildContext context) {
    if (!hasLifelineContacts) {
      // Stato "non configurato": mostra CTA per impostare i contatti.
      return InkWell(
        onTap: onLifelineSetup,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.info.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.info.withValues(alpha: 0.25),
              style: BorderStyle.solid,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.shield_outlined,
                  size: 20, color: AppColors.info),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.preStartLifelineLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.preStartLifelineNoContacts,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 18, color: AppColors.info),
            ],
          ),
        ),
      );
    }

    final on = lifelineEnabled;
    return InkWell(
      onTap: onLifelineToggle,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: on
              ? AppColors.info.withValues(alpha: 0.14)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: on
                ? AppColors.info
                : AppColors.info.withValues(alpha: 0.30),
            width: on ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              on ? Icons.shield : Icons.shield_outlined,
              size: 20,
              color: AppColors.info,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.preStartLifelineLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    on
                        ? context.l10n.preStartLifelineOn(contactsCount)
                        : context.l10n.preStartLifelineOff,
                    style: TextStyle(
                      fontSize: 11,
                      color: on ? AppColors.info : context.textSecondary,
                      fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: on,
              onChanged: (_) => onLifelineToggle?.call(),
              activeThumbColor: AppColors.info,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDistanceKm(double meters) {
    if (meters <= 0) return '0';
    final km = meters / 1000;
    return km < 10 ? km.toStringAsFixed(1) : km.toStringAsFixed(0);
  }
}

class _StatCell extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String unit;

  const _StatCell({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 6),
          StatNumber.medium(
            value,
            unit: unit.isEmpty ? null : unit,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: context.textMuted,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
