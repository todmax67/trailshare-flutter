import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../services/owner_pro_status_cache.dart';
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

/// Colore accent da usare nelle viste interne al gruppo.
///
/// Sprint B (2026-05-10): il branding custom è ora gated dietro lo stato
/// **Consumer Pro dell'OWNER del gruppo** (non più dietro il legacy
/// `isBusinessGroup`). Quando l'owner downgrade da Pro, il branding
/// sparisce automaticamente al successivo render.
///
/// Comportamento:
/// - cache hit (Pro=true) E brandColor presente → ritorna brandColor
/// - cache hit (Pro=false) o cache miss → arancio TrailShare default
/// - cache miss = primo render: il chiamante deve aver fatto un
///   pre-fetch via [OwnerProStatusCache.primeOwners] o
///   [isOwnerPro] await per evitare flicker
Color groupAccentColor(Group? group) {
  if (group == null) return AppColors.primary;
  final v = group.brandColor;
  if (v == null) return AppColors.primary;
  // Branding visibile se il gruppo è "Pro-equivalent". Vedi
  // Group.hasCustomLogo per la lista dei path.
  if (group.isBusinessGroup || group.isLinkedToBusiness) return Color(v);
  final ownerPro =
      OwnerProStatusCache().isOwnerProCached(group.createdBy);
  if (ownerPro == true) return Color(v);
  return AppColors.primary;
}

/// `true` se il gruppo deve mostrare il logo custom (avatarUrl).
/// Gating: owner Consumer Pro OR override admin `isBusinessGroup=true`.
bool groupShowsCustomLogo(Group group) {
  if (group.avatarUrl == null || group.avatarUrl!.isEmpty) return false;
  if (group.isBusinessGroup || group.isLinkedToBusiness) return true;
  return OwnerProStatusCache().isOwnerProCached(group.createdBy) == true;
}

/// `true` se il gruppo deve mostrare la cover custom (coverUrl).
bool groupShowsCustomCover(Group group) {
  if (group.coverUrl == null || group.coverUrl!.isEmpty) return false;
  if (group.isBusinessGroup || group.isLinkedToBusiness) return true;
  return OwnerProStatusCache().isOwnerProCached(group.createdBy) == true;
}
