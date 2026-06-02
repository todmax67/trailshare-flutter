import 'package:flutter/material.dart';

import '../../core/constants/map_styles.dart';
import '../../core/services/map_style_prefs.dart';
import '../../core/services/pro_gate_service.dart';
import 'paywall_sheet.dart';

/// Apre il bottom sheet di scelta stile mappa con gating Pro e restituisce
/// l'indice selezionato in [mapStyles], oppure `null` se l'utente annulla o
/// tocca uno stile Pro senza esserlo (in quel caso apre il PaywallSheet).
///
/// Persiste automaticamente la scelta in [MapStylePrefs] così lo stile è
/// condiviso tra tutte le interfacce mappa dell'app. È il punto unico di
/// verità per il picker: usato sia da [MapLayerButton] sia dalle pagine che
/// hanno un proprio affordance (AppBar icon, ecc.).
Future<int?> showMapStylePicker(BuildContext context, int currentIndex) async {
  final styles = mapStyles;
  final selected = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.8,
    ),
    builder: (ctx) => _MapStylePickerSheet(
      styles: styles,
      currentIndex: currentIndex,
    ),
  );
  if (selected != null && selected != currentIndex) {
    MapStylePrefs().setIndex(selected);
    return selected;
  }
  return null;
}

/// Bottone circolare per cambiare stile mappa.
///
/// Apre un bottom sheet con tutti gli stili disponibili. Quelli marcati
/// come Pro mostrano un badge; se l'utente non è Pro, al tap apre il
/// PaywallSheet invece di applicare lo stile.
///
/// ```dart
/// MapLayerButton(
///   currentIndex: _currentMapStyle,
///   onChanged: (i) => setState(() => _currentMapStyle = i),
/// )
/// ```
class MapLayerButton extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onChanged;

  const MapLayerButton({
    super.key,
    required this.currentIndex,
    required this.onChanged,
  });

  Future<void> _openPicker(BuildContext context) async {
    final selected = await showMapStylePicker(context, currentIndex);
    if (selected != null) {
      onChanged(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final styles = mapStyles;
    final style = styles[currentIndex.clamp(0, styles.length - 1)];

    return Tooltip(
      message: style.name,
      child: Material(
        color: Colors.white,
        elevation: 2,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openPicker(context),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(
              style.icon,
              size: 22,
              color: Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet che lista tutti gli stili mappa con badge Pro per
/// quelli premium. Restituisce l'indice scelto via `Navigator.pop`.
class _MapStylePickerSheet extends StatelessWidget {
  final List<MapStyle> styles;
  final int currentIndex;

  const _MapStylePickerSheet({
    required this.styles,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    final isPro = ProGateService().isPro;
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Stile mappa',
              style: theme.textTheme.titleLarge,
            ),
          ),
          // ListView dentro Flexible così la lista scrolla internamente
          // quando i 7 stili eccedono lo spazio disponibile.
          Flexible(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              shrinkWrap: true,
              itemCount: styles.length,
              itemBuilder: (ctx, i) {
                final style = styles[i];
                final isCurrent = i == currentIndex;
                final locked = style.isPro && !isPro;
                return _StyleTile(
                  style: style,
                  isCurrent: isCurrent,
                  locked: locked,
                  onTap: () async {
                    if (locked) {
                      // Chiudi prima il picker, poi apri il paywall
                      // (altrimenti si sovrappongono).
                      Navigator.of(context).pop();
                      await showPaywallSheet(
                        context,
                        trigger: PaywallTrigger.mapStylePro,
                      );
                    } else {
                      Navigator.of(context).pop(i);
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StyleTile extends StatelessWidget {
  final MapStyle style;
  final bool isCurrent;
  final bool locked;
  final VoidCallback onTap;

  const _StyleTile({
    required this.style,
    required this.isCurrent,
    required this.locked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Row(
          children: [
            // Icona stile
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isCurrent
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                style.icon,
                color: isCurrent
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            // Testo (nome + sottotitolo)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          style.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: isCurrent
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (style.isPro) ...[
                        const SizedBox(width: 8),
                        const _ProBadge(),
                      ],
                    ],
                  ),
                  if (style.subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        style.subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Icona stato a destra
            if (locked)
              Icon(
                Icons.lock_outline,
                color: colorScheme.onSurfaceVariant,
                size: 20,
              )
            else if (isCurrent)
              Icon(
                Icons.check_circle,
                color: colorScheme.primary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

class _ProBadge extends StatelessWidget {
  const _ProBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFE0712B), // primary orange
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'PRO',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
