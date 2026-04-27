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
  static Future<Uint8List> render({
    required Uint8List imageBytes,
    required List<ProjectedPeak> projected,
    required Size originalViewport,
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

  static List<_RenderLayout> _layoutLabels(
    List<ProjectedPeak> peaks,
    double scaleX,
    double scaleY, {
    required double offsetX,
    required double offsetY,
    required double imgWidth,
    required double imgHeight,
  }) {
    final scaleFactor = (scaleX + scaleY) / 2;
    final labelW = 360.0 * scaleFactor; // 180 pt * scale
    final labelH = 110.0 * scaleFactor; // 55 pt * scale
    final gap = 12.0 * scaleFactor;
    final defaultOffsetY = 80.0 * scaleFactor;

    final placed = <_RenderLayout>[];

    for (final p in peaks) {
      // Coordinate dot nello spazio immagine
      final dotX = offsetX + p.screenX * scaleX;
      final dotY = offsetY + p.screenY * scaleY;
      // Posizione label iniziale: sopra il dot
      double labelY = dotY - defaultOffsetY;
      bool collides = true;
      int safety = 0;
      while (collides && safety < 30) {
        collides = false;
        for (final pl in placed) {
          final dx = (dotX - pl.labelX).abs();
          final dy = (labelY - pl.labelY).abs();
          if (dx < labelW * 0.85 && dy < labelH + gap) {
            labelY = pl.labelY - labelH - gap;
            collides = true;
            break;
          }
        }
        safety++;
      }

      // Limite superiore: non mettere label sotto il bordo top
      if (labelY < labelH / 2 + 8 * scaleFactor) {
        labelY = labelH / 2 + 8 * scaleFactor;
      }

      placed.add(_RenderLayout(
        peak: p,
        dotX: dotX,
        dotY: dotY,
        labelX: dotX,
        labelY: labelY,
        labelW: labelW,
        labelH: labelH,
        scale: scaleFactor,
      ));
    }
    return placed;
  }

  static void _drawConnectorLine(Canvas canvas, _RenderLayout l) {
    if ((l.labelY - l.dotY).abs() < l.labelH * 0.6) return;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.65)
      ..strokeWidth = 1.5 * l.scale
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(l.labelX, l.labelY + l.labelH / 2),
      Offset(l.dotX, l.dotY - 6 * l.scale),
      paint,
    );
  }

  static void _drawLabelBox(Canvas canvas, _RenderLayout l) {
    final isVolcano = l.peak.peak.type == 'volcano';
    final borderColor =
        isVolcano ? const Color(0xFFE85751) : const Color(0xFFFFD700);

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
      Paint()..color = Colors.black.withValues(alpha: 0.78),
    );

    // Bordo
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = borderColor.withValues(alpha: 0.85)
        ..strokeWidth = 2 * l.scale
        ..style = PaintingStyle.stroke,
    );

    // Testo: nome + altitudine/distanza
    final nameSpan = TextSpan(
      text: l.peak.peak.name,
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: 28 * l.scale,
        height: 1.0,
      ),
    );
    final subtitleSpan = TextSpan(
      text: _subtitle(l.peak),
      style: TextStyle(
        color: borderColor,
        fontWeight: FontWeight.w700,
        fontSize: 22 * l.scale,
        height: 1.0,
      ),
    );

    final namePainter = TextPainter(
      text: nameSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: l.labelW - 24 * l.scale);

    final subtitlePainter = TextPainter(
      text: subtitleSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();

    final totalH = namePainter.height + 4 * l.scale + subtitlePainter.height;
    final startY = l.labelY - totalH / 2;

    namePainter.paint(
      canvas,
      Offset(l.labelX - namePainter.width / 2, startY),
    );
    subtitlePainter.paint(
      canvas,
      Offset(
        l.labelX - subtitlePainter.width / 2,
        startY + namePainter.height + 4 * l.scale,
      ),
    );
  }

  static void _drawDot(Canvas canvas, _RenderLayout l) {
    final isVolcano = l.peak.peak.type == 'volcano';
    final color = isVolcano
        ? const Color(0xFFE85751)
        : const Color(0xFFFFD700);
    // Outer ring bianco
    canvas.drawCircle(
      Offset(l.dotX, l.dotY),
      8 * l.scale,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(l.dotX, l.dotY),
      6 * l.scale,
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
