import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/constants/api_keys.dart';
import '../../data/models/business.dart';

/// Epic 7.H10 — Generatore PDF Outreach Kit lato client.
///
/// Piano B (dopo che il Cmd+P del browser con Flutter CanvasKit non
/// produceva PDF correttamente impaginati): generiamo direttamente un
/// PDF nativo con il pacchetto `pdf` Dart. Output: Uint8List da
/// passare a `printing.Printing.sharePdf(...)` per il save dialog.
///
/// Layout A4 portrait, header brandizzato, stats funnel, mappa static
/// PNG (OpenStreetMap.de), competitor zona, footer con link e QR.
class OutreachPdfGenerator {
  /// Genera bytes PDF per un business specifico + lista di competitor
  /// vicini. Restituisce sempre un PDF (anche se la mappa non si
  /// scarica): nel peggior caso il blocco mappa viene saltato con
  /// un placeholder testuale.
  static Future<Uint8List> generate({
    required Business business,
    required List<Business> nearby,
  }) async {
    // Carica Noto Sans (Unicode completo) da Google Fonts. Senza
    // questo, il font default Helvetica del pacchetto pdf NON ha
    // glyph per em-dash (—), middle-dot (·), apostrofi ricciolati,
    // accenti italiani in alcuni casi. La generation può fallire o
    // produrre quadratini al loro posto.
    // `printing` package cachefica il download dopo il primo accesso.
    final notoRegular = await PdfGoogleFonts.notoSansRegular();
    final notoBold = await PdfGoogleFonts.notoSansBold();
    final notoItalic = await PdfGoogleFonts.notoSansItalic();

    final doc = pw.Document(
      title: 'TrailShare Outreach Kit — ${business.name}',
      author: 'TrailShare (Bluspose S.r.l.)',
      theme: pw.ThemeData.withFont(
        base: notoRegular,
        bold: notoBold,
        italic: notoItalic,
      ),
    );

    // Fetch static map in background. Se fallisce, proseguiamo senza.
    final mapBytes = await _fetchStaticMap(business, nearby);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(
            horizontal: 32, vertical: 32),
        build: (ctx) => [
          _buildHeader(business),
          pw.SizedBox(height: 14),
          _buildIntro(business),
          pw.SizedBox(height: 12),
          _buildFunnelStats(business),
          pw.SizedBox(height: 12),
          _buildMap(business, nearby, mapBytes),
          pw.SizedBox(height: 12),
          _buildCompetitor(business, nearby),
          pw.SizedBox(height: 14),
          _buildFooter(business),
        ],
      ),
    );

    return doc.save();
  }

  // ─── COLORS (TrailShare palette) ────────────────────────────────────
  static const _primary = PdfColor.fromInt(0xFFE07B4C);
  static const _success = PdfColor.fromInt(0xFF4CAF50);
  static const _info = PdfColor.fromInt(0xFF29B6F6);
  static const _warning = PdfColor.fromInt(0xFFFFA726);
  static const _muted = PdfColor.fromInt(0xFFB2BEC3);
  static const _textSecondary = PdfColor.fromInt(0xFF636E72);
  static const _surface = PdfColor.fromInt(0xFFFAF9F7);
  static const _border = PdfColor.fromInt(0xFFDFE6E9);
  static const _white = PdfColor.fromInt(0xFFFFFFFF);

  // ─── HEADER ─────────────────────────────────────────────────────────
  static pw.Widget _buildHeader(Business b) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        gradient: const pw.LinearGradient(
          colors: [
            PdfColor.fromInt(0x22E07B4C),
            PdfColor.fromInt(0x14FFA726),
          ],
        ),
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: PdfColor.fromInt(0x55E07B4C)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: pw.BoxDecoration(
                  color: _primary,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(
                  'TrailShare',
                  style: pw.TextStyle(
                    color: _white,
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                'OUTREACH KIT — ${b.type.displayName.toUpperCase()}',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: _muted,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            b.name,
            style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            [
              if (b.location.city != null) b.location.city,
              if (b.location.address != null) b.location.address,
              'lat ${b.location.lat.toStringAsFixed(4)}, lng ${b.location.lng.toStringAsFixed(4)}',
            ].whereType<String>().join(' · '),
            style: pw.TextStyle(
              fontSize: 11,
              color: _textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ─── INTRO ──────────────────────────────────────────────────────────
  static pw.Widget _buildIntro(Business b) {
    final isUnclaimed = b.tier == BusinessTier.unclaimed;
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _surface,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: _border),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Perché ti contattiamo',
            style: pw.TextStyle(
                fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            isUnclaimed
                ? 'Abbiamo creato una scheda pubblica del tuo ${b.type.displayName.toLowerCase()} '
                    'su TrailShare a partire da fonti pubbliche (OpenStreetMap, sito CAI, '
                    'registro imprese). La scheda è già online ed è visitata da escursionisti '
                    'che cercano informazioni nella tua zona. Ti proponiamo di prenderne il '
                    'controllo: aggiornarla, aggiungere foto, listino, percorsi consigliati e '
                    'ricevere statistiche reali delle visite.'
                : 'TrailShare è il social per outdoor enthusiast che usano l\'app per trovare '
                    'percorsi, registrare le proprie attività e scoprire i luoghi della '
                    'montagna italiana. La scheda del tuo '
                    '${b.type.displayName.toLowerCase()} su TrailShare è attiva e ti porta '
                    'visibilità.',
            style: pw.TextStyle(fontSize: 10, lineSpacing: 2),
          ),
        ],
      ),
    );
  }

  // ─── FUNNEL STATS ──────────────────────────────────────────────────
  static pw.Widget _buildFunnelStats(Business b) {
    final c = b.funnelCounters;
    final views = c['unclaimed_view'] ?? 0;
    final started = c['claim_started'] ?? 0;
    final completed = c['claim_completed'] ?? 0;
    final conversion = views > 0
        ? '${((completed / views) * 100).toStringAsFixed(1)}%'
        : '—';
    final hasData = views + started + completed > 0;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Cosa sta già succedendo',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        if (!hasData)
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: _surface,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: _border),
            ),
            child: pw.Text(
              'La scheda è stata pubblicata da poco: non abbiamo ancora dati statistici '
              'significativi. Possiamo aggiornarli al prossimo contatto.',
              style: pw.TextStyle(
                fontSize: 10,
                color: _textSecondary,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          )
        else
          pw.Row(
            children: [
              pw.Expanded(child: _statBox('VISUALIZZAZIONI', '$views', _info)),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _statBox('CLICK "RIVENDICA"', '$started', _warning)),
              pw.SizedBox(width: 8),
              pw.Expanded(child: _statBox('CONVERSIONE', conversion, _primary)),
            ],
          ),
      ],
    );
  }

  static pw.Widget _statBox(String label, String value, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColor(color.red, color.green, color.blue, 0.08),
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(
            color: PdfColor(color.red, color.green, color.blue, 0.3)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: color,
              letterSpacing: 0.6,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ─── MAP ────────────────────────────────────────────────────────────
  static pw.Widget _buildMap(
      Business b, List<Business> nearby, Uint8List? mapBytes) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Dove sei e chi c\'è intorno',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        if (mapBytes != null)
          pw.ClipRRect(
            horizontalRadius: 6,
            verticalRadius: 6,
            child: pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _border),
              ),
              child: pw.Image(
                pw.MemoryImage(mapBytes),
                fit: pw.BoxFit.cover,
                height: 180,
                width: double.infinity,
              ),
            ),
          )
        else
          pw.Container(
            height: 60,
            decoration: pw.BoxDecoration(
              color: _surface,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: _border),
            ),
            alignment: pw.Alignment.center,
            child: pw.Text(
              '(Mappa non disponibile in questo momento — vedi link in fondo)',
              style: pw.TextStyle(
                  fontSize: 10,
                  color: _textSecondary,
                  fontStyle: pw.FontStyle.italic),
            ),
          ),
        pw.SizedBox(height: 4),
        pw.Row(
          children: [
            _legend(_primary, 'La tua scheda'),
            pw.SizedBox(width: 12),
            _legend(_success, 'Schede rivendicate (Pro)'),
            pw.SizedBox(width: 12),
            _legend(_muted, 'Schede non rivendicate'),
          ],
        ),
      ],
    );
  }

  static pw.Widget _legend(PdfColor color, String label) {
    return pw.Row(
      children: [
        pw.Container(
          width: 8,
          height: 8,
          decoration:
              pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
        ),
        pw.SizedBox(width: 4),
        pw.Text(label,
            style: pw.TextStyle(fontSize: 9, color: _textSecondary)),
      ],
    );
  }

  // ─── COMPETITOR ─────────────────────────────────────────────────────
  static pw.Widget _buildCompetitor(Business b, List<Business> nearby) {
    final claimed =
        nearby.where((n) => n.tier != BusinessTier.unclaimed).length;
    final unclaimed =
        nearby.where((n) => n.tier == BusinessTier.unclaimed).length;
    final total = claimed + unclaimed;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Concorrenza zona (entro 10 km)',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        if (total == 0)
          pw.Text(
            'Sei l\'unico Spazio Pro nella zona. Vantaggio: chi cerca '
            'servizi outdoor qui trova solo te.',
            style: pw.TextStyle(fontSize: 10),
          )
        else
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: _surface,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: _border),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '$total schede TrailShare nella zona, $claimed già rivendicate.',
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold),
                ),
                if (claimed > 0) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'I tuoi colleghi stanno già usando TrailShare per farsi trovare. '
                    'Più aspetti, più il loro vantaggio di visibilità cresce.',
                    style: pw.TextStyle(
                      fontSize: 9,
                      color: _textSecondary,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                ],
                if (nearby.isNotEmpty) ...[
                  pw.SizedBox(height: 8),
                  ...nearby.take(8).map((n) => pw.Padding(
                        padding:
                            const pw.EdgeInsets.symmetric(vertical: 1.5),
                        child: pw.Row(
                          children: [
                            pw.Container(
                              width: 6,
                              height: 6,
                              decoration: pw.BoxDecoration(
                                color: n.tier == BusinessTier.unclaimed
                                    ? _muted
                                    : _success,
                                shape: pw.BoxShape.circle,
                              ),
                            ),
                            pw.SizedBox(width: 6),
                            pw.Expanded(
                              child: pw.Text(
                                n.name,
                                style: pw.TextStyle(fontSize: 9),
                                maxLines: 1,
                                overflow: pw.TextOverflow.clip,
                              ),
                            ),
                            pw.SizedBox(width: 6),
                            pw.Text(
                              n.tier == BusinessTier.unclaimed
                                  ? 'non rivendicata'
                                  : 'attiva',
                              style: pw.TextStyle(
                                fontSize: 8,
                                color: n.tier == BusinessTier.unclaimed
                                    ? _muted
                                    : _success,
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ],
            ),
          ),
      ],
    );
  }

  // ─── FOOTER ─────────────────────────────────────────────────────────
  static pw.Widget _buildFooter(Business b) {
    final url = 'https://trailshare.app/b/${b.slug}';
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(0x14E07B4C),
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColor.fromInt(0x55E07B4C)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Cosa puoi fare adesso',
            style:
                pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('1. Apri la pagina della tua scheda',
                        style: pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(height: 2),
                    pw.UrlLink(
                      destination: url,
                      child: pw.Text(
                        url,
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: _primary,
                          decoration: pw.TextDecoration.underline,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      '2. Clicca "Rivendica la scheda" e compila il form (5 minuti)',
                      style: pw.TextStyle(fontSize: 10),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      '3. Il team TrailShare verifica entro 48h. Da lì gestisci '
                      'foto, orari, listino, percorsi consigliati, statistiche.',
                      style: pw.TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              // QR code per scansione su carta
              pw.Container(
                padding: const pw.EdgeInsets.all(4),
                decoration: pw.BoxDecoration(
                  color: _white,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.BarcodeWidget(
                  data: url,
                  barcode: pw.Barcode.qrCode(),
                  width: 80,
                  height: 80,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Divider(color: _border, height: 1),
          pw.SizedBox(height: 6),
          pw.Text(
            'Per qualunque domanda: info@trailshare.app\n'
            'TrailShare è gestita da Bluspose S.r.l.',
            style: pw.TextStyle(fontSize: 8, color: _muted),
          ),
        ],
      ),
    );
  }

  // ─── STATIC MAP FETCH ──────────────────────────────────────────────
  /// Recupera un PNG static map da MapTiler.
  /// Sostituito staticmap.openstreetmap.de (offline / DNS fail) con
  /// MapTiler Static API che usa la stessa chiave già in app.
  /// Free tier MapTiler: 100k tile/mese — abbondante per il volume
  /// outreach (max ~50 PDF/mese).
  /// Se fallisce ritorna null e il PDF viene generato senza la mappa.
  ///
  /// Nota: il MapTiler API endpoint usa lon,lat (non lat,lon!) sia
  /// per il centro che per i marker. Inversione comune di errore.
  static Future<Uint8List?> _fetchStaticMap(
      Business b, List<Business> nearby) async {
    // Marker pattern MapTiler: `pin-s+{color}({lon},{lat})` per pin
    // semplici. Limitiamo a 8 concorrenti per non gonfiare la URL.
    final markersList = <String>[
      'pin-s+E07B4C(${b.location.lng},${b.location.lat})',
      ...nearby.take(8).map((n) {
        final color = n.tier == BusinessTier.unclaimed ? 'B2BEC3' : '4CAF50';
        return 'pin-s+$color(${n.location.lng},${n.location.lat})';
      }),
    ];

    final url = Uri.parse(
      'https://api.maptiler.com/maps/streets-v2/static/auto/640x300.png'
      '?key=${ApiKeys.mapTiler}'
      '&padding=40'
      '&markers=${markersList.join(",")}',
    );
    try {
      final resp = await http
          .get(url)
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        return resp.bodyBytes;
      }
      debugPrint('[OutreachPdf] MapTiler static HTTP ${resp.statusCode}: '
          '${resp.body.length < 300 ? resp.body : "..."}');
      return null;
    } catch (e) {
      debugPrint('[OutreachPdf] MapTiler static fetch error: $e');
      return null;
    }
  }
}
