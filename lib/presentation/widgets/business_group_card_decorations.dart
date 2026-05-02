import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/utils/group_brand.dart';
import '../../data/repositories/groups_repository.dart';

/// Banner cover 16:9 ridotto in altezza usato come "hero" della card
/// gruppo Business nelle liste. Renderizzato solo se il gruppo ha
/// caricato una cover.
class BusinessCoverHeader extends StatelessWidget {
  final Group group;

  /// Altezza fissa del banner. 110px è un compromesso tra impatto
  /// visivo e ingombro nella lista.
  static const double height = 110;

  const BusinessCoverHeader({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    if (!group.hasCustomCover) return const SizedBox.shrink();
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CachedNetworkImage(
        imageUrl: group.coverUrl!,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          color: groupAccentColor(group).withValues(alpha: 0.08),
        ),
        errorWidget: (_, __, ___) => Container(
          color: groupAccentColor(group).withValues(alpha: 0.08),
        ),
      ),
    );
  }
}

/// Pill "BUSINESS" colorata col brand del gruppo, da mostrare sotto
/// il nome nelle card lista. Sostituisce/affianca la sola spunta
/// `verified` per dare risalto extra ai gruppi a pagamento.
class BusinessPill extends StatelessWidget {
  final Group group;

  const BusinessPill({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    if (!group.isBusinessGroup) return const SizedBox.shrink();
    final accent = groupAccentColor(group);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 1),
      ),
      child: Text(
        'BUSINESS',
        style: TextStyle(
          color: accent,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

/// Shape per la Card del gruppo: i Business hanno bordo accent visibile,
/// i normali restano col bordo neutro Material di default.
RoundedRectangleBorder businessCardShape(Group group) {
  if (!group.isBusinessGroup) {
    return RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  }
  final accent = groupAccentColor(group);
  return RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
    side: BorderSide(
      color: accent.withValues(alpha: 0.55),
      width: 1.5,
    ),
  );
}

/// Colore di sfondo card: i Business hanno una sfumatura accent
/// molto leggera che li distingue anche senza cover.
Color businessCardSurface(BuildContext context, Group group) {
  if (!group.isBusinessGroup) return Theme.of(context).cardColor;
  return Color.alphaBlend(
    groupAccentColor(group).withValues(alpha: 0.04),
    Theme.of(context).cardColor,
  );
}

