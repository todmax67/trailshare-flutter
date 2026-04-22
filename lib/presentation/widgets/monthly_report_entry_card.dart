import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/extensions/l10n_extension.dart';
import '../../core/extensions/theme_colors_extension.dart';
import '../pages/monthly_report/monthly_report_page.dart';

/// Tile compatta nella Dashboard che invita l'utente a vedere il report
/// mensile ("Il tuo mese di aprile").
///
/// Al tap apre [MonthlyReportPage]. Si nasconde in versione discreta se
/// il mese è appena iniziato e non ci sono ancora tracce (evita noise).
class MonthlyReportEntryCard extends StatelessWidget {
  const MonthlyReportEntryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final now = DateTime.now();
    final monthName = DateFormat.MMMM(locale).format(now);
    final monthCap = monthName.isNotEmpty
        ? '${monthName[0].toUpperCase()}${monthName.substring(1)}'
        : monthName;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MonthlyReportPage()),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.themedBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.insert_chart_outlined,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${context.l10n.monthlyReportEntryTitle} · $monthCap',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.l10n.monthlyReportEntrySubtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: context.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
