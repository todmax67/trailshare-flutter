import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/theme_colors_extension.dart';
import '../../../data/models/visible_peak.dart';
import 'panorama_page.dart';

/// L'elenco delle cime che si vedono da qui, in giro d'orizzonte.
///
/// È la funzione che il concorrente ha e noi no, ed è anche la più economica di
/// tutte: il calcolo esiste già, mancava solo un posto dove leggerlo. Serve a
/// tre cose che il mirino non sa fare — sapere cosa c'è **alle spalle** senza
/// girarsi, leggere i nomi **senza tenere il telefono alzato**, e ritrovare una
/// cima quando la luce è finita.
///
/// È anche la risposta accessibile che le etichette disegnate non possono più
/// dare: qui i nomi sono testo vero, leggibile da uno screen reader.
class VisiblePeaksSheet extends StatelessWidget {
  final List<VisiblePeak> peaks;

  /// Dove punta la fotocamera adesso, per evidenziare la fetta inquadrata.
  /// `null` se i sensori non hanno ancora risposto.
  final double? currentAzimuthDeg;

  const VisiblePeaksSheet({
    super.key,
    required this.peaks,
    this.currentAzimuthDeg,
  });

  static const _settori = <(double, double, String)>[
    (337.5, 22.5, 'Nord'),
    (22.5, 67.5, 'Nordest'),
    (67.5, 112.5, 'Est'),
    (112.5, 157.5, 'Sudest'),
    (157.5, 202.5, 'Sud'),
    (202.5, 247.5, 'Sudovest'),
    (247.5, 292.5, 'Ovest'),
    (292.5, 337.5, 'Nordovest'),
  ];

  static bool _inSettore(double az, double da, double a) =>
      da > a ? (az >= da || az < a) : (az >= da && az < a);

  @override
  Widget build(BuildContext context) {
    // In giro d'orizzonte, non per distanza né per quota: è l'ordine in cui si
    // guardano davvero le montagne, e rende l'elenco una mappa mentale invece
    // di una classifica.
    final ordinate = [...peaks]
      ..sort((a, b) => a.azimuthDeg.compareTo(b.azimuthDeg));

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.themedBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Row(
              children: [
                Icon(Icons.list_alt, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cime visibili da qui',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary,
                        ),
                      ),
                      Text(
                        '${peaks.length} in tutto il giro d\'orizzonte',
                        style: TextStyle(
                            fontSize: 12, color: context.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (ordinate.isEmpty)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                'Nessuna cima riconosciuta da questa posizione.',
                style: TextStyle(color: context.textMuted),
              ),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 20),
                children: [
                  for (final (da, a, nome) in _settori) ...[
                    if (ordinate.any((p) => _inSettore(p.azimuthDeg, da, a)))
                      _Intestazione(
                        nome: nome,
                        // La fetta che si sta inquadrando si evidenzia: fa da
                        // ponte fra l'elenco e quello che si ha davanti.
                        attiva: currentAzimuthDeg != null &&
                            _inSettore(currentAzimuthDeg!, da, a),
                      ),
                    for (final p in ordinate)
                      if (_inSettore(p.azimuthDeg, da, a)) _Riga(peak: p),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Intestazione extends StatelessWidget {
  final String nome;
  final bool attiva;
  const _Intestazione({required this.nome, required this.attiva});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Row(
        children: [
          Text(
            nome.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: attiva ? AppColors.primary : context.textSecondary,
            ),
          ),
          if (attiva) ...[
            const SizedBox(width: 8),
            Icon(Icons.center_focus_strong,
                size: 13, color: AppColors.primary),
            const SizedBox(width: 4),
            Text(
              'stai guardando qui',
              style: TextStyle(fontSize: 11, color: AppColors.primary),
            ),
          ],
        ],
      ),
    );
  }
}

class _Riga extends StatelessWidget {
  final VisiblePeak peak;
  const _Riga({required this.peak});

  String get _distanza {
    final km = peak.distanceMeters / 1000;
    return km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';
  }

  @override
  Widget build(BuildContext context) {
    final quota = peak.peak.elevation;
    final dettagli = <String>[
      if (quota != null) '${quota.round()} m',
      _distanza,
      '${peak.azimuthDeg.round()}°',
    ];

    return ListTile(
      dense: true,
      leading: Icon(
        peak.peak.type == 'volcano' ? Icons.volcano : Icons.terrain,
        size: 20,
        color: peak.peak.type == 'volcano'
            ? AppColors.danger
            : AppColors.primary,
      ),
      title: Text(
        peak.peak.name,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: context.textPrimary,
        ),
      ),
      subtitle: Row(
        children: [
          Text(
            dettagli.join(' · '),
            style: TextStyle(fontSize: 12, color: context.textMuted),
          ),
          // L'incertezza si dice, non si nasconde: quella cima la mostriamo
          // perché non possiamo dimostrare che sia nascosta, il che è diverso
          // dall'aver dimostrato che si vede.
          if (peak.uncertain) ...[
            const SizedBox(width: 6),
            Icon(Icons.help_outline, size: 13, color: context.textMuted),
          ],
        ],
      ),
      trailing: Icon(Icons.panorama_horizontal_outlined,
          size: 18, color: context.textMuted),
      onTap: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PanoramaPage.fromPeak(peak.peak),
          ),
        );
      },
    );
  }
}
