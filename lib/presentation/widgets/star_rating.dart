import 'package:flutter/material.dart';

/// Widget riusabile per mostrare o selezionare un rating a 5 stelle.
///
/// Due modalità:
/// - **Display** (readOnly=true): mostra stelle piene/mezze/vuote per un [value] double
/// - **Input** (readOnly=false): 5 stelle tap-abili con callback [onChanged]
///
/// ```dart
/// // Display
/// StarRating(value: 4.3, size: 18, readOnly: true)
///
/// // Input
/// StarRating(
///   value: _rating.toDouble(),
///   onChanged: (v) => setState(() => _rating = v),
/// )
/// ```
class StarRating extends StatelessWidget {
  final double value;
  final double size;
  final Color color;
  final Color unselectedColor;
  final bool readOnly;
  final ValueChanged<int>? onChanged;

  const StarRating({
    super.key,
    required this.value,
    this.size = 24,
    this.color = Colors.amber,
    this.unselectedColor = Colors.grey,
    this.readOnly = true,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starValue = index + 1;
        final IconData icon;
        if (value >= starValue) {
          icon = Icons.star;
        } else if (value >= starValue - 0.5) {
          icon = Icons.star_half;
        } else {
          icon = Icons.star_border;
        }

        final starColor = value >= starValue - 0.5 ? color : unselectedColor;

        if (readOnly) {
          return Icon(icon, size: size, color: starColor);
        }
        return IconButton(
          onPressed: () => onChanged?.call(starValue),
          icon: Icon(icon, size: size, color: starColor),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(),
          splashRadius: size * 0.8,
          tooltip: '$starValue',
        );
      }),
    );
  }
}
