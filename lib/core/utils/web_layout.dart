import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Wrapper che limita la larghezza del contenuto su web (desktop) e
/// resta no-op su mobile.
///
/// Le pagine condivise tra app mobile e dashboard B2B web (es.
/// GroupCustomizePage, GroupStatsPage) usano un body a tutta larghezza
/// che ha senso su mobile ma si stira male su monitor grandi. Wrapparlo
/// con [WebContentWrapper] lo centra dentro un [ConstrainedBox] solo
/// quando `kIsWeb`.
class WebContentWrapper extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const WebContentWrapper({
    super.key,
    required this.child,
    this.maxWidth = 800,
  });

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
