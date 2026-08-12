import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/mountain_projection.dart';
import 'ar_frame.dart';

/// Punti, steli ed etichette delle cime, disegnati invece che costruiti.
///
/// Erano sessanta widget con chiave, animazione e ombra sfocata, ricreati a ogni
/// campione dei sensori. Ora sono un solo strato: il `CustomPaint` che lo
/// contiene riceve [ArFrame] come `repaint:`, quindi si ridipinge senza passare
/// né da `build` né da `layout`.
///
/// **Cosa si perde e come si recupera.** Un'etichetta disegnata non è più un
/// widget, quindi non riceve il tap da sola e sparisce dall'albero di
/// accessibilità. Il tap si recupera con [peakAt] qui sotto, che rifà la
/// matematica del rettangolo ruotato. L'accessibilità no, ed è un debito
/// dichiarato: la risposta giusta non sarebbe comunque un'etichetta ruotata di
/// 45° dentro un mirino, ma un elenco consultabile delle cime visibili — che
/// oggi manca del tutto.
class ArPeaksPainter extends CustomPainter {
  final ArFrame frame;

  /// Paragrafi già composti, riusati fra un fotogramma e l'altro.
  ///
  /// Comporre il testo è la parte cara del disegnare un'etichetta, e il testo di
  /// una cima non cambia mentre si gira il telefono: cambia solo dove sta. La
  /// cache è tenuta dal painter e non ricreata con lui, altrimenti servirebbe a
  /// niente.
  final Map<String, ui.Paragraph> _paragraphs;

  ArPeaksPainter({required this.frame, required Map<String, ui.Paragraph> cache})
      : _paragraphs = cache,
        super(repaint: frame);

  /// -45°: il testo sale verso destra. In Flutter l'angolo positivo è orario,
  /// perché l'asse Y punta in basso.
  static const double angleRad = -45 * math.pi / 180;

  static const double _labelPadLeft = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final projected = frame.projected;
    if (projected.isEmpty) return;
    final centeredId = frame.centeredId;

    _paintStems(canvas);
    _paintDots(canvas, projected, centeredId);
    _paintLabels(canvas, centeredId);
    _paintTarget(canvas);
  }

  /// La cima cercata, quando è già nell'inquadratura.
  ///
  /// Un anello aperto e non un cerchio pieno: il bersaglio va indicato, non
  /// coperto — la montagna sotto è quello che si è venuti a vedere.
  void _paintTarget(Canvas canvas) {
    final t = frame.targetProjected;
    if (t == null) return;
    final c = Offset(t.screenX, t.screenY);

    canvas.drawCircle(
      c,
      20,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = const Color(0x66000000),
    );
    canvas.drawCircle(
      c,
      20,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = AppColors.primary,
    );
    // Quattro tacche a croce: dicono "questo qui" meglio di un anello liscio,
    // che in mezzo alle etichette si confonderebbe con un punto grosso.
    for (final a in [0, 90, 180, 270]) {
      final r = a * math.pi / 180;
      final d = Offset(math.cos(r), math.sin(r));
      canvas.drawLine(
        c + d * 20,
        c + d * 29,
        Paint()
          ..strokeWidth = 3
          ..color = AppColors.primary,
      );
    }
  }

  void _paintStems(Canvas canvas) {
    if (frame.layouts.isEmpty) return;
    final paint = Paint()
      ..color = const Color(0x99FFFFFF)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final alone = Paint()
      ..color = const Color(0x66000000)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (final l in frame.layouts) {
      path.moveTo(l.dotX, l.dotY - 4);
      path.lineTo(l.labelX, l.labelY);
    }
    // Un alone netto invece di una sfocatura: contro la neve o il cielo chiaro
    // serve lo stesso stacco, e un `MaskFilter.blur` per ogni stelo costerebbe
    // molto di più di una riga più spessa sotto.
    canvas.drawPath(path, alone);
    canvas.drawPath(path, paint);
  }

  void _paintDots(
      Canvas canvas, List<ProjectedPeak> projected, String? centeredId) {
    for (final p in projected) {
      final isVolcano = p.peak.type == 'volcano';
      final isCentered = p.peak.id == centeredId;
      final color = isVolcano
          ? AppColors.danger
          : (isCentered ? AppColors.warning : Colors.white);
      final c = Offset(p.screenX, p.screenY);

      if (isCentered) {
        canvas.drawCircle(
            c, 11, Paint()..color = color.withValues(alpha: 0.28));
      }
      canvas.drawCircle(c, 6.5, Paint()..color = const Color(0x66000000));
      canvas.drawCircle(c, 5, Paint()..color = color);
      canvas.drawCircle(
        c,
        5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white,
      );
    }
  }

  void _paintLabels(Canvas canvas, String? centeredId) {
    for (final l in frame.layouts) {
      final isCentered = l.peak.peak.id == centeredId;
      final par = _paragraphFor(l.peak, isCentered);
      canvas.save();
      canvas.translate(l.labelX, l.labelY);
      canvas.rotate(angleRad);
      canvas.drawParagraph(par, const Offset(_labelPadLeft, 0));
      canvas.restore();
    }
  }

  ui.Paragraph _paragraphFor(ProjectedPeak p, bool isCentered) {
    final meta = peakLabelMeta(p, full: isCentered);
    final key = '${p.peak.id}|$isCentered|$meta';
    final cached = _paragraphs[key];
    if (cached != null) return cached;

    final isVolcano = p.peak.type == 'volcano';
    final accent = isVolcano
        ? AppColors.danger
        : (isCentered ? AppColors.warning : Colors.white);

    const shadows = [
      Shadow(color: Colors.black, blurRadius: 3, offset: Offset(0, 1)),
      Shadow(color: Colors.black87, blurRadius: 6),
    ];

    final b = ui.ParagraphBuilder(ui.ParagraphStyle(
      textDirection: TextDirection.ltr,
      maxLines: 1,
    ))
      ..pushStyle(ui.TextStyle(
        color: isCentered ? accent : Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: isCentered ? 16 : 14,
        height: 1.0,
        shadows: shadows,
      ))
      ..addText(p.peak.name)
      ..pop();
    if (meta.isNotEmpty) {
      b
        ..pushStyle(ui.TextStyle(
          color: accent,
          fontWeight: FontWeight.w600,
          fontSize: isCentered ? 12 : 11,
          height: 1.0,
          shadows: shadows,
          fontFeatures: const [FontFeature.tabularFigures()],
        ))
        ..addText('  $meta')
        ..pop();
    }

    final par = b.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));

    // Un tetto alla cache: girando su sé stessi si passa da centinaia di cime,
    // e tenerle tutte sarebbe una perdita lenta di memoria per una funzione che
    // si usa mezz'ora di fila.
    if (_paragraphs.length > 400) _paragraphs.clear();
    _paragraphs[key] = par;
    return par;
  }

  /// La cima la cui etichetta è stata toccata, se ce n'è una.
  ///
  /// Rifà al contrario la trasformazione del disegno: il tocco si porta nel
  /// sistema di riferimento dell'etichetta ruotata e si guarda se cade nel
  /// riquadro del testo. Usare invece la distanza dall'ancoraggio, come si è
  /// tentati di fare, renderebbe intoccabili i nomi lunghi — che sono proprio
  /// quelli che si vogliono toccare.
  static ProjectedPeak? peakAt(
    Offset tap,
    ArFrame frame,
    Map<String, ui.Paragraph> cache,
  ) {
    const c = 0.70710678; // cos(-45°)
    const s = -0.70710678; // sin(-45°)
    const slop = 6.0;

    // Dall'ultima disegnata alla prima: se due si sovrappongono vince quella
    // che si vede sopra, che è quella che l'utente crede di toccare.
    for (var i = frame.layouts.length - 1; i >= 0; i--) {
      final l = frame.layouts[i];
      final isCentered = l.peak.peak.id == frame.centeredId;
      final meta = peakLabelMeta(l.peak, full: isCentered);
      final par = cache['${l.peak.peak.id}|$isCentered|$meta'];
      if (par == null) continue;

      final gx = tap.dx - l.labelX;
      final gy = tap.dy - l.labelY;
      final lx = gx * c + gy * s;
      final ly = -gx * s + gy * c;

      if (lx >= -slop &&
          lx <= _labelPadLeft + par.maxIntrinsicWidth + slop &&
          ly >= -slop &&
          ly <= par.height + slop) {
        return l.peak;
      }
    }
    return null;
  }

  @override
  bool shouldRepaint(covariant ArPeaksPainter old) => false;
}

/// Metadati della cima nell'etichetta. [full] (la cima centrata) = quota più
/// distanza; altrimenti solo quota, così l'etichetta è più corta e nei gruppi
/// fitti se ne salvano di più.
///
/// Condiviso fra il disegno e la stima dell'ingombro nel layout
/// anti-collisione: se i due divergessero, le etichette verrebbero posizionate
/// per una lunghezza che non hanno.
String peakLabelMeta(ProjectedPeak p, {required bool full}) {
  final ele = p.peak.elevation;
  final dist = p.distanceMeters / 1000;
  final distStr = dist < 10 ? dist.toStringAsFixed(1) : dist.toStringAsFixed(0);
  if (ele == null) return full ? '$distStr km' : '';
  return full ? '${ele.round()} m · $distStr km' : '${ele.round()} m';
}
