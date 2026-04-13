import 'package:flutter/material.dart';
import '../../core/constants/map_styles.dart';

/// Bottone circolare per ciclare tra gli stili mappa.
///
/// Mostra l'icona dello stile corrente e il nome in un tooltip.
/// Al tap cicla allo stile successivo.
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

  void _cycle() {
    onChanged((currentIndex + 1) % mapStyles.length);
  }

  @override
  Widget build(BuildContext context) {
    final style = mapStyles[currentIndex];

    return Tooltip(
      message: style.name,
      child: Material(
        color: Colors.white,
        elevation: 2,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _cycle,
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
