import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../../data/repositories/groups_repository.dart';

/// Palette guidata per il colore brand dei gruppi Business L1.
///
/// Curata per funzionare con tema light/dark senza problemi di
/// contrasto. Il primo elemento (Default) corrisponde all'arancio
/// TrailShare e di fatto significa "nessun colore custom".
class GroupBrandPalette {
  static const List<GroupBrandSwatch> swatches = [
    GroupBrandSwatch('Arancio TrailShare', AppColors.primary),
    GroupBrandSwatch('Verde foresta', Color(0xFF2E7D32)),
    GroupBrandSwatch('Blu oceano', Color(0xFF1565C0)),
    GroupBrandSwatch('Teal montagna', Color(0xFF00838F)),
    GroupBrandSwatch('Ardesia', Color(0xFF455A64)),
    GroupBrandSwatch('Rosso tramonto', Color(0xFFC62828)),
    GroupBrandSwatch('Viola lavanda', Color(0xFF6A1B9A)),
    GroupBrandSwatch('Rosa sport', Color(0xFFD81B60)),
    GroupBrandSwatch('Senape', Color(0xFFB28704)),
    GroupBrandSwatch('Bordeaux', Color(0xFF8E2A2A)),
    GroupBrandSwatch('Ciano', Color(0xFF0097A7)),
    GroupBrandSwatch('Antracite', Color(0xFF263238)),
  ];
}

class GroupBrandSwatch {
  final String label;
  final Color color;
  const GroupBrandSwatch(this.label, this.color);
}

/// Colore accent da usare nelle viste interne al gruppo. Restituisce il
/// brand color custom se il gruppo è Business e ha un valore impostato,
/// altrimenti l'arancio TrailShare di default.
Color groupAccentColor(Group? group) {
  if (group == null) return AppColors.primary;
  if (!group.isBusinessGroup) return AppColors.primary;
  final v = group.brandColor;
  if (v == null) return AppColors.primary;
  return Color(v);
}
