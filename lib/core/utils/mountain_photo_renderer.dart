import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'mountain_projection.dart';

/// Renderer **server-less** che compone un'immagine annotata partendo da
/// una foto catturata + lista di [ProjectedPeak] e produce PNG bytes.
///
/// La pipeline è interamente client-side (no backend, no rete) ed è la
/// stessa math di proiezione usata in live AR — solo che qui processiamo
/// un singolo frame congelato.
///
/// Output:
/// - PNG bytes pronti per essere salvati / condivisi
/// - watermark "TrailShare" in basso a destra
/// - le label peak vengono rese con label boxes neri semi-opachi e una
///   linea verticale sottile fino al dot (stesso stile della live AR)
class MountainPhotoRenderer {
  MountainPhotoRenderer._();

  /// Renderizza un'immagine sorgente con sopra le annotazioni dei peak.
  ///
  /// [imageBytes] - JPEG/PNG dell'immagine catturata
  /// [projected] - peak proiettati ai pixel del **viewport originale**
  ///               (sarà scalato all'immagine reale)
  /// [originalViewport] - dimensioni del viewport in cui è stata fatta
  ///                     la proiezione (tipicamente la screen size)
  /// [watermark] - testo del watermark (es. "TrailShare")
  /// Cap massimo POI renderizzati per non sovrastare le cime
  /// (che restano gli elementi principali della foto AR).
  static const int _maxVisiblePois = 12;

  static Future<Uint8List> render({
    required Uint8List imageBytes,
    required List<ProjectedPeak> projected,
    required Size originalViewport,
    List<ProjectedPoi> pois = const [],
    String watermark = 'TrailShare',
  }) async {
    // 1. Decodifica l'immagine sorgente
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final src = frame.image;

    final imgW = src.width.toDouble();
    final imgH = src.height.toDouble();

    // Le coordinate dei peak sono in pixel del viewport (es. 1080x2400);
    // l'immagine catturata ha tipicamente dimensioni diverse (es. 3840x2160
    // landscape native). Scaliamo le coordinate al sistema dell'immagine.
    //
    // Nota: la camera in portrait restituisce un buffer landscape; il
    // FittedBox(BoxFit.cover) usato in preview aplica un crop. Usiamo
    // lo stesso crop logico qui.
    final imageOrientationLandscape = imgW > imgH;
    double effectiveW;
    double effectiveH;
    double offsetX = 0;
    double offsetY = 0;

    if (imageOrientationLandscape) {
      // Buffer landscape ma viewport portrait → crop ai bordi laterali.
      final viewportRatio = originalViewport.width / originalViewport.height;
      final imageRatio = imgW / imgH;
      if (imageRatio > viewportRatio) {
        // Immagine più "larga": crop laterali
        effectiveH = imgH;
        effectiveW = imgH * viewportRatio;
        offsetX = (imgW - effectiveW) / 2;
      } else {
        effectiveW = imgW;
        effectiveH = imgW / viewportRatio;
        offsetY = (imgH - effectiveH) / 2;
      }
    } else {
      effectiveW = imgW;
      effectiveH = imgH;
    }

    final scaleX = effectiveW / originalViewport.width;
    final scaleY = effectiveH / originalViewport.height;

    // 2. Inizia il recording su PictureRecorder
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 3. Disegna l'immagine come background (full size)
    canvas.drawImage(src, Offset.zero, Paint());

    // 4. Disegna tutte le label dei peak (anti-collisione semplice)
    final layouts = _layoutLabels(projected, scaleX, scaleY,
        offsetX: offsetX, offsetY: offsetY, imgWidth: imgW, imgHeight: imgH);

    for (final l in layouts) {
      _drawConnectorLine(canvas, l);
    }
    for (final l in layouts) {
      _drawLabelBox(canvas, l);
      _drawDot(canvas, l);
    }

    // 4b. POI OSM (rifugi, sorgenti, ecc.) — sotto le label peak per
    //     non sovrastarle, ma con stile distinto (info-blue chip).
    if (pois.isNotEmpty) {
      _drawPois(canvas, pois, scaleX, scaleY,
          offsetX: offsetX, offsetY: offsetY, imgW: imgW, imgH: imgH);
    }

    // 5. Watermark TrailShare in basso a destra
    _drawWatermark(canvas, imgW, imgH, watermark);

    // 6. Encoder PNG
    final picture = recorder.endRecording();
    final outImage = await picture.toImage(src.width, src.height);
    final byteData =
        await outImage.toByteData(format: ui.ImageByteFormat.png);
    src.dispose();
    outImage.dispose();
    picture.dispose();
    return byteData!.buffer.asUint8List();
  }

  // ─── Layout interno ───────────────────────────────────────────────

  /// Numero massimo di righe nella label-band superiore.
  static const int _maxRows = 3;

  /// Cap del numero totale di label visibili (priorità ai più centrati +
  /// alti). Oltre questo numero la foto diventa illeggibile.
  static const int _maxVisibleLabels = 16;

  /// Algoritmo di layout: distribuisce le label in una **fascia
  /// orizzontale superiore** (massimo [_maxRows] righe) con leader
  /// lines che le collegano ai dot reali sull'immagine.
  ///
  /// Strategia (PeakFinder/PeakVisor-style):
  /// 1. Cap a [_maxVisibleLabels] (drop gli excess in fondo al ranking)
  /// 2. Sort by dotX (sinistra→destra)
  /// 3. Per ogni peak, prova a inserirlo nella prima riga libera al
  ///    suo dotX. Se occupato, prova le righe successive. Se nessuna
  ///    libera, push laterale per fare spazio.
  /// 4. Le label sono dimensionate in % dell'immagine con cap assoluti
  ///    per evitare label gigantesche su immagini ad alta risoluzione.
  static List<_RenderLayout> _layoutLabels(
    List<ProjectedPeak> peaks,
    double scaleX,
    double scaleY, {
    required double offsetX,
    required double offsetY,
    required double imgWidth,
    required double imgHeight,
  }) {
    if (peaks.isEmpty) return const [];

    // ─── Dimensioni label adattive ma limitate ─────────────────────
    // labelH: ~4.5% dell'altezza immagine, clampato 60-110 px
    final labelH = (imgHeight * 0.045).clamp(60.0, 110.0);
    // labelW: 28% larghezza immagine, clampato 280-460 px
    final labelW = (imgWidth * 0.28).clamp(280.0, 460.0);
    final gapY = labelH * 0.18;
    final gapX = labelW * 0.05;
    final topMargin = labelH * 0.5 + 8;
    // Scale factor solo per testo/dots (il box è absoluto).
    final scaleFactor = (labelH / 88.0).clamp(0.8, 2.5);

    // ─── Cap a _maxVisibleLabels (preserva ranking originale) ─────
    final capped = peaks.length > _maxVisibleLabels
        ? peaks.sublist(0, _maxVisibleLabels)
        : List<ProjectedPeak>.from(peaks);

    // ─── Sort by dotX per layout sinistra→destra ─────────────────
    capped.sort((a, b) {
      final ax = offsetX + a.screenX * scaleX;
      final bx = offsetX + b.screenX * scaleX;
      return ax.compareTo(bx);
    });

    // ─── Top-band layout multi-riga ──────────────────────────────
    // Ogni riga è una lista di label già piazzate (per check collisione).
    final rows = List<List<_RenderLayout>>.generate(_maxRows, (_) => []);
    final placed = <_RenderLayout>[];
    final halfW = labelW / 2;

    for (final p in capped) {
      final dotX = offsetX + p.screenX * scaleX;
      final dotY = offsetY + p.screenY * scaleY;

      _RenderLayout? best;
      double bestDistance = double.infinity;
      int bestRow = -1;
      double bestX = dotX;

      // Per ogni riga, calcola la X minima dove la label può essere
      // posizionata senza overlap con le label già nella riga.
      for (var r = 0; r < _maxRows; r++) {
        final row = rows[r];
        // X minima ammessa: dopo l'ultima label della riga (con gap).
        final minXInRow = row.isEmpty
            ? halfW + 8 // bordo sinistro + padding
            : row.last.labelX + halfW + gapX + halfW;
        final maxXInRow = imgWidth - halfW - 8;

        // Riga gia piena verso destra: nessun posto. Critico fare
        // questo check PRIMA del clamp, che altrimenti lancerebbe
        // ArgumentError quando minXInRow > maxXInRow.
        if (minXInRow > maxXInRow) continue;

        // Candidate X: il più vicino possibile a dotX, ma rispettando
        // sia il minimo (no overlap a sinistra) sia il bordo dx.
        final candidateX =
            dotX.clamp(minXInRow, maxXInRow).toDouble();

        final distance = (candidateX - dotX).abs();
        if (distance < bestDistance) {
          bestDistance = distance;
          bestRow = r;
          bestX = candidateX;
        }
      }

      if (bestRow == -1) {
        // Nessuna riga ha spazio: scartiamo questa label
        continue;
      }

      final labelY = topMargin + bestRow * (labelH + gapY) + labelH / 2;
      best = _RenderLayout(
        peak: p,
        dotX: dotX,
        dotY: dotY,
        labelX: bestX,
        labelY: labelY,
        labelW: labelW,
        labelH: labelH,
        scale: scaleFactor,
      );
      rows[bestRow].add(best);
      placed.add(best);
    }

    return placed;
  }

  static void _drawConnectorLine(Canvas canvas, _RenderLayout l) {
    // Disegna sempre la leader line (anche corte) per chiarezza visiva.
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = (l.labelH * 0.025).clamp(1.0, 3.0)
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(l.labelX, l.labelY + l.labelH / 2),
      Offset(l.dotX, l.dotY - l.labelH * 0.10),
      paint,
    );
  }

  static void _drawLabelBox(Canvas canvas, _RenderLayout l) {
    final isVolcano = l.peak.peak.type == 'volcano';
    final borderColor =
        isVolcano ? const Color(0xFFE85751) : const Color(0xFFFFD700);

    // Font sizes proporzionali a labelH (size totali ragionevoli).
    final nameFontSize = l.labelH * 0.34;
    final subtitleFontSize = l.labelH * 0.24;
    final padding = l.labelH * 0.18;
    final borderWidth = (l.labelH * 0.025).clamp(1.5, 3.0);

    final rect = Rect.fromCenter(
      center: Offset(l.labelX, l.labelY),
      width: l.labelW,
      height: l.labelH,
    );
    final rrect =
        RRect.fromRectAndRadius(rect, Radius.circular(l.labelH / 2));

    // Background nero semi-opaco
    canvas.drawRRect(
      rrect,
      Paint()..color = Colors.black.withValues(alpha: 0.80),
    );

    // Bordo
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = borderColor.withValues(alpha: 0.9)
        ..strokeWidth = borderWidth
        ..style = PaintingStyle.stroke,
    );

    // Testo: nome + altitudine/distanza
    final nameSpan = TextSpan(
      text: l.peak.peak.name,
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: nameFontSize,
        height: 1.05,
      ),
    );
    final subtitleSpan = TextSpan(
      text: _subtitle(l.peak),
      style: TextStyle(
        color: borderColor,
        fontWeight: FontWeight.w700,
        fontSize: subtitleFontSize,
        height: 1.05,
      ),
    );

    final namePainter = TextPainter(
      text: nameSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: l.labelW - padding * 2);

    final subtitlePainter = TextPainter(
      text: subtitleSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();

    final spacer = l.labelH * 0.06;
    final totalH = namePainter.height + spacer + subtitlePainter.height;
    final startY = l.labelY - totalH / 2;

    namePainter.paint(
      canvas,
      Offset(l.labelX - namePainter.width / 2, startY),
    );
    subtitlePainter.paint(
      canvas,
      Offset(
        l.labelX - subtitlePainter.width / 2,
        startY + namePainter.height + spacer,
      ),
    );
  }

  static void _drawDot(Canvas canvas, _RenderLayout l) {
    final isVolcano = l.peak.peak.type == 'volcano';
    final color = isVolcano
        ? const Color(0xFFE85751)
        : const Color(0xFFFFD700);
    // Dimensioni dot proporzionali a labelH (no più scale moltiplicativo).
    final outerR = (l.labelH * 0.10).clamp(8.0, 14.0);
    final innerR = outerR * 0.72;
    canvas.drawCircle(
      Offset(l.dotX, l.dotY),
      outerR,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(l.dotX, l.dotY),
      innerR,
      Paint()..color = color,
    );
  }

  static void _drawWatermark(
      Canvas canvas, double imgW, double imgH, String text) {
    final scale = (imgW + imgH) / 4000;
    final span = TextSpan(
      text: text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.85),
        fontWeight: FontWeight.w800,
        fontSize: 28 * scale,
        height: 1.0,
        shadows: [
          Shadow(
            blurRadius: 6 * scale,
            color: Colors.black.withValues(alpha: 0.6),
            offset: Offset(0, 2 * scale),
          ),
        ],
      ),
    );
    final painter = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
    )..layout();
    final padding = 24 * scale;
    painter.paint(
      canvas,
      Offset(
        imgW - painter.width - padding,
        imgH - painter.height - padding,
      ),
    );
  }

  // ─── Render POI OSM ───────────────────────────────────────────────

  /// Disegna i POI OSM come pin info-blue piccoli con label inline.
  /// Stile distinto dai peak (border colore, font più piccolo) per
  /// gerarchizzare visualmente: peak = elementi principali, POI =
  /// info accessoria.
  static void _drawPois(
    Canvas canvas,
    List<ProjectedPoi> pois,
    double scaleX,
    double scaleY, {
    required double offsetX,
    required double offsetY,
    required double imgW,
    required double imgH,
  }) {
    final capped = pois.length > _maxVisiblePois
        ? pois.sublist(0, _maxVisiblePois)
        : pois;

    final dotR = (imgH * 0.012).clamp(8.0, 16.0);
    final fontSize = (imgH * 0.022).clamp(20.0, 36.0);
    final pad = fontSize * 0.4;
    final labelGap = dotR * 1.4; // distanza dot → label

    // Tracciamo i bbox label già piazzati per anti-overlap.
    final placed = <Rect>[];

    // Sort: i POI più centrati (relBearing piccolo) prima, così se
    // dobbiamo scartarne alcuni in caso di overlap, scarta quelli ai
    // margini.
    final sorted = List<ProjectedPoi>.from(capped)
      ..sort((a, b) => a.relativeBearingDeg
          .abs()
          .compareTo(b.relativeBearingDeg.abs()));

    for (final p in sorted) {
      final dotX = offsetX + p.screenX * scaleX;
      final dotY = offsetY + p.screenY * scaleY;

      // Label string: "Rifugio Curò · 1915m" oppure "Sorgente · 0.5km"
      final labelText = _poiLabel(p);
      final span = TextSpan(
        text: labelText,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          height: 1.05,
        ),
      );
      final painter = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: imgW * 0.5);

      final labelW = painter.width + pad * 2;
      final labelH = painter.height + pad * 1.2;

      // Position iniziale: label sotto il dot, centrata orizz.
      double labelX = dotX - labelW / 2;
      double labelY = dotY + labelGap;

      // Clamp ai bordi immagine
      labelX = labelX.clamp(8.0, imgW - labelW - 8);
      // Se il label uscirebbe dal bordo basso, mettilo sopra il dot
      if (labelY + labelH > imgH - 8) {
        labelY = dotY - labelGap - labelH;
      }

      // Anti-overlap: se confligge con un altro POI già piazzato,
      // spostalo verticalmente a step di labelH+gap. Limit 4 step
      // così evitiamo di spostarlo "fuori contesto".
      Rect bbox = Rect.fromLTWH(labelX, labelY, labelW, labelH);
      bool conflict = true;
      int attempts = 0;
      while (conflict && attempts < 4) {
        conflict = placed.any((r) => r.overlaps(bbox.inflate(2)));
        if (!conflict) break;
        labelY += labelH + 4;
        if (labelY + labelH > imgH - 8) break; // troppo in basso, skip
        bbox = Rect.fromLTWH(labelX, labelY, labelW, labelH);
        attempts++;
      }
      if (conflict) continue; // non c'è posto, scarta questo POI

      placed.add(bbox);

      // ─── Disegna ───
      // 1. Dot (cerchio bianco con interno blu)
      canvas.drawCircle(
        Offset(dotX, dotY),
        dotR,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        Offset(dotX, dotY),
        dotR * 0.7,
        Paint()..color = const Color(0xFF1976D2),
      );

      // 2. Linea connector sottile dal dot al label
      canvas.drawLine(
        Offset(dotX, dotY + dotR),
        Offset(bbox.center.dx, bbox.top),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.6)
          ..strokeWidth = (dotR * 0.15).clamp(1.0, 2.5),
      );

      // 3. Background pillola
      final rrect = RRect.fromRectAndRadius(bbox, Radius.circular(labelH / 2));
      canvas.drawRRect(
        rrect,
        Paint()..color = const Color(0xFF1976D2).withValues(alpha: 0.92),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );

      // 4. Testo
      painter.paint(
        canvas,
        Offset(bbox.left + pad, bbox.top + pad * 0.6),
      );
    }
  }

  static String _poiLabel(ProjectedPoi p) {
    final ele = p.poi.elevation;
    final dist = p.distanceMeters / 1000;
    final distStr =
        dist < 10 ? dist.toStringAsFixed(1) : dist.toStringAsFixed(0);
    if (ele != null) {
      return '${p.poi.name} · ${ele.round()}m';
    }
    return '${p.poi.name} · ${distStr}km';
  }

  static String _subtitle(ProjectedPeak p) {
    final ele = p.peak.elevation;
    final dist = p.distanceMeters / 1000;
    final distStr =
        dist < 10 ? dist.toStringAsFixed(1) : dist.toStringAsFixed(0);
    if (ele == null) return '$distStr km';
    return '${ele.round()} m  ·  $distStr km';
  }
}

class _RenderLayout {
  final ProjectedPeak peak;
  final double dotX;
  final double dotY;
  final double labelX;
  final double labelY;
  final double labelW;
  final double labelH;
  final double scale;

  const _RenderLayout({
    required this.peak,
    required this.dotX,
    required this.dotY,
    required this.labelX,
    required this.labelY,
    required this.labelW,
    required this.labelH,
    required this.scale,
  });
}
