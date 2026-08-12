import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/theme_colors_extension.dart';
import '../../../core/services/peaks_dataset_service.dart';
import '../../../core/services/pro_gate_service.dart';
import '../../../core/services/terrain_tile_service.dart';
import '../../../core/services/viewshed_service.dart';
import '../../../data/models/mountain_peak.dart';
import '../../../data/models/visible_peak.dart';
import '../../../data/repositories/admin_repository.dart';

/// Il panorama a 360° visto **da un punto qualsiasi**, disegnato dal terreno.
///
/// È la risposta a una domanda che la fotocamera non può porre: *cosa vedrò
/// dalla vetta di quel monte?* Puntare il telefono richiede di essere già lì,
/// col bel tempo e di giorno. Il panorama disegnato si guarda dal divano la
/// sera prima, ed è anche l'unico modo in cui qualcuno può capire cosa fa
/// questa funzione **prima** di pagarla.
///
/// Non è una schermata nuova nel motore: usa lo stesso skyline e lo stesso
/// elenco di cime visibili dell'AR, con l'osservatore spostato altrove.
class PanoramaPage extends StatefulWidget {
  /// Da dove si guarda.
  final double observerLat;
  final double observerLng;

  /// Nome del punto di vista, per il titolo.
  final String viewpointName;

  const PanoramaPage({
    super.key,
    required this.observerLat,
    required this.observerLng,
    required this.viewpointName,
  });

  /// Comodità: il panorama visto da una cima.
  factory PanoramaPage.fromPeak(MountainPeak peak) => PanoramaPage(
        observerLat: peak.latitude,
        observerLng: peak.longitude,
        viewpointName: peak.name,
      );

  @override
  State<PanoramaPage> createState() => _PanoramaPageState();
}

class _PanoramaPageState extends State<PanoramaPage> {
  List<double> _skyline = const [];
  List<VisiblePeak> _peaks = const [];
  double? _observerElevation;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  Future<void> _compute() async {
    try {
      final ds = PeaksDatasetService();
      if (!ds.isLoaded) await ds.ensureLoaded();

      // Quota del punto di vista: serve prima delle cime, perché il criterio
      // di selezione delle candidate dipende da quanto una cima si alza
      // rispetto a chi guarda.
      final ground = await TerrainTileService().groundElevationAt(
        widget.observerLat,
        widget.observerLng,
      );

      final isPro = ProGateService().isPro;
      final isAdmin = await AdminRepository.isCurrentUserAdmin();
      final tier = (isPro || isAdmin) ? ViewshedTier.pro : ViewshedTier.free;

      final candidates = ds.findWithinRadius(
        widget.observerLat,
        widget.observerLng,
        radiusKm: tier.maxRadiusKm.toDouble(),
        observerElevationM: ground ?? 0,
      );

      final result = await ViewshedService().computeVisible(
        observerLat: widget.observerLat,
        observerLng: widget.observerLng,
        candidates: candidates,
        tier: tier,
        computeSkyline: true,
        // Il punto di vista non è dove si trova l'utente: senza questo, il
        // panorama butterebbe fuori dalla cache il risultato dell'AR.
        useCache: false,
      );

      if (!mounted) return;
      setState(() {
        _skyline = result.skylineAngles;
        _peaks = result.visible;
        _observerElevation = result.observerGroundElevationM ?? ground;
        _loading = false;
        if (result.status == ViewshedStatus.demUnavailable) {
          _error = context.l10nTerrainMissing;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.viewpointName,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            if (_observerElevation != null)
              Text(
                '${_observerElevation!.round()} m · ${_peaks.length} cime',
                style: TextStyle(fontSize: 12, color: context.textMuted),
              ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildPanorama(),
    );
  }

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 48, color: context.textMuted),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
            ],
          ),
        ),
      );

  Widget _buildPanorama() {
    if (_skyline.length < 8) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Terreno non disponibile per questo punto di vista.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.textMuted),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Quattro schermate per il giro completo: abbastanza da leggere i nomi
        // senza che il panorama diventi un nastro infinito da scorrere.
        final totalWidth = constraints.maxWidth * 4;
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: totalWidth,
                  height: constraints.maxHeight - 44,
                  child: CustomPaint(
                    painter: _PanoramaPainter(
                      skyline: _skyline,
                      peaks: _peaks,
                      terrainColor: AppColors.primary,
                      textColor: context.textPrimary,
                      mutedColor: context.textMuted,
                    ),
                  ),
                ),
              ),
            ),
            _buildLegend(),
          ],
        );
      },
    );
  }

  Widget _buildLegend() => SizedBox(
        height: 44,
        child: Center(
          child: Text(
            'Scorri per girare lo sguardo · N E S O',
            style: TextStyle(fontSize: 12, color: context.textMuted),
          ),
        ),
      );
}

/// Proiezione **cilindrica**: l'asse orizzontale è l'azimut, quello verticale
/// l'angolo di elevazione.
///
/// È una proiezione diversa da quella della fotocamera, e deve esserlo: una
/// camera vede un cono di sessanta gradi, qui se ne mostrano trecentosessanta.
/// Con la prospettiva rettilinea i bordi si stirerebbero all'infinito.
class _PanoramaPainter extends CustomPainter {
  final List<double> skyline;
  final List<VisiblePeak> peaks;
  final Color terrainColor;
  final Color textColor;
  final Color mutedColor;

  _PanoramaPainter({
    required this.skyline,
    required this.peaks,
    required this.terrainColor,
    required this.textColor,
    required this.mutedColor,
  });

  /// Fascia verticale mostrata, in gradi. Sotto l'orizzonte si lascia poco:
  /// serve a far capire dove cade, non a disegnare i propri piedi.
  static const double _topDeg = 42;
  static const double _bottomDeg = -18;

  double _xFor(double azDeg, double width) => azDeg / 360 * width;

  double _yFor(double elevDeg, double height) =>
      (_topDeg - elevDeg) / (_topDeg - _bottomDeg) * height;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final steps = skyline.length;

    // Cielo.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = const Color(0xFF9FC6E8).withValues(alpha: 0.25),
    );

    // Linea dell'orizzonte teorico (elevazione zero): dà la scala verticale.
    final horizonY = _yFor(0, h);
    canvas.drawLine(
      Offset(0, horizonY),
      Offset(w, horizonY),
      Paint()
        ..color = mutedColor.withValues(alpha: 0.35)
        ..strokeWidth = 1,
    );

    // Profilo del terreno, riempito fino in fondo.
    final path = Path();
    bool started = false;
    for (var i = 0; i < steps; i++) {
      final elev = skyline[i];
      if (elev.isNaN) {
        // Buco nel terreno: si chiude la figura e si riprende dopo. Meglio
        // un'interruzione visibile di una montagna inventata.
        if (started) {
          path.lineTo(_xFor(i * 360 / steps, w), h);
          started = false;
        }
        continue;
      }
      final x = _xFor(i * 360 / steps, w);
      final y = _yFor(elev.clamp(_bottomDeg, _topDeg), h);
      if (!started) {
        path.moveTo(x, h);
        path.lineTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    if (started) path.lineTo(w, h);
    path.close();

    canvas.drawPath(path, Paint()..color = terrainColor.withValues(alpha: 0.55));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = terrainColor,
    );

    _paintCompass(canvas, size);
    _paintPeaks(canvas, size);
  }

  /// Riferimenti cardinali: senza, un panorama a 360° è un nastro senza nord.
  void _paintCompass(Canvas canvas, Size size) {
    const marks = {0: 'N', 45: 'NE', 90: 'E', 135: 'SE', 180: 'S', 225: 'SO', 270: 'O', 315: 'NO'};
    for (final entry in marks.entries) {
      final x = _xFor(entry.key.toDouble(), size.width);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()..color = mutedColor.withValues(alpha: 0.18),
      );
      final tp = TextPainter(
        text: TextSpan(
          text: entry.value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: mutedColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + 4, size.height - 20));
    }
  }

  void _paintPeaks(Canvas canvas, Size size) {
    // Le più imponenti per prime: se due nomi si accavallano vince quella che
    // nel panorama si vede di più, non quella che capita prima nell'elenco.
    final ordered = [...peaks]
      ..sort((a, b) => b.elevationAngleDeg.compareTo(a.elevationAngleDeg));

    final placed = <Rect>[];
    for (final p in ordered) {
      final x = _xFor(p.azimuthDeg, size.width);
      final y = _yFor(
        p.elevationAngleDeg.clamp(_bottomDeg, _topDeg),
        size.height,
      );

      final label = '${p.peak.name}  ${p.peak.elevation?.round() ?? ''}'
          '${p.peak.elevation != null ? ' m' : ''}';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // Il testo sale in verticale dalla cima, come sulle carte panoramiche.
      const stem = 26.0;
      final labelRect = Rect.fromLTWH(x - 7, y - stem - tp.width, 16, tp.width);
      if (placed.any((r) => r.overlaps(labelRect.inflate(2)))) continue;
      placed.add(labelRect);

      canvas.drawLine(
        Offset(x, y),
        Offset(x, y - stem),
        Paint()
          ..color = mutedColor.withValues(alpha: 0.8)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(Offset(x, y), 3, Paint()..color = AppColors.warning);

      canvas.save();
      canvas.translate(x + 4, y - stem);
      canvas.rotate(-math.pi / 2);
      tp.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _PanoramaPainter old) =>
      old.skyline != skyline || old.peaks != peaks;
}

/// Messaggio per il terreno mancante, senza dipendere dal contesto l10n dentro
/// il calcolo asincrono.
extension on BuildContext {
  String get l10nTerrainMissing =>
      'Terreno non disponibile: serve la rete, oppure scarica la zona da '
      'Mappe Offline.';
}
