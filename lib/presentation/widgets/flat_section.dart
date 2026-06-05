import 'package:flutter/material.dart';

/// Helper UI condivisi per il look "lista minimalista" del design system:
/// sezioni sullo stesso sfondo (salvia), senza cornice, separate da linee leggere.
///
/// Vedi `docs/design-system.md`. Nati nella pagina dettaglio trail, estratti qui
/// per applicarli in modo coerente a tutte le pagine dettaglio.

/// Avvolge una sezione perché sieda direttamente sullo sfondo (niente card):
/// rende trasparenti `Card`, `colorScheme.surface` e `outlineVariant`, così
/// anche i `Container` basati sui ruoli tema perdono fondo e cornice.
class SageSurface extends StatelessWidget {
  final Widget child;
  const SageSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        cardTheme: theme.cardTheme.copyWith(
          color: Colors.transparent,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            side: BorderSide.none,
          ),
        ),
        colorScheme: theme.colorScheme.copyWith(
          surface: Colors.transparent, // Container(surface) → sfondo pagina
          outlineVariant: Colors.transparent, // cornici sezioni → via
        ),
      ),
      child: child,
    );
  }
}

/// Linea leggera che separa le sezioni nella vista "a lista".
class SectionDivider extends StatelessWidget {
  const SectionDivider({super.key});

  @override
  Widget build(BuildContext context) => const Divider(
        height: 16,
        thickness: 1,
        color: Color(0xFFD6D9C5), // salvia leggermente più scuro dello sfondo
      );
}

/// Rende un contenuto basato su `Card` (es. mappa header) a tutta larghezza:
/// niente margine, niente bordo, angoli vivi (edge-to-edge).
class FullBleedCard extends StatelessWidget {
  final Widget child;
  const FullBleedCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        cardTheme: theme.cardTheme.copyWith(
          margin: EdgeInsets.zero,
          color: Colors.transparent,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide.none,
          ),
        ),
      ),
      child: child,
    );
  }
}
