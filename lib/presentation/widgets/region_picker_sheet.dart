import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/italian_regions.dart';
import '../../core/extensions/l10n_extension.dart';
import '../../core/extensions/theme_colors_extension.dart';
import '../../core/services/user_region_service.dart';
import 'app_snackbar.dart';

/// Modal bottom sheet che mostra l'elenco delle regioni italiane e
/// permette di selezionarne una. Salva su Firestore via [UserRegionService].
///
/// Usage:
/// ```dart
/// final selected = await showRegionPickerSheet(context);
/// if (selected != null) { ... }
/// ```
Future<ItalianRegion?> showRegionPickerSheet(
  BuildContext context, {
  String? currentCode,
}) async {
  return showModalBottomSheet<ItalianRegion>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _RegionPickerSheet(currentCode: currentCode),
  );
}

class _RegionPickerSheet extends StatefulWidget {
  final String? currentCode;

  const _RegionPickerSheet({this.currentCode});

  @override
  State<_RegionPickerSheet> createState() => _RegionPickerSheetState();
}

class _RegionPickerSheetState extends State<_RegionPickerSheet> {
  bool _saving = false;

  Future<void> _select(ItalianRegion region) async {
    if (_saving) return;
    setState(() => _saving = true);
    final ok = await UserRegionService().setRegion(region.code);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, region);
    } else {
      setState(() => _saving = false);
      AppSnackBar.error(context, context.l10n.regionPickerSaveError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final height = MediaQuery.of(context).size.height * 0.75;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: height),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.themedBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.regionPickerTitle,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.regionPickerSubtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: ItalianRegions.all.length,
                separatorBuilder: (_, i) => const SizedBox(height: 2),
                itemBuilder: (_, i) {
                  final region = ItalianRegions.all[i];
                  final isSelected = region.code == widget.currentCode;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: _saving ? null : () => _select(region),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary.withValues(alpha: 0.08)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Text(
                              region.flag,
                              style: const TextStyle(fontSize: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                region.displayName(locale),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: context.textPrimary,
                                ),
                              ),
                            ),
                            if (isSelected)
                              Icon(
                                Icons.check_circle,
                                color: AppColors.primary,
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
