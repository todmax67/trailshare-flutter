import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../models/discover_filters.dart';
import '../../../../core/extensions/theme_colors_extension.dart';

/// Bottom sheet modale per i filtri avanzati della pagina Scopri.
///
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   isScrollControlled: true,
///   builder: (_) => DiscoverFilterSheet(
///     initial: _filters,
///     onApply: (filters) => setState(() => _filters = filters),
///   ),
/// );
/// ```
class DiscoverFilterSheet extends StatefulWidget {
  final DiscoverFilters initial;
  final ValueChanged<DiscoverFilters> onApply;

  const DiscoverFilterSheet({
    super.key,
    required this.initial,
    required this.onApply,
  });

  @override
  State<DiscoverFilterSheet> createState() => _DiscoverFilterSheetState();
}

class _DiscoverFilterSheetState extends State<DiscoverFilterSheet> {
  late DiscoverFilters _filters;

  // Limiti degli slider
  static const _maxLengthKm = 30.0;
  static const _maxElevation = 2000.0;

  static const _difficultyOptions = [
    _DifficultyOption('t', 'Turistico', '🟢'),
    _DifficultyOption('e', 'Escursionistico', '🔵'),
    _DifficultyOption('ee', 'Esperti', '🟠'),
    _DifficultyOption('eea', 'Alpinistico', '🔴'),
  ];

  @override
  void initState() {
    super.initState();
    _filters = widget.initial;
  }

  void _toggleDifficulty(String code) {
    setState(() {
      final next = Set<String>.from(_filters.difficulties);
      if (!next.add(code)) next.remove(code);
      _filters = _filters.copyWith(difficulties: next);
    });
  }

  void _toggleCategory(ActivityCategory cat) {
    setState(() {
      final next = Set<ActivityCategory>.from(_filters.categories);
      if (!next.add(cat)) next.remove(cat);
      _filters = _filters.copyWith(categories: next);
    });
  }

  void _reset() {
    setState(() => _filters = const DiscoverFilters.empty());
  }

  void _apply() {
    widget.onApply(_filters);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Filtri',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton(
                    onPressed: _filters.isEmpty ? null : _reset,
                    child: const Text('Reset'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Body
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(20),
                children: [
                  _buildSectionTitle('Difficoltà'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _difficultyOptions.map((opt) {
                      final selected = _filters.difficulties.contains(opt.code);
                      return _FilterChip(
                        label: '${opt.emoji} ${opt.label}',
                        isSelected: selected,
                        onTap: () => _toggleDifficulty(opt.code),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 24),
                  _buildSectionTitle('Tipo attività'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ActivityCategory.values.map((cat) {
                      final selected = _filters.categories.contains(cat);
                      return _FilterChip(
                        label: cat.label,
                        icon: cat.icon,
                        isSelected: selected,
                        onTap: () => _toggleCategory(cat),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 24),
                  _buildSectionTitle('Lunghezza'),
                  _RangeSliderField(
                    value: _filters.lengthKm ?? const RangeValues(0, _maxLengthKm),
                    min: 0,
                    max: _maxLengthKm,
                    divisions: 30,
                    labelFormat: (v) => '${v.toStringAsFixed(0)} km',
                    onChanged: (values) {
                      setState(() {
                        final isFull = values.start == 0 && values.end == _maxLengthKm;
                        _filters = _filters.copyWith(
                          lengthKm: isFull ? null : values,
                          clearLengthKm: isFull,
                        );
                      });
                    },
                  ),

                  const SizedBox(height: 24),
                  _buildSectionTitle('Dislivello'),
                  _RangeSliderField(
                    value: _filters.elevation ?? const RangeValues(0, _maxElevation),
                    min: 0,
                    max: _maxElevation,
                    divisions: 20,
                    labelFormat: (v) => '${v.toStringAsFixed(0)} m',
                    onChanged: (values) {
                      setState(() {
                        final isFull = values.start == 0 && values.end == _maxElevation;
                        _filters = _filters.copyWith(
                          elevation: isFull ? null : values,
                          clearElevation: isFull,
                        );
                      });
                    },
                  ),

                  const SizedBox(height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Solo sentieri circolari'),
                    value: _filters.onlyCircular,
                    onChanged: (v) => setState(
                      () => _filters = _filters.copyWith(onlyCircular: v),
                    ),
                  ),

                  const SizedBox(height: 16),
                  _buildSectionTitle('Ordinamento'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<TrailSortBy>(
                    initialValue: _filters.sortBy,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: TrailSortBy.values
                        .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _filters = _filters.copyWith(sortBy: v));
                      }
                    },
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
            // Footer
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _apply,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Applica', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    );
  }
}

class _DifficultyOption {
  final String code;
  final String label;
  final String emoji;
  const _DifficultyOption(this.code, this.label, this.emoji);
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey.shade400,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : context.textSecondary,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : context.textPrimary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RangeSliderField extends StatelessWidget {
  final RangeValues value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) labelFormat;
  final ValueChanged<RangeValues> onChanged;

  const _RangeSliderField({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.labelFormat,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              labelFormat(value.start),
              style: TextStyle(fontSize: 12, color: context.textSecondary),
            ),
            Text(
              labelFormat(value.end),
              style: TextStyle(fontSize: 12, color: context.textSecondary),
            ),
          ],
        ),
        RangeSlider(
          values: value,
          min: min,
          max: max,
          divisions: divisions,
          labels: RangeLabels(labelFormat(value.start), labelFormat(value.end)),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
