import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// Sezione del terreno attorno a un rifugio, disegnata al posto della foto
/// che non c'è.
///
/// Non è un ornamento: è il profilo vero del suolo su 6 km est-ovest, campionato
/// dal DEM europeo a 25 m (`scripts/business_terrain_profile.cjs`). Due rifugi
/// diversi danno due disegni diversi, e si legge se il posto sta in cresta o a
/// mezza costa. Il gradiente con l'emoji che c'era prima era identico per
/// tutti e 2.575.
///
/// I campioni arrivano quantizzati su 0-255 in base64: nel documento pesano
/// ~80 caratteri invece di sessanta interi, perché `getNearby` carica fino a
/// mille schede per volta e i punti annegati nei doc sono già costati una
/// saturazione della cache sulle tracce.
class TerrainProfile {
  /// Altezze normalizzate 0-1, da ovest a est.
  final List<double> samples;
  final int minM;
  final int maxM;
  final double widthKm;

  const TerrainProfile({
    required this.samples,
    required this.minM,
    required this.maxM,
    required this.widthKm,
  });

  int get relief => maxM - minM;

  static TerrainProfile? fromMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    final packed = m['p']?.toString();
    if (packed == null || packed.isEmpty) return null;
    final minM = (m['minM'] as num?)?.toInt();
    final maxM = (m['maxM'] as num?)?.toInt();
    if (minM == null || maxM == null) return null;
    try {
      final bytes = base64Decode(packed);
      if (bytes.length < 8) return null;
      return TerrainProfile(
        samples: [for (final b in bytes) b / 255.0],
        minM: minM,
        maxM: maxM,
        widthKm: (m['widthKm'] as num?)?.toDouble() ?? 6,
      );
    } on FormatException {
      return null; // dato malformato: si ricade sul fallback precedente
    }
  }
}

/// Copertina generata per una scheda senza foto.
///
/// [name] va passato solo dove il nome non compare già accanto: nella pagina
/// del rifugio sta subito sotto l'immagine, e ripeterlo dentro è rumore.
/// [compact] è per le miniature in lista, dove ci sta solo la quota.
class TerrainCover extends StatelessWidget {
  final TerrainProfile profile;
  final String? name;
  final int? elevationM;
  final String? subtitle;
  final bool compact;

  const TerrainCover({
    super.key,
    required this.profile,
    this.name,
    this.elevationM,
    this.subtitle,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final quota = elevationM ?? profile.maxM;
    return Container(
      color: const Color(0xFF0F2A22),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _TerrainPainter(profile)),
          if (!compact)
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (name != null && name!.isNotEmpty) ...[
                    Text(
                      name!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFE1F5EE),
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    [
                      '$quota m',
                      if (subtitle != null && subtitle!.isNotEmpty) subtitle!,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF9FE1CB),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          if (compact)
            Positioned(
              left: 8,
              bottom: 6,
              child: Text(
                '$quota m',
                style: const TextStyle(
                  color: Color(0xFF9FE1CB),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TerrainPainter extends CustomPainter {
  final TerrainProfile profile;
  const _TerrainPainter(this.profile);

  static const _fill = Color(0xFF164034);
  static const _line = Color(0xFF5DCAA5);
  static const _marker = Color(0xFFE1F5EE);

  @override
  void paint(Canvas canvas, Size size) {
    final s = profile.samples;
    if (s.length < 2) return;

    // Il terreno occupa la fascia centrale: sopra resta cielo, sotto lo spazio
    // per nome e quota, che altrimenti finirebbero sulla montagna.
    final topPad = size.height * 0.20;
    final bottomPad = size.height * 0.28;
    final usable = size.height - topPad - bottomPad;
    final dx = size.width / (s.length - 1);

    Offset pointAt(int i) =>
        Offset(dx * i, topPad + usable * (1 - s[i]));

    final line = ui.Path()..moveTo(0, pointAt(0).dy);
    for (var i = 1; i < s.length; i++) {
      final p = pointAt(i);
      line.lineTo(p.dx, p.dy);
    }

    final area = ui.Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(area, Paint()..color = _fill);
    canvas.drawPath(
      line,
      Paint()
        ..color = _line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );

    // Il rifugio sta al centro della sezione, per costruzione.
    final mid = pointAt((s.length / 2).floor());
    canvas.drawLine(
      Offset(mid.dx, mid.dy),
      Offset(mid.dx, size.height),
      Paint()
        ..color = _line.withValues(alpha: 0.35)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(mid, 4.5, Paint()..color = _marker);
  }

  @override
  bool shouldRepaint(covariant _TerrainPainter old) =>
      !identical(old.profile, profile);
}

/// Il ripiego di sempre, per le schede che un profilo non ce l'hanno: fuori
/// dalla copertura del DEM europeo, oppure in pianura dove non c'è rilievo
/// da disegnare.
class BusinessCoverFallback extends StatelessWidget {
  final String icon;
  const BusinessCoverFallback({super.key, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.85),
            AppColors.primaryDark.withValues(alpha: 0.85),
          ],
        ),
      ),
      child: Center(child: Text(icon, style: const TextStyle(fontSize: 80))),
    );
  }
}
