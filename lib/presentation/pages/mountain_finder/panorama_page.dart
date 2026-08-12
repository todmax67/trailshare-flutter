import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/theme_colors_extension.dart';
import '../../../core/services/peaks_dataset_service.dart';
import '../../../core/services/pro_gate_service.dart';
import '../../../core/services/terrain_tile_service.dart';
import '../../../core/services/viewshed_service.dart';
import '../../../core/utils/viewshed_compute.dart' show skylineElevationAt, occluderIndex;
import '../../../core/utils/sun_moon.dart';
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

  /// Il cielo si può spegnere: quando è acceso la fascia verticale si allarga
  /// per far stare il sole d'estate, e il terreno si schiaccia un po'.
  bool _showSky = true;

  /// L'istante mostrato, in ora locale del dispositivo.
  late DateTime _when;
  DateTime _dayMidnightUtc = DateTime.utc(2000);
  List<SkyTrackPoint> _sunTrack = const [];
  List<SkyTrackPoint> _moonTrack = const [];

  /// Dove e quando il sole sparisce dietro il terreno, e la cima che glielo
  /// nasconde. Calcolati una volta per giornata invece che a ogni fotogramma
  /// del cursore dell'ora.
  ({DateTime time, double azimuthDeg, double elevationDeg})? _sunset;
  VisiblePeak? _sunsetPeak;

  @override
  void initState() {
    super.initState();
    _when = DateTime.now();
    _computeSky();
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
        // Il tramonto dipende dal terreno, che arriva solo adesso.
        _recomputeSunset();
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

  /// Sole e luna per il giorno scelto. Nessuna rete, nessun terreno: sono
  /// formule, quindi si calcola in sincrono e all'istante.
  void _computeSky() {
    _dayMidnightUtc = DateTime(_when.year, _when.month, _when.day).toUtc();
    _sunTrack = sunTrack(
        _dayMidnightUtc, widget.observerLat, widget.observerLng,
        stepMinutes: 4);
    _moonTrack = moonTrack(
        _dayMidnightUtc, widget.observerLat, widget.observerLng,
        stepMinutes: 4);
    _recomputeSunset();
  }

  /// L'istante in cui il sole passa dietro la cresta, e dietro quale cima.
  ///
  /// Si ricalcola su un campionamento **al minuto**, non su quello del disegno:
  /// un tramonto annunciato con quattro minuti di tolleranza non serve a chi si
  /// piazza col treppiede.
  void _recomputeSunset() {
    if (_skyline.isEmpty || _sunTrack.isEmpty) {
      _sunset = null;
      _sunsetPeak = null;
      return;
    }
    final fine = sunTrack(
        _dayMidnightUtc, widget.observerLat, widget.observerLng,
        stepMinutes: 1);
    _sunset = horizonCrossing(fine, _skylineAt);
    final s = _sunset;
    _sunsetPeak = s == null ? null : _occluderNear(s.azimuthDeg, s.elevationDeg);
  }

  double _skylineAt(double azDeg) => skylineElevationAt(_skyline, azDeg);

  /// La cima che nasconde il sole in una certa direzione, se ce n'è una.
  ///
  /// Quando nessuna arriva all'altezza giusta si tace il nome e si dà la
  /// direzione: sparire dietro una cresta senza nome è la norma, inventarle un
  /// nome no.
  VisiblePeak? _occluderNear(double azDeg, double elevDeg) {
    final i = occluderIndex(
      [for (final p in _peaks) p.azimuthDeg],
      [for (final p in _peaks) p.elevationAngleDeg],
      azDeg,
      elevDeg,
    );
    return i == null ? null : _peaks[i];
  }

  /// La fascia verticale mostrata. Col cielo acceso deve arrivare fin dove
  /// sale il sole, altrimenti a mezzogiorno d'estate l'arco uscirebbe dal
  /// riquadro e si vedrebbe una linea piatta finta.
  double get _topDeg {
    if (!_showSky) return 42;
    var top = 42.0;
    for (final p in _sunTrack) {
      if (p.position.elevationDeg > top - 6) top = p.position.elevationDeg + 6;
    }
    return math.min(top, 78);
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
        actions: [
          IconButton(
            tooltip: _showSky ? 'Nascondi sole e luna' : 'Mostra sole e luna',
            icon: Icon(_showSky ? Icons.wb_sunny : Icons.wb_sunny_outlined),
            onPressed: () => setState(() => _showSky = !_showSky),
          ),
        ],
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
        final controlsHeight = _showSky ? 132.0 : 44.0;
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: totalWidth,
                  height: constraints.maxHeight - controlsHeight,
                  child: CustomPaint(
                    painter: _PanoramaPainter(
                      skyline: _skyline,
                      peaks: _peaks,
                      terrainColor: AppColors.primary,
                      textColor: context.textPrimary,
                      mutedColor: context.textMuted,
                      topDeg: _topDeg,
                      sunTrack: _showSky ? _sunTrack : const [],
                      moonTrack: _showSky ? _moonTrack : const [],
                      sunNow: _showSky
                          ? sunPosition(_when.toUtc(), widget.observerLat,
                              widget.observerLng)
                          : null,
                      moonNow: _showSky
                          ? moonPosition(_when.toUtc(), widget.observerLat,
                                  widget.observerLng)
                              .position
                          : null,
                    ),
                  ),
                ),
              ),
            ),
            if (_showSky) _buildSkyControls() else _buildLegend(),
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

  /// Data, ora e — la riga che vale il prezzo — dietro quale cima sparisce il
  /// sole.
  Widget _buildSkyControls() {
    final minutes = _when.hour * 60 + _when.minute;
    return SizedBox(
      height: 132,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSunsetSummary(),
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 15),
                  label: Text(_formatDate(_when),
                      style: const TextStyle(fontSize: 13)),
                  onPressed: _pickDate,
                ),
                const Spacer(),
                Text(
                  _formatTime(_when),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Adesso',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.schedule, size: 18),
                  onPressed: () => setState(() {
                    _when = DateTime.now();
                    _computeSky();
                  }),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                value: minutes.toDouble(),
                min: 0,
                max: 24 * 60 - 1,
                onChanged: (v) => setState(() {
                  final m = v.round();
                  _when = DateTime(_when.year, _when.month, _when.day,
                      m ~/ 60, m % 60);
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSunsetSummary() {
    // Il tramonto vero è quello dietro la cresta, non quello da almanacco: in
    // montagna i due possono distare mezz'ora.
    final crossing = _sunset;
    if (crossing == null) {
      return SizedBox(
        height: 26,
        child: Center(
          child: Text(
            _sunTrack.any((p) => p.position.elevationDeg > 0)
                ? 'Tramonto oltre il terreno che conosciamo'
                : 'Il sole non sorge in questa data',
            style: TextStyle(fontSize: 12, color: context.textMuted),
          ),
        ),
      );
    }

    final peak = _sunsetPeak;
    final local = crossing.time.toLocal();
    final where = peak == null
        ? 'a ${crossing.azimuthDeg.round()}°'
        : 'dietro ${peak.peak.name}';

    return SizedBox(
      height: 26,
      child: Row(
        children: [
          Icon(Icons.wb_twilight, size: 16, color: AppColors.warning),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Il sole sparisce $where alle ${_formatTime(local)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            moonPhaseLabel(moonPhase(_when.toUtc())),
            style: TextStyle(fontSize: 11, color: context.textMuted),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(_when.year - 2),
      lastDate: DateTime(_when.year + 3),
    );
    if (picked == null) return;
    setState(() {
      _when = DateTime(
          picked.year, picked.month, picked.day, _when.hour, _when.minute);
      _computeSky();
    });
  }

  String _formatDate(DateTime d) =>
      '${d.day} ${_mesi[d.month - 1]} ${d.year}';

  String _formatTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static const _mesi = [
    'gen', 'feb', 'mar', 'apr', 'mag', 'giu',
    'lug', 'ago', 'set', 'ott', 'nov', 'dic',
  ];
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

  /// Cammino del sole e della luna nel giorno scelto. Vuoti = cielo spento.
  final List<SkyTrackPoint> sunTrack;
  final List<SkyTrackPoint> moonTrack;

  /// Dove stanno i due astri nell'istante selezionato.
  final SkyPosition? sunNow;
  final SkyPosition? moonNow;

  /// Bordo superiore della fascia mostrata, in gradi: si allarga quando c'è il
  /// sole da far stare dentro.
  final double topDeg;

  _PanoramaPainter({
    required this.skyline,
    required this.peaks,
    required this.terrainColor,
    required this.textColor,
    required this.mutedColor,
    required this.topDeg,
    this.sunTrack = const [],
    this.moonTrack = const [],
    this.sunNow,
    this.moonNow,
  });

  /// Sotto l'orizzonte si lascia poco: serve a far capire dove cade, non a
  /// disegnare i propri piedi.
  static const double _bottomDeg = -18;

  double _xFor(double azDeg, double width) => azDeg / 360 * width;

  double _yFor(double elevDeg, double height) =>
      (topDeg - elevDeg) / (topDeg - _bottomDeg) * height;

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

    // Archi e dischi vanno **sotto** al terreno: quando il sole è già dietro la
    // cresta deve sparirci dietro anche nel disegno. Disegnarlo sopra
    // racconterebbe il contrario di quello che dice la riga in fondo.
    _paintSkyTrack(canvas, size, moonTrack, const Color(0xFF7E8CA0), dashed: true);
    _paintSkyTrack(canvas, size, sunTrack, AppColors.warning);
    _paintSkyDiscs(canvas, size);

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
      final y = _yFor(elev.clamp(_bottomDeg, topDeg), h);
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

  /// L'arco percorso da un astro nella giornata, con le ore segnate.
  ///
  /// Il cammino attraversa lo zero dell'azimut: lì il disegno va **spezzato**,
  /// altrimenti comparirebbe una riga orizzontale che taglia tutto il panorama
  /// da nordovest a nordest.
  void _paintSkyTrack(
    Canvas canvas,
    Size size,
    List<SkyTrackPoint> track,
    Color color, {
    bool dashed = false,
  }) {
    if (track.isEmpty) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = dashed ? 1.6 : 2.2
      ..color = color.withValues(alpha: 0.85);

    Offset? prev;
    var dashOn = true;
    for (final p in track) {
      final elev = p.position.elevationDeg;
      // Sotto la fascia mostrata non si disegna: l'arco notturno del sole non
      // interessa e riempirebbe il basso di righe.
      if (elev < _bottomDeg) {
        prev = null;
        continue;
      }
      final cur = Offset(
        _xFor(p.position.azimuthDeg, size.width),
        _yFor(math.min(elev, topDeg), size.height),
      );
      if (prev != null && (cur.dx - prev.dx).abs() < size.width / 2) {
        if (!dashed || dashOn) canvas.drawLine(prev, cur, paint);
      }
      dashOn = !dashOn;
      prev = cur;
    }

    _paintHourMarks(canvas, size, track, color);
  }

  /// Le ore tonde lungo l'arco: senza, la traiettoria dice *dove* ma non
  /// *quando*, e il quando è metà della domanda.
  void _paintHourMarks(
    Canvas canvas,
    Size size,
    List<SkyTrackPoint> track,
    Color color,
  ) {
    for (final p in track) {
      final local = p.time.toLocal();
      if (local.minute != 0 || local.hour.isOdd) continue;
      final elev = p.position.elevationDeg;
      if (elev < 0) continue;

      final x = _xFor(p.position.azimuthDeg, size.width);
      final y = _yFor(math.min(elev, topDeg), size.height);
      canvas.drawCircle(Offset(x, y), 2.5, Paint()..color = color);

      final tp = TextPainter(
        text: TextSpan(
          text: '${local.hour}',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y - 16));
    }
  }

  /// Sole e luna nell'istante scelto, disegnati sopra tutto il resto.
  void _paintSkyDiscs(Canvas canvas, Size size) {
    final sun = sunNow;
    if (sun != null && sun.elevationDeg > _bottomDeg) {
      final c = Offset(
        _xFor(sun.azimuthDeg, size.width),
        _yFor(math.min(sun.elevationDeg, topDeg), size.height),
      );
      canvas.drawCircle(
          c, 13, Paint()..color = AppColors.warning.withValues(alpha: 0.28));
      canvas.drawCircle(c, 7, Paint()..color = AppColors.warning);
    }

    final moon = moonNow;
    if (moon != null && moon.elevationDeg > _bottomDeg) {
      final c = Offset(
        _xFor(moon.azimuthDeg, size.width),
        _yFor(math.min(moon.elevationDeg, topDeg), size.height),
      );
      canvas.drawCircle(c, 6, Paint()..color = const Color(0xFFE8ECF2));
      canvas.drawCircle(
        c,
        6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFF7E8CA0),
      );
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
        p.elevationAngleDeg.clamp(_bottomDeg, topDeg),
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
      old.skyline != skyline ||
      old.peaks != peaks ||
      old.topDeg != topDeg ||
      old.sunTrack != sunTrack ||
      old.moonTrack != moonTrack ||
      old.sunNow?.azimuthDeg != sunNow?.azimuthDeg ||
      old.moonNow?.azimuthDeg != moonNow?.azimuthDeg;
}

/// Messaggio per il terreno mancante, senza dipendere dal contesto l10n dentro
/// il calcolo asincrono.
extension on BuildContext {
  String get l10nTerrainMissing =>
      'Terreno non disponibile: serve la rete, oppure scarica la zona da '
      'Mappe Offline.';
}
