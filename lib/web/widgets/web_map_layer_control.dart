import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/map_styles.dart';
import '../../core/services/pro_gate_service.dart';

/// Stili mappa disponibili su **web**.
///
/// Filtra [mapStyles] escludendo gli stili che richiedono un
/// `tileColorFilter` (es. "Notte" CartoDB), perché su web non
/// applichiamo il filtro di schiaritura. Gli stili Pro sono inclusi
/// solo se l'utente è Pro (su web `ProGateService.isPro` riflette lo
/// stato Firestore — grandfathered inclusi).
List<MapStyle> webMapStyles() {
  final isPro = ProGateService().isPro;
  return mapStyles.where((s) {
    if (s.tileColorFilter != null) return false;
    if (s.isPro && !isPro) return false;
    return true;
  }).toList();
}

/// Costruisce il [TileLayer] flutter_map per uno [MapStyle].
TileLayer tileLayerForStyle(MapStyle style) {
  return TileLayer(
    urlTemplate: style.urlTemplate,
    subdomains: style.subdomains,
    userAgentPackageName: 'app.trailshare',
    maxNativeZoom: 19,
  );
}

/// Pulsante overlay (in alto a destra sulla mappa) per scegliere lo
/// stile/livello mappa. Mostra un menu con le opzioni disponibili e
/// un check sulla selezione corrente.
class WebMapLayerControl extends StatelessWidget {
  final MapStyle current;
  final ValueChanged<MapStyle> onChanged;

  const WebMapLayerControl({
    super.key,
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final styles = webMapStyles();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      elevation: 3,
      child: PopupMenuButton<MapStyle>(
        tooltip: 'Livello mappa',
        position: PopupMenuPosition.under,
        onSelected: onChanged,
        itemBuilder: (context) => [
          for (final s in styles)
            PopupMenuItem<MapStyle>(
              value: s,
              child: Row(
                children: [
                  Icon(s.icon,
                      size: 20,
                      color: s.name == current.name
                          ? AppColors.primary
                          : AppColors.textMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          s.name,
                          style: TextStyle(
                            fontWeight: s.name == current.name
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        if (s.subtitle != null)
                          Text(
                            s.subtitle!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (s.name == current.name)
                    const Icon(Icons.check,
                        size: 18, color: AppColors.primary),
                ],
              ),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(current.icon, size: 20, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                current.name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Icon(Icons.arrow_drop_down, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
