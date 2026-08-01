import 'package:flutter/material.dart';

/// Ripiego per un'immagine che non si carica.
///
/// Nasce dal non-fatal `dart:ui .instantiateImageCodecWithSize` →
/// *Invalid image data*, comparso su 2.8.1–2.9.4: un file troncato o corrotto
/// che il decoder rifiuta. Senza `errorBuilder`, `Image.network` e
/// `Image.memory` rilanciano l'eccezione al framework, che finisce in
/// Crashlytics — mentre all'utente resta uno spazio vuoto senza spiegazione.
///
/// `CachedNetworkImage` non ha questo problema: gestisce il fallimento per
/// conto suo. Per questo il ripiego serve solo dove si usa `Image.*` diretto.
class BrokenImageBox extends StatelessWidget {
  /// Icona più piccola nelle miniature, dove quella standard riempirebbe
  /// tutto il riquadro.
  final bool compact;

  const BrokenImageBox({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.broken_image_outlined,
        size: compact ? 18 : 32,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
      ),
    );
  }
}
